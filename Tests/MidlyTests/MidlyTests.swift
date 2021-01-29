import XCTest
@testable import Midly

final class MidlyTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Midly().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
