import 'package:flutter_test/flutter_test.dart';
import 'native/preload.dart';

/// Base class for function spies: records every call's positional arguments.
///
/// Use [Spy0], [Spy1] or [Spy2] to create one, pass it wherever a callback is
/// expected, then assert with [wasCalled], [wasCalledTimes], [wasCalledWith]
/// or [wasNotCalled]. No code generation or mocking framework needed.
abstract class Spy {
  final List<List<Object?>> _calls = [];

  /// Arguments of every call, oldest first.
  List<List<Object?>> get calls => List.unmodifiable(_calls);

  /// Number of calls so far.
  int get callCount => _calls.length;

  /// Whether the spy was called at least once.
  bool get called => _calls.isNotEmpty;

  /// Arguments of the most recent call. Throws if never called.
  List<Object?> get lastCall {
    if (_calls.isEmpty) throw StateError('Spy was never called');
    return _calls.last;
  }

  /// Forgets all recorded calls.
  void reset() => _calls.clear();

  void _record(List<Object?> args) => _calls.add(List.unmodifiable(args));

  @override
  String toString() => '$runtimeType(calls: $_calls)';
}

/// Spy for a zero-argument function.
///
/// ```dart
/// final onTap = Spy0<void>(() {});
/// await tester.pumpApp(ElevatedButton(onPressed: onTap.call, child: ...));
/// await tester.tapAndSettle(find.byType(ElevatedButton));
/// expect(onTap, wasCalledTimes(1));
/// ```
class Spy0<R> extends Spy {
  /// Creates a spy that delegates to [impl].
  Spy0(this.impl) {
    preloadNativeBridge();
  }

  /// The implementation invoked on each call.
  final R Function() impl;

  /// Records the call and delegates to [impl].
  R call() {
    _record(const []);
    return impl();
  }
}

/// Spy for a one-argument function.
class Spy1<A, R> extends Spy {
  /// Creates a spy that delegates to [impl].
  Spy1(this.impl) {
    preloadNativeBridge();
  }

  /// The implementation invoked on each call.
  final R Function(A a) impl;

  /// Records the call and delegates to [impl].
  R call(A a) {
    _record([a]);
    return impl(a);
  }
}

/// Spy for a two-argument function.
class Spy2<A, B, R> extends Spy {
  /// Creates a spy that delegates to [impl].
  Spy2(this.impl) {
    preloadNativeBridge();
  }

  /// The implementation invoked on each call.
  final R Function(A a, B b) impl;

  /// Records the call and delegates to [impl].
  R call(A a, B b) {
    _record([a, b]);
    return impl(a, b);
  }
}

/// Matches a [Spy] that was called at least once.
const Matcher wasCalled = _SpyMatcher._called();

/// Matches a [Spy] that was never called.
const Matcher wasNotCalled = _SpyMatcher._times(0);

/// Matches a [Spy] called exactly [times] times.
Matcher wasCalledTimes(int times) => _SpyMatcher._times(times);

/// Matches a [Spy] that has at least one call whose arguments match [args].
/// Each element may be a value or a [Matcher].
///
/// ```dart
/// expect(onChanged, wasCalledWith(['hello']));
/// expect(onResize, wasCalledWith([greaterThan(0), anything]));
/// ```
Matcher wasCalledWith(List<Object?> args) => _SpyMatcher._with(args);

class _SpyMatcher extends Matcher {
  const _SpyMatcher._called() : _times = null, _args = null;
  const _SpyMatcher._times(int times) : _times = times, _args = null;
  const _SpyMatcher._with(List<Object?> args) : _times = null, _args = args;

  final int? _times;
  final List<Object?>? _args;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! Spy) return false;
    if (_args case final args?) {
      final m = equals(args);
      return item._calls.any((c) => m.matches(c, {}));
    }
    if (_times case final times?) return item.callCount == times;
    return item.called;
  }

  @override
  Description describe(Description description) {
    if (_args != null) {
      return description.add('a spy called with ').addDescriptionOf(_args);
    }
    if (_times == 0) return description.add('a spy that was never called');
    if (_times != null) {
      return description.add('a spy called $_times time(s)');
    }
    return description.add('a spy called at least once');
  }

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (item is! Spy) return mismatchDescription.add('is not a Spy');
    return mismatchDescription
        .add('was called ${item.callCount} time(s) with ')
        .addDescriptionOf(item._calls);
  }
}
