import Foundation

/// Seeded, reproducible fake data: the same seed gives the same values on
/// every platform and Swift version (it uses its own SplitMix64 generator).
///
/// ```swift
/// let data = TestData(seed: 42)
/// let user = User(name: data.word(), email: data.email(), age: data.integer(in: 18...90))
/// ```
///
/// Print ``seed`` in a failure message (or use ``description``) so a failing
/// run can be reproduced.
public final class TestData: CustomStringConvertible {
  /// The seed this generator was created with.
  public let seed: UInt64
  private var state: UInt64

  /// Creates a generator. Defaults to seed `0`.
  public init(seed: UInt64 = 0) {
    NativeBridge.preload()
    self.seed = seed
    self.state = seed
  }

  /// Creates a generator with a random seed; read ``seed`` to reproduce it.
  public static func randomSeed() -> TestData {
    TestData(seed: UInt64.random(in: 0...UInt64.max))
  }

  /// `TestData(seed: 42)`.
  public var description: String { "TestData(seed: \(seed))" }

  /// The next 64 random bits.
  public func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// An integer in `range` (inclusive).
  public func integer(in range: ClosedRange<Int> = 0...100) -> Int {
    let span = UInt64(bitPattern: Int64(range.upperBound) &- Int64(range.lowerBound)) &+ 1
    let offset = span == 0 ? next() : uniform(below: span)
    return Int(Int64(range.lowerBound) &+ Int64(bitPattern: offset))
  }

  /// A double in `0..<1`.
  public func double() -> Double {
    Double(next() >> 11) / Double(UInt64(1) << 53)
  }

  /// `true` or `false`.
  public func bool() -> Bool {
    next() >> 63 == 1
  }

  /// `length` characters from `alphabet` (letters and digits by default).
  public func string(length: Int = 10, alphabet: String = TestData.alphanumeric) throws -> String {
    if length < 0 { throw SuggestedTestsArgumentError("length must be >= 0, got \(length)") }
    let characters = Array(alphabet)
    if characters.isEmpty, length > 0 { throw SuggestedTestsArgumentError("alphabet is empty") }
    return String(
      (0..<length).map { _ in characters[Int(uniform(below: UInt64(characters.count)))] })
  }

  /// A lowercase word.
  public func word() -> String {
    TestData.words[Int(uniform(below: UInt64(TestData.words.count)))]
  }

  /// `words` words, the first capitalized, ending in a full stop.
  public func sentence(words: Int = 6) throws -> String {
    if words < 1 { throw SuggestedTestsArgumentError("words must be >= 1, got \(words)") }
    let text = (0..<words).map { _ in word() }.joined(separator: " ")
    return text.prefix(1).uppercased() + text.dropFirst() + "."
  }

  /// An address like `delta.qwxyz@example.com`.
  public func email() -> String {
    "\(word()).\((try? string(length: 5, alphabet: "abcdefghijklmnopqrstuvwxyz")) ?? "")@example.com"
  }

  /// A random (version 4) UUID string, lowercase.
  public func uuid() -> String {
    var bytes = (0..<16).map { _ in UInt8(truncatingIfNeeded: next()) }
    bytes[6] = bytes[6] & 0x0F | 0x40
    bytes[8] = bytes[8] & 0x3F | 0x80
    let hex = bytes.map {
      String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16)
    }
    return [0..<4, 4..<6, 6..<8, 8..<10, 10..<16].map { hex[$0].joined() }.joined(separator: "-")
  }

  /// A date in `range` (default 2000-01-01 to 2030-01-01 UTC).
  public func date(
    in range: ClosedRange<Date> = Date(
      timeIntervalSince1970: 946_684_800)...Date(
        timeIntervalSince1970: 1_893_456_000)
  ) -> Date {
    range.lowerBound.addingTimeInterval(
      double() * range.upperBound.timeIntervalSince(range.lowerBound))
  }

  /// One of `options`.
  public func pick<T>(_ options: [T]) throws -> T {
    if options.isEmpty { throw SuggestedTestsArgumentError("options is empty") }
    return options[Int(uniform(below: UInt64(options.count)))]
  }

  /// `count` values made by `generate`.
  public func list<T>(_ count: Int, _ generate: (TestData) throws -> T) throws -> [T] {
    if count < 0 { throw SuggestedTestsArgumentError("count must be >= 0, got \(count)") }
    return try (0..<count).map { _ in try generate(self) }
  }

  /// `items` in a random order.
  public func shuffled<T>(_ items: [T]) -> [T] {
    var result = items
    for i in stride(from: result.count - 1, to: 0, by: -1) {
      result.swapAt(i, Int(uniform(below: UInt64(i + 1))))
    }
    return result
  }

  /// Letters and digits, the default alphabet of ``string(length:alphabet:)``.
  public static let alphanumeric = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

  /// A value in `0..<bound` without modulo bias (Lemire's method).
  private func uniform(below bound: UInt64) -> UInt64 {
    let threshold = (0 &- bound) % bound
    while true {
      let product = next().multipliedFullWidth(by: bound)
      if product.low >= threshold { return product.high }
    }
  }

  private static let words = [
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet",
    "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo", "sierra", "tango",
    "uniform", "victor", "whiskey", "xray", "yankee", "zulu", "amber", "basil", "cedar", "dune",
    "ember", "fern", "grove", "harbor", "iris", "jade", "koala", "lotus", "maple", "nectar",
  ]
}
