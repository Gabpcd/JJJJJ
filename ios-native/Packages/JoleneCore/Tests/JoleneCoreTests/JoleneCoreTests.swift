import XCTest
@testable import JoleneCore

final class JoleneCoreTests: XCTestCase {
    func testVersion() { XCTAssertEqual(JoleneCore.version, "2.0.0") }
}
