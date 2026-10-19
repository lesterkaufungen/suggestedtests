import XCTest

@testable import SuggestedTests

final class TestDataTests: XCTestCase {
  func testTheSameSeedGivesTheSameValues() throws {
    let a = TestData(seed: 42)
    let b = TestData(seed: 42)
    XCTAssertEqual(try a.list(20) { $0.integer() }, try b.list(20) { $0.integer() })
    XCTAssertEqual(a.uuid(), b.uuid())
    XCTAssertEqual(a.email(), b.email())
    XCTAssertNotEqual(TestData(seed: 1).next(), TestData(seed: 2).next())
    // Pinned: a change to the generator would change every user's data.
    XCTAssertEqual(TestData(seed: 0).next(), 0xE220_A839_7B1D_CDAF)
  }

  func testValuesStayInRange() throws {
    let data = TestData(seed: 7)
    for _ in 0..<1000 {
      XCTAssertTrue((18...90).contains(data.integer(in: 18...90)))
      XCTAssertTrue((0..<1).contains(data.double()))
    }
    XCTAssertEqual(data.integer(in: 5...5), 5)
    XCTAssertTrue((Int.min...Int.max).contains(data.integer(in: Int.min...Int.max)))
    XCTAssertEqual(try data.string(length: 12).count, 12)
    XCTAssertTrue(try data.string(length: 50, alphabet: "ab").allSatisfy { "ab".contains($0) })
    XCTAssertTrue(try data.sentence(words: 3).hasSuffix("."))
    XCTAssertTrue(data.email().hasSuffix("@example.com"))
    XCTAssertEqual(Set(data.shuffled(Array(0..<10))), Set(0..<10))
    XCTAssertTrue([1, 2, 3].contains(try data.pick([1, 2, 3])))
  }

  func testUUIDsAreVersion4() {
    let uuid = TestData(seed: 3).uuid()
    XCTAssertNotNil(UUID(uuidString: uuid), uuid)
    let parts = uuid.split(separator: "-")
    XCTAssertEqual(parts.map(\.count), [8, 4, 4, 4, 12])
    XCTAssertEqual(parts[2].first, "4")
    XCTAssertTrue("89ab".contains(parts[3].first!))
  }

  func testArgumentsAreValidated() {
    let data = TestData()
    XCTAssertThrowsError(try data.string(length: -1)) {
      XCTAssertTrue($0 is SuggestedTestsArgumentError)
    }
    XCTAssertThrowsError(try data.string(length: 3, alphabet: "")) {
      XCTAssertTrue($0 is SuggestedTestsArgumentError)
    }
    XCTAssertThrowsError(try data.sentence(words: 0)) {
      XCTAssertTrue($0 is SuggestedTestsArgumentError)
    }
    XCTAssertThrowsError(try data.pick([Int]())) {
      XCTAssertTrue($0 is SuggestedTestsArgumentError)
    }
    XCTAssertThrowsError(try data.list(-1) { $0.bool() }) {
      XCTAssertTrue($0 is SuggestedTestsArgumentError)
    }
    XCTAssertEqual("\(TestData(seed: 9))", "TestData(seed: 9)")
  }
}
