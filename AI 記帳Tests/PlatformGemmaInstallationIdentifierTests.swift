import XCTest
@testable import AI_記帳

@MainActor
final class PlatformGemmaInstallationIdentifierTests: XCTestCase {
    func testExistingIdentifierDoesNotWriteAgain() throws {
        var writes = 0
        let value = try PlatformGemmaInstallationIdentifier.loadOrCreate(
            existing: " existing-id ",
            generate: { "generated-id" },
            persist: { _ in writes += 1; return true }
        )

        XCTAssertEqual(value, "existing-id")
        XCTAssertEqual(writes, 0)
    }

    func testNewIdentifierIsNotReturnedWhenPersistenceFails() {
        var attemptedValue: String?

        XCTAssertThrowsError(
            try PlatformGemmaInstallationIdentifier.loadOrCreate(
                existing: nil,
                generate: { "generated-id" },
                persist: { value in attemptedValue = value; return false }
            )
        ) { error in
            XCTAssertTrue(error is PlatformGemmaInstallationIdentifierError)
        }
        XCTAssertEqual(attemptedValue, "generated-id")
    }

    func testNewIdentifierReturnsOnlyAfterSuccessfulPersistence() throws {
        var persistedValue: String?
        let value = try PlatformGemmaInstallationIdentifier.loadOrCreate(
            existing: nil,
            generate: { "generated-id" },
            persist: { generated in persistedValue = generated; return true }
        )

        XCTAssertEqual(value, "generated-id")
        XCTAssertEqual(persistedValue, "generated-id")
    }
}
