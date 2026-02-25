#if os(iOS)
import SwiftUI
import CloudKit

@MainActor
class iOSIntruderViewModel: ObservableObject {
    @Published var photoRecords: [CKRecord] = []
    @Published var isLoading = false

    func load() {
        isLoading = true
        Task {
            photoRecords = (try? await CloudKitManager.shared.fetchFailedAuthEvents()) ?? []
            isLoading = false
        }
    }
}

struct iOSIntruderPhotosView: View {
    @StateObject private var vm = iOSIntruderViewModel()
    let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading…")
                } else if vm.photoRecords.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "eye.trianglebadge.exclamationmark")
                            .font(.system(size: 60)).foregroundColor(.secondary)
                        Text("No intruder captures").foregroundColor(.secondary)
                        Text("Photos appear here after failed unlock attempts on your Mac")
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }.padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(vm.photoRecords, id: \.recordID) { rec in
                                IntruderPhotoCell(record: rec)
                            }
                        }.padding()
                    }
                }
            }
            .navigationTitle("Intruder Photos")
            .refreshable { vm.load() }
            .task { vm.load() }
        }
    }
}

struct IntruderPhotoCell: View {
    let record: CKRecord
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.2))
                        .overlay(ProgressView())
                }
            }
            .frame(height: 150).clipped().cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(record["deviceName"] as? String ?? "Mac")
                    .font(.caption2).foregroundColor(.secondary)
                if let ts = record["timestamp"] as? Date {
                    Text(ts.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .task {
            guard let asset = record["photoAsset"] as? CKAsset,
                  let url = asset.fileURL,
                  let data = try? Data(contentsOf: url) else { return }
            image = UIImage(data: data)
        }
    }
}
#endif
