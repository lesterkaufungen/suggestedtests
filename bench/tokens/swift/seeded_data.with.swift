import SuggestedTests
import XCTest

final class SignupTests: XCTestCase {
  func testSignupAcceptsGeneratedUsers() {
    let data = TestData(seed: 42)
    let user = User(
      id: data.uuid(), name: data.word(), email: data.email(), age: data.integer(in: 18...90))
    XCTAssertTrue(signup(user))
  }
}
