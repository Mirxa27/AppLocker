// Sources/AppLocker/iOS/ScreenPrivacy/iOSScreenPrivacyView.swift
#if os(iOS)
import SwiftUI

struct iOSScreenPrivacyView: View {
    @StateObject private var vm = iOSScreenPrivacyManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    protectionCard
                    configCard
                    historyCard
                }
                .padding(16)
            }
            .appScreenBackground()
            .navigationTitle("Screen Privacy")
            .toolbar {
                if !vm.recentScreenshots.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") {
                            vm.clearHistory()
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current Status")
                    .font(.headline)
                Spacer()
                if vm.isScreenBeingRecorded {
                    AppStatusBadge(text: "Recording", color: AppDesign.danger)
                } else {
                    AppStatusBadge(text: "Safe", color: AppDesign.success)
                }
            }

            if vm.isScreenBeingRecorded {
                HStack(spacing: 8) {
                    Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                        .foregroundStyle(AppDesign.danger)
                    Text("Screen recording is active. App content has been hidden.")
                        .font(.subheadline)
                        .foregroundStyle(AppDesign.danger)
                }
            }

            if vm.screenshotDetected {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(AppDesign.warning)
                    Text("Screenshot detected!")
                        .font(.subheadline)
                        .foregroundStyle(AppDesign.warning)
                }
            }
        }
        .appSurface()
    }

    private var protectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Protection Methods")
                .font(.headline)

            statusRow(
                label: "Recording Detection",
                icon: "eye.trianglebadge.exclamationmark",
                active: vm.isRecordingDetectionEnabled
            )
            statusRow(
                label: "Screenshot Tracking",
                icon: "camera.fill",
                active: vm.isScreenshotProtectionEnabled
            )
            statusRow(
                label: "Hide Content on Background",
                icon: "eye.slash.fill",
                active: vm.hideContentOnBackground
            )
            statusRow(
                label: "Auto-Lock on Recording",
                icon: "lock.shield.fill",
                active: vm.autoLockOnRecording
            )
        }
        .appSurface()
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            Toggle(isOn: $vm.isRecordingDetectionEnabled) {
                Label("Recording Detection", systemImage: "eye.trianglebadge.exclamationmark")
            }

            Toggle(isOn: $vm.isScreenshotProtectionEnabled) {
                Label("Screenshot Protection", systemImage: "camera.fill")
            }

            Toggle(isOn: $vm.hideContentOnBackground) {
                Label("Hide on Background", systemImage: "eye.slash.fill")
            }

            Toggle(isOn: $vm.autoLockOnRecording) {
                Label("Auto-Lock on Recording", systemImage: "lock.shield.fill")
            }
        }
        .appSurface()
    }

    @ViewBuilder
    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Screenshot History")
                    .font(.headline)
                Spacer()
                AppStatusBadge(
                    text: "\(vm.screenshotCountThisWeek) this week",
                    color: AppDesign.warning
                )
            }

            if vm.recentScreenshots.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "camera.badge.ellipsis")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No Screenshots Detected")
                        .font(.title3.weight(.semibold))
                    Text("Screenshots taken while the app is open will be logged here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(vm.recentScreenshots.prefix(10), id: \.self) { date in
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(AppDesign.warning)
                            .frame(width: 22)
                        Text(date.formatted(date: .abbreviated, time: .standard))
                            .font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .appSurface()
    }

    private func statusRow(label: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(active ? AppDesign.success : .secondary)
                .frame(width: 18)
            Text(label)
                .font(.subheadline)
            Spacer(minLength: 0)
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(active ? AppDesign.success : .secondary)
                .font(.caption)
        }
    }
}
#endif
