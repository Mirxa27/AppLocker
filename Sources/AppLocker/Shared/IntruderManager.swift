import Foundation
import AVFoundation

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
                }
            }
        default:
            print("Camera access denied")
        }
    }

    private func configureSession() {
        guard !isSessionConfigured else { return }

        captureSession.beginConfiguration()

        // Input
        #if os(macOS)
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("No camera available")
            captureSession.commitConfiguration()
            return
        }
        #else
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("No front camera available")
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
            let salt = try CryptoHelper.getOrCreateSalt(keychainKey: "intruder-photos")
            let key  = CryptoHelper.deriveKey(passcode: "intruder", salt: salt, context: "intruder")
            let encrypted = try CryptoHelper.encrypt(data, using: key)
            try encrypted.write(to: url)
        } catch {
            print("IntruderManager: failed to save encrypted photo: \(error)")
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
              let salt = CryptoHelper.loadSaltFromKeychain(key: "intruder-photos") else { return nil }
        let key = CryptoHelper.deriveKey(passcode: "intruder", salt: salt, context: "intruder")
        return try? CryptoHelper.decrypt(encrypted, using: key)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension IntruderManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.stopRunning()
        }

        guard let imageData = photo.fileDataRepresentation() else { return }

        // Save locally
        saveIntruderPhoto(data: imageData)

        // Notify
        NotificationManager.shared.sendCrossDeviceNotification(appName: "AppLocker", bundleID: "com.applocker.intruder", isFailed: true)
    }
}
