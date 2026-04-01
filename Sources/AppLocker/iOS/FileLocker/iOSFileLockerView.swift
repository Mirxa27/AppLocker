// Sources/AppLocker/iOS/FileLocker/iOSFileLockerView.swift
#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct iOSFileLockerView: View {
    @StateObject private var vm = iOSFileLockerManager.shared
    @State private var passcodeEntry = ""
    @State private var showFilePicker = false
    @State private var searchText = ""

    private var filteredFiles: [LockedFileEntry] {
        searchText.isEmpty
            ? vm.lockedFiles
            : vm.lockedFiles.filter { $0.originalName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if vm.isUnlocked {
                        statsCard
                        filesListCard
                    } else {
                        unlockCard
                    }
                }
                .padding(16)
            }
            .appScreenBackground()
            .navigationTitle("File Locker")
            .searchable(text: $searchText, prompt: "Search files")
            .toolbar {
                if vm.isUnlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showFilePicker = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Lock") {
                            vm.lock()
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        let _ = vm.addFile(from: url)
                    }
                case .failure(let error):
                    vm.lastError = error.localizedDescription
                }
            }
        }
    }

    private var unlockCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.rectangle.stack.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(AppDesign.accent)

            Text("File Locker")
                .font(.title2.weight(.bold))

            Text("Enter your AppLocker master passcode to access encrypted files.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("Master passcode", text: $passcodeEntry)
                .textFieldStyle(.roundedBorder)

            if let err = vm.lastError {
                Text(err)
                    .foregroundStyle(AppDesign.danger)
                    .font(.caption)
            }

            Button("Unlock Files") {
                _ = vm.unlock(passcode: passcodeEntry)
                passcodeEntry = ""
            }
            .buttonStyle(.borderedProminent)
            .tint(AppDesign.accent)
            .disabled(passcodeEntry.isEmpty)

            Button("Use Face ID / Touch ID") {
                Task {
                    _ = await vm.unlockWithBiometric()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .appSurface()
    }

    private var statsCard: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 155), spacing: 12)],
            spacing: 12
        ) {
            AppMetricCard(
                title: "Files",
                value: "\(vm.totalFiles)",
                subtitle: "encrypted",
                icon: "lock.doc.fill",
                color: AppDesign.accent
            )
            AppMetricCard(
                title: "Total Size",
                value: vm.formattedTotalSize,
                subtitle: "encrypted data",
                icon: "internaldrive.fill",
                color: AppDesign.warning
            )
        }
    }

    @ViewBuilder
    private var filesListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Encrypted Files")
                    .font(.headline)
                Spacer()
                AppStatusBadge(text: "\(filteredFiles.count)", color: AppDesign.accent)
            }

            if filteredFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No Files")
                        .font(.title3.weight(.semibold))
                    Text("Add files to encrypt them with AES-256-GCM.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(filteredFiles) { file in
                    FileLockerRow(file: file, vm: vm)
                }
            }
        }
        .appSurface()
    }
}

// MARK: - File Row

struct FileLockerRow: View {
    let file: LockedFileEntry
    @ObservedObject var vm: iOSFileLockerManager
    @State private var showShareSheet = false
    @State private var shareURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: vm.iconForExtension(file.fileExtension))
                .font(.title3)
                .foregroundStyle(AppDesign.accent)
                .frame(width: 36, height: 36)
                .background(AppDesign.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.originalName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(vm.formattedSize(file.fileSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(file.dateAdded.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    if let url = vm.decryptToTempURL(file) {
                        shareURL = url
                        showShareSheet = true
                    }
                } label: {
                    Label("Share Decrypted", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    withAnimation {
                        vm.deleteFile(file)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityView(activityItems: [url])
            }
        }
    }
}

// MARK: - Activity View (Share Sheet)

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
