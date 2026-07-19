#include <errno.h>
#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>

MOONBIT_FFI_EXPORT
int32_t moonflow_operator_materialization_native_rename_v1(
    moonbit_bytes_t source,
    moonbit_bytes_t destination) {
  if (rename((const char *)source, (const char *)destination) == 0) {
    return 0;
  }
  return errno;
}
