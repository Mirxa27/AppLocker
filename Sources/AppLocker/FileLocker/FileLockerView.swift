// Sources/AppLocker/FileLocker/FileLockerView.swift
#if os(macOS)
import SwiftUI

struct FileLockerView: View {
    @ObservedObject var locker = FileLockerManager.shared
    @State private var passcode = ""
    @State private var showPasscodeSheet = false
    @State private var pendingAction: LockerAction = .lock
    @State private var isDragTargeted = false

    enum LockerAction { case lock, unlock }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(isPresented: $showPasscodeSheet) { passcodeSheet }
        .alert("File Locker", isPresented: Binding(
            get: { locker.lastError != nil },
            set: { if !$0 { locker.lastError = nil } }
        )) { Button("OK") { locker.lastError = nil } } message: {
            Text(locker.lastError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("File Locker").font(.headline)
            Spacer()
            if locker.isProcessing {
                ProgressView().controlSize(.small)
                Text("Processing…").font(.caption).foregroundColor(.secondary)
            }
            Button { pendingAction = .lock; showPasscodeSheet = true }
            label: { Label("Lock Files", systemImage: "lock.fill") }
            .buttonStyle(.borderedProminent).controlSize(.small).disabled(locker.isProcessing)

            Button { pendingAction = .unlock; showPasscodeSheet = true }
            label: { Label("Unlock .aplk", systemImage: "lock.open.fill") }
            .buttonStyle(.bordered).controlSize(.small).disabled(locker.isProcessing)
        }
        .padding()
    }

    private var content: some View {
        HSplitView {
            VStack(alignment: .leading) {
                HStack {
                    Text("Locked Files (\(locker.lockedFiles.count))")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button("Refresh") { locker.clearMissingRecords() }
                        .buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
                }
                .padding([.horizontal, .top])

                if locker.lockedFiles.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "doc.badge.lock").font(.system(size: 36)).foregroundColor(.secondary)
                        Text("No locked files tracked").foregroundColor(.secondary).font(.caption)
                        Spacer()
                    }.frame(maxWidth: .infinity)
                } else {
                    List(locker.lockedFiles) { record in LockedFileRow(record: record) }
                }
            }
            .frame(minWidth: 260)

            VStack(spacing: 16) {
                Spacer()
                Image(systemName: isDragTargeted ? "arrow.down.doc.fill" : "doc.badge.lock")
                    .font(.system(size: 52)).foregroundColor(isDragTargeted ? .blue : .secondary)
                Text("Drop files here to lock them").foregroundColor(.secondary)
                Text("Encrypted in-place with AES-256-GCM.\nOriginals are securely deleted.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(isDragTargeted ? Color.blue.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { _ in
                pendingAction = .lock; showPasscodeSheet = true; return true
            }
        }
    }

    private var passcodeSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: pendingAction == .lock ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 44)).foregroundColor(.blue)
            Text(pendingAction == .lock ? "Lock Files" : "Unlock .aplk Files")
                .font(.title2).fontWeight(.semibold)
            Text(pendingAction == .lock
                 ? "Files will be encrypted in-place.\nOriginals are securely deleted."
                 : "Select .aplk files to decrypt and restore.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).font(.subheadline)
            SecureField("Master Passcode", text: $passcode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 240).onSubmit { performAction() }
            HStack {
                Button("Cancel") { showPasscodeSheet = false; passcode = "" }.keyboardShortcut(.cancelAction)
                Button(pendingAction == .lock ? "Lock" : "Unlock") { performAction() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(passcode.isEmpty)
            }
        }
        .padding(32).frame(width: 340)
    }

    private func performAction() {
        let pc = passcode; passcode = ""; showPasscodeSheet = false
        pendingAction == .lock ? locker.lockFiles(passcode: pc) : locker.unlockFiles(passcode: pc)
    }
}

struct LockedFileRow: View {
    let record: LockedFileRecord
    var body: some View {
        HStack {
            Image(systemName: "doc.badge.lock").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: record.lockedPath).lastPathComponent)
                    .font(.subheadline).lineLimit(1)
                Text("Locked \(record.dateEncrypted, style: .relative) ago")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: FileManager.default.fileExists(atPath: record.lockedPath)
                  ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(FileManager.default.fileExists(atPath: record.lockedPath) ? .green : .red)
                .font(.caption)
        }
        .padding(.vertical, 2)
    }
}
#endif
