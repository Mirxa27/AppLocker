// Sources/AppLocker/SecureVault/VaultView.swift
#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct VaultView: View {
    @ObservedObject var vault = VaultManager.shared
    @State private var passcode = ""
    @State private var showUnlockSheet = false
    @State private var isDragTargeted = false
    @State private var selectedFileID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Secure Vault")
                    .font(.headline)
                Spacer()
                if vault.isUnlocked {
                    Text("\(vault.files.count) files · \(totalSize)")
                        .font(.caption).foregroundColor(.secondary)
                    Button("Lock Vault") { vault.lock() }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = true
                        panel.canChooseDirectories = false
                        panel.begin { response in
                            guard response == .OK else { return }
                            for url in panel.urls { vault.addFile(from: url) }
                        }
                    } label: { Label("Add Files", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            .padding()
            Divider()
            if !vault.isUnlocked {
                lockedPlaceholder
            } else {
                unlockedContent
            }
        }
        .sheet(isPresented: $showUnlockSheet) { unlockSheet }
        .alert("Vault Error", isPresented: Binding(
            get: { vault.lastError != nil },
            set: { if !$0 { vault.lastError = nil } }
        )) { Button("OK") { vault.lastError = nil } } message: {
            Text(vault.lastError ?? "")
        }
    }

    private var lockedPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 64)).foregroundColor(.blue)
            Text("Secure Vault").font(.title2).fontWeight(.semibold)
            Text("Files are encrypted with AES-256-GCM.\nUnlock to access your vault.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).font(.subheadline)
            Button("Unlock Vault") { showUnlockSheet = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var unlockedContent: some View {
        Group {
            if vault.files.isEmpty {
                dropZone
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160))], spacing: 12) {
                        ForEach(vault.files) { file in
                            VaultFileCard(file: file, isSelected: selectedFileID == file.id)
                                .onTapGesture { selectedFileID = file.id }
                                .contextMenu {
                                    Button("Open") { vault.openFile(file) }
                                    Button("Export...") { vault.exportFile(file) }
                                    Divider()
                                    Button("Delete", role: .destructive) { vault.deleteFile(file) }
                                }
                        }
                    }
                    .padding()
                }
                .overlay(dropTargetOverlay)
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            Color.clear
            VStack(spacing: 12) {
                Image(systemName: isDragTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 48))
                    .foregroundColor(isDragTargeted ? .blue : .secondary)
                Text("Drop files here or click Add Files").foregroundColor(.secondary)
            }
        }
        .background(isDragTargeted ? Color.blue.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var dropTargetOverlay: some View {
        ZStack {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.blue, lineWidth: 2)
                    .background(Color.blue.opacity(0.05).cornerRadius(8))
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { vault.addFile(from: url) }
            }
        }
        return true
    }

    private var unlockSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.doc.fill").font(.system(size: 48)).foregroundColor(.blue)
            Text("Unlock Vault").font(.title2).fontWeight(.semibold)
            SecureField("Master Passcode", text: $passcode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 240).onSubmit { attemptUnlock() }
            if let error = vault.lastError {
                Text(error).foregroundColor(.red).font(.caption)
            }
            HStack {
                Button("Cancel") { showUnlockSheet = false; passcode = "" }.keyboardShortcut(.cancelAction)
                Button("Unlock") { attemptUnlock() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(passcode.isEmpty)
            }
            if AuthenticationManager.shared.canUseBiometrics() {
                Button {
                    AuthenticationManager.shared.authenticateWithBiometrics { success, _ in
                        if success {
                            // For biometric unlock we still need the session key.
                            // Since biometrics proves identity but we need the raw passcode for HKDF,
                            // show a prompt noting the limitation.
                            DispatchQueue.main.async {
                                vault.lastError = "Biometric unlock requires entering passcode once per session to derive encryption key."
                            }
                        }
                    }
                } label: { Label("Use Biometrics", systemImage: "touchid") }
                .buttonStyle(.borderless)
            }
        }
        .padding(32).frame(width: 320)
    }

    private func attemptUnlock() {
        if vault.unlock(passcode: passcode) {
            passcode = ""
            showUnlockSheet = false
        }
    }

    private var totalSize: String {
        vault.formattedSize(vault.files.reduce(0) { $0 + $1.fileSize })
    }
}

struct VaultFileCard: View {
    let file: VaultFile
    let isSelected: Bool
    @ObservedObject var vault = VaultManager.shared

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: vault.iconForExtension(file.fileExtension))
                .font(.system(size: 36)).foregroundColor(.blue).frame(height: 44)
            Text(file.originalName).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            Text(vault.formattedSize(file.fileSize)).font(.caption2).foregroundColor(.secondary)
        }
        .padding(10)
        .frame(width: 120, height: 110)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
    }
}
#endif
