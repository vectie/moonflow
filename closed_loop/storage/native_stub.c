#define _DARWIN_C_SOURCE
#define _GNU_SOURCE

#include <moonbit.h>

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#if defined(__linux__)
#include <linux/fs.h>
#include <sys/syscall.h>
#endif

#define MF_STATUS_UNSAFE 100001
#define MF_STATUS_SYMLINK 100002
#define MF_STATUS_FAULT_BASE 200000
#define MF_MAX_FILE_BYTES (64 * 1024 * 1024)

static _Atomic uint64_t mf_temporary_counter = 0;
static _Atomic uint64_t mf_fixture_counter = 0;

typedef struct {
  int workspace_fd;
  int dir_fd;
  int lock_fd;
  int exclusive;
  char *workspace_path;
  char *root_path;
} mf_storage_session_t;

static void mf_storage_session_finalize(void *object) {
  mf_storage_session_t *session = (mf_storage_session_t *)object;
  if (session->lock_fd >= 0) {
    flock(session->lock_fd, LOCK_UN);
    close(session->lock_fd);
    session->lock_fd = -1;
  }
  if (session->dir_fd >= 0) {
    close(session->dir_fd);
    session->dir_fd = -1;
  }
  if (session->workspace_fd >= 0) {
    close(session->workspace_fd);
    session->workspace_fd = -1;
  }
  session->exclusive = 0;
  free(session->workspace_path);
  session->workspace_path = NULL;
  free(session->root_path);
  session->root_path = NULL;
}

static char *mf_exact_storage_root(
    const char *workspace,
    const char *relative,
    int *status_out) {
  size_t workspace_length = strlen(workspace);
  size_t relative_length = strlen(relative);
  int needs_separator = workspace_length != 1 || workspace[0] != '/';
  if (workspace_length > SIZE_MAX - relative_length - 2) {
    *status_out = EOVERFLOW;
    return NULL;
  }
  size_t length = workspace_length + (size_t)needs_separator + relative_length;
  char *candidate = (char *)malloc(length + 1);
  if (candidate == NULL) {
    *status_out = ENOMEM;
    return NULL;
  }
  memcpy(candidate, workspace, workspace_length);
  size_t offset = workspace_length;
  if (needs_separator) {
    candidate[offset++] = '/';
  }
  memcpy(candidate + offset, relative, relative_length);
  candidate[length] = '\0';
  char *canonical = realpath(candidate, NULL);
  if (canonical == NULL) {
    *status_out = errno;
    free(candidate);
    return NULL;
  }
  if (strcmp(candidate, canonical) != 0) {
    *status_out = MF_STATUS_UNSAFE;
    free(candidate);
    free(canonical);
    return NULL;
  }
  free(candidate);
  return canonical;
}

static int mf_bytes_are_c_string(moonbit_bytes_t value) {
  size_t length = (size_t)Moonbit_array_length(value);
  return strlen((const char *)value) == length;
}

static int mf_valid_relative_path(const char *path) {
  if (path == NULL || path[0] == '\0' || path[0] == '/' ||
      strchr(path, '\\') != NULL) {
    return 0;
  }
  const char *segment = path;
  for (const char *cursor = path;; cursor++) {
    if (*cursor == '/' || *cursor == '\0') {
      size_t length = (size_t)(cursor - segment);
      if (length == 0 || (length == 1 && segment[0] == '.') ||
          (length == 2 && segment[0] == '.' && segment[1] == '.')) {
        return 0;
      }
      if (*cursor == '\0') {
        break;
      }
      segment = cursor + 1;
    }
  }
  return 1;
}

static int mf_valid_name(const char *name) {
  return mf_valid_relative_path(name) && strchr(name, '/') == NULL;
}

static int mf_symlink_status(int error) {
  return error == ELOOP ? MF_STATUS_SYMLINK : error;
}

