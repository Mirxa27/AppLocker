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

    private let kv = KVStoreManager.shared

    func unlock(passcode: String) {
        guard let salt = kv.notesSalt else {
            error = "Notes have not synced yet. Unlock Secure Notes on your Mac first."
            return
        }

        let key = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "applocker.notes.v1")
        if let firstNote = kv.encryptedNotes.first,
           (try? CryptoHelper.decrypt(firstNote.encryptedBody, using: key)) == nil {
            error = "Incorrect passcode"
            return
        }

        sessionKey = key
        requiresPasscode = false
        error = nil
        refreshFromSync()
    }

    func lock() {
        sessionKey = nil
        requiresPasscode = true
        notes = []
        error = nil
    }

    func refreshFromSync() {
        guard !requiresPasscode else { return }
        notes = kv.encryptedNotes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func note(for noteID: UUID) -> EncryptedNote? {
        notes.first(where: { $0.id == noteID })
    }

    @discardableResult
    func createNote() -> UUID? {
        guard let key = sessionKey,
              let emptyBody = try? CryptoHelper.encrypt(Data(), using: key) else {
            error = "Unlock notes before creating a note."
            return nil
        }

        let note = EncryptedNote(
            id: UUID(),
            title: "New Note",
            encryptedBody: emptyBody,
            createdAt: Date(),
            modifiedAt: Date()
        )
        notes.insert(note, at: 0)
        syncNotes()
        error = nil
        return note.id
    }

    func deleteNote(_ noteID: UUID) {
        notes.removeAll { $0.id == noteID }
        syncNotes()
    }

    func renameNote(_ noteID: UUID, title: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[index].title = normalizedTitle.isEmpty ? "Untitled Note" : normalizedTitle
        notes[index].modifiedAt = Date()
        syncNotes()
    }

    func decryptBody(of noteID: UUID) -> String {
        guard let key = sessionKey,
              let note = note(for: noteID),
              let data = try? CryptoHelper.decrypt(note.encryptedBody, using: key) else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func saveBody(_ body: String, for noteID: UUID) {
        guard let key = sessionKey,
              let index = notes.firstIndex(where: { $0.id == noteID }),
              let encrypted = try? CryptoHelper.encrypt(Data(body.utf8), using: key) else {
            return
        }

        notes[index].encryptedBody = encrypted
        notes[index].modifiedAt = Date()
        syncNotes()
    }

    private func syncNotes() {
        notes.sort { $0.modifiedAt > $1.modifiedAt }
        kv.storeEncryptedNotes(notes)
    }
}

struct iOSSecureNotesView: View {
    @StateObject private var vm = iOSNotesViewModel()
    @ObservedObject private var kv = KVStoreManager.shared
    @State private var passcodeEntry = ""
    @State private var editingNoteID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if vm.requiresPasscode {
                    unlockPlaceholder
                } else if vm.notes.isEmpty {
                    emptyState
                } else {
                    notesList
                }
            }
            .appScreenBackground()
            .navigationTitle("Secure Notes")
            .toolbar {
                if !vm.requiresPasscode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Lock") {
                            vm.lock()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editingNoteID = vm.createNote()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            }
        }
        .onReceive(kv.$encryptedNotes) { _ in
            vm.refreshFromSync()
        }
        .navigationDestination(isPresented: Binding(
            get: { editingNoteID != nil },
            set: { if !$0 { editingNoteID = nil } }
        )) {
            if let editingNoteID {
                iOSNoteEditorView(noteID: editingNoteID, vm: vm)
            }
        }
    }

    private var notesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.notes) { note in
                    NavigationLink(destination: iOSNoteEditorView(noteID: note.id, vm: vm)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(note.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface(padding: 14, cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            vm.deleteNote(note.id)
                        } label: {
                            Label("Delete Note", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var unlockPlaceholder: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.rectangle.stack.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(AppDesign.accent)

            Text("Secure Notes")
                .font(.title2.weight(.bold))

            Text("Enter your AppLocker master passcode to unlock, edit, and sync your encrypted notes.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("Master passcode", text: $passcodeEntry)
                .textFieldStyle(.roundedBorder)

            if let err = vm.error {
                Text(err)
                    .foregroundStyle(AppDesign.danger)
                    .font(.caption)
            }

            Button("Unlock Notes") {
                vm.unlock(passcode: passcodeEntry)
                passcodeEntry = ""
            }
            .buttonStyle(.borderedProminent)
            .tint(AppDesign.accent)
            .disabled(passcodeEntry.isEmpty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppDesign.accent)
            Text("No Notes Yet")
                .font(.title3.weight(.semibold))
            Text("Create your first encrypted note here. Changes sync back through your iCloud AppLocker data store.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Create Note") {
                editingNoteID = vm.createNote()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppDesign.accent)
            if let err = vm.error {
                Text(err)
                    .foregroundStyle(AppDesign.danger)
                    .font(.caption)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct iOSNoteEditorView: View {
    let noteID: UUID
    @ObservedObject var vm: iOSNotesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var hasLoaded = false
    @State private var saveWorkItem: DispatchWorkItem?

    private var note: EncryptedNote? {
        vm.note(for: noteID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TextField("Note title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.weight(.semibold))
                    .onChange(of: title) { _ in
                        scheduleSave()
                    }

                TextEditor(text: $bodyText)
                    .font(.body)
                    .frame(minHeight: 360)
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
                    .onChange(of: bodyText) { _ in
                        scheduleSave()
                    }
            }
            .appSurface(padding: 16, cornerRadius: 18)
            .padding(16)
        }
        .appScreenBackground()
        .navigationTitle(note?.title ?? "Note")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    vm.deleteNote(noteID)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onAppear {
            loadDraft()
        }
        .onDisappear {
            flushPendingSave()
        }
    }

    private func loadDraft() {
        guard let note else { return }
        title = note.title
        bodyText = vm.decryptBody(of: noteID)
        hasLoaded = true
    }

    private func scheduleSave() {
        guard hasLoaded else { return }
        saveWorkItem?.cancel()
        let item = DispatchWorkItem {
            persistDraft()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func flushPendingSave() {
        saveWorkItem?.cancel()
        guard hasLoaded else { return }
        persistDraft()
    }

    private func persistDraft() {
        vm.renameNote(noteID, title: title)
        vm.saveBody(bodyText, for: noteID)
    }
}
#endif
