// Sources/AppLocker/SecureNotes/SecureNotesView.swift
#if os(macOS)
import SwiftUI

struct SecureNotesView: View {
    @ObservedObject var manager = SecureNotesManager.shared
    @State private var selectedNoteID: UUID?
    @State private var editingBody: String = ""
    @State private var passcode = ""
    @State private var showUnlockSheet = false
    @State private var saveWorkItem: DispatchWorkItem?
    @State private var editingTitle: String = ""
    @State private var isEditingTitle = false

    var selectedNote: EncryptedNote? {
        guard let id = selectedNoteID else { return nil }
        return manager.notes.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if !manager.isUnlocked {
                lockedPlaceholder
            } else {
                editorLayout
            }
        }
        .sheet(isPresented: $showUnlockSheet) { unlockSheet }
        .alert("Notes Error", isPresented: Binding(
            get: { manager.lastError != nil },
            set: { if !$0 { manager.lastError = nil } }
        )) { Button("OK") { manager.lastError = nil } } message: {
            Text(manager.lastError ?? "")
        }
    }

    private var lockedPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.rectangle.stack.fill").font(.system(size: 64)).foregroundColor(.blue)
            Text("Secure Notes").font(.title2).fontWeight(.semibold)
            Text("Notes are encrypted with AES-256-GCM.\nUnlock to read and edit.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("Unlock Notes") { showUnlockSheet = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var editorLayout: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Notes (\(manager.notes.count))")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        if let note = manager.createNote() {
                            selectedNoteID = note.id
                            editingBody = ""
                            editingTitle = note.title
                        }
                    } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).help("New Note")
                    Button("Lock") { manager.lock(); selectedNoteID = nil }
                        .buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal).padding(.top, 8)
                Divider().padding(.top, 6)

                List(manager.notes, selection: $selectedNoteID) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).fontWeight(.medium).lineLimit(1)
                        Text(note.modifiedAt, style: .relative)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .tag(note.id)
                    .contextMenu {
                        Button("Delete Note", role: .destructive) { manager.deleteNote(note) }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 180, maxWidth: 240)

            VStack(alignment: .leading, spacing: 0) {
                if let note = selectedNote {
                    HStack {
                        if isEditingTitle {
                            TextField("Note title", text: $editingTitle)
                                .textFieldStyle(.plain).font(.title3.bold())
                                .onSubmit { manager.renameNote(note.id, title: editingTitle); isEditingTitle = false }
                                .onExitCommand { manager.renameNote(note.id, title: editingTitle); isEditingTitle = false }
                        } else {
                            Text(note.title).font(.title3.bold())
                                .onTapGesture(count: 2) { editingTitle = note.title; isEditingTitle = true }
                        }
                        Spacer()
                        Text("Modified \(note.modifiedAt, style: .relative) ago")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding()
                    Divider()
                    TextEditor(text: $editingBody)
                        .font(.body).padding(8)
                        .onChange(of: editingBody) { _ in scheduleSave(noteID: note.id) }
                        .onAppear {
                            editingBody = manager.decryptBody(of: note)
                            editingTitle = note.title
                        }
                        .onChange(of: selectedNoteID) { newID in
                            if let id = newID, let n = manager.notes.first(where: { $0.id == id }) {
                                editingBody = manager.decryptBody(of: n)
                                editingTitle = n.title
                                isEditingTitle = false
                            }
                        }
                } else {
                    VStack { Spacer(); Text("Select a note or create one").foregroundColor(.secondary); Spacer() }
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var unlockSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.rectangle.stack.fill").font(.system(size: 48)).foregroundColor(.blue)
            Text("Unlock Notes").font(.title2).fontWeight(.semibold)
            SecureField("Master Passcode", text: $passcode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 240).onSubmit { attemptUnlock() }
            if let error = manager.lastError {
                Text(error).foregroundColor(.red).font(.caption)
            }
            HStack {
                Button("Cancel") { showUnlockSheet = false; passcode = "" }.keyboardShortcut(.cancelAction)
                Button("Unlock") { attemptUnlock() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(passcode.isEmpty)
            }
        }
        .padding(32).frame(width: 320)
    }

    private func attemptUnlock() {
        if manager.unlock(passcode: passcode) { passcode = ""; showUnlockSheet = false }
    }

    private func scheduleSave(noteID: UUID) {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { manager.saveBody(editingBody, for: noteID) }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}
#endif