static int mf_open_or_create_storage_dir(
    int workspace_fd,
    const char *relative,
    int *out_fd) {
  char *copy = strdup(relative);
  if (copy == NULL) {
    return ENOMEM;
  }
  int current = dup(workspace_fd);
  if (current < 0) {
    int status = errno;
    free(copy);
    return status;
  }
  char *cursor = copy;
  while (cursor != NULL && *cursor != '\0') {
    char *slash = strchr(cursor, '/');
    if (slash != NULL) {
      *slash = '\0';
    }
    int created = 0;
    if (mkdirat(current, cursor, 0700) != 0) {
      if (errno != EEXIST) {
        int status = mf_symlink_status(errno);
        close(current);
        free(copy);
        return status;
      }
      struct stat existing_stat;
      if (fstatat(
              current,
              cursor,
              &existing_stat,
              AT_SYMLINK_NOFOLLOW) != 0) {
        int status = errno;
        close(current);
        free(copy);
        return status;
      }
      if (S_ISLNK(existing_stat.st_mode)) {
        close(current);
        free(copy);
        return MF_STATUS_SYMLINK;
      }
      if (!S_ISDIR(existing_stat.st_mode)) {
        close(current);
        free(copy);
        return MF_STATUS_UNSAFE;
      }
    } else {
      created = 1;
    }
    int next = openat(
        current,
        cursor,
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (next < 0) {
      int status = mf_symlink_status(errno);
      close(current);
      free(copy);
      return status;
    }
    struct stat stat_value;
    if (fstat(next, &stat_value) != 0 || !S_ISDIR(stat_value.st_mode)) {
      int status = errno == 0 ? MF_STATUS_UNSAFE : errno;
      close(next);
      close(current);
      free(copy);
      return status;
    }
    if (created && fsync(current) != 0) {
      int status = errno;
      close(next);
      close(current);
      free(copy);
      return status;
    }
    close(current);
    current = next;
    cursor = slash == NULL ? NULL : slash + 1;
  }
  free(copy);
  *out_fd = current;
  return 0;
}

MOONBIT_FFI_EXPORT
mf_storage_session_t *moonflow_storage_native_acquire(
    moonbit_bytes_t workspace,
    moonbit_bytes_t relative,
    int32_t exclusive,
    int32_t *status_out) {
  mf_storage_session_t *session =
      (mf_storage_session_t *)moonbit_make_external_object(
          mf_storage_session_finalize,
          sizeof(mf_storage_session_t));
  session->dir_fd = -1;
  session->workspace_fd = -1;
  session->lock_fd = -1;
  session->exclusive = 0;
  session->workspace_path = NULL;
  session->root_path = NULL;
  *status_out = 0;
  if (!mf_bytes_are_c_string(workspace) ||
      !mf_bytes_are_c_string(relative) ||
      !mf_valid_relative_path((const char *)relative)) {
    *status_out = MF_STATUS_UNSAFE;
    return session;
  }
  const char *workspace_path = (const char *)workspace;
  if (workspace_path[0] != '/') {
    *status_out = MF_STATUS_UNSAFE;
    return session;
  }
  struct stat root_lstat;
  if (lstat(workspace_path, &root_lstat) != 0) {
    *status_out = errno;
    return session;
  }
  if (S_ISLNK(root_lstat.st_mode)) {
    *status_out = MF_STATUS_SYMLINK;
    return session;
  }
  if (!S_ISDIR(root_lstat.st_mode)) {
    *status_out = MF_STATUS_UNSAFE;
    return session;
  }
  char *canonical = realpath(workspace_path, NULL);
  if (canonical == NULL) {
    *status_out = errno;
    return session;
  }
  if (strcmp(canonical, workspace_path) != 0) {
    free(canonical);
    *status_out = MF_STATUS_UNSAFE;
    return session;
  }
  free(canonical);
  int workspace_fd = open(
      workspace_path,
      O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (workspace_fd < 0) {
    *status_out = mf_symlink_status(errno);
    return session;
  }
  int lock_fd = openat(
      workspace_fd,
      ".moonflow-flow4a.lock",
      O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
      0600);
  if (lock_fd < 0) {
    *status_out = mf_symlink_status(errno);
    close(workspace_fd);
    return session;
  }
  struct stat lock_stat;
  if (fstat(lock_fd, &lock_stat) != 0 || !S_ISREG(lock_stat.st_mode)) {
    *status_out = errno == 0 ? MF_STATUS_UNSAFE : errno;
    close(lock_fd);
    close(workspace_fd);
    return session;
  }
  if (flock(lock_fd, exclusive ? LOCK_EX : LOCK_SH) != 0) {
    *status_out = errno;
    close(lock_fd);
    close(workspace_fd);
    return session;
  }
  int storage_fd = -1;
  int status = mf_open_or_create_storage_dir(
      workspace_fd,
      (const char *)relative,
      &storage_fd);
  if (status != 0) {
    flock(lock_fd, LOCK_UN);
    close(lock_fd);
    close(workspace_fd);
    *status_out = status;
    return session;
  }
  int path_status = 0;
  char *root_path = mf_exact_storage_root(
      workspace_path,
      (const char *)relative,
      &path_status);
  if (root_path == NULL) {
    close(storage_fd);
    flock(lock_fd, LOCK_UN);
    close(lock_fd);
    close(workspace_fd);
    *status_out = path_status;
    return session;
  }
  char *stored_workspace = strdup(workspace_path);
  if (stored_workspace == NULL) {
    free(root_path);
    close(storage_fd);
    flock(lock_fd, LOCK_UN);
    close(lock_fd);
    close(workspace_fd);
    *status_out = ENOMEM;
    return session;
  }
  session->workspace_fd = workspace_fd;
  session->dir_fd = storage_fd;
  session->lock_fd = lock_fd;
  session->exclusive = exclusive ? 1 : 0;
  session->workspace_path = stored_workspace;
  session->root_path = root_path;
  return session;
}

MOONBIT_FFI_EXPORT
mf_storage_session_t *moonflow_storage_native_open_related(
    mf_storage_session_t *parent,
    moonbit_bytes_t relative,
    int32_t *status_out) {
  mf_storage_session_t *session =
      (mf_storage_session_t *)moonbit_make_external_object(
          mf_storage_session_finalize,
          sizeof(mf_storage_session_t));
  session->workspace_fd = -1;
  session->dir_fd = -1;
  session->lock_fd = -1;
  session->exclusive = 0;
  session->workspace_path = NULL;
  session->root_path = NULL;
  *status_out = 0;
  if (parent->workspace_fd < 0 || parent->lock_fd < 0 ||
      !parent->exclusive) {
    *status_out = EPERM;
    return session;
  }
  if (!mf_bytes_are_c_string(relative) ||
      !mf_valid_relative_path((const char *)relative)) {
    *status_out = MF_STATUS_UNSAFE;
    return session;
  }
  int workspace_fd = dup(parent->workspace_fd);
  if (workspace_fd < 0) {
    *status_out = errno;
    return session;
  }
  int storage_fd = -1;
  int status = mf_open_or_create_storage_dir(
      workspace_fd,
      (const char *)relative,
      &storage_fd);
  if (status != 0) {
    close(workspace_fd);
    *status_out = status;
    return session;
  }
  int path_status = 0;
  char *root_path = mf_exact_storage_root(
      parent->workspace_path,
      (const char *)relative,
      &path_status);
  if (root_path == NULL) {
    close(storage_fd);
    close(workspace_fd);
    *status_out = path_status;
    return session;
  }
  char *stored_workspace = strdup(parent->workspace_path);
  if (stored_workspace == NULL) {
    free(root_path);
    close(storage_fd);
    close(workspace_fd);
    *status_out = ENOMEM;
    return session;
  }
  session->workspace_fd = workspace_fd;
  session->dir_fd = storage_fd;
  session->workspace_path = stored_workspace;
  session->root_path = root_path;
  return session;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonflow_storage_native_root_identity(
    mf_storage_session_t *session,
    int32_t *status_out) {
  *status_out = 0;
  if (session->dir_fd < 0 || session->root_path == NULL) {
    *status_out = EBADF;
    return moonbit_make_bytes(0, 0);
  }
  size_t length = strlen(session->root_path);
  if (length > INT32_MAX) {
    *status_out = EOVERFLOW;
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  if (length > 0) {
    memcpy(result, session->root_path, length);
  }
  return result;
}

MOONBIT_FFI_EXPORT
void moonflow_storage_native_close(mf_storage_session_t *session) {
  mf_storage_session_finalize(session);
}

static int mf_append_name(
    uint8_t **buffer,
    size_t *length,
    size_t *capacity,
    const char *name) {
  size_t name_length = strlen(name);
  if (name_length > INT32_MAX ||
      *length > SIZE_MAX - name_length - 4) {
    return EOVERFLOW;
  }
  size_t required = *length + name_length + 4;
  if (required > *capacity) {
    size_t next = *capacity == 0 ? 256 : *capacity;
    while (next < required) {
      if (next > SIZE_MAX / 2) {
        return EOVERFLOW;
      }
      next *= 2;
    }
    uint8_t *grown = (uint8_t *)realloc(*buffer, next);
    if (grown == NULL) {
      return ENOMEM;
    }
    *buffer = grown;
    *capacity = next;
  }
  uint32_t encoded = (uint32_t)name_length;
  (*buffer)[*length] = (uint8_t)(encoded >> 24);
  (*buffer)[*length + 1] = (uint8_t)(encoded >> 16);
  (*buffer)[*length + 2] = (uint8_t)(encoded >> 8);
  (*buffer)[*length + 3] = (uint8_t)encoded;
  memcpy(*buffer + *length + 4, name, name_length);
  *length = required;
  return 0;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonflow_storage_native_list(
    mf_storage_session_t *session,
    int32_t *status_out) {
  *status_out = 0;
  if (session->dir_fd < 0) {
    *status_out = EBADF;
    return moonbit_make_bytes(0, 0);
  }
  int duplicate = dup(session->dir_fd);
  if (duplicate < 0) {
    *status_out = errno;
    return moonbit_make_bytes(0, 0);
  }
  DIR *directory = fdopendir(duplicate);
  if (directory == NULL) {
    *status_out = errno;
    close(duplicate);
    return moonbit_make_bytes(0, 0);
  }
  uint8_t *buffer = NULL;
  size_t length = 0;
  size_t capacity = 0;
  errno = 0;
  for (;;) {
    struct dirent *entry = readdir(directory);
    if (entry == NULL) {
      break;
    }
    if (strcmp(entry->d_name, ".") == 0 ||
        strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    int status = mf_append_name(
        &buffer,
        &length,
        &capacity,
        entry->d_name);
    if (status != 0) {
      *status_out = status;
      break;
    }
  }
  if (*status_out == 0 && errno != 0) {
    *status_out = errno;
  }
  closedir(directory);
  if (*status_out != 0 || length > INT32_MAX) {
    if (*status_out == 0) {
      *status_out = EOVERFLOW;
    }
    free(buffer);
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  if (length > 0) {
    memcpy(result, buffer, length);
  }
  free(buffer);
  return result;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonflow_storage_native_read(
    mf_storage_session_t *session,
    moonbit_bytes_t name,
    int32_t *status_out) {
  *status_out = 0;
  if (session->dir_fd < 0) {
    *status_out = EBADF;
    return moonbit_make_bytes(0, 0);
  }
  if (!mf_bytes_are_c_string(name) ||
      !mf_valid_name((const char *)name)) {
    *status_out = MF_STATUS_UNSAFE;
    return moonbit_make_bytes(0, 0);
  }
  struct stat link_stat;
  if (fstatat(
          session->dir_fd,
          (const char *)name,
          &link_stat,
          AT_SYMLINK_NOFOLLOW) != 0) {
    *status_out = errno;
    return moonbit_make_bytes(0, 0);
  }
  if (S_ISLNK(link_stat.st_mode)) {
    *status_out = MF_STATUS_SYMLINK;
    return moonbit_make_bytes(0, 0);
  }
  if (!S_ISREG(link_stat.st_mode)) {
    *status_out = MF_STATUS_UNSAFE;
    return moonbit_make_bytes(0, 0);
  }
  int fd = openat(
      session->dir_fd,
      (const char *)name,
      O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0) {
    *status_out = mf_symlink_status(errno);
    return moonbit_make_bytes(0, 0);
  }
  struct stat stat_value;
  if (fstat(fd, &stat_value) != 0) {
    *status_out = errno;
    close(fd);
    return moonbit_make_bytes(0, 0);
  }
  if (stat_value.st_size < 0 || stat_value.st_size > MF_MAX_FILE_BYTES) {
    *status_out = EFBIG;
    close(fd);
    return moonbit_make_bytes(0, 0);
  }
  int32_t length = (int32_t)stat_value.st_size;
  moonbit_bytes_t result = moonbit_make_bytes(length, 0);
  int32_t offset = 0;
  while (offset < length) {
    ssize_t count = read(fd, result + offset, (size_t)(length - offset));
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      *status_out = count == 0 ? EIO : errno;
      break;
    }
    offset += (int32_t)count;
  }
  if (close(fd) != 0 && *status_out == 0) {
    *status_out = errno;
  }
  return result;
}

static int mf_atomic_rename_exclusive(
    int directory_fd,
    const char *temporary,
    const char *committed) {
#if defined(__APPLE__)
  return renameatx_np(
      directory_fd,
      temporary,
      directory_fd,
      committed,
      RENAME_EXCL);
#elif defined(__linux__) && defined(SYS_renameat2)
  return (int)syscall(
      SYS_renameat2,
      directory_fd,
      temporary,
      directory_fd,
      committed,
      RENAME_NOREPLACE);
#else
  errno = ENOTSUP;
  return -1;
#endif
}

static int mf_write_all(int fd, const uint8_t *data, int32_t length) {
  int32_t offset = 0;
  while (offset < length) {
    ssize_t count = write(fd, data + offset, (size_t)(length - offset));
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      return count == 0 ? EIO : errno;
    }
    offset += (int32_t)count;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonflow_storage_native_atomic_store(
    mf_storage_session_t *session,
    moonbit_bytes_t committed_name,
    moonbit_bytes_t contents,
    int32_t fault_point) {
  if (session->dir_fd < 0) {
    return EBADF;
  }
  if (!mf_bytes_are_c_string(committed_name) ||
      !mf_valid_name((const char *)committed_name)) {
    return MF_STATUS_UNSAFE;
  }
  if (fault_point == 1) {
    return MF_STATUS_FAULT_BASE + fault_point;
  }
  char temporary[128];
  int fd = -1;
  for (int attempt = 0; attempt < 100; attempt++) {
    uint64_t nonce = atomic_fetch_add_explicit(
        &mf_temporary_counter,
        1,
        memory_order_relaxed) + 1;
    snprintf(
        temporary,
        sizeof(temporary),
        ".flow4a-tmp-%ld-%llu",
        (long)getpid(),
        (unsigned long long)nonce);
    fd = openat(
        session->dir_fd,
        temporary,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
        0600);
    if (fd >= 0 || errno != EEXIST) {
      break;
    }
  }
  if (fd < 0) {
    return mf_symlink_status(errno);
  }
  if (fault_point == 2) {
    close(fd);
    return MF_STATUS_FAULT_BASE + fault_point;
  }
  int32_t length = Moonbit_array_length(contents);
  if (fault_point == 3) {
    int32_t partial = length == 0 ? 0 : (length + 1) / 2;
    int status = mf_write_all(fd, contents, partial);
    close(fd);
    return status == 0 ? MF_STATUS_FAULT_BASE + fault_point : status;
  }
  int status = mf_write_all(fd, contents, length);
  if (status != 0) {
    close(fd);
    return status;
  }
  if (fault_point == 4) {
    close(fd);
    return MF_STATUS_FAULT_BASE + fault_point;
  }
  if (fsync(fd) != 0) {
    status = errno;
    close(fd);
    return status;
  }
  if (fault_point == 5) {
    close(fd);
    return MF_STATUS_FAULT_BASE + fault_point;
  }
  if (close(fd) != 0) {
    return errno;
  }
  if (fault_point == 6) {
    return MF_STATUS_FAULT_BASE + fault_point;
  }
  if (mf_atomic_rename_exclusive(
          session->dir_fd,
          temporary,
          (const char *)committed_name) != 0) {
    return mf_symlink_status(errno);
  }
  if (fault_point == 7) {
    return MF_STATUS_FAULT_BASE + fault_point;
  }
  if (fsync(session->dir_fd) != 0) {
    return errno;
  }
  if (fault_point == 8) {
    return MF_STATUS_FAULT_BASE + fault_point;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonflow_storage_native_temporary_root(int32_t *status_out) {
  const char *candidate = getenv("TMPDIR");
  if (candidate == NULL || candidate[0] == '\0') {
    candidate = "/tmp";
  }
  char *canonical = realpath(candidate, NULL);
  if (canonical == NULL) {
    *status_out = errno;
    return moonbit_make_bytes(0, 0);
  }
  size_t length = strlen(canonical);
  if (length > INT32_MAX) {
    free(canonical);
    *status_out = EOVERFLOW;
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  memcpy(result, canonical, length);
  free(canonical);
  *status_out = 0;
  return result;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonflow_storage_native_unique_suffix(void) {
  char value[96];
  uint64_t nonce = atomic_fetch_add_explicit(
      &mf_fixture_counter,
      1,
      memory_order_relaxed) + 1;
  int length = snprintf(
      value,
      sizeof(value),
      "mf-flow4a-%ld-%llu",
      (long)getpid(),
      (unsigned long long)nonce);
  moonbit_bytes_t result = moonbit_make_bytes(length, 0);
  memcpy(result, value, (size_t)length);
  return result;
}
