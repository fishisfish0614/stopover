import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// Add photos to a trip: pick from the phone, upload the original bytes one by one
// (HEIC is not converted; the server reads it and skips exact duplicates by sha256).

struct AddPhotoSheet: View {
    let trip: StopoverCheckin
    @ObservedObject var store: StopoverStore
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PhotosPickerItem] = []
    @State private var picks: [Pick] = []
    @State private var preparing = false
    @State private var progress: String?

    struct Pick: Identifiable {
        let id = UUID()
        let data: Data
        let filename: String
        let mime: String
        let thumb: UIImage?
        var caption = ""
    }

    private var cityName: String { store.cities[trip.city]?.name ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("给\(cityName)这一次加照片").font(StopoverK.serif(18, .semibold)).foregroundStyle(StopoverK.ink)
                    Spacer()
                    Button { dismiss() } label: { Text("×").font(.system(size: 22)).foregroundStyle(StopoverK.ink2) }.buttonStyle(.plain)
                }
                if preparing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读照片…").font(StopoverK.serif(15)).foregroundStyle(StopoverK.ink)
                    }
                } else if picks.isEmpty {
                    // .current = hand over the original encoding (HEIC stays HEIC)
                    PhotosPicker(selection: $items, maxSelectionCount: 30, matching: .images, preferredItemEncoding: .current) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("从手机选").font(StopoverK.serif(17, .semibold)).foregroundStyle(StopoverK.ink)
                            Text("一次可以选好几张，传过的同一张不会重复存").font(.system(size: 12.5)).foregroundStyle(StopoverK.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(UIColor(hex: 0xF4F1EB)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .onChange(of: items) { _, v in if !v.isEmpty { Task { await prepare(v) } } }
                } else {
                    ForEach($picks) { $p in
                        HStack(alignment: .top, spacing: 12) {
                            Color(UIColor(hex: 0xD8CBB2))
                                .frame(width: 64, height: 64)
                                .overlay { if let t = p.thumb { Image(uiImage: t).resizable().scaledToFill() } }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            // The page forces dark mode for the status bar, so text colors are spelled out
                            TextField("", text: $p.caption, prompt: Text("写一句配文（选填）").foregroundStyle(StopoverK.ink2.opacity(0.7)), axis: .vertical)
                                .lineLimit(1...4)
                                .font(StopoverK.serif(15)).foregroundStyle(StopoverK.ink).tint(StopoverK.harbor)
                                .padding(12)
                                .background(Color(UIColor(hex: 0xF4F1EB)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    Button { Task { await upload() } } label: {
                        Text(progress ?? "挂上 \(picks.count) 张").font(.system(size: 15)).foregroundStyle(StopoverK.paper)
                            .padding(.horizontal, 22).frame(minHeight: 44)
                            .background(Capsule().fill(StopoverK.harbor))
                    }
                    .buttonStyle(.plain).disabled(progress != nil)
                }
            }
            .padding(20)
        }
        .background(Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).ignoresSafeArea())
    }

    private func prepare(_ items: [PhotosPickerItem]) async {
        preparing = true
        var out: [Pick] = []
        for (i, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first ?? .jpeg
            let thumb = await Task.detached { UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 240, height: 240)) }.value
            out.append(Pick(data: data, filename: "photo-\(i + 1).\(type.preferredFilenameExtension ?? "jpg")",
                            mime: type.preferredMIMEType ?? "image/jpeg", thumb: thumb))
        }
        picks = out
        preparing = false
    }

    private func upload() async {
        var ok = 0, capMiss = 0
        for (i, p) in picks.enumerated() {
            progress = "上传第 \(i + 1) / \(picks.count) 张…"
            let (good, pid) = await store.upload(trip: trip.id, data: p.data, filename: p.filename, mime: p.mime)
            guard good else { store.toast = "第 \(i + 1) 张没传上"; continue }
            ok += 1
            // The photo is on the server first; a caption that fails can be written later from the photo itself
            let cap = String(p.caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
            if !cap.isEmpty {
                if let pid, await store.updatePhoto(pid, ["caption": cap]) {} else { capMiss += 1 }
            }
        }
        await store.reloadState()
        store.toast = "挂上 \(ok) 张" + (capMiss > 0 ? "，\(capMiss) 段配文没存上，抽出来再写一下" : "")
        dismiss()
    }
}
