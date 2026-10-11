import 'package:flutter_test/flutter_test.dart';

/// Matches an [Iterable] with no duplicate elements (by `==`).
const Matcher hasUniqueElements = _HasUniqueElements();

class _HasUniqueElements extends Matcher {
  const _HasUniqueElements();

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! Iterable) return false;
    final seen = <Object?>{};
    for (final e in item) {
      if (!seen.add(e)) {
        matchState['duplicate'] = e;
        return false;
      }
    }
    return true;
  }

  @override
  Description describe(Description description) =>
      description.add('an iterable with unique elements');

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (item is! Iterable) {
      return mismatchDescription.add('is not an Iterable');
    }
    return mismatchDescription
        .add('contains duplicate ')
        .addDescriptionOf(matchState['duplicate']);
  }
}
