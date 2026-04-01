// Sources/AppLocker/iOS/AppHiding/iOSAppHidingView.swift
#if os(iOS)
import SwiftUI
import FamilyControls
import ManagedSettings

struct iOSAppHidingView: View {
    @StateObject private var vm = iOSAppHidingManager.shared
    @State private var showAddApp = false
    @State private var searchText = ""

    private var filteredApps: [HiddenApp] {
        let source = searchText.isEmpty
            ? vm.hiddenApps
            : vm.hiddenApps.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        return source.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    statsCard
                    appsListCard
                }
                .padding(16)
            }
            .appScreenBackground()
            .navigationTitle("App Hiding")
            .searchable(text: $searchText, prompt: "Search hidden apps")
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
            }
            .sheet(isPresented: $showAddApp) {
                iOSAddHiddenAppSheet()
            }
            .task {
                vm.checkAuthorizationStatus()
            }
        }
    }

    private var statusCard: some View {
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
                Text("Hidden apps are enforced with the same system shield used by Screen Time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Enable Screen Time access to hide selected apps from casual access.")
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
                title: "Hidden",
                value: "\(vm.totalHiddenCount)",
                subtitle: "apps hidden",
                icon: "eye.slash.fill",
                color: AppDesign.warning
            )
            AppMetricCard(
                title: "Shielded",
                value: "\(vm.shieldedAppCount)",
                subtitle: "shields active",
                icon: "shield.fill",
                color: AppDesign.accent
            )
        }
    }

    @ViewBuilder
    private var appsListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hidden Apps")
                    .font(.headline)
                Spacer()
                AppStatusBadge(text: "\(filteredApps.count)", color: AppDesign.warning)
            }

            if filteredApps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No Hidden Apps")
                        .font(.title3.weight(.semibold))
                    Text("Select installed apps from the system picker to hide them behind the Screen Time shield.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(filteredApps) { app in
                    HiddenAppRow(app: app, vm: vm)
                }
            }
        }
        .appSurface()
    }
}

struct HiddenAppRow: View {
    let app: HiddenApp
    @ObservedObject var vm: iOSAppHidingManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.shieldEnabled ? "eye.slash.fill" : "eye.fill")
                .foregroundStyle(app.shieldEnabled ? AppDesign.warning : .secondary)
                .font(.title3)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(app.displayIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(app.dateHidden.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { app.shieldEnabled },
                set: { _ in vm.toggleShield(bundleID: app.bundleID) }
            ))
            .labelsHidden()

            Button {
                withAnimation {
                    vm.unhideApp(bundleID: app.bundleID)
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

struct iOSAddHiddenAppSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vm = iOSAppHidingManager.shared
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false

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
                        Text("Authorize Screen Time in the main App Hiding screen before adding apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Hide Selected Apps") {
                        let added = vm.hideApplications(from: selection)
                        if added > 0 {
                            dismiss()
                        }
                    }
                    .disabled(!vm.isAuthorized || selectedTokenCount == 0)
                }

                if let error = vm.authorizationError {
                    Section {
                        Text(error)
                            .foregroundStyle(AppDesign.warning)
                            .font(.caption)
                    }
                }

                Section("Info") {
                    Text("System apps such as Phone, Messages, Settings, and App Store are excluded automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Hide Apps")
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
#endif
