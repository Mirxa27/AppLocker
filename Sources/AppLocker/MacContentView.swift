#if os(macOS)
import SwiftUI

struct MacContentView: View {
    @ObservedObject var appMonitor = AppMonitor.shared
    @ObservedObject var authManager = AuthenticationManager.shared
    @State private var selectedTab = 0
    @State private var showingAddSheet = false
    @State private var showingUnlockDialog = false
    @State private var unlockPassword = ""
    @State private var shakeAnimation = 0
    @State private var unlockError: String?

    var body: some View {
        ZStack {
            if !authManager.isAuthenticated {
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
        }
        .animation(.easeInOut, value: authManager.isAuthenticated)
        .animation(.easeInOut, value: appMonitor.showUnlockDialog)
    }

    func unlockApp() {
        if authManager.authenticate(withPasscode: unlockPassword) {
            unlockPassword = ""
            unlockError = nil
        } else {
            unlockError = authManager.authenticationError
            withAnimation(.default) {
                shakeAnimation += 1
            }
            unlockPassword = ""
        }
    }
}

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

struct MainInterface: View {
    @Binding var selectedTab: Int
    @Binding var showingAddSheet: Bool
    @ObservedObject var appMonitor = AppMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AppLocker")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Toggle("Monitoring", isOn: $appMonitor.isMonitoring)
                    .toggleStyle(.switch)
                    .onChange(of: appMonitor.isMonitoring) { newValue in
                        if newValue {
                            appMonitor.startMonitoring()
                        } else {
                            appMonitor.stopMonitoring()
                        }
                    }

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
                VStack(alignment: .leading, spacing: 10) {
                    SidebarButton(title: "Locked Apps", icon: "lock.app.dashed", isSelected: selectedTab == 0) { selectedTab = 0 }
                    SidebarButton(title: "Add Apps", icon: "plus.app", isSelected: selectedTab == 1) { selectedTab = 1 }
                    SidebarButton(title: "Stats", icon: "chart.bar", isSelected: selectedTab == 2) { selectedTab = 2 }
                    SidebarButton(title: "Settings", icon: "gear", isSelected: selectedTab == 3) { selectedTab = 3 }

                    Spacer()
                }
                .padding()
                .frame(width: 200, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))

                // Main Content
                VStack {
                    switch selectedTab {
                    case 0: LockedAppsView()
                    case 1: AddAppsView()
                    case 2: StatsView()
                    case 3: SettingsView()
                    default: Text("Select an option")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
}

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

struct LockedAppsView: View {
    @ObservedObject var appMonitor = AppMonitor.shared

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
                        // In a real app, this would switch tabs
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

struct LockedAppRow: View {
    let app: LockedAppInfo
    @ObservedObject private var appMonitor = AppMonitor.shared
    @State private var showSchedule = false
    @State private var editSchedule: LockSchedule

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
        }
    }
}

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

struct AppIconView: View {
    let bundleID: String
    let path: String?
    let size: CGFloat

    var body: some View {
        if let path = path, let image = NSWorkspace.shared.icon(forFile: path) {
            Image(nsImage: image)
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
        if authManager.authenticate(withPasscode: password) {
            appMonitor.temporarilyUnlock(bundleID: appMonitor.lastBlockedBundleID)
        } else {
            error = authManager.authenticationError
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

struct AddAppsView: View {
    @State private var runningApps: [NSRunningApplication] = []
    @ObservedObject var appMonitor = AppMonitor.shared

    var body: some View {
        VStack {
            Text("Add Apps to Lock")
                .font(.headline)
                .padding()

            List(runningApps, id: \.bundleIdentifier) { app in
                HStack {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 32, height: 32)
                    }
                    Text(app.localizedName ?? "Unknown App")
                    Spacer()
                    Button("Lock") {
                        if let bundleID = app.bundleIdentifier {
                            appMonitor.addLockedApp(bundleID: bundleID)
                        }
                    }
                }
            }
            .onAppear {
                runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            }

            Button("Refresh Running Apps") {
                runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            }
            .padding()
        }
    }
}

struct StatsView: View {
    @ObservedObject var appMonitor = AppMonitor.shared

    var body: some View {
        VStack {
            Text("Usage Statistics")
                .font(.headline)
                .padding()

            List(appMonitor.getUsageStats()) { stat in
                HStack {
                    Text(stat.appName)
                    Spacer()
                    Text("Blocked: \(stat.blockedCount)")
                    Text("Failed: \(stat.failedAttemptCount)")
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appMonitor = AppMonitor.shared
    @ObservedObject var authManager = AuthenticationManager.shared
    @State private var newPasscode = ""
    @State private var currentPasscode = ""
    @State private var message = ""

    var body: some View {
        Form {
            Section(header: Text("Security")) {
                SecureField("Current Passcode", text: $currentPasscode)
                SecureField("New Passcode", text: $newPasscode)
                Button("Change Passcode") {
                    let result = authManager.changePasscode(currentPasscode: currentPasscode, newPasscode: newPasscode)
                    message = result.success ? "Passcode changed" : (result.error ?? "Error")
                }
            }

            Section(header: Text("Options")) {
                Toggle("Auto Lock on Sleep", isOn: $appMonitor.autoLockOnSleep)
                Slider(value: $appMonitor.unlockDuration, in: 60...3600, step: 60) {
                    Text("Unlock Duration: \(Int(appMonitor.unlockDuration/60)) min")
                }
            }

            Text(message)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#endif
