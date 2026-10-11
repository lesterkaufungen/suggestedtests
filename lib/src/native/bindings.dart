// Raw FFI bindings to the Rust bridge in `native/`. Mirrors
// `native/include/suggestedtests_native.h`; keep the two in sync.
//
// The asset id of this library (`package:suggestedtests/src/native/bindings.dart`)
// is the code asset name registered by `hook/build.dart`.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';

const stAbiVersion = 1;

const stOk = 0;
const stErrNull = -1;
const stErrUnsupported = -2;
const stErrUnknown = -3;

final class StCpuTime extends Struct {
  @Uint64()
  external int userNs;

  @Uint64()
  external int systemNs;
}

final class StMemory extends Struct {
  @Uint64()
  external int currentRssBytes;

  @Uint64()
  external int peakRssBytes;
}

@Native<Uint32 Function()>(symbol: 'st_abi_version', isLeaf: true)
external int stAbiVersionNative();

@Native<Int32 Function(Pointer<StCpuTime>)>(
  symbol: 'st_process_cpu_time',
  isLeaf: true,
)
external int stProcessCpuTime(Pointer<StCpuTime> out);

@Native<Int32 Function(Pointer<Uint64>)>(
  symbol: 'st_thread_cpu_time_ns',
  isLeaf: true,
)
external int stThreadCpuTimeNs(Pointer<Uint64> out);

@Native<Int32 Function(Pointer<StMemory>)>(
  symbol: 'st_memory_usage',
  isLeaf: true,
)
external int stMemoryUsage(Pointer<StMemory> out);

@Native<Uint32 Function()>(symbol: 'st_cpu_count', isLeaf: true)
external int stCpuCount();
