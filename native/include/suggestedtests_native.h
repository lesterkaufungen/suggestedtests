/*
 * C ABI of the suggestedtests native bridge (native/src/lib.rs).
 * Identical on Windows, Linux and macOS.
 *
 * Status codes: 0 = ok, <0 = bridge error, >0 = OS error code
 * (errno on Unix, GetLastError() on Windows).
 */
#ifndef SUGGESTEDTESTS_NATIVE_H
#define SUGGESTEDTESTS_NATIVE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ST_ABI_VERSION 1u

#define ST_OK 0
#define ST_ERR_NULL (-1)
#define ST_ERR_UNSUPPORTED (-2)
#define ST_ERR_UNKNOWN (-3)

typedef struct StCpuTime {
  uint64_t user_ns;
  uint64_t system_ns;
} StCpuTime;

typedef struct StMemory {
  uint64_t current_rss_bytes;
  uint64_t peak_rss_bytes;
} StMemory;

uint32_t st_abi_version(void);
int32_t st_process_cpu_time(StCpuTime *out);
int32_t st_thread_cpu_time_ns(uint64_t *out);
int32_t st_memory_usage(StMemory *out);
uint32_t st_cpu_count(void);

#ifdef __cplusplus
}
#endif

#endif /* SUGGESTEDTESTS_NATIVE_H */
