#include <errno.h>
#include <fcntl.h>
#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/file.h>
#include <unistd.h>

MOONBIT_FFI_EXPORT
int32_t moonflow_operator_materialization_native_rename_v1(
    moonbit_bytes_t source,
    moonbit_bytes_t destination) {
  if (rename((const char *)source, (const char *)destination) == 0) {
    return 0;
  }
  return errno;
}

MOONBIT_FFI_EXPORT
int32_t moonflow_operator_materialization_native_lock_v1(
    moonbit_bytes_t path) {
  int fd = open((const char *)path, O_WRONLY | O_CREAT, 0600);
  if (fd < 0) {
    return -errno;
  }
  if (flock(fd, LOCK_EX) != 0) {
    int error = errno;
    close(fd);
    return -error;
  }
  return fd;
}

MOONBIT_FFI_EXPORT
int32_t moonflow_operator_materialization_native_unlock_v1(int32_t handle) {
  int status = flock(handle, LOCK_UN);
  int error = status == 0 ? 0 : errno;
  close(handle);
  return error;
}
