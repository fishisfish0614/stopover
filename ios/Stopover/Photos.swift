import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// Add photos to a trip: pick from the phone, upload the original bytes one by one
// (HEIC is not converted; the server reads it and skips exact duplicates by sha256).

struct AddPhotoSheet: View {
    let trip: StopoverCheckin
    @ObservedObject var store: StopoverStore
    @Environment(\.dismiss) private var dismiss
    @State private var picks: [PhotosPickerItem] = []
    @State private var progress: String?

    private var cityName: String { store.cities[trip.city]?.name ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("给\(cityName)这一次加照片").font(StopoverK.serif(18, .semibold)).foregroundStyle(StopoverK.ink)
                Spacer()
                Button { dismiss() } label: { Text("×").font(.system(size: 22)).foregroundStyle(StopoverK.ink2) }.buttonStyle(.plain)
            }
            if let progress {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(progress).font(StopoverK.serif(15)).foregroundStyle(StopoverK.ink)
                }
            } else {
                // .current = hand over the original encoding (HEIC stays HEIC)
                PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .images, preferredItemEncoding: .current) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("从手机选").font(StopoverK.serif(17, .semibold)).foregroundStyle(StopoverK.ink)
                        Text("一次可以选好几张，传过的同一张不会重复存").font(.system(size: 12.5)).foregroundStyle(StopoverK.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(UIColor(hex: 0xF4F1EB)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .onChange(of: picks) { _, v in if !v.isEmpty { Task { await upload(v) } } }
            }
            Spacer()
        }
        .padding(20)
        .background(Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).ignoresSafeArea())
    }

    private func upload(_ items: [PhotosPickerItem]) async {
        var ok = 0
        for (i, item) in items.enumerated() {
            progress = "上传第 \(i + 1) / \(items.count) 张…"
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first ?? .jpeg
            let name = "photo-\(i + 1).\(type.preferredFilenameExtension ?? "jpg")"
            if await store.upload(trip: trip.id, data: data, filename: name, mime: type.preferredMIMEType ?? "image/jpeg") { ok += 1 }
            else { store.toast = "第 \(i + 1) 张没传上" }
        }
        await store.reloadState()
        store.toast = "挂上 \(ok) 张"
        dismiss()
    }
}
