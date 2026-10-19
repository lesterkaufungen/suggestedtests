import Foundation
import XCTest

// SystemRandomNumberGenerator can't be seeded, so a reproducible test needs its own.
struct SplitMix64: RandomNumberGenerator {
  var state: UInt64

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

final class SignupTests: XCTestCase {
  func testSignupAcceptsGeneratedUsers() {
    var random = SplitMix64(state: 42)
    func word() -> String {
      let letters = Array("abcdefghijklmnopqrstuvwxyz")
      return String(
        (0..<Int.random(in: 4...8, using: &random)).map { _ in
          letters.randomElement(using: &random)!
        })
    }
    var bytes = (0..<16).map { _ in UInt8.random(in: 0...255, using: &random) }
    bytes[6] = bytes[6] & 0x0F | 0x40
    bytes[8] = bytes[8] & 0x3F | 0x80
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    let id = [
      hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
      hex.dropFirst(16).prefix(4), hex.dropFirst(20),
    ]
    .joined(separator: "-")
    let user = User(
      id: id, name: word(), email: "\(word()).\(word())@example.com",
      age: Int.random(in: 18...90, using: &random))
    XCTAssertTrue(signup(user))
  }
}
