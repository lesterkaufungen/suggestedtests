import 'dart:ffi';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'native/bindings.dart' as native;

/// CPU time consumed by the process, split into user and kernel time.
@immutable
class CpuTime {
  /// Creates a CPU time sample.
  const CpuTime({required this.user, required this.system});

  /// Time spent running user-space code.
  final Duration user;

  /// Time spent in the kernel on behalf of the process.
  final Duration system;

  /// [user] + [system].
  Duration get total => user + system;

  /// The CPU time spent between [earlier] and this sample.
  CpuTime operator -(CpuTime earlier) =>
      CpuTime(user: user - earlier.user, system: system - earlier.system);

  @override
  bool operator ==(Object other) =>
      other is CpuTime && other.user == user && other.system == system;

  @override
  int get hashCode => Object.hash(user, system);

  @override
  String toString() =>
      'CpuTime(user: ${formatDuration(user)}, system: ${formatDuration(system)})';
}

/// Resident memory (RSS / working set) of the process, in bytes.
@immutable
class MemoryUsage {
  /// Creates a memory sample.
  const MemoryUsage({
    required this.currentRssBytes,
    required this.peakRssBytes,
  });

  /// Memory currently resident in RAM.
  final int currentRssBytes;

  /// Highest resident memory since the process started.
  final int peakRssBytes;

  @override
  bool operator ==(Object other) =>
      other is MemoryUsage &&
      other.currentRssBytes == currentRssBytes &&
      other.peakRssBytes == peakRssBytes;

  @override
  int get hashCode => Object.hash(currentRssBytes, peakRssBytes);

  @override
  String toString() =>
      'MemoryUsage(current: ${formatBytes(currentRssBytes)}, '
      'peak: ${formatBytes(peakRssBytes)})';
}

/// Thrown when the native bridge is missing or an OS call fails.
class NativeBridgeException implements Exception {
  /// Creates an exception for [operation] with status [code].
  NativeBridgeException(this.operation, this.code, [this.detail]);

  /// The bridge function that failed.
  final String operation;

  /// Bridge status: negative for bridge errors, positive for the raw OS error
  /// code (`errno` on Linux/macOS, `GetLastError()` on Windows).
  final int code;

  /// Extra context, if any.
  final String? detail;

  @override
  String toString() {
    final reason = switch (code) {
      native.stErrNull => 'null pointer',
      native.stErrUnsupported => 'not supported on this OS',
      native.stErrUnknown => 'unknown OS error',
      _ => 'OS error $code',
    };
    return 'NativeBridgeException: $operation failed: $reason'
        '${detail == null ? '' : '\n$detail'}';
  }
}

/// Process metrics read through the OS-agnostic Rust bridge (Windows, Linux
/// and macOS).
///
/// The bridge ships prebuilt for common desktop targets and is otherwise
/// built from source when `cargo` is installed. Check [isAvailable], or use
/// [skipReason] to skip tests where it isn't:
///
/// ```dart
/// test('no leak', skip: SystemProbe.skipReason, () async { ... });
/// ```
abstract final class SystemProbe {
  static String? _unavailable;
  static bool? _available;

  /// Whether the native bridge is loaded and has the expected ABI version.
  static bool get isAvailable => _available ??= _probe();

  /// `null` when [isAvailable]; otherwise why not. Pass to `test(skip:)`.
  static String? get skipReason => isAvailable ? null : _unavailable;

  static bool _probe() {
    try {
      final version = native.stAbiVersionNative();
      if (version != native.stAbiVersion) {
        _unavailable =
            'suggestedtests native bridge has ABI v$version, '
            'expected v${native.stAbiVersion}. Rebuild it.';
        return false;
      }
      try {
        // Best-effort and additive (no ABI bump): an older prebuilt that
        // predates this symbol must not make the whole bridge look
        // unavailable over it.
        native.stOnLoadNative();
      } on Object {
        // Ignored.
      }
      return true;
    } on Object catch (e) {
      _unavailable =
          'suggestedtests native bridge is not available for this '
          'platform. Install Rust (https://rustup.rs) so it can be built from '
          'source. ($e)';
      return false;
    }
  }

  static void _ensure(String operation) {
    if (!isAvailable) {
      throw NativeBridgeException(
        operation,
        native.stErrUnsupported,
        _unavailable,
      );
    }
  }

  static void _check(String operation, int status) {
    if (status != native.stOk) throw NativeBridgeException(operation, status);
  }

  /// CPU time used by the whole process (all threads) so far.
  static CpuTime processCpuTime() {
    _ensure('processCpuTime');
    final out = Struct.create<native.StCpuTime>();
    _check('processCpuTime', native.stProcessCpuTime(out.address));
    return CpuTime(
      user: Duration(microseconds: out.userNs ~/ 1000),
      system: Duration(microseconds: out.systemNs ~/ 1000),
    );
  }

  /// CPU time used by the calling OS thread so far.
  ///
  /// Only compare two samples taken without an `await` in between: an isolate
  /// may resume on a different OS thread after an asynchronous gap.
  static Duration threadCpuTime() {
    _ensure('threadCpuTime');
    final out = Uint64List(1);
    _check('threadCpuTime', native.stThreadCpuTimeNs(out.address));
    return Duration(microseconds: out[0] ~/ 1000);
  }

  /// Current and peak resident memory of the process.
  static MemoryUsage memoryUsage() {
    _ensure('memoryUsage');
    final out = Struct.create<native.StMemory>();
    _check('memoryUsage', native.stMemoryUsage(out.address));
    return MemoryUsage(
      currentRssBytes: out.currentRssBytes,
      peakRssBytes: out.peakRssBytes,
    );
  }

  /// Number of logical CPUs available to the process.
  static int get cpuCount {
    _ensure('cpuCount');
    return native.stCpuCount();
  }

  /// Turns the bridge's startup report on or off; returns the previous
  /// setting.
  ///
  /// The report is three `suggestedtests: ...` lines on stderr describing the
  /// platform and environment (OS, arch, libc, container, VM). It is printed
  /// at most once per process; turning verbose on prints it now if it hasn't
  /// been printed. Verbose controls nothing else. To get it when the bridge
  /// loads, run the tests with `SUGGESTEDTESTS_VERBOSE=1`:
  ///
  /// ```dart
  /// setUpAll(() => SystemProbe.setVerbose(true));
  /// ```
  static bool setVerbose(bool verbose) {
    _ensure('setVerbose');
    return native.stSetVerbose(verbose ? 1 : 0) != 0;
  }

  /// Whether the bridge's startup report is on (see [setVerbose]).
  static bool get verbose {
    _ensure('verbose');
    return native.stVerbose() != 0;
  }
}

/// Formats [duration] the way failure messages do, e.g. `850µs`, `12.50ms`
/// or `1.25s`.
String formatDuration(Duration duration) {
  final us = duration.inMicroseconds;
  if (us.abs() < 1000) return '$usµs';
  if (us.abs() < 1000000) return '${(us / 1000).toStringAsFixed(2)}ms';
  return '${(us / 1000000).toStringAsFixed(2)}s';
}

/// Formats [bytes] as a human readable size, e.g. `12.5 MiB`.
String formatBytes(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.abs().toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '$bytes B';
  final sign = bytes < 0 ? '-' : '';
  return '$sign${value.toStringAsFixed(1)} ${units[unit]}';
}
