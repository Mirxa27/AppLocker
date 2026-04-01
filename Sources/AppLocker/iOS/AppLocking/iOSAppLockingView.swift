// Sources/AppLocker/iOS/AppLocking/iOSAppLockingView.swift
#if os(iOS)
import SwiftUI
import FamilyControls
import ManagedSettings

struct iOSAppLockingView: View {
    @StateObject private var vm = iOSAppLockManager.shared
    @State private var showAddApp = false
    @State private var searchText = ""
    @State private var showSettings = false

    private var filteredApps: [LockedAppEntry] {
        let source = searchText.isEmpty
            ? vm.lockedApps
            : vm.lockedApps.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        return source.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    authorizationCard
                    statsCard
                    configCard
                    appsListCard
                }
                .padding(16)
            }
            .appScreenBackground()
            .navigationTitle("App Locking")
            .searchable(text: $searchText, prompt: "Search locked apps")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            showAddApp = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showAddApp) {
                iOSAddLockedAppSheet()
            }
            .sheet(isPresented: $showSettings) {
                iOSAppLockSettingsSheet()
            }
            .sheet(isPresented: $vm.showUnlockPrompt) {
                if let bundleID = vm.pendingUnlockBundleID {
                    AppUnlockPasscodeSheet(bundleID: bundleID)
                }
            }
            .task {
                vm.checkAuthorizationStatus()
            }
        }
    }

    private var authorizationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Screen Time Authorization")
                    .font(.headline)
                Spacer()
                AppStatusBadge(
                    text: vm.isAuthorized ? "Authorized" : "Required",
                    color: vm.isAuthorized ? AppDesign.success : AppDesign.warning
                )
            }

            if vm.isAuthorized {
                Text("AppLocker is applying real iOS shields to selected apps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Authorize Screen Time access to enforce app locks with the system shield.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await vm.requestAuthorization() }
                } label: {
                    Label("Authorize Screen Time", systemImage: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppDesign.accent)
            }

            if let error = vm.authorizationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppDesign.warning)
            }
        }
        .appSurface()
    }

    private var statsCard: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 155), spacing: 12)],
            spacing: 12
        ) {
            AppMetricCard(
                title: "Locked",
                value: "\(vm.lockedAppCount)",
                subtitle: "apps protected",
                icon: "lock.fill",
                color: AppDesign.accent
            )
            AppMetricCard(
                title: "Shielded",
                value: "\(vm.shieldedAppCount)",
                subtitle: "actively blocked",
                icon: "shield.lefthalf.filled",
                color: AppDesign.warning
            )
            AppMetricCard(
                title: "Unlocked",
                value: "\(vm.currentlyUnlockedCount)",
                subtitle: "temporarily open",
                icon: "lock.open.fill",
                color: AppDesign.success
            )
        }
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)

            HStack {
                Label("Biometric Unlock", systemImage: "faceid")
                Spacer()
                AppStatusBadge(
                    text: vm.useBiometricForUnlock ? "Enabled" : "Disabled",
                    color: vm.useBiometricForUnlock ? AppDesign.success : .secondary
                )
            }

            HStack {
                Label("Auto-Lock on Background", systemImage: "arrow.down.app.fill")
                Spacer()
                AppStatusBadge(
                    text: vm.autoLockOnBackground ? "Enabled" : "Disabled",
                    color: vm.autoLockOnBackground ? AppDesign.success : .secondary
                )
            }

            HStack {
                Label("Unlock Duration", systemImage: "timer")
                Spacer()
                Text(formatDuration(vm.unlockDuration))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .appSurface()
    }

    @ViewBuilder
    private var appsListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Locked Apps")
                    .font(.headline)
                Spacer()
                AppStatusBadge(text: "\(filteredApps.count)", color: AppDesign.accent)
            }

            if filteredApps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No Locked Apps")
                        .font(.title3.weight(.semibold))
                    Text("Choose installed apps from the system picker to require authentication before they open.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(filteredApps) { app in
                    LockedAppRow(app: app, vm: vm)
                }
            }

            if let error = vm.lastError {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppDesign.warning)
            }
        }
        .appSurface()
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

struct LockedAppRow: View {
    let app: LockedAppEntry
    @ObservedObject var vm: iOSAppLockManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: vm.isAppLocked(bundleID: app.bundleID) ? "lock.fill" : "lock.open.fill")
                .foregroundStyle(vm.isAppLocked(bundleID: app.bundleID) ? AppDesign.accent : AppDesign.success)
                .font(.title3)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(app.displayIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if app.requireBiometric {
                        Label("Biometric", systemImage: "faceid")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if app.perAppPasscodeHash != nil {
                        Label("Custom PIN", systemImage: "number")
                            .font(.caption2)
                            .foregroundStyle(AppDesign.warning)
                    }
                }
            }

            Spacer(minLength: 8)

            if vm.isAppLocked(bundleID: app.bundleID) {
                Button {
                    Task {
                        _ = await vm.authenticateToUnlock(bundleID: app.bundleID)
                    }
                } label: {
                    Image(systemName: "lock.open.fill")
                        .foregroundStyle(AppDesign.success)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    vm.lockApp(bundleID: app.bundleID)
                } label: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(AppDesign.warning)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation {
                    vm.removeLockedApp(bundleID: app.bundleID)
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(AppDesign.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct iOSAddLockedAppSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vm = iOSAppLockManager.shared
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var useCustomPasscode = false
    @State private var customPasscode = ""
    @State private var confirmPasscode = ""

    private var selectedTokenCount: Int {
        selection.applicationTokens.count
    }

    private var selectedApplications: [ManagedSettings.Application] {
        selection.applications.sorted { lhs, rhs in
            let left = lhs.localizedDisplayName ?? lhs.bundleIdentifier ?? ""
            let right = rhs.localizedDisplayName ?? rhs.bundleIdentifier ?? ""
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Selection") {
                    if vm.isAuthorized {
                        Button {
                            showPicker = true
                        } label: {
                            Label(selectedTokenCount == 0 ? "Choose Apps" : "Update Selection", systemImage: "square.grid.2x2.fill")
                        }

                        if selectedTokenCount == 0 {
                            Text("Select installed apps from the Screen Time picker.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if selectedApplications.isEmpty {
                            Text("\(selectedTokenCount) app selections are ready. Detailed identifiers will resolve on-device when Screen Time exposes them.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(selectedApplications, id: \.self) { application in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(application.localizedDisplayName ?? application.bundleIdentifier ?? "Unknown App")
                                        .font(.subheadline.weight(.semibold))
                                    if let bundleID = application.bundleIdentifier {
                                        Text(bundleID)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } else {
                        Text("Authorize Screen Time in the main App Locking screen before adding apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Lock Options") {
                    Toggle("Use Custom Passcode", isOn: $useCustomPasscode)

                    if useCustomPasscode {
                        SecureField("Passcode (4+ digits)", text: $customPasscode)
                            .keyboardType(.numberPad)
                        SecureField("Confirm Passcode", text: $confirmPasscode)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Button("Lock Selected Apps") {
                        let added = vm.addLockedApplications(
                            from: selection,
                            perAppPasscode: useCustomPasscode ? customPasscode : nil
                        )
                        if added > 0 {
                            dismiss()
                        }
                    }
                    .disabled(
                        !vm.isAuthorized ||
                        selectedTokenCount == 0 ||
                        (useCustomPasscode && (customPasscode != confirmPasscode || customPasscode.count < 4))
                    )
                }

                if let error = vm.lastError {
                    Section {
                        Text(error)
                            .foregroundStyle(AppDesign.warning)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Lock Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        }
    }
}

struct AppUnlockPasscodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vm = iOSAppLockManager.shared
    let bundleID: String
    @State private var passcode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Unlock") {
                    Text(vm.pendingUnlockAppName ?? bundleID)
                        .font(.headline)
                    SecureField("Enter PIN", text: $passcode)
                        .keyboardType(.numberPad)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppDesign.danger)
                    }
                }

                Section {
                    Button("Unlock") {
                        if vm.verifyPasscode(passcode, for: bundleID) {
                            dismiss()
                        } else {
                            errorMessage = "Incorrect passcode."
                            passcode = ""
                        }
                    }
                    .disabled(passcode.isEmpty)
                }
            }
            .navigationTitle("Unlock App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.cancelUnlockPrompt()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct iOSAppLockSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vm = iOSAppLockManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Unlock Behavior") {
                    Toggle("Biometric Unlock", isOn: $vm.useBiometricForUnlock)
                    Toggle("Auto-Lock on Background", isOn: $vm.autoLockOnBackground)
                }

                Section("Unlock Duration") {
                    Picker("Duration", selection: $vm.unlockDuration) {
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                        Text("15 minutes").tag(900.0)
                        Text("30 minutes").tag(1800.0)
                        Text("1 hour").tag(3600.0)
                    }
                }

                Section {
                    Button("Lock All Apps Now") {
                        vm.lockAll()
                    }
                    .tint(AppDesign.danger)
                }
            }
            .navigationTitle("Lock Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
