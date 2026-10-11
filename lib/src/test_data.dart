import 'dart:math';

const _lower = 'abcdefghijklmnopqrstuvwxyz';
const _alphanumeric =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const _words = [
  'alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel', //
  'india', 'juliet', 'kilo', 'lima', 'mike', 'november', 'oscar', 'papa',
  'quebec', 'romeo', 'sierra', 'tango', 'uniform', 'victor', 'whiskey',
  'xray', 'yankee', 'zulu',
];

/// Deterministic random test data.
///
/// The same [seed] always produces the same sequence of values, so a failing
/// test can be reproduced exactly. Print or log [seed] when using a random one.
///
/// ```dart
/// final data = TestData(42);
/// final user = User(name: data.word(), email: data.email(), age: data.integer(18, 90));
/// ```
class TestData {
  /// Creates a generator. Defaults to seed `0`.
  TestData([this.seed = 0]) : _random = Random(seed);

  /// Creates a generator with a random seed. Read [seed] to reproduce it.
  factory TestData.randomSeed() => TestData(Random().nextInt(1 << 31));

  /// The seed this generator was created with.
  final int seed;

  final Random _random;

  /// An integer in `[min, max]` (inclusive).
  int integer([int min = 0, int max = 100]) {
    if (max < min) throw ArgumentError('max ($max) < min ($min)');
    return min + _random.nextInt(max - min + 1);
  }

  /// A double in `[min, max)`.
  double decimal([double min = 0, double max = 1]) =>
      min + _random.nextDouble() * (max - min);

  /// `true` with probability [probability].
  bool boolean([double probability = 0.5]) =>
      _random.nextDouble() < probability;

  /// A string of [length] characters drawn from [alphabet].
  String string({int length = 10, String alphabet = _alphanumeric}) {
    if (alphabet.isEmpty) throw ArgumentError('alphabet must not be empty');
    return String.fromCharCodes(
      List.generate(
        length,
        (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
      ),
    );
  }

  /// A short lowercase word.
  String word() => pick(_words);

  /// A sentence of [words] words, capitalised and ending with a period.
  String sentence([int words = 6]) {
    if (words < 1) throw RangeError.value(words, 'words');
    final s = List.generate(words, (_) => word()).join(' ');
    return '${s[0].toUpperCase()}${s.substring(1)}.';
  }

  /// A syntactically valid email address on the reserved `example.com` domain.
  String email() =>
      '${word()}.${string(length: 5, alphabet: _lower)}@example.com';

  /// A version 4 UUID string.
  String uuid() {
    final b = List.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// A UTC [DateTime] between [from] (default 2000-01-01) and [to]
  /// (default 2030-01-01).
  DateTime date({DateTime? from, DateTime? to}) {
    final start = (from ?? DateTime.utc(2000)).microsecondsSinceEpoch;
    final end = (to ?? DateTime.utc(2030)).microsecondsSinceEpoch;
    if (end < start) throw ArgumentError('to is before from');
    final offset = (_random.nextDouble() * (end - start)).floor();
    return DateTime.fromMicrosecondsSinceEpoch(start + offset, isUtc: true);
  }

  /// A random element of [options].
  T pick<T>(List<T> options) {
    if (options.isEmpty) throw ArgumentError('options must not be empty');
    return options[_random.nextInt(options.length)];
  }

  /// [count] values produced by [generate].
  List<T> listOf<T>(int count, T Function(TestData data) generate) =>
      List.generate(count, (_) => generate(this));

  /// A shuffled copy of [items].
  List<T> shuffled<T>(Iterable<T> items) => [...items]..shuffle(_random);
}
