// Sources/AppLocker/iOS/SecureNotes/iOSSecureNotesView.swift
#if os(iOS)
import SwiftUI
import CryptoKit

@MainActor
class iOSNotesViewModel: ObservableObject {
    @Published var notes: [EncryptedNote] = []
    @Published var sessionKey: SymmetricKey? = nil
    @Published var requiresPasscode = true
    @Published var error: String?

    func unlock(passcode: String) {
        let kv = KVStoreManager.shared
        guard let salt = kv.notesSalt else {
            error = "Notes not yet synced from Mac — unlock notes on your Mac first"
            return
        }
        guard !kv.encryptedNotes.isEmpty else {
            sessionKey = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "applocker.notes.v1")
            requiresPasscode = false; notes = []; error = nil
            return
        }
        let key = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "applocker.notes.v1")
        guard let _ = try? CryptoHelper.decrypt(kv.encryptedNotes[0].encryptedBody, using: key) else {
            error = "Incorrect passcode"; return
        }
        sessionKey = key
        notes = kv.encryptedNotes.sorted { $0.modifiedAt > $1.modifiedAt }
        requiresPasscode = false; error = nil
    }

    func lock() { sessionKey = nil; requiresPasscode = true; notes = [] }

    func decryptBody(of note: EncryptedNote) -> String {
        guard let key = sessionKey,
              let data = try? CryptoHelper.decrypt(note.encryptedBody, using: key) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct iOSSecureNotesView: View {
    @StateObject private var vm = iOSNotesViewModel()
    @State private var passcodeEntry = ""

    var body: some View {
        NavigationStack {
            Group {
                if vm.requiresPasscode {
                    unlockPlaceholder
                } else if vm.notes.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "note.text").font(.system(size: 48)).foregroundColor(.secondary)
                        Text("No Notes").font(.title2).foregroundColor(.secondary)
                        Text("Create notes in AppLocker on your Mac.\nThey'll appear here once synced.")
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Spacer()
                    }
                } else {
                    List(vm.notes) { note in
                        NavigationLink(destination: iOSNoteDetailView(note: note, vm: vm)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title).font(.headline)
                                Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Secure Notes")
            .toolbar {
                if !vm.requiresPasscode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Lock") { vm.lock() }
                    }
                }
            }
        }
    }

    private var unlockPlaceholder: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.rectangle.stack.fill").font(.system(size: 60)).foregroundColor(.blue)
            Text("Secure Notes").font(.title2.bold())
            Text("Enter your AppLocker master passcode\nto read notes synced from your Mac.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            SecureField("Master passcode", text: $passcodeEntry)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            if let err = vm.error {
                Text(err).foregroundColor(.red).font(.caption)
            }
            Button("Unlock Notes") { vm.unlock(passcode: passcodeEntry); passcodeEntry = "" }
                .buttonStyle(.borderedProminent).disabled(passcodeEntry.isEmpty)
            Spacer()
        }
        .padding()
    }
}

struct iOSNoteDetailView: View {
    let note: EncryptedNote
    @ObservedObject var vm: iOSNotesViewModel
    @State private var bodyText = ""

    var body: some View {
        ScrollView {
            Text(bodyText.isEmpty ? "(empty note)" : bodyText)
                .padding().frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(note.title)
        .onAppear { bodyText = vm.decryptBody(of: note) }
    }
}
#endif
