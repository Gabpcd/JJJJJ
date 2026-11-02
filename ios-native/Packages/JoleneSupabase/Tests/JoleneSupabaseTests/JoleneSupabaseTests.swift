import XCTest
@testable import JoleneSupabase

final class JoleneSupabaseTests: XCTestCase {
    func testSDK() { XCTAssertTrue(JoleneSupabase.sdk.hasPrefix("supabase-swift")) }
    func testSDKVersionIsPinned() { XCTAssertEqual(JoleneSupabase.sdk, "supabase-swift 2.55.5") }
}
