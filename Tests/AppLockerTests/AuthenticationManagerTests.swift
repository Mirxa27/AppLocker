import Foundation
import XCTest
import CryptoKit
@testable import AppLocker

@MainActor
final class AuthenticationManagerTests: XCTestCase {
    
    var authManager: AuthenticationManager!
    
    override func setUp() async throws {
        authManager = AuthenticationManager.shared
        // Clear any existing state
        _ = authManager.resetAllData()
    }
    
    func testPasscodeSetupAndVerification() async {
        let testPasscode = "test1234"
        
        // Test initial setup
        XCTAssertTrue(authManager.setPasscode(testPasscode))
        XCTAssertTrue(authManager.isPasscodeSet())
        
        // Test verification
        XCTAssertTrue(authManager.verifyPasscode(testPasscode))
        XCTAssertFalse(authManager.verifyPasscode("wrongpasscode"))
    }
    
    func testPBKDF2KeyDerivation() async {
        let passcode = "testpasscode"
        let salt = Data("testsalt".utf8)
        
        let key1 = PBKDF2Helper.deriveKey(passcode: passcode, salt: salt)
        let key2 = PBKDF2Helper.deriveKey(passcode: passcode, salt: salt)
        
        XCTAssertNotNil(key1)
        XCTAssertNotNil(key2)
        XCTAssertEqual(key1, key2)
        XCTAssertEqual(key1?.count, PBKDF2Helper.keyLength)
    }
    
    func testFailedAttemptTracking() async {
        let testPasscode = "testpass"
        XCTAssertTrue(authManager.setPasscode(testPasscode))
        
        // Failed-attempt tracking is tied to authenticate(withPasscode:), not verifyPasscode.
        for _ in 1...4 {
            _ = authManager.authenticate(withPasscode: "wrong")
        }
        
        XCTAssertFalse(authManager.isLockedOut)
        
        // 5th attempt should trigger lockout (first threshold in lockoutDurations)
        _ = authManager.authenticate(withPasscode: "wrong")
        XCTAssertTrue(authManager.isLockedOut)
        XCTAssertNotNil(authManager.lockoutEndTime)
    }
    
    func testPasscodeChange() async {
        let oldPasscode = "oldpass123"
        let newPasscode = "newpass456"
        
        XCTAssertTrue(authManager.setPasscode(oldPasscode))
        
        // Test successful change
        let result = authManager.changePasscode(currentPasscode: oldPasscode, newPasscode: newPasscode)
        XCTAssertTrue(result.success)
        XCTAssertNil(result.error)
        
        // Test verification with new passcode
        XCTAssertTrue(authManager.verifyPasscode(newPasscode))
        XCTAssertFalse(authManager.verifyPasscode(oldPasscode))
    }
    
    func testBiometricAvailability() async {
        // LocalAuthentication can be slow on some hosts; we only require the call to return.
        _ = authManager.canUseBiometrics()
    }
    
    func testResetAllData() async {
        let testPasscode = "resetpass"
        XCTAssertTrue(authManager.setPasscode(testPasscode))
        
        // Make some failed attempts
        _ = authManager.authenticate(withPasscode: "wrong")
        XCTAssertEqual(authManager.failedAttempts, 1)
        
        // Reset everything
        XCTAssertTrue(authManager.resetAllData())
        
        // Verify reset
        XCTAssertFalse(authManager.isPasscodeSet())
        XCTAssertEqual(authManager.failedAttempts, 0)
        XCTAssertFalse(authManager.isLockedOut)
    }
    
    func testHashPasscodeForStorage() async {
        let testPasscode = "apppass123"
        
        // Mock the salt retrieval
        _ = authManager.setPasscode("dummy") // Set a dummy passcode to initialize salt
        
        let hash = authManager.hashPasscodeForStorage(testPasscode)
        XCTAssertNotNil(hash)
        XCTAssertFalse(hash?.isEmpty ?? true)
    }
    
    func testLockoutDurationEscalation() async {
        let testPasscode = "lockouttest"
        XCTAssertTrue(authManager.setPasscode(testPasscode))
        
        // First tier: 5 failed authentications → 30s lockout (see AuthenticationManager.lockoutDurations)
        for _ in 1...5 {
            _ = authManager.authenticate(withPasscode: "wrong")
        }
        XCTAssertTrue(authManager.isLockedOut)
        let remaining = authManager.lockoutRemainingSeconds
        XCTAssertGreaterThanOrEqual(remaining, 28)
        XCTAssertLessThanOrEqual(remaining, 30)
    }
}