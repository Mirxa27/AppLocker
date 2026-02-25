#if os(macOS)
import SwiftUI

// MARK: - Root View

struct MacContentView: View {
    @ObservedObject var appMonitor = AppMonitor.shared
    @ObservedObject var authManager = AuthenticationManager.shared
    @State private var selectedTab = 0
    @State private var showingAddSheet = false
    @State private var unlockPassword = ""
    @State private var shakeAnimation = 0
    @State private var unlockError: String?
    @State private var showBlockingOverlay = false

    var body: some View {
        ZStack {
            if !authManager.isPasscodeSet() {
                SetupWizardView()
                    .transition(.opacity)
            } else if !authManager.isAuthenticated {
                LockScreen(
                    password: $unlockPassword,
                    error: $unlockError,
                    shake: $shakeAnimation,
                    onUnlock: unlockApp
                )
                .transition(.opacity)
            } else {
                MainInterface(selectedTab: $selectedTab, showingAddSheet: $showingAddSheet)
                    .transition(.opacity)
            }

            if appMonitor.showUnlockDialog {
                UnlockDialogView()
            }

            if showBlockingOverlay {
                BlockingOverlayView(appName: appMonitor.lastBlockedAppName ?? "App")
                    .background(Color.black.opacity(0.85))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: authManager.isAuthenticated)
        .animation(.easeInOut, value: appMonitor.showUnlockDialog)
        .animation(.easeInOut, value: showBlockingOverlay)
        .onChange(of: appMonitor.showUnlockDialog) { newValue in
            if newValue {
                showBlockingOverlay = true
                DispatchQueue.main.asyncAfter(deadline: .now() + appMonitor.blockingOverlayDuration) {
                    withAnimation {
                        showBlockingOverlay = false
                    }
                }
            }
        }
    }

    func unlockApp() {
        if authManager.authenticate(withPasscode: unlockPassword) {
            unlockPassword = ""
            unlockError = nil
        } else {
            unlockError = authManager.authenticationError
            NotificationManager.shared.sendFailedAuthNotification(
                appName: "AppLocker",
                bundleID: Bundle.main.bundleIdentifier ?? "com.applocker"
            )
            withAnimation(.default) {
                shakeAnimation += 1
            }
            unlockPassword = ""
        }
    }
}

// MARK: - Setup Wizard (Gap 1)

struct SetupWizardView: View {
    @ObservedObject var authManager = AuthenticationManager.shared
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var error: String?
    @State private var step = 0

    var body: some View {
        VStack(spacing: 30) {
            if step == 0 {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                Text("Welcome to AppLocker")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Protect your apps with a passcode and biometrics.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 350)

                Button("Get Started") {
                    withAnimation { step = 1 }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Image(systemName: "key.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Create Your Passcode")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(spacing: 15) {
                    SecureField("Passcode (min 4 characters)", text: $passcode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 280)

                    SecureField("Confirm Passcode", text: $confirmPasscode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 280)
                        .onSubmit(createPasscode)

                    if let error = error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    Button("Create Passcode") {
                        createPasscode()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(passcode.count < 4 || confirmPasscode.isEmpty)
                }

                Divider().frame(width: 280)

                VStack(spacing: 8) {
                    Text("AppLocker needs Accessibility permissions to block apps.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Grant Accessibility Access") {
                        AppMonitor.shared.requestAccessibilityPermissions()
                    }
                    .buttonStyle(.bordered)
                }

                if authManager.canUseBiometrics() {
                    Text("Touch ID / Face ID will be available after setup.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }

    private func createPasscode() {
        guard passcode.count >= 4 else {
            error = "Passcode must be at least 4 characters"
            return
        }
        guard passcode == confirmPasscode else {
            error = "Passcodes don't match"
            return
        }
        if authManager.setPasscode(passcode) {
            error = nil
            let _ = authManager.authenticate(withPasscode: passcode)
        } else {
            error = "Failed to save passcode"
        }
    }
}

// MARK: - Lock Screen

struct LockScreen: View {
    @Binding var password: String
    @Binding var error: String?
    @Binding var shake: Int
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding(.bottom, 20)

            Text("AppLocker")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 15) {
                SecureField("Enter Passcode", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 250)
                    .onSubmit(onUnlock)
                    .modifier(ShakeEffect(animatableData: CGFloat(shake)))

                if let error = error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button("Unlock") {
                    onUnlock()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(password.isEmpty)
            }

            if AuthenticationManager.shared.canUseBiometrics() {
                Button {
                    AuthenticationManager.shared.authenticateWithBiometrics { success, error in
                        if !success {
                            self.error = error
                        }
                    }
                } label: {
                    Label("Use Touch ID / Face ID", systemImage: "touchid")
                }
                .buttonStyle(.borderless)
                .padding(.top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
}

// MARK: - Main Interface

struct MainInterface: View {
    @Binding var selectedTab: Int
    @Binding var showingAddSheet: Bool
    @ObservedObject var appMonitor = AppMonitor.shared
    @State private var hasAccessibility = AppMonitor.shared.hasAccessibilityPermissions()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AppLocker")
                    .font(.title2)
                    .fontWeight(.bold)

                if !hasAccessibility {
                    Button {
                        appMonitor.requestAccessibilityPermissions()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Accessibility Required")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Click to grant accessibility permissions")
                }

                Spacer()

                Toggle("Monitoring", isOn: Binding(
                    get: { appMonitor.isMonitoring },
                    set: { newValue in
                        if newValue { appMonitor.startMonitoring() }
                        else { appMonitor.stopMonitoring() }
                    }
                ))
                .toggleStyle(.switch)

                Button {
                    AuthenticationManager.shared.logout()
                } label: {
                    Image(systemName: "lock.fill")
                }
                .help("Lock AppLocker")
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            HSplitView {
                // Sidebar
                VStack(alignment: .leading, spacing: 4) {
                    SidebarButton(title: "Locked Apps",      icon: "lock.app.dashed",                  isSelected: selectedTab == 0)  { selectedTab = 0  }
                    SidebarButton(title: "Add Apps",         icon: "plus.app",                         isSelected: selectedTab == 1)  { selectedTab = 1  }
                    SidebarButton(title: "Stats",            icon: "chart.bar",                        isSelected: selectedTab == 2)  { selectedTab = 2  }
                    SidebarButton(title: "Settings",         icon: "gear",                             isSelected: selectedTab == 3)  { selectedTab = 3  }
                    SidebarButton(title: "Activity Log",     icon: "list.bullet.rectangle",            isSelected: selectedTab == 4)  { selectedTab = 4  }
                    SidebarButton(title: "Intruder Photos",  icon: "person.crop.circle.badge.exclamationmark", isSelected: selectedTab == 5) { selectedTab = 5 }
                    SidebarButton(title: "Categories",       icon: "folder.fill",                      isSelected: selectedTab == 6)  { selectedTab = 6  }

                    Divider().padding(.vertical, 4)

                    Text("Security Tools")
                        .font(.caption2).foregroundColor(.secondary).padding(.horizontal, 8)

                    SidebarButton(title: "Secure Vault",     icon: "lock.doc.fill",                   isSelected: selectedTab == 7)  { selectedTab = 7  }
                    SidebarButton(title: "File Locker",      icon: "doc.badge.lock",                  isSelected: selectedTab == 8)  { selectedTab = 8  }
                    SidebarButton(title: "Clipboard Guard",  icon: "clipboard.fill",                  isSelected: selectedTab == 9)  { selectedTab = 9  }
                    SidebarButton(title: "Screen Privacy",   icon: "eye.slash.fill",                  isSelected: selectedTab == 10) { selectedTab = 10 }
                    SidebarButton(title: "Network Monitor",  icon: "network",                         isSelected: selectedTab == 11) { selectedTab = 11 }
                    SidebarButton(title: "Secure Notes",     icon: "lock.rectangle.stack.fill",       isSelected: selectedTab == 12) { selectedTab = 12 }

                    Spacer()
                }
                .padding()
                .frame(width: 200)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))

                // Main Content
                VStack {
                    switch selectedTab {
                    case 0: LockedAppsView(selectedTab: $selectedTab)
                    case 1: AddAppsView()
                    case 2: StatsView()
                    case 3: SettingsView()
                    case 4: ActivityLogView()
                    case 5: IntruderPhotoView()
                    case 6: CategoryManagementView()
                    case 7: VaultView()
                    case 8: FileLockerView()
                    case 9: ClipboardGuardView()
                    case 10: ScreenPrivacyView()
                    case 11: NetworkMonitorView()
                    case 12: SecureNotesView()
                    default: Text("Select an option")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            hasAccessibility = appMonitor.hasAccessibilityPermissions()
        }
    }
}

// MARK: - Sidebar Button

struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .accentColor : .primary)
    }
}

// MARK: - Locked Apps View (Gap 2 fix)

struct LockedAppsView: View {
    @ObservedObject var appMonitor = AppMonitor.shared
    @Binding var selectedTab: Int

    var body: some View {
        VStack(alignment: .leading) {
            Text("Locked Applications")
                .font(.headline)

            if appMonitor.lockedApps.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "lock.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No apps are currently locked")
                        .foregroundColor(.secondary)
                        .padding(.top)
                    Button("Add Apps") {
                        selectedTab = 1
                    }
                    .padding(.top)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(appMonitor.lockedApps) { app in
                        LockedAppRow(app: app)
                    }
                }
            }
        }
    }
}

// MARK: - Locked App Row (Gap 4: per-app passcode, Gap 9: category picker)

struct LockedAppRow: View {
    let app: LockedAppInfo
    @ObservedObject private var appMonitor = AppMonitor.shared
    @State private var showSchedule = false
    @State private var editSchedule: LockSchedule
    @State private var showPasscodeEditor = false
    @State private var appPasscode = ""
    @State private var appPasscodeConfirm = ""
    @State private var passcodeError: String?

    init(app: LockedAppInfo) {
        self.app = app
        self._editSchedule = State(initialValue: app.schedule ?? LockSchedule())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppIconView(bundleID: app.bundleID, path: app.path, size: 32)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text(app.bundleID)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if let category = app.category {
                            Text("| \(category)")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    }
                }

                Spacer()

                if let schedule = app.schedule, schedule.enabled {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Scheduled")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("\(schedule.startTimeFormatted)-\(schedule.endTimeFormatted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Always Locked")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }

                // Category picker
                Menu {
                    Button("None") {
                        appMonitor.updateAppCategory(bundleID: app.bundleID, category: nil)
                    }
                    Divider()
                    ForEach(appMonitor.categories) { cat in
                        Button {
                            appMonitor.updateAppCategory(bundleID: app.bundleID, category: cat.name)
                        } label: {
                            Label(cat.name, systemImage: cat.icon)
                        }
                    }
                } label: {
                    Image(systemName: "folder")
                        .foregroundColor(app.category != nil ? .purple : .secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Set category")

                // Per-app passcode button
                Button {
                    showPasscodeEditor.toggle()
                } label: {
                    Image(systemName: "key.fill")
                        .foregroundColor(app.passcode != nil ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(app.passcode != nil ? "Per-app passcode set" : "Set per-app passcode")

                Button {
                    showSchedule.toggle()
                } label: {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Set schedule")

                Button {
                    appMonitor.removeLockedApp(bundleID: app.bundleID)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)

            if showSchedule {
                ScheduleEditorView(
                    schedule: $editSchedule,
                    onSave: {
                        appMonitor.updateAppSchedule(bundleID: app.bundleID, schedule: editSchedule.enabled ? editSchedule : nil)
                        showSchedule = false
                    },
                    onCancel: {
                        editSchedule = app.schedule ?? LockSchedule()
                        showSchedule = false
                    }
                )
                .padding(.top, 8)
                .padding(.leading, 44)
            }

            if showPasscodeEditor {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Per-app Passcode (min 4 chars)", text: $appPasscode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 220)

                    SecureField("Confirm Passcode", text: $appPasscodeConfirm)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 220)

                    if let error = passcodeError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    HStack {
                        Button("Cancel") {
                            appPasscode = ""
                            appPasscodeConfirm = ""
                            passcodeError = nil
                            showPasscodeEditor = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Save") {
                            guard appPasscode.count >= 4 else {
                                passcodeError = "Min 4 characters"
                                return
                            }
                            guard appPasscode == appPasscodeConfirm else {
                                passcodeError = "Passcodes don't match"
                                return
                            }
                            if let hash = AuthenticationManager.shared.hashPasscodeForStorage(appPasscode) {
                                appMonitor.updateAppPasscode(bundleID: app.bundleID, passcodeHash: hash)
                                appPasscode = ""
                                appPasscodeConfirm = ""
                                passcodeError = nil
                                showPasscodeEditor = false
                            } else {
                                passcodeError = "Failed to hash passcode"
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if app.passcode != nil {
                            Button("Remove") {
                                appMonitor.updateAppPasscode(bundleID: app.bundleID, passcodeHash: nil)
                                appPasscode = ""
                                appPasscodeConfirm = ""
                                passcodeError = nil
                                showPasscodeEditor = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(.red)
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.top, 8)
                .padding(.leading, 44)
            }
        }
    }
}

// MARK: - Schedule Editor

struct ScheduleEditorView: View {
    @Binding var schedule: LockSchedule
    let onSave: () -> Void
    let onCancel: () -> Void

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enable Schedule", isOn: $schedule.enabled)
                .font(.subheadline)

            if schedule.enabled {
                HStack(spacing: 15) {
                    VStack(alignment: .leading) {
                        Text("Start")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Picker("Hour", selection: $schedule.startHour) {
                                ForEach(0..<24, id: \.self) { h in
                                    Text(String(format: "%02d", h)).tag(h)
                                }
                            }
                            .frame(width: 60)
                            Text(":")
                            Picker("Min", selection: $schedule.startMinute) {
                                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                                    Text(String(format: "%02d", m)).tag(m)
                                }
                            }
                            .frame(width: 60)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("End")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Picker("Hour", selection: $schedule.endHour) {
                                ForEach(0..<24, id: \.self) { h in
                                    Text(String(format: "%02d", h)).tag(h)
                                }
                            }
                            .frame(width: 60)
                            Text(":")
                            Picker("Min", selection: $schedule.endMinute) {
                                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                                    Text(String(format: "%02d", m)).tag(m)
                                }
                            }
                            .frame(width: 60)
                        }
                    }
                }

                // Day selector
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { day in
                        let isActive = schedule.activeDays.contains(day)
                        Button(dayNames[day - 1]) {
                            if isActive {
                                schedule.activeDays.remove(day)
                            } else {
                                schedule.activeDays.insert(day)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(isActive ? .blue : .gray)
                        .controlSize(.small)
                    }
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Save Schedule", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Add Apps View (Gap 2 fix, Gap 12: installed apps)

struct AddAppsView: View {
    @State private var runningApps: [NSRunningApplication] = []
    @State private var installedApps: [InstalledAppInfo] = []
    @ObservedObject var appMonitor = AppMonitor.shared
    @State private var mode = 0
    @State private var searchText = ""

    var filteredRunningApps: [NSRunningApplication] {
        if searchText.isEmpty { return runningApps }
        return runningApps.filter { ($0.localizedName ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    var filteredInstalledApps: [InstalledAppInfo] {
        if searchText.isEmpty { return installedApps }
        return installedApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack {
            Text("Add Apps to Lock")
                .font(.headline)
                .padding(.top)

            Picker("Source", selection: $mode) {
                Text("Running").tag(0)
                Text("Installed").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
            .padding(.bottom, 5)

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            if mode == 0 {
                List(filteredRunningApps, id: \.bundleIdentifier) { app in
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 32, height: 32)
                        }
                        Text(app.localizedName ?? "Unknown App")
                        Spacer()
                        if let bundleID = app.bundleIdentifier,
                           appMonitor.lockedApps.contains(where: { $0.bundleID == bundleID }) {
                            Text("Locked")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(4)
                        } else {
                            Button("Lock") {
                                if let bundleID = app.bundleIdentifier {
                                    appMonitor.addLockedApp(bundleID: bundleID)
                                }
                            }
                        }
                    }
                }
            } else {
                List(filteredInstalledApps) { app in
                    HStack {
                        AppIconView(bundleID: app.bundleID, path: app.path, size: 32)
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading) {
                            Text(app.displayName)
                            Text(app.bundleID)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if appMonitor.lockedApps.contains(where: { $0.bundleID == app.bundleID }) {
                            Text("Locked")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(4)
                        } else {
                            Button("Lock") {
                                appMonitor.addLockedApp(bundleID: app.bundleID)
                            }
                        }
                    }
                }
            }

            Button("Refresh") {
                refreshApps()
            }
            .padding()
        }
        .onAppear {
            refreshApps()
        }
    }

    private func refreshApps() {
        runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        installedApps = appMonitor.getInstalledApps()
    }
}

// MARK: - Stats View (Gap 6: time-period filtering)

struct StatsView: View {
    @ObservedObject var appMonitor = AppMonitor.shared
    @State private var selectedPeriod = 0

    var stats: [UsageStats] {
        switch selectedPeriod {
        case 0: return appMonitor.getUsageStatsForPeriod(days: 1)
        case 1: return appMonitor.getUsageStatsForPeriod(days: 7)
        case 2: return appMonitor.getUsageStatsForPeriod(days: 30)
        default: return appMonitor.getUsageStats()
        }
    }

    var totalBlocked: Int { stats.reduce(0) { $0 + $1.blockedCount } }
    var totalUnlocked: Int { stats.reduce(0) { $0 + $1.unlockedCount } }
    var totalFailed: Int { stats.reduce(0) { $0 + $1.failedAttemptCount } }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Usage Statistics")
                .font(.headline)

            Picker("Period", selection: $selectedPeriod) {
                Text("Today").tag(0)
                Text("Week").tag(1)
                Text("Month").tag(2)
                Text("All Time").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(width: 350)
            .padding(.bottom, 10)

            HStack(spacing: 16) {
                StatCard(title: "Blocked", count: totalBlocked, color: .orange, icon: "hand.raised.fill")
                StatCard(title: "Unlocked", count: totalUnlocked, color: .green, icon: "lock.open.fill")
                StatCard(title: "Failed", count: totalFailed, color: .red, icon: "exclamationmark.triangle.fill")
            }
            .padding(.bottom, 10)

            if stats.isEmpty {
                VStack {
                    Spacer()
                    Text("No activity for this period")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(stats) { stat in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(stat.appName)
                                .font(.headline)
                            if let lastBlocked = stat.lastBlocked {
                                Text("Last blocked: \(lastBlocked, style: .relative) ago")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            Label("\(stat.blockedCount)", systemImage: "hand.raised.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Label("\(stat.unlockedCount)", systemImage: "lock.open.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Label("\(stat.failedAttemptCount)", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text("\(count)")
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Settings View (Gap 7, Gap 13)

struct SettingsView: View {
    @ObservedObject var appMonitor = AppMonitor.shared
    @ObservedObject var authManager = AuthenticationManager.shared
    @ObservedObject var notificationManager = NotificationManager.shared
    @State private var newPasscode = ""
    @State private var currentPasscode = ""
    @State private var message = ""
    @State private var showResetConfirmation = false
    @State private var hasAccessibility = false

    var body: some View {
        Form {
            Section(header: Text("Security")) {
                SecureField("Current Passcode", text: $currentPasscode)
                SecureField("New Passcode", text: $newPasscode)
                Button("Change Passcode") {
                    let result = authManager.changePasscode(currentPasscode: currentPasscode, newPasscode: newPasscode)
                    message = result.success ? "Passcode changed" : (result.error ?? "Error")
                    if result.success {
                        currentPasscode = ""
                        newPasscode = ""
                    }
                }

                HStack {
                    Image(systemName: hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasAccessibility ? .green : .orange)
                    Text(hasAccessibility ? "Accessibility: Granted" : "Accessibility: Not Granted")
                    Spacer()
                    if !hasAccessibility {
                        Button("Grant Access") {
                            appMonitor.requestAccessibilityPermissions()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .onAppear {
                    hasAccessibility = appMonitor.hasAccessibilityPermissions()
                }
                .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                    hasAccessibility = appMonitor.hasAccessibilityPermissions()
                }
            }

            Section(header: Text("Options")) {
                Toggle("Auto Lock on Sleep", isOn: $appMonitor.autoLockOnSleep)
                    .onChange(of: appMonitor.autoLockOnSleep) { _ in appMonitor.saveSettings() }

                VStack(alignment: .leading) {
                    Text("Unlock Duration: \(Int(appMonitor.unlockDuration / 60)) min")
                    Slider(value: $appMonitor.unlockDuration, in: 60...3600, step: 60)
                        .onChange(of: appMonitor.unlockDuration) { _ in appMonitor.saveSettings() }
                }

                VStack(alignment: .leading) {
                    Text("Blocking Overlay Duration: \(String(format: "%.0f", appMonitor.blockingOverlayDuration))s")
                    Slider(value: $appMonitor.blockingOverlayDuration, in: 1...10, step: 1)
                        .onChange(of: appMonitor.blockingOverlayDuration) { _ in appMonitor.saveSettings() }
                }
            }

            Section(header: Text("Notifications")) {
                Toggle("Notifications Enabled", isOn: $notificationManager.notificationsEnabled)
                    .onChange(of: notificationManager.notificationsEnabled) { _ in notificationManager.saveSettings() }
                Toggle("Cross-Device Alerts", isOn: $notificationManager.crossDeviceEnabled)
                    .onChange(of: notificationManager.crossDeviceEnabled) { _ in notificationManager.saveSettings() }
            }

            Section(header: Text("Backup & Restore")) {
                HStack {
                    Button("Export Configuration") {
                        appMonitor.exportToFile()
                    }
                    Button("Import Configuration") {
                        appMonitor.importFromFile()
                    }
                }
            }

            Section(header: Text("Danger Zone")) {
                Button("Reset All Data") {
                    showResetConfirmation = true
                }
                .foregroundColor(.red)
            }

            if !message.isEmpty {
                Text(message)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .alert("Reset All Data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                appMonitor.resetAllData()
                let _ = authManager.resetAllData()
                message = "All data has been reset. Please restart."
            }
        } message: {
            Text("This will delete all locked apps, categories, usage data, logs, and your passcode. This cannot be undone.")
        }
    }
}

// MARK: - Activity Log View (Gap 8)

struct ActivityLogView: View {
    @ObservedObject var appMonitor = AppMonitor.shared
    @State private var searchText = ""

    var filteredLogs: [String] {
        if searchText.isEmpty { return appMonitor.blockLog }
        return appMonitor.blockLog.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Activity Log")
                    .font(.headline)
                Spacer()
                Text("\(filteredLogs.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Clear") {
                    appMonitor.clearLog()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            TextField("Search logs...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            if filteredLogs.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No log entries")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filteredLogs, id: \.self) { entry in
                    Text(entry)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }
}

// MARK: - Intruder Photo View (Gap 5)

struct IntruderPhotoView: View {
    @State private var photos: [URL] = []

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Intruder Photos")
                    .font(.headline)
                Spacer()
                    Button {
                    photos = IntruderManager.shared.getIntruderPhotos()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")

                if !photos.isEmpty {
                    Button("Delete All") {
                        for url in photos {
                            try? FileManager.default.removeItem(at: url)
                        }
                        photos = IntruderManager.shared.getIntruderPhotos()
                    }
                    .foregroundColor(.red)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if photos.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No intruder photos captured")
                        .foregroundColor(.secondary)
                    Text("Photos are captured after 2+ failed unlock attempts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                        ForEach(photos, id: \.absoluteString) { url in
                            VStack {
                                if let nsImage = NSImage(contentsOf: url) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 150, height: 112)
                                        .clipped()
                                        .cornerRadius(8)
                                }
                                Text(timestampFromFilename(url))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 5)
                }
            }
        }
        .onAppear {
            photos = IntruderManager.shared.getIntruderPhotos()
        }
    }

    private func timestampFromFilename(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(of: "intruder-"),
           let interval = TimeInterval(name[range.upperBound...]) {
            let date = Date(timeIntervalSince1970: interval)
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        }
        return name
    }
}

// MARK: - Category Management View (Gap 9)

struct CategoryManagementView: View {
    @ObservedObject var appMonitor = AppMonitor.shared
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryIcon = "folder.fill"

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Categories")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if appMonitor.categories.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No categories")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(appMonitor.categories) { category in
                        CategoryRow(category: category)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            VStack(spacing: 15) {
                Text("New Category")
                    .font(.headline)

                TextField("Category Name", text: $newCategoryName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 250)

                HStack {
                    Button("Cancel") {
                        newCategoryName = ""
                        showingAddCategory = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Add") {
                        guard !newCategoryName.isEmpty else { return }
                        appMonitor.addCategory(AppCategory(name: newCategoryName, icon: newCategoryIcon, appBundleIDs: []))
                        newCategoryName = ""
                        showingAddCategory = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newCategoryName.isEmpty)
                }
            }
            .padding(30)
            .frame(width: 320)
        }
    }
}

struct CategoryRow: View {
    let category: AppCategory
    @ObservedObject var appMonitor = AppMonitor.shared

    var appsInCategory: [LockedAppInfo] {
        appMonitor.lockedApps.filter { $0.category == category.name }
    }

    var body: some View {
        DisclosureGroup {
            if appsInCategory.isEmpty {
                Text("No apps in this category")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading)
            } else {
                ForEach(appsInCategory) { app in
                    HStack {
                        AppIconView(bundleID: app.bundleID, path: app.path, size: 20)
                            .frame(width: 20, height: 20)
                        Text(app.displayName)
                            .font(.subheadline)
                        Spacer()
                        Button {
                            appMonitor.updateAppCategory(bundleID: app.bundleID, category: nil)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(.blue)
                Text(category.name)
                    .fontWeight(.medium)
                Spacer()
                Text("\(appsInCategory.count) apps")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Lock All") {
                    appMonitor.lockAllInCategory(category.name)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Unlock All") {
                    appMonitor.unlockAllInCategory(category.name)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button {
                    appMonitor.removeCategory(name: category.name)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Unlock Dialog (Gap 4: per-app passcode, Gap 10: failed auth notification)

struct UnlockDialogView: View {
    @ObservedObject var appMonitor = AppMonitor.shared
    @ObservedObject var authManager = AuthenticationManager.shared
    @State private var password = ""
    @State private var error: String?
    @State private var shake = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                Text("Unlock \(appMonitor.lastBlockedAppName ?? "App")")
                    .font(.headline)

                Text("This app is locked.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                SecureField("Enter Passcode", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
                    .onSubmit(unlock)
                    .modifier(ShakeEffect(animatableData: CGFloat(shake)))

                if let error = error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                HStack {
                    Button("Cancel") {
                        appMonitor.showUnlockDialog = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Unlock") {
                        unlock()
                    }
                    .keyboardShortcut(.defaultAction)
                }

                if authManager.canUseBiometrics() {
                    Button {
                        authenticateBiometrics()
                    } label: {
                        Label("Use Biometrics", systemImage: "touchid")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(30)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(12)
            .shadow(radius: 20)
        }
    }

    func unlock() {
        let appHash = appMonitor.lockedApps.first(where: { $0.bundleID == appMonitor.lastBlockedBundleID })?.passcode

        if authManager.authenticate(withPasscode: password, forAppHash: appHash) {
            appMonitor.temporarilyUnlock(bundleID: appMonitor.lastBlockedBundleID)
        } else {
            error = authManager.authenticationError
            let appName = appMonitor.lastBlockedAppName ?? appMonitor.lastBlockedBundleID
            NotificationManager.shared.sendFailedAuthNotification(appName: appName, bundleID: appMonitor.lastBlockedBundleID)
            appMonitor.recordUsage(bundleID: appMonitor.lastBlockedBundleID, appName: appName, event: .failedAttempt)
            withAnimation { shake += 1 }
            password = ""
        }
    }

    func authenticateBiometrics() {
        authManager.authenticateWithBiometrics { success, msg in
            if success {
                appMonitor.temporarilyUnlock(bundleID: appMonitor.lastBlockedBundleID)
            } else {
                error = msg
            }
        }
    }
}

// MARK: - Helper Views

struct AppIconView: View {
    let bundleID: String
    let path: String?
    let size: CGFloat

    var body: some View {
        if let path = path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.secondary)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 2), y: 0))
    }
}

#endif
