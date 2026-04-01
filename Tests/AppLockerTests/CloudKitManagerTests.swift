import XCTest
@testable import AppLocker

final class CloudKitManagerTests: XCTestCase {
    @MainActor
    func testHandleRemoteNotificationAcceptsEmptyPayload() async {
        await CloudKitManager.shared.handleRemoteNotification([:])
    }

    @MainActor
    func testHandleRemoteNotificationAcceptsAPSStylePayload() async {
        let aps: [String: Any] = ["content-available": 1]
        let userInfo: [AnyHashable: Any] = ["aps": aps]
        await CloudKitManager.shared.handleRemoteNotification(userInfo)
    }
}
