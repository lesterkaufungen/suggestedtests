import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

void main() {
  test('same seed produces the same values', () {
    List<Object> sample(TestData d) =>
        [d.integer(), d.string(), d.email(), d.uuid(), d.date()];
    expect(sample(TestData(7)), sample(TestData(7)));
    expect(sample(TestData(7)), isNot(sample(TestData(8))));
  });

  test('integer is inclusive and validated', () {
    final d = TestData();
    final values = d.listOf(500, (d) => d.integer(1, 3)).toSet();
    expect(values, {1, 2, 3});
    expect(() => d.integer(5, 1), throwsArgumentError);
  });

  test('formats', () {
    final d = TestData(1);
    expect(d.string(length: 4), hasLength(4));
    expect(d.email(), matches(RegExp(r'^[a-z]+\.[a-z]{5}@example\.com$')));
    expect(
      d.uuid(),
      matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
    expect(d.sentence(3), matches(RegExp(r'^[A-Z][a-z]+( [a-z]+){2}\.$')));
  });

  test('date stays in range', () {
    final d = TestData(3);
    final from = DateTime.utc(2024);
    final to = DateTime.utc(2024, 2);
    for (var i = 0; i < 100; i++) {
      final date = d.date(from: from, to: to);
      expect(date.isBefore(from), isFalse);
      expect(date.isAfter(to), isFalse);
    }
  });

  test('pick and shuffled', () {
    final d = TestData(4);
    expect([1, 2, 3], contains(d.pick([1, 2, 3])));
    expect(() => d.pick(<int>[]), throwsArgumentError);
    expect(d.shuffled([1, 2, 3, 4]), unorderedEquals([1, 2, 3, 4]));
  });

  test('randomSeed exposes its seed', () {
    final d = TestData.randomSeed();
    expect(TestData(d.seed).integer(), d.integer());
  });
}
