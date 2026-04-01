// Sources/AppLocker/iOS/Dashboard/DashboardView.swift
#if os(iOS)
import SwiftUI

struct DashboardView: View {
    @ObservedObject private var kv         = KVStoreManager.shared
    @ObservedObject private var protection = AppProtectionManager.shared
    @ObservedObject private var lockManager = iOSAppLockManager.shared
    @ObservedObject private var focusManager = iOSFocusModeManager.shared

    private var recentBlocks: [AlertRecord] {
        Array(kv.alertHistory.filter { $0.type.contains("block") }.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    deviceCard
                    quickActionsCard
                    metricsCard
                    securityCard
                    focusStatusCard
                    recentBlocksCard
                }
                .padding(16)
            }
            .appScreenBackground()
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        kv.decodeAllKeys()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                kv.decodeAllKeys()
            }
        }
    }

    // MARK: - Device Card

    @ViewBuilder
    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mac Device")
                        .font(.headline)
                    if let device = kv.lastMacDevice {
                        Text(device)
                            .font(.title3.weight(.semibold))
                        if let sync = kv.lastSyncTime {
                            Text("Last seen \(sync.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No Mac connected")
                            .font(.title3.weight(.semibold))
                        Text("Open AppLocker on your Mac to enable remote status and controls.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                AppStatusBadge(
                    text: kv.lastMacDevice == nil ? "Disconnected" : "Connected",
                    color: kv.lastMacDevice == nil ? AppDesign.warning : AppDesign.success
                )
            }
        }
        .appSurface()
    }

    // MARK: - Quick Actions

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                quickActionButton(
                    title: "Lock All",
                    icon: "lock.fill",
                    color: AppDesign.danger
                ) {
                    lockManager.lockAll()
                }

                quickActionButton(
                    title: "Focus",
                    icon: "timer",
                    color: AppDesign.accent
                ) {
                    if !focusManager.isActive {
                        focusManager.startFocus(profile: .work)
                    }
                }

                quickActionButton(
                    title: "Clear Clipboard",
                    icon: "doc.on.clipboard",
                    color: AppDesign.warning
                ) {
                    iOSClipboardGuard.shared.clearNow()
                }

                quickActionButton(
                    title: "Lock App",
                    icon: "lock.shield.fill",
                    color: AppDesign.accentSecondary
                ) {
                    protection.lock()
                }
            }
        }
        .appSurface()
    }

    private func quickActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metrics

    private var metricsCard: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 155), spacing: 12)],
            spacing: 12
        ) {
            AppMetricCard(
                title: "Locked Apps",
                value: "\(kv.lockedApps.count)",
                subtitle: kv.lockedApps.count == 1 ? "app protected" : "apps protected",
                icon: "lock.app.dashed",
                color: AppDesign.warning
            )
            AppMetricCard(
                title: "Local Locks",
                value: "\(lockManager.lockedAppCount)",
                subtitle: "on this device",
                icon: "lock.fill",
                color: AppDesign.accent
            )
            AppMetricCard(
                title: "Total Alerts",
                value: "\(kv.alertHistory.count)",
                subtitle: "security events",
                icon: "bell.badge.fill",
                color: AppDesign.accent
            )
            AppMetricCard(
                title: "Failed Auth",
                value: "\(kv.alertHistory.filter { $0.type.contains("fail") }.count)",
                subtitle: "intruder attempts",
                icon: "exclamationmark.triangle.fill",
                color: AppDesign.danger
            )
        }
    }

    // MARK: - Security Card

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iOS Security")
                .font(.headline)
            statusRow(
                label: protection.isJailbroken ? "Jailbreak detected" : "Device integrity OK",
                icon: protection.isJailbroken ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
                color: protection.isJailbroken ? AppDesign.danger : AppDesign.success
            )
            statusRow(
                label: protection.isPINSet() ? "PIN protection enabled" : "PIN protection disabled",
                icon: protection.isPINSet() ? "lock.fill" : "lock.slash",
                color: protection.isPINSet() ? AppDesign.success : AppDesign.warning
            )
            statusRow(
                label: protection.isScreenRecording ? "Screen recording detected" : "Screen capture not active",
                icon: protection.isScreenRecording ? "eye.trianglebadge.exclamationmark" : "eye.slash",
                color: protection.isScreenRecording ? AppDesign.danger : .secondary
            )
            statusRow(
                label: lockManager.useBiometricForUnlock ? "Biometric unlock enabled" : "Biometric unlock disabled",
                icon: "faceid",
                color: lockManager.useBiometricForUnlock ? AppDesign.success : .secondary
            )
        }
        .appSurface()
    }

    // MARK: - Focus Status

    @ViewBuilder
    private var focusStatusCard: some View {
        if focusManager.isActive {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Focus Mode Active")
                        .font(.headline)
                    Spacer()
                    AppStatusBadge(text: focusManager.isOnBreak ? "Break" : "Active", color: focusManager.isOnBreak ? AppDesign.success : AppDesign.accent)
                }

                HStack(spacing: 12) {
                    Image(systemName: focusManager.selectedProfile.icon)
                        .font(.title2)
                        .foregroundStyle(focusManager.selectedProfile.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(focusManager.selectedProfile.rawValue)
                            .font(.subheadline.weight(.semibold))
                        Text(focusManager.formattedTimeRemaining + " remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("End") {
                        focusManager.stopFocus()
                    }
                    .buttonStyle(.bordered)
                    .tint(AppDesign.danger)
                }
            }
            .appSurface()
        }
    }

    // MARK: - Recent Blocks

    @ViewBuilder
    private var recentBlocksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Blocks")
                    .font(.headline)
                Spacer()
                AppStatusBadge(
                    text: "\(recentBlocks.count)",
                    color: AppDesign.warning
                )
            }

            if recentBlocks.isEmpty {
                Text("No recent app blocks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentBlocks) { alert in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(AppDesign.warning)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.appName)
                                .font(.subheadline.weight(.semibold))
                            Text(alert.timestamp.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .appSurface()
    }

    // MARK: - Helpers

    private func statusRow(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(label)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}
#endif
