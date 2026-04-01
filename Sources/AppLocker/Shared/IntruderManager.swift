import Foundation
import AVFoundation
import CryptoKit
import Security

#if os(macOS)
import AppKit
#else
import UIKit
#endif

class IntruderManager: NSObject {
    static let shared = IntruderManager()

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var isSessionConfigured = false
    private let keychainService = "com.mirxa.AppLocker.intruder"
    private let keychainAccount = "intruder-photo-key"

    override private init() {
        super.init()
        checkPermissions()
    }

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.configureSession()
                    }
                } else {
                    AppLogger.intruder.error("Camera permission request denied")
                }
            }
        default:
            AppLogger.intruder.error("Camera access denied")
        }
    }

    private func configureSession() {
        guard !isSessionConfigured else { return }

        captureSession.beginConfiguration()

        // Input
        #if os(macOS)
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            AppLogger.intruder.error("No camera available")
            captureSession.commitConfiguration()
            return
        }
        #else
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            AppLogger.intruder.error("No front camera available")
            captureSession.commitConfiguration()
            return
        }
        #endif

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // Output
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()
        isSessionConfigured = true
    }

    func captureIntruder() {
        guard isSessionConfigured else {
            checkPermissions()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            // Give the camera a moment to adjust
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let settings = AVCapturePhotoSettings()
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func saveIntruderPhoto(data: Data) {
        let filename = "intruder-\(Date().timeIntervalSince1970).aplkimg"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url  = docs.appendingPathComponent(filename)

        do {
            let key = try loadOrCreateIntruderKey()
            let encrypted = try CryptoHelper.encrypt(data, using: key)
            try encrypted.write(to: url)
        } catch {
            AppLogger.intruder.error("Failed to save encrypted intruder photo: \(error.localizedDescription, privacy: .public)")
        }
    }

    func getIntruderPhotos() -> [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(
                at: docs, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "aplkimg" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func decryptIntruderPhoto(url: URL) -> Data? {
        guard let encrypted = try? Data(contentsOf: url),
              let key = try? loadOrCreateIntruderKey() else { return nil }
        return try? CryptoHelper.decrypt(encrypted, using: key)
    }

    private func loadOrCreateIntruderKey() throws -> SymmetricKey {
        if let existing = try loadKeyMaterialFromKeychain() {
            return SymmetricKey(data: existing)
        }

        let material = try CryptoHelper.randomSalt()
        try saveKeyMaterialToKeychain(material)
        return SymmetricKey(data: material)
    }

    private func loadKeyMaterialFromKeychain() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain lookup failed (\(status))"]
            )
        }
    }

    private func saveKeyMaterialToKeychain(_ material: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = material
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain save failed (\(status))"]
            )
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension IntruderManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.stopRunning()
        }

        guard let imageData = photo.fileDataRepresentation() else { return }

        // Save encrypted copy locally (AES-GCM at rest)
        saveIntruderPhoto(data: imageData)

        // Upload original JPEG to CloudKit so iOS companion can display it.
        // CloudKit encrypts data in transit and at rest; the local .aplkimg remains
        // separately encrypted for defence-in-depth on-device.
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("intruder-upload-\(UUID().uuidString).jpg")
        if (try? imageData.write(to: tmpURL)) != nil {
            Task { @MainActor in
                CloudKitManager.shared.publishFailedAuth(
                    appName: "AppLocker",
                    bundleID: "com.applocker.intruder",
                    encryptedPhotoURL: tmpURL
                )
            }
        }

        // Notify via iCloud KV
        NotificationManager.shared.sendCrossDeviceNotification(appName: "AppLocker", bundleID: "com.applocker.intruder", isFailed: true)
    }
}
