import SwiftUI
import CoreText

import UserNotifications

@main
struct StopoverApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var push
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

extension Notification.Name {
    /// object = city id; posted when a push is tapped
    static let stopoverOpenCity = Notification.Name("stopoverOpenCity")
}

/// Optional push (off by default). Builds and runs without any push entitlement or paid developer account;
/// it only does something after the user turns it on in Settings, the server reports features.push_apns,
/// and the app was signed with the Push Notifications capability (see ios/README.md).
final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "push") }
        set { UserDefaults.standard.set(newValue, forKey: "push") }
    }

    func application(_ app: UIApplication, didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if Self.enabled { app.registerForRemoteNotifications() }
        return true
    }

    static func turnOn() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            guard ok else { return }
            DispatchQueue.main.async { enabled = true; UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        Task { @MainActor in await StopoverStore.shared.registerPush(token: hex, sandbox: sandbox) }
    }

    func application(_ app: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("push: not registered (\(error.localizedDescription)) — is the Push Notifications capability on?")
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// custom: {"route":"stopover","city":…,"target":…,"share_id":…} → fly to that city
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        let info = r.notification.request.content.userInfo
        guard (info["route"] as? String)?.hasSuffix("stopover") == true, let city = info["city"] as? String else { return }
        await MainActor.run { NotificationCenter.default.post(name: .stopoverOpenCity, object: city) }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Chinese serif = the system's on-demand Songti SC. iOS ships no Simplified Chinese serif
/// (the built-in Mincho is Japanese and misses many common characters), so it's requested at launch;
/// until it arrives the system fallback is used.
enum Songti {
    static let names = ["STSongti-SC-Regular", "STSongti-SC-Bold", "STSongti-SC-Black"]
    static var installed: Bool { UIFont(name: "STSongti-SC-Black", size: 12) != nil }

    static func request(_ done: @escaping () -> Void) {
        guard !installed else { return }
        let descs = names.map { CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary) }
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descs as CFArray, nil) { state, _ in
            if state == .didFinish { DispatchQueue.main.async(execute: done) }
            return true
        }
    }
}

/// Remote image (Wikimedia, or the server's own photo thumbnails), cached on disk
struct WikiImage: View {
    let url: URL
    var fit = false
    var onFail: (() -> Void)? = nil
    @State private var image: UIImage?

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("img", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    var body: some View {
        Group {
            if let image {
                if fit { Image(uiImage: image).resizable().scaledToFit() } else { Image(uiImage: image).resizable().scaledToFill() }
            } else {
                Rectangle().fill(StopoverK.ink.opacity(0.06))
            }
        }
        .task(id: url) {
            let file = Self.dir.appendingPathComponent(String(url.absoluteString.hashValue, radix: 36) + "-" + url.lastPathComponent.prefix(40))
            if let d = try? Data(contentsOf: file), let img = UIImage(data: d) { image = img; return }
            guard let (d, r) = try? await URLSession.shared.data(from: url),
                  (r as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: d) else { onFail?(); return }
            try? d.write(to: file, options: .atomic)
            withAnimation(.easeOut(duration: 0.25)) { image = img }
        }
    }
}

/// Chips that wrap onto the next line
struct ChipFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > b.maxX, x > b.minX { x = b.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

/// One-line toast that clears itself after 3 seconds
extension View {
    func stopoverToast(_ store: StopoverStore) -> some View { modifier(StopoverToast(store: store)) }
}

private struct StopoverToast: ViewModifier {
    @ObservedObject var store: StopoverStore
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let t = store.toast {
                // Paper background, dark text: readable on the dark ticket, the night globe and the paper card alike
                Text(t).font(StopoverK.serif(14)).foregroundStyle(StopoverK.ink)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(StopoverK.paper, in: Capsule())
                    .overlay(Capsule().strokeBorder(StopoverK.ink.opacity(0.08)))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .padding(.top, 60).padding(.horizontal, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: t) {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { if store.toast == t { store.toast = nil } }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.toast)
    }
}

/// Server address. Shown on first launch and from the gear on the globe page.
struct ServerSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = StopoverStore.serverString
    @State private var push = PushDelegate.enabled
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("服务器地址").font(StopoverK.serif(20, .semibold)).foregroundStyle(StopoverK.ink)
            Text("运行 server/stopover.py 的那台机器。在同一台 Mac 上开模拟器就用默认的 localhost；真机要填电脑的局域网地址，比如 http://192.168.1.10:8000。")
                .font(.system(size: 13)).foregroundStyle(StopoverK.ink2).lineSpacing(4)
            TextField(StopoverStore.defaultServer, text: $text)
                .font(.system(size: 16, design: .monospaced))
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .padding(12)
                .background(Color(UIColor(hex: 0xF4F1EB)), in: RoundedRectangle(cornerRadius: 10))
            if StopoverStore.shared.config.pushAPNs {
                Toggle(isOn: Binding(get: { push }, set: { v in push = v; if v { PushDelegate.turnOn() } else { PushDelegate.enabled = false } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("推送").font(StopoverK.serif(15, .semibold)).foregroundStyle(StopoverK.ink)
                        Text("\(StopoverStore.shared.config.partner)递东西给你、回你时提醒（需要签名时开了推送能力，见 README）")
                            .font(.system(size: 12)).foregroundStyle(StopoverK.ink2)
                    }
                }
                .tint(StopoverK.harbor)
            }
            HStack {
                Button {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    StopoverStore.serverString = t.isEmpty ? StopoverStore.defaultServer : (t.hasSuffix("/") ? String(t.dropLast()) : t)
                    UserDefaults.standard.set(true, forKey: "serverSet")
                    onSave()
                    dismiss()
                } label: {
                    Text("保存").font(.system(size: 15)).foregroundStyle(StopoverK.paper)
                        .padding(.horizontal, 22).frame(minHeight: 44).background(Capsule().fill(StopoverK.harbor))
                }
                .buttonStyle(.plain)
                Button("恢复默认") { text = StopoverStore.defaultServer }
                    .font(.system(size: 14)).foregroundStyle(StopoverK.harbor).padding(.leading, 12)
            }
            Spacer()
        }
        .padding(24)
        .background(StopoverK.paper.ignoresSafeArea())
    }
}
