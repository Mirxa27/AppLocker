#if os(iOS)
import SwiftUI

@MainActor
class iOSNotesViewModel: ObservableObject {
    @Published var notes: [EncryptedNote] = []
    @Published var sessionPasscode: String?
    @Published var requiresPasscode = true
    @Published var error: String?

    private let notesKey  = "com.applocker.secureNotes"
    private let saltKey   = "notes-salt"

    func loadNotes() {
        guard let data = UserDefaults.standard.data(forKey: notesKey),
              let decoded = try? JSONDecoder().decode([EncryptedNote].self, from: data)
        else { notes = []; return }
        notes = decoded
    }

    func unlock(passcode: String) {
        guard let first = notes.first else {
            sessionPasscode = passcode; requiresPasscode = false; return
        }
        guard let salt = CryptoHelper.loadSaltFromKeychain(key: saltKey) else {
            error = "No notes encryption key found on this device"; return
        }
        let key = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "notes")
        if (try? CryptoHelper.decrypt(first.encryptedBody, using: key)) != nil {
            sessionPasscode = passcode; requiresPasscode = false; error = nil
        } else {
            error = "Incorrect passcode"
        }
    }

    func decryptNote(_ note: EncryptedNote) -> String? {
        guard let passcode = sessionPasscode,
              let salt = CryptoHelper.loadSaltFromKeychain(key: saltKey) else { return nil }
        let key = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "notes")
        guard let data = try? CryptoHelper.decrypt(note.encryptedBody, using: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveNote(_ note: EncryptedNote, body: String) {
        guard let passcode = sessionPasscode,
              let salt = CryptoHelper.loadSaltFromKeychain(key: saltKey),
              let bodyData = body.data(using: .utf8),
              let encrypted = try? CryptoHelper.encrypt(
                  bodyData,
                  using: CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "notes")
              )
        else { return }
        var updated = note
        updated.encryptedBody = encrypted
        updated.modifiedAt    = Date()
        if let idx = notes.firstIndex(where: { $0.id == note.id }) { notes[idx] = updated }
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: notesKey)
        }
    }
}

struct iOSSecureNotesView: View {
    @StateObject private var vm = iOSNotesViewModel()
    @State private var passcodeEntry = ""

    var body: some View {
        NavigationStack {
            Group {
                if vm.requiresPasscode {
                    VStack(spacing: 20) {
                        Image(systemName: "note.text")
                            .font(.system(size: 60)).foregroundColor(.blue)
                        Text("Enter your master passcode to view notes")
                            .multilineTextAlignment(.center)
                        SecureField("Master passcode", text: $passcodeEntry)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                        if let err = vm.error { Text(err).foregroundColor(.red).font(.caption) }
                        Button("Unlock Notes") {
                            vm.unlock(passcode: passcodeEntry); passcodeEntry = ""
                        }.buttonStyle(.borderedProminent)
                    }.padding()
                } else {
                    List(vm.notes) { note in
                        NavigationLink(destination: iOSNoteDetailView(note: note, vm: vm)) {
                            VStack(alignment: .leading) {
                                Text(note.title).font(.headline)
                                Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .overlay(vm.notes.isEmpty
                        ? Text("No notes on Mac yet").foregroundColor(.secondary) : nil)
                }
            }
            .navigationTitle("Secure Notes")
            .task { vm.loadNotes() }
        }
    }
}

struct iOSNoteDetailView: View {
    let note: EncryptedNote
    @ObservedObject var vm: iOSNotesViewModel
    @State private var body_ = ""
    @State private var isEditing = false

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $body_)
                    .padding()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { vm.saveNote(note, body: body_); isEditing = false }
                        }
                    }
            } else {
                ScrollView { Text(body_).padding() }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Edit") { isEditing = true }
                        }
                    }
            }
        }
        .navigationTitle(note.title)
        .onAppear { body_ = vm.decryptNote(note) ?? "" }
    }
}
#endif
