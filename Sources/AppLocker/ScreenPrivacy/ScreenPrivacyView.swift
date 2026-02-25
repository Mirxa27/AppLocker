// Sources/AppLocker/ScreenPrivacy/ScreenPrivacyView.swift
#if os(macOS)
import SwiftUI

struct ScreenPrivacyView: View {
    @ObservedObject var manager = ScreenPrivacyManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Screen Privacy").font(.headline)

            HStack {
                Image(systemName: manager.isWindowProtected ? "eye.slash.fill" : "eye")
                    .font(.title2).foregroundColor(manager.isWindowProtected ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.isWindowProtected ? "Window Protected" : "Window Unprotected")
                        .fontWeight(.semibold)
                    Text(manager.isWindowProtected
                         ? "AppLocker is invisible in screenshots and screen recordings."
                         : "Apply protection to hide this window from screen capture.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if !manager.isWindowProtected {
                    Button("Apply Protection") { manager.applyWindowProtection() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Lock on Recording Detected").fontWeight(.medium)
                    Text("Immediately locks AppLocker when a screen recorder is detected.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $manager.autoLockOnRecording).toggleStyle(.switch).labelsHidden()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Detected Capture Processes").font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button { manager.scanForRecorders() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain)
                }
                if manager.detectedRecorders.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                        Text("No screen capture apps detected").font(.caption)
                    }
                } else {
                    ForEach(manager.detectedRecorders, id: \.self) { name in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text(name).font(.caption).foregroundColor(.red)
                        }
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            Spacer()
        }
        .padding()
    }
}
#endif
