import XCTest
@testable import ItsypadCore

final class KVSMigrationTests: XCTestCase {
    private let testFlagKey = "kvsTestMigrationFlag_\(UUID().uuidString)"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testFlagKey)
        super.tearDown()
    }

    func testSkipsWhenFlagAlreadySet() {
        UserDefaults.standard.set(true, forKey: testFlagKey)
        var importCalled = false

        _ = KVSMigration(flagKey: testFlagKey) { _ in
            importCalled = true
            return false
        }

        XCTAssertFalse(importCalled)
    }

    func testCallsImportDataOnInit() {
        var importCalled = false

        _ = KVSMigration(flagKey: testFlagKey) { _ in
            importCalled = true
            return true
        }

        XCTAssertTrue(importCalled)
    }

    func testDoesNotSetFlagWhenImportSucceeds() {
        // When importData returns true, the flag is set by the caller's import
        // function (not by KVSMigration), matching the existing behaviour where
        // importKVSTabs/importKVSClipboard sets the flag after successful import.
        _ = KVSMigration(flagKey: testFlagKey) { _ in
            return true
        }

        // KVSMigration itself does not set the flag on immediate success --
        // that's the caller's responsibility (done inside the import closure).
        // This verifies KVSMigration doesn't double-set.
        XCTAssertFalse(UserDefaults.standard.bool(forKey: testFlagKey))
    }

    func testDeinitRemovesObserver() {
        // When import returns false, an observer is registered.
        // Verify deinit doesn't crash (observer cleanup).
        var migration: KVSMigration? = KVSMigration(flagKey: testFlagKey) { _ in
            return false
        }
        XCTAssertNotNil(migration)
        migration = nil
        // If deinit observer cleanup failed, this test would crash
    }
}
