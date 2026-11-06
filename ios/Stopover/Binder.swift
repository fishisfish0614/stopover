import SwiftUI
import Vision

// 「这一次」的活页夹。
// 合上: 票 + 文件夹(头几张照片探出来)+ 加一页 / GATE / 对方说。点开: 前盖翻下、纸飞出来变竖条占满全屏。
// 竖条左右滑;手指按住一条往上拖 = 把这页抽出来,抽够了展开成海报内页。
// 开合时画的是一层绝对定位的纸(fanLayer),动完才换成真的横滑列表,不然懒列表没法一张张飞。
// 老的网格页还在 TripPage 里: 票右上角能切,递东西「挑几段、几张」也走它。

private enum BinderK {
    static let tabW: CGFloat = 30
    static let tabH: CGFloat = 96
    static let narrowW: CGFloat = 46
    static let coverW: CGFloat = 78
    static let minW: CGFloat = 66
    static let topGap: CGFloat = 14
    static let pullToOpen: CGFloat = 110

    /// 纸的颜色,一条条轮着来
    static let tones: [(paper: Color, ink: Color)] = [
        (Color(UIColor(hex: 0xA89F8F)), Color(UIColor(hex: 0x24221F))),
        (Color(UIColor(hex: 0xE4DCC8)), Color(UIColor(hex: 0x2B2A28))),
        (Color(UIColor(hex: 0x8E97A3)), Color(UIColor(hex: 0x14181D))),
        (Color(UIColor(hex: 0xB08F63)), Color(UIColor(hex: 0x24190D))),
        (Color(UIColor(hex: 0x34322E)), Color(UIColor(hex: 0xE6E2DA))),
        (Color(UIColor(hex: 0x8A8A76)), Color(UIColor(hex: 0x191A12))),
    ]
    static let night = Color(UIColor(hex: 0x1F2A38))
    static let nightInk = Color(UIColor(hex: 0xE6E2DA))

    /// 纸纹: 一小块随机细点平铺,比模糊便宜
    static let grain: UIImage = {
        let n: CGFloat = 90
        var gen = SystemRandomNumberGenerator()
        return UIGraphicsImageRenderer(size: CGSize(width: n, height: n)).image { ctx in
            for _ in 0..<520 {
                let x = CGFloat.random(in: 0..<n, using: &gen), y = CGFloat.random(in: 0..<n, using: &gen)
                let dark = Bool.random(using: &gen)
                (dark ? UIColor.black : UIColor.white).withAlphaComponent(CGFloat.random(in: 0.03...0.09, using: &gen)).setFill()
                ctx.fill(CGRect(x: x, y: y, width: 1, height: CGFloat.random(in: 1...2.5, using: &gen)))
            }
        }
    }()

    static let cnBody = UIFont(name: "STSongti-SC-Regular", size: 17) ?? .systemFont(ofSize: 17)
}

/// 夹子里的一页
enum BinderLeaf: Identifiable, Equatable {
    case cover(title: String, range: String, sub: String)
    case day(n: Int, date: String)
    case photo(StopoverPhoto, fig: Int)
    case note(StopoverNote)
    case add
    case gate
    case talk(Int)

    var id: String {
        switch self {
        case .cover: "cover"
        case .day(let n, _): "day\(n)"
        case .photo(let p, _): "p\(p.id)"
        case .note(let n): "n\(n.id)"
        case .add: "add"
        case .gate: "gate"
        case .talk: "talk"
        }
    }

    var pullable: Bool {
        switch self { case .cover, .day: false; default: true }
    }

    var hasTab: Bool {
        switch self { case .photo, .note: true; default: false }
    }

    var flexible: Bool { hasTab }

    /// 按拍摄时间排、跨天才分章;随记写的时间落在哪天就夹进哪天,写得晚的(事后补的)放最前面
    static func build(cityEn: String, photos: [StopoverPhoto], notes: [StopoverNote], talk: Int) -> [BinderLeaf] {
        let cal = Calendar.current
        let sorted = photos.sorted { ($0.taken ?? .infinity, $0.id) < ($1.taken ?? .infinity, $1.id) }
        let days = Array(Set(sorted.compactMap(\.taken).map { cal.startOfDay(for: Date(timeIntervalSince1970: $0)) })).sorted()
        func dayIndex(_ t: Double) -> Int? {
            days.firstIndex(of: cal.startOfDay(for: Date(timeIntervalSince1970: t)))
        }
        var buckets = Array(repeating: [(t: Double, leaf: BinderLeaf)](), count: max(1, days.count))
        for (i, p) in sorted.enumerated() {
            // 没拍摄时间的跟在最后一天后面
            let b = p.taken.flatMap(dayIndex) ?? (buckets.count - 1)
            buckets[b].append((p.taken ?? .infinity, .photo(p, fig: i + 1)))
        }
        var loose: [BinderLeaf] = []
        for n in notes.sorted(by: { $0.created < $1.created }) {
            if let b = dayIndex(n.created) { buckets[b].append((n.created, .note(n))) } else { loose.append(.note(n)) }
        }

        var out: [BinderLeaf] = []
        let dayWord = days.count > 1 ? " · \(days.count) DAYS" : ""
        out.append(.cover(title: cityEn.uppercased(),
                          range: sorted.isEmpty ? "" : String(format: "_01–%02d", sorted.count),
                          sub: sorted.isEmpty ? "NO FIGS YET" : "\(sorted.count) FIG\(sorted.count == 1 ? "" : "S")" + dayWord))
        out += loose
        let df = DateFormatter(); df.dateFormat = "M.d"
        for (i, b) in buckets.enumerated() {
            if days.count > 1 { out.append(.day(n: i + 1, date: df.string(from: days[i]))) }
            out += b.sorted { $0.t < $1.t }.map(\.leaf)
        }
        return out
    }
}

// MARK: - 图和人脸

/// 竖条用的中图 + 脸在哪(窄条按脸对齐,不然自拍只剩半张脸)。整页共用一份
@MainActor
final class BinderImages: ObservableObject {
    @Published var images: [Int: UIImage] = [:]
    @Published var focus: [Int: CGFloat] = [:]
    /// 海报内页的底色: 这张照片的主色压深
    @Published var tones: [Int: Color] = [:]
    private var loading: Set<Int> = []

    /// 不跟视图的 .task 走: 懒列表重排会取消 task,图就永远下不完了
    func request(_ id: Int, big: Bool) {
        guard images[id] == nil, !loading.contains(id) else { return }
        loading.insert(id)
        Task { await load(id, big: big); loading.remove(id) }
    }

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("binder", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func load(_ id: Int, big: Bool) async {
        // 600 = 服务端的小图;十几张同时解码大图吃不消。照片少、竖条宽的时候 600 会糊,才要大图
        let w = big ? 1600 : 600
        let url = StopoverStore.photoURL(id, w: w)
        let file = Self.dir.appendingPathComponent("\(url.host ?? "local")-\(id)-\(w)")
        var img = (try? Data(contentsOf: file)).flatMap { UIImage(data: $0) }
        if img == nil, let (d, r) = try? await URLSession.shared.data(from: url),
           (r as? HTTPURLResponse)?.statusCode == 200, let x = UIImage(data: d) {
            try? d.write(to: file, options: .atomic)
            img = x
        }
        guard let img else { return }
        withAnimation(.easeOut(duration: 0.25)) { images[id] = img }
        let f = await Task.detached(priority: .utility) { Self.faceFocus(img) }.value
        withAnimation(.easeInOut(duration: 0.3)) { focus[id] = f }
        let c = await Task.detached(priority: .utility) { Self.posterTone(img) }.value
        tones[id] = Color(c)
    }

    /// 按色相分桶,鲜艳的像素权重大,取最多的那一桶,压成能托住浅色字的深色。
    /// 不直接求平均: 平均出来一张照片一个灰
    nonisolated private static func posterTone(_ img: UIImage) -> UIColor {
        let n = 28
        let fallback = UIColor(hue: 0.08, saturation: 0.16, brightness: 0.27, alpha: 1)
        guard let cg = img.cgImage,
              let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = { ctx.interpolationQuality = .medium
                  ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
                  return ctx.data }() else { return fallback }
        let px = raw.bindMemory(to: UInt8.self, capacity: n * n * 4)
        let bins = 14
        var weight = [CGFloat](repeating: 0, count: bins)
        var satSum = [CGFloat](repeating: 0, count: bins)
        var hueX = [CGFloat](repeating: 0, count: bins)
        var hueY = [CGFloat](repeating: 0, count: bins)
        for i in 0..<(n * n) {
            let c = UIColor(red: CGFloat(px[i * 4]) / 255, green: CGFloat(px[i * 4 + 1]) / 255, blue: CGFloat(px[i * 4 + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0
            c.getHue(&h, saturation: &sat, brightness: &b, alpha: nil)
            guard sat > 0.14, b > 0.12 else { continue }
            let w = sat * b
            let k = min(bins - 1, Int(h * CGFloat(bins)))
            weight[k] += w
            satSum[k] += sat * w
            hueX[k] += cos(h * 2 * .pi) * w
            hueY[k] += sin(h * 2 * .pi) * w
        }
        guard let top = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[top] > 1 else { return fallback }
        var h = atan2(hueY[top], hueX[top]) / (2 * .pi)
        if h < 0 { h += 1 }
        let sat = min(0.62, max(0.3, satSum[top] / weight[top]))
        return UIColor(hue: h, saturation: sat, brightness: 0.33, alpha: 1)
    }

    /// 最大那张脸的水平中心(0...1),没脸就居中
    nonisolated private static func faceFocus(_ img: UIImage) -> CGFloat {
        guard let cg = img.cgImage else { return 0.5 }
        let orientation: CGImagePropertyOrientation
        switch img.imageOrientation {
        case .down: orientation = .down
        case .left: orientation = .left
        case .right: orientation = .right
        default: orientation = .up
        }
        let req = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([req])
        guard let face = req.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else { return 0.5 }
        return face.boundingBox.midX
    }
}

/// 一张图按 fill 填进 size,水平方向让 focus 尽量落在正中
private struct BinderSlice: View {
    let image: UIImage
    let focus: CGFloat
    let size: CGSize

    var body: some View {
        let iw = max(image.size.width, 1), ih = max(image.size.height, 1)
        let s = max(size.width / iw, size.height / ih)
        let dw = iw * s, dh = ih * s
        let room = max(0, (dw - size.width) / 2)
        let dx = min(room, max(-room, (0.5 - focus) * dw))
        Image(uiImage: image).resizable()
            .frame(width: dw, height: dh)
            .offset(x: dx)
            .frame(width: size.width, height: size.height)
            .clipped()
    }
}

/// 胖胖的标签: 外角圆、和纸相接的地方内凹,不是硬贴上去的一块
private struct BinderTabShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, f: CGFloat = 8, c: CGFloat = 12
        var p = Path()
        p.move(to: CGPoint(x: w, y: 0))
        p.addQuadCurve(to: CGPoint(x: w - f, y: f), control: CGPoint(x: w, y: f))
        p.addLine(to: CGPoint(x: c, y: f))
        p.addQuadCurve(to: CGPoint(x: 0, y: f + c), control: CGPoint(x: 0, y: f))
        p.addLine(to: CGPoint(x: 0, y: h - f - c))
        p.addQuadCurve(to: CGPoint(x: c, y: h - f), control: CGPoint(x: 0, y: h - f))
        p.addLine(to: CGPoint(x: w - f, y: h - f))
        p.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w, y: h - f))
        p.closeSubpath()
        return p
    }
}

/// 文件夹后片: 左上角一个胖标签,和身子接的地方是弧的
private struct FolderBackShape: Shape {
    let tabH: CGFloat
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, c: CGFloat = 22, tabW = min(120, w * 0.4)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h - c))
        p.addLine(to: CGPoint(x: 0, y: 14))
        p.addQuadCurve(to: CGPoint(x: 14, y: 0), control: .zero)
        p.addLine(to: CGPoint(x: tabW - 10, y: 0))
        p.addCurve(to: CGPoint(x: tabW + 18, y: tabH), control1: CGPoint(x: tabW + 4, y: 0), control2: CGPoint(x: tabW + 4, y: tabH))
        p.addLine(to: CGPoint(x: w - c, y: tabH))
        p.addQuadCurve(to: CGPoint(x: w, y: tabH + c), control: CGPoint(x: w, y: tabH))
        p.addLine(to: CGPoint(x: w, y: h - c))
        p.addQuadCurve(to: CGPoint(x: w - c, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: c, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - c), control: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}

/// 转 90° 的一块(字从上往下读),宽高按转完之后算
private struct BinderVertical<C: View>: View {
    let w: CGFloat
    let h: CGFloat
    var alignment: Alignment = .leading
    @ViewBuilder let content: C
    var body: some View {
        content.frame(width: h, height: w, alignment: alignment)
            .rotationEffect(.degrees(90))
            .frame(width: w, height: h)
    }
}

// MARK: - 往上抽的手势

/// 挂在 ScrollView 内容里,往上找到真正的 UIScrollView: 观察滚动位置,需要的话再加一个只认
/// 「往上、竖向为主」的拖动,横向留给 ScrollView。最低 iOS 17,没有 onScrollGeometryChange / UIGestureRecognizerRepresentable
private struct BinderScrollHook: UIViewRepresentable {
    var onOffset: (CGPoint) -> Void
    var began: ((CGPoint) -> Void)? = nil
    var changed: ((CGFloat) -> Void)? = nil
    var ended: ((CGFloat) -> Void)? = nil

    final class Probe: UIView {
        var found: ((UIScrollView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var v = superview
            while let x = v {
                if let s = x as? UIScrollView { found?(s); return }
                v = x.superview
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: BinderScrollHook
        private weak var scroll: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var pan: UIPanGestureRecognizer?

        init(_ p: BinderScrollHook) { parent = p }

        func attach(_ s: UIScrollView) {
            guard scroll !== s else { return }
            detach()
            scroll = s
            observation = s.observe(\.contentOffset, options: [.initial, .new]) { [weak self] sv, _ in
                let o = sv.contentOffset, i = sv.adjustedContentInset
                let at = CGPoint(x: o.x + i.left, y: o.y + i.top)
                DispatchQueue.main.async { self?.parent.onOffset(at) }
            }
            guard parent.began != nil else { return }
            let g = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            g.delegate = self
            s.addGestureRecognizer(g)
            s.panGestureRecognizer.require(toFail: g)
            pan = g
        }

        func detach() {
            observation?.invalidate(); observation = nil
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            pan = nil; scroll = nil
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return true }
            let v = p.velocity(in: p.view)
            return v.y < 0 && abs(v.y) > abs(v.x) * 1.15
        }

        @objc func handle(_ g: UIPanGestureRecognizer) {
            guard let sv = g.view as? UIScrollView else { return }
            switch g.state {
            case .began:
                let t = g.translation(in: sv), at = g.location(in: sv), o = sv.contentOffset
                parent.began?(CGPoint(x: at.x - o.x - t.x, y: at.y - o.y - t.y))
            case .changed: parent.changed?(-g.translation(in: sv).y)
            case .ended, .cancelled, .failed: parent.ended?(g.velocity(in: sv).y)
            default: break
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Probe {
        let v = Probe()
        v.isUserInteractionEnabled = false
        let c = context.coordinator
        v.found = { [weak c] s in c?.attach(s) }
        return v
    }

    func updateUIView(_ v: Probe, context: Context) { context.coordinator.parent = self }

    static func dismantleUIView(_ v: Probe, coordinator: Coordinator) { coordinator.detach() }
}

// MARK: - 整页

struct StopoverBinderPage: View {
    let trip: StopoverCheckin
    @ObservedObject var store: StopoverStore
    /// 进来就从文件夹里抽出这一页(BinderLeaf.id)
    var focusLeaf: String? = nil
    let ticket: AnyView
    let gatePage: AnyView
    let talkPage: AnyView
    let editPhoto: (StopoverPhoto) -> Void
    let editNote: (StopoverNote) -> Void
    let shareNote: (StopoverNote) -> Void
    let newNote: () -> Void
    let addPhoto: () -> Void
    /// features.share = false: 没有 GATE / 对方说
    var sharing = true

    @StateObject private var images = BinderImages()
    @State private var binderFrame: CGRect = .zero
    // 文件夹: 每次进来都是合上的
    @State private var opened = false          // 开合动画的目标
    @State private var showReal = false        // 动完了,换成真的横滑列表
    @State private var fanOffset: CGFloat = 0  // 收的时候从滑到的位置收回去
    @State private var openToken = 0
    @State private var ticketH: CGFloat = 0
    @State private var entryFrames: [String: CGRect] = [:]
    @State private var focusDone = false
    // 内页里的对话: 键盘盖住输入框时把那组滚上来
    @State private var keyboardH: CGFloat = 0
    @State private var threadFocus: String?
    @State private var scroll = ScrollRef()

    // 正抽着 / 抽出来的那页
    @State private var active: Active?
    @State private var pullY: CGFloat = 0
    @State private var t: CGFloat = 0          // 0 还是窄条,1 铺满
    @State private var settled = false         // 动画走完,换成能滚的内页
    @State private var textIn = false
    @State private var passed = false
    private let tick = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)

    final class ScrollRef { var x: CGFloat = 0 }

    struct Active: Equatable {
        let leaf: BinderLeaf
        let source: CGRect
        let tone: Int
        let tabY: CGFloat
    }

    private var leaves: [BinderLeaf] {
        BinderLeaf.build(cityEn: store.cities[trip.city]?.en ?? "",
                         photos: store.photos(trip: trip.id), notes: store.notes(trip: trip.id),
                         talk: store.comments("trip:\(trip.id)").count)
    }

    var body: some View {
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            GeometryReader { g in
                let ls = leaves
                let ws = widths(ls, total: g.size.width)
                let f = folderLayout(screen: g.size, insets: insets)
                ZStack(alignment: .topLeading) {
                    if !showReal {
                        folderAura(f, ls: ls)
                            .opacity(opened ? 0 : 1)
                            .animation(.easeOut(duration: 0.24).delay(opened ? 0.05 : 0.18), value: opened)
                    }
                    folderBack(f)
                    // 高出后片的那截照片也要点得开(纸本身不接点击)
                    if !opened {
                        Color.clear.contentShape(Rectangle())
                            .frame(width: f.backRect.width, height: f.backRect.height * 0.34 + 4)
                            .offset(x: f.backRect.minX, y: f.backRect.minY - 4)
                            .onTapGesture { tapFolder(f) }
                    }
                    if showReal {
                        binder(width: g.size.width).padding(.top, insets.top)
                    } else {
                        fanLayer(ls, ws: ws, screen: g.size, insets: insets, f: f)
                    }
                    folderFront(f, ls: ls)
                    entries(f, width: g.size.width)
                    ticket.padding(.horizontal, 18).padding(.top, insets.top)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { ticketH = $0 }
                        // 打开时票收到顶上,只留深色那条垫着状态栏
                        .offset(y: opened ? -(ticketH - 10 - insets.top) : 0)
                        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: opened)
                    // 票的字别露在状态栏后面: 只留一条干净的深色
                    Color(UIColor(hex: 0x1F2A38))
                        .frame(height: max(0, insets.top - 6))
                        .opacity(opened ? 1 : 0)
                        .animation(.easeOut(duration: 0.18).delay(opened ? 0.12 : 0), value: opened)
                        .allowsHitTesting(false)
                    closePill(insets: insets)
                    if let a = active { sheet(a, screen: g.size, insets: insets) }
                }
                .coordinateSpace(.named("binderPage"))
            }
            .ignoresSafeArea()
        }
        .background(Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).ignoresSafeArea())
        .onChange(of: store.photos) { _, ps in
            // 抽出来的这张被取下了,插回去
            if case .photo(let p, _)? = active?.leaf, !ps.contains(where: { $0.id == p.id }) { close() }
        }
        .task { await openFocusLeaf() }
    }

    // MARK: 文件夹

    /// 从往来跳来的: 先把文件夹打开,再从竖条上抽出那一页,和手动抽走同一条路。
    /// 不能在合着的文件夹上直接抽: 真机上之后第三方键盘打不了字,杀掉 App 才恢复
    private func openFocusLeaf() async {
        guard !focusDone, let id = focusLeaf else { return }
        focusDone = true
        guard leaves.contains(where: { $0.id == id }) else { return }
        for _ in 0..<20 where ticketH == 0 { try? await Task.sleep(for: .milliseconds(50)) }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { opened = true; showReal = true }
        scroll.x = 0
        for _ in 0..<20 where binderFrame == .zero { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .milliseconds(350))
        let ls = leaves
        guard active == nil, let i = ls.firstIndex(where: { $0.id == id }), binderFrame != .zero else { return }
        if case .photo(let p, _) = ls[i] { images.request(p.id, big: false) }
        let ws = widths(ls, total: binderFrame.width)
        begin(i, ls: ls, ws: ws, seq: tabSequence(ls), H: binderFrame.height - BinderK.topGap)
        // 滑到屏幕外的那条: 从屏幕边上长出来,别从看不见的地方飞进来
        if let a = active, a.source.minX > binderFrame.width - a.source.width {
            var s = a.source
            s.origin.x = binderFrame.width - s.width
            active = Active(leaf: a.leaf, source: s, tone: a.tone, tabY: a.tabY)
        }
        open()
    }

    private struct FolderLayout {
        var backRect: CGRect     // 文件夹占的整块;前片贴它的底
        /// 后片比照片矮: 照片要高出后片一截
        var shellRect: CGRect {
            CGRect(x: backRect.minX, y: backRect.minY + backRect.height * 0.22,
                   width: backRect.width, height: backRect.height * 0.78)
        }
        var frontH: CGFloat
        var entriesTop: CGFloat
        var cardSize: CGSize
    }

    private func folderLayout(screen: CGSize, insets: EdgeInsets) -> FolderLayout {
        let entriesH: CGFloat = sharing ? 54 * 2 + 10 : 54
        let entriesTop = screen.height - insets.bottom - 16 - entriesH
        let top = ticketH + 40
        let room = entriesTop - 18 - top
        let h = max(170, min(room, 310))
        let back = CGRect(x: 24, y: top + max(0, room - h) / 2, width: screen.width - 48, height: h)
        return FolderLayout(backRect: back, frontH: h * 0.66, entriesTop: entriesTop,
                            // 卡片只伸进前片一点: 玻璃里透的要是光晕,垫着深色纸会发灰
                            cardSize: CGSize(width: min(screen.width * 0.27, 108), height: h * 0.6))
    }

    /// 玻璃里的颜色: 头几张照片糊开,只垫在文件夹形状里面(漏到外面会像一圈图片,页面背景保持纯色)。
    /// 外面只有一圈很淡的白色柔光。合着才画,打开后拆掉
    private func folderAura(_ f: FolderLayout, ls: [BinderLeaf]) -> some View {
        let tabH: CGFloat = 22
        let shape = FolderBackShape(tabH: tabH)
        let ids: [Int] = ls.compactMap { if case .photo(let p, _) = $0 { p.id } else { nil } }
        let shots = ids.prefix(4).compactMap { images.images[$0] }
        let size = CGSize(width: f.shellRect.width, height: f.shellRect.height + tabH)
        return ZStack {
            shape.fill(Color.white).blur(radius: 14).opacity(0.8)
            ZStack {
                // 没图(还没下完 / 只有随记)也有一层暖光
                Color(UIColor(hex: 0xE9B878))
                HStack(spacing: 0) {
                    ForEach(Array(shots.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: size.width / CGFloat(max(1, shots.count)), height: size.height).clipped()
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .saturation(1.7)
            .blur(radius: 30, opaque: true)
            .clipShape(shape)
            .opacity(0.9)
        }
        .frame(width: size.width, height: size.height)
        .offset(x: f.shellRect.minX, y: f.shellRect.minY - tabH)
        .allowsHitTesting(false)
    }

    private func folderBack(_ f: FolderLayout) -> some View {
        let tabH: CGFloat = 22
        let shape = FolderBackShape(tabH: tabH)
        return ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.white.opacity(0.22))
            shape.stroke(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .environment(\.colorScheme, .light)
        .frame(width: f.shellRect.width, height: f.shellRect.height + tabH)
        .contentShape(shape)
        .offset(x: f.shellRect.minX, y: f.shellRect.minY - tabH)
            .opacity(opened ? 0 : 1)
            .animation(.easeOut(duration: 0.22).delay(opened ? 0.2 : 0.14), value: opened)
            .onTapGesture { tapFolder(f) }
    }

    private func folderFront(_ f: FolderLayout, ls: [BinderLeaf]) -> some View {
        let ink = Color(UIColor(hex: 0x4A3722))
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            Text((store.cities[trip.city]?.en ?? "").uppercased())
                .font(.system(size: 34, weight: .black)).fontWidth(.expanded)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(folderSub(ls)).font(StopoverK.mono(12, .medium)).opacity(0.75)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(width: f.backRect.width, height: f.frontH, alignment: .topLeading)
        // 磨砂玻璃都垫在字下面,反光别盖到字上。页面整体压了深色模式,这里要拿回浅色的料子
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.white.opacity(0.16))
                // 顶上一层反光 + 贴着边的一圈柔光 + 细亮边(左上最亮)
                LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.42))
                    .clipShape(shape)
                shape.stroke(.white.opacity(0.75), lineWidth: 8).blur(radius: 7).clipShape(shape)
                shape.strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.35), .white.opacity(0.7)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
            }
            .environment(\.colorScheme, .light)
            .allowsHitTesting(false)
        }
        .contentShape(shape)
        .onTapGesture { tapFolder(f) }
        .rotation3DEffect(.degrees(opened ? -112 : 0), axis: (1, 0, 0), anchor: .bottom, perspective: 0.5)
        .animation(opened ? .easeIn(duration: 0.28) : .spring(response: 0.36, dampingFraction: 0.82).delay(0.2), value: opened)
        .opacity(opened ? 0 : 1)
        .animation(.easeOut(duration: 0.12).delay(opened ? 0.17 : 0.2), value: opened)
        .allowsHitTesting(!opened)
        .offset(x: f.backRect.minX, y: f.backRect.maxY - f.frontH)
    }

    private func folderSub(_ ls: [BinderLeaf]) -> String {
        let ps = store.photos(trip: trip.id).count, ns = store.notes(trip: trip.id).count
        let days = ls.filter { if case .day = $0 { true } else { false } }.count
        let bits = [ps > 0 ? "\(ps) 张" : nil, ns > 0 ? "\(ns) 段" : nil, days > 1 ? "\(days) 天" : nil].compactMap { $0 }
        return bits.isEmpty ? "还是空的" : bits.joined(separator: " · ")
    }

    private func tapFolder(_ f: FolderLayout) {
        guard active == nil, !opened else { return }
        if store.photos(trip: trip.id).isEmpty, store.notes(trip: trip.id).isEmpty {
            openEntry(.add, from: CGRect(x: f.backRect.minX, y: f.backRect.maxY - f.frontH, width: f.backRect.width, height: f.frontH))
            return
        }
        soft.impactOccurred()
        fanOffset = 0; scroll.x = 0
        opened = true
        openToken += 1
        let token = openToken
        Task {
            // 最后一张落定才换真列表;换早了纸会跳一下
            try? await Task.sleep(for: .milliseconds(760))
            guard token == openToken, opened else { return }
            showReal = true
        }
    }

    private func closeFolder() {
        guard opened, active == nil else { return }
        tick.impactOccurred()
        openToken += 1
        // 先在滑到的位置把纸画出来,下一帧才开始收
        fanOffset = scroll.x
        showReal = false
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            opened = false
        }
    }

    /// 探出文件夹的那几张: 照片优先,没照片才拿字纸
    private func fanIDs(_ ls: [BinderLeaf]) -> [String] {
        let photos = ls.filter { if case .photo = $0 { true } else { false } }
        let notes = ls.filter { if case .note = $0 { true } else { false } }
        return (photos + notes).prefix(5).map(\.id)
    }

    /// 开合时的那层纸: 合上时是扇形的卡片,打开时落到竖条的位置。只画看得见的那些
    private func fanLayer(_ ls: [BinderLeaf], ws: [CGFloat], screen: CGSize, insets: EdgeInsets, f: FolderLayout) -> some View {
        let fan = fanIDs(ls)
        let xs = positions(ws)
        let openH = screen.height - insets.top - BinderK.topGap
        let seq = tabSequence(ls)
        let items = ls.indices.filter { i in
            fan.contains(ls[i].id) || (xs[i] - fanOffset < screen.width && xs[i] + ws[i] - fanOffset > -BinderK.tabW)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element) { rank, i in
                let leaf = ls[i]
                let slot = fan.firstIndex(of: leaf.id)
                let o = slot.map { CGFloat($0) - CGFloat(fan.count - 1) / 2 } ?? 0
                let card = f.cardSize
                let spread = min(38, (f.backRect.width - card.width) / CGFloat(max(1, fan.count - 1)))
                let w = opened ? ws[i] : card.width
                let h = opened ? openH : card.height
                let x = opened ? xs[i] - fanOffset : screen.width / 2 + o * spread - card.width / 2
                let y = opened ? insets.top + BinderK.topGap : f.backRect.minY - 4 + abs(o) * 9
                let delay = opened ? 0.05 + Double(rank) * 0.02 : Double(items.count - 1 - rank) * 0.014
                strip(leaf, index: i, width: w, height: h, tabY: tabY(tabIndex: seq[i], height: openH),
                      big: ws[i] > 110, tabOpacity: opened ? 1 : 0)
                    .rotationEffect(.degrees(opened ? 0 : Double(o) * 5.5), anchor: .bottom)
                    .offset(x: x, y: y)
                    .opacity(opened || slot != nil ? 1 : 0)
                    .animation(.spring(response: 0.38, dampingFraction: 0.84).delay(delay), value: opened)
                    .zIndex(Double(i))
            }
        }
        .allowsHitTesting(false)
    }

    private func entries(_ f: FolderLayout, width W: CGFloat) -> some View {
        let talk = store.comments("trip:\(trip.id)").count
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                entryButton(.add, icon: "plus", title: "加一页", paper: StopoverK.dune, ink: StopoverK.ink)
                if sharing { entryButton(.gate, icon: "paperplane", title: "GATE", paper: StopoverK.harbor, ink: StopoverK.paper) }
            }
            if sharing {
                let who = store.config.partner
                entryButton(.talk(talk), icon: "bubble.left", title: talk > 0 ? "\(who)说 · \(talk)" : "\(who)说", paper: BinderK.night, ink: BinderK.nightInk)
            }
        }
        .padding(.horizontal, 24)
        .frame(width: W)
        .offset(y: f.entriesTop + (opened ? 170 : 0))
        .opacity(opened ? 0 : 1)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: opened)
        .allowsHitTesting(!opened)
    }

    private func entryButton(_ leaf: BinderLeaf, icon: String, title: String, paper: Color, ink: Color) -> some View {
        Button {
            guard active == nil else { return }
            openEntry(leaf, from: entryFrames[leaf.id] ?? .zero)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium))
                Text(title).font(title == "GATE" ? StopoverK.mono(15, .semibold) : StopoverK.serif(16, .semibold))
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(active?.leaf.id == leaf.id ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("binderPage")) } action: { entryFrames[leaf.id] = $0 }
    }

    private func openEntry(_ leaf: BinderLeaf, from rect: CGRect) {
        pullY = 0; t = 0; settled = false; textIn = false; passed = false
        active = Active(leaf: leaf, source: rect, tone: 0, tabY: 0)
        soft.impactOccurred()
        open()
    }

    private func closePill(insets: EdgeInsets) -> some View {
        Button { closeFolder() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                Text("合上").font(StopoverK.serif(14, .semibold))
            }
            .foregroundStyle(StopoverK.ink)
            .padding(.horizontal, 15).frame(height: 36)
            .background(StopoverK.paper, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 14).padding(.top, insets.top + 24)
        .opacity(opened ? 1 : 0)
        .animation(.easeOut(duration: 0.2).delay(opened ? 0.35 : 0), value: opened)
        .allowsHitTesting(opened)
    }

    // MARK: 夹子

    private func widths(_ ls: [BinderLeaf], total: CGFloat) -> [CGFloat] {
        // 封面后面紧跟带标签的页(没分天): 封面加宽一个标签,不然城名被盖住
        let cover = BinderK.coverW + (ls.count > 1 && ls[1].hasTab ? BinderK.tabW : 0)
        let fixed = ls.reduce(CGFloat(0)) { s, l in
            if l.flexible { return s }
            if case .cover = l { return s + cover }
            return s + BinderK.narrowW
        }
        let n = CGFloat(ls.filter(\.flexible).count)
        let room = total - fixed
        let flex = n > 0 ? max(BinderK.minW, room / n) : 0
        return ls.map { l in
            if l.flexible { return flex }
            if case .cover = l { return cover }
            return BinderK.narrowW
        }
    }

    private func tabY(tabIndex: Int, height: CGFloat) -> CGFloat {
        let step = max(40, (height - BinderK.tabH - 60) / 4)
        return 18 + CGFloat(tabIndex % 5) * step
    }

    private func tabSequence(_ ls: [BinderLeaf]) -> [Int] {
        // 每天从头排: 分隔页后面第一个标签总在最上面,不会盖住 DAY 字
        var n = 0
        return ls.map { l in
            if case .day = l { n = 0 }
            guard l.hasTab else { return 0 }
            defer { n += 1 }
            return n
        }
    }

    private func binder(width W: CGFloat) -> some View {
        GeometryReader { b in
            let H = b.size.height - BinderK.topGap
            let ls = leaves
            let ws = widths(ls, total: W)
            let seq = tabSequence(ls)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(Array(ls.enumerated()), id: \.element.id) { i, leaf in
                        strip(leaf, index: i, width: ws[i], height: H, tabY: tabY(tabIndex: seq[i], height: H), big: ws[i] > 110)
                            .opacity(active?.leaf.id == leaf.id ? 0 : 1)
                            .zIndex(Double(i))
                            .onTapGesture {
                                guard leaf.pullable, active == nil else { return }
                                begin(i, ls: ls, ws: ws, seq: seq, H: H)
                                open()
                            }
                    }
                }
                .padding(.top, BinderK.topGap)
                .background {
                    BinderScrollHook(
                        onOffset: { scroll.x = $0.x },
                        began: { at in
                            guard active == nil, let i = hit(at, ls: ls, ws: ws, seq: seq, H: H), ls[i].pullable else { return }
                            begin(i, ls: ls, ws: ws, seq: seq, H: H)
                        },
                        changed: { up in
                            guard active != nil, !settled, t == 0 else { return }
                            // 越往上越沉: 纸从夹子里往外蹭的阻力
                            let y = max(0, up)
                            pullY = y < BinderK.pullToOpen ? y : BinderK.pullToOpen + (y - BinderK.pullToOpen) * 0.55
                            if y > BinderK.pullToOpen, !passed { passed = true; tick.impactOccurred() }
                            if y < BinderK.pullToOpen - 12 { passed = false }
                        },
                        ended: { vy in
                            guard active != nil, !settled, t == 0 else { return }
                            if pullY > BinderK.pullToOpen || vy < -900 { open() } else { close() }
                        })
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("binderPage")) } action: { binderFrame = $0 }
    }

    private func positions(_ ws: [CGFloat]) -> [CGFloat] {
        var x: CGFloat = 0
        return ws.map { w in defer { x += w }; return x }
    }

    /// 手指落在哪一条: 后面的条盖着前面,标签又伸到前一条上,所以从后往前找
    private func hit(_ at: CGPoint, ls: [BinderLeaf], ws: [CGFloat], seq: [Int], H: CGFloat) -> Int? {
        let x = at.x + scroll.x, y = at.y - BinderK.topGap
        let xs = positions(ws)
        for i in ls.indices.reversed() {
            if x >= xs[i], x < xs[i] + ws[i] { return i }
            if ls[i].hasTab, x >= xs[i] - BinderK.tabW, x < xs[i] {
                let ty = tabY(tabIndex: seq[i], height: H)
                if y >= ty, y <= ty + BinderK.tabH { return i }
            }
        }
        return nil
    }

    private func begin(_ i: Int, ls: [BinderLeaf], ws: [CGFloat], seq: [Int], H: CGFloat) {
        let xs = positions(ws)
        let src = CGRect(x: binderFrame.minX + xs[i] - scroll.x, y: binderFrame.minY + BinderK.topGap, width: ws[i], height: H)
        pullY = 0; t = 0; settled = false; textIn = false; passed = false
        active = Active(leaf: ls[i], source: src, tone: i % BinderK.tones.count, tabY: tabY(tabIndex: seq[i], height: H))
        soft.impactOccurred()
        tick.prepare()
    }

    private func open() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.87)) {
            t = 1
        } completion: {
            guard t == 1 else { return }
            settled = true
            withAnimation(.easeOut(duration: 0.28)) { textIn = true }
        }
    }

    private func close() {
        settled = false
        textIn = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            t = 0; pullY = 0
        } completion: {
            guard t == 0, pullY == 0 else { return }
            active = nil
        }
    }

    // MARK: 一条

    @ViewBuilder
    private func strip(_ leaf: BinderLeaf, index i: Int, width w: CGFloat, height h: CGFloat, tabY ty: CGFloat, big: Bool, tabOpacity: Double = 1) -> some View {
        let tone = BinderK.tones[i % BinderK.tones.count]
        switch leaf {
        case .cover(let title, let range, let sub):
            coverStrip(title: title, range: range, sub: sub, w: w, h: h)
        case .day(let n, let date):
            utility(big: "DAY \(n)", small: date, w: w, h: h, paper: BinderK.night, ink: BinderK.nightInk, lead: BinderK.tabH + 44)
        case .add, .gate, .talk:
            EmptyView()   // 这三个在文件夹外面,不进竖条
        case .photo(let p, let fig):
            paperStrip(tone: tone, w: w, h: h) {
                photoInset(p, w: w, h: h)
            }
            .overlay(alignment: .topLeading) { tab(line1: String(format: "FIG.%02d", fig), line2: Self.clock(p.taken), tone: tone, y: ty).opacity(tabOpacity) }
            .onAppear { images.request(p.id, big: big) }
        case .note(let x):
            paperStrip(tone: (Color(UIColor(hex: 0xF3EFE3)), StopoverK.ink), w: w, h: h) {
                noteColumn(x.text, w: w, h: h)
            }
            .overlay(alignment: .topLeading) { tab(line1: "NOTE", line2: "随记", tone: (Color(UIColor(hex: 0xF3EFE3)), StopoverK.ink), y: ty).opacity(tabOpacity) }
        }
    }

    private func paperStrip<C: View>(tone: (paper: Color, ink: Color), w: CGFloat, h: CGFloat, @ViewBuilder content: () -> C) -> some View {
        ZStack(alignment: .topLeading) {
            tone.paper
            // 纸纹只铺纸,别盖到照片上
            Image(uiImage: BinderK.grain).resizable(resizingMode: .tile).allowsHitTesting(false)
            content()
        }
        .frame(width: w, height: h)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9, style: .continuous))
        // 压在前一条上的那点影子: 一条窄渐变,比 shadow 便宜得多(一屏十几条)
        .background(alignment: .leading) {
            LinearGradient(colors: [.clear, .black.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 7).offset(x: -7)
        }
        .contentShape(Rectangle())
    }

    private func photoInset(_ p: StopoverPhoto, w: CGFloat, h: CGFloat) -> some View {
        let size = CGSize(width: max(1, w - 14), height: max(1, h - 44))
        return Group {
            if let img = images.images[p.id] {
                BinderSlice(image: img, focus: images.focus[p.id] ?? 0.5, size: size)
            } else {
                StopoverK.ink.opacity(0.1).frame(width: size.width, height: size.height)
            }
        }
        .offset(x: 7, y: 14)
    }

    private func noteColumn(_ text: String, w: CGFloat, h: CGFloat) -> some View {
        let chars = Array(text.replacingOccurrences(of: "\n", with: "").prefix(max(4, Int((h - 60) / 19))))
        return VStack(spacing: 3) {
            ForEach(Array(chars.enumerated()), id: \.offset) { _, c in
                Text(String(c)).font(StopoverK.serif(13)).foregroundStyle(StopoverK.ink).frame(height: 16)
            }
        }
        .frame(width: w).padding(.top, 22)
    }

    private func tab(line1: String, line2: String?, tone: (paper: Color, ink: Color), y: CGFloat) -> some View {
        BinderTabShape().fill(tone.paper)
            .overlay(Image(uiImage: BinderK.grain).resizable(resizingMode: .tile).clipShape(BinderTabShape()).allowsHitTesting(false))
            .overlay {
                BinderVertical(w: BinderK.tabW, h: BinderK.tabH, alignment: .center) {
                    VStack(alignment: .leading, spacing: -1) {
                        Text(line1).font(StopoverK.mono(9.5, .semibold)).tracking(0.5)
                        if let line2 { Text(line2).font(StopoverK.mono(9)).opacity(0.72) }
                    }
                    .foregroundStyle(tone.ink)
                }
            }
            .frame(width: BinderK.tabW, height: BinderK.tabH)
            .offset(x: -BinderK.tabW + 0.5, y: y)
            .contentShape(BinderTabShape().offset(x: -BinderK.tabW + 0.5, y: y))
    }

    private func coverStrip(title: String, range: String, sub: String, w: CGFloat, h: CGFloat) -> some View {
        paperStrip(tone: BinderK.tones[0], w: w, h: h) {
            VStack(alignment: .leading, spacing: 0) {
                BinderVertical(w: BinderK.coverW, h: max(10, h - 150)) {
                    Text(title + range)
                        .font(.system(size: 40, weight: .black)).fontWidth(.expanded)
                        .foregroundStyle(Color(UIColor(hex: 0x3B3A2B)))
                        .lineLimit(1).minimumScaleFactor(0.45)
                        .padding(.leading, 16)
                }
                BinderVertical(w: BinderK.coverW, h: 130, alignment: .center) {
                    Text(sub).font(StopoverK.mono(9, .medium)).foregroundStyle(Color(UIColor(hex: 0x3B3A2B)))
                }
            }
        }
    }

    private func utility(big: String, small: String, w: CGFloat, h: CGFloat, paper: Color, ink: Color, lead: CGFloat = 20) -> some View {
        paperStrip(tone: (paper, ink), w: w, h: h) {
            BinderVertical(w: w, h: h - 16) {
                HStack(spacing: 10) {
                    Text(big).font(big.first?.isASCII == true ? StopoverK.mono(19, .semibold) : StopoverK.serif(18, .bold))
                    if !small.isEmpty { Text(small).font(StopoverK.mono(10)).opacity(0.75) }
                }
                .foregroundStyle(ink)
                .padding(.leading, lead)
            }
        }
    }

    // MARK: 抽出来的那页

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ k: CGFloat) -> CGFloat { a + (b - a) * k }

    private func imageHeight(_ img: UIImage?, screen: CGSize) -> CGFloat {
        guard let img, img.size.width > 0 else { return screen.height * 0.55 }
        return min(screen.width * img.size.height / img.size.width, screen.height * 0.68)
    }

    @ViewBuilder
    private func sheet(_ a: Active, screen: CGSize, insets: EdgeInsets) -> some View {
        if settled {
            settledPage(a, screen: screen, insets: insets)
                .frame(width: screen.width, height: screen.height)
        } else {
            morph(a, screen: screen)
        }
    }

    /// 抽的过程: 窄条跟手往上走,松手后从窄条长成整页
    private func morph(_ a: Active, screen: CGSize) -> some View {
        let s = a.source
        let x = lerp(s.minX, 0, t), y = lerp(s.minY - pullY, 0, t)
        let w = lerp(s.width, screen.width, t), h = lerp(s.height, screen.height, t)
        let tone = toneOf(a)
        return ZStack(alignment: .topLeading) {
            tone.paper
            if case .photo(let p, _) = a.leaf {
                posterTone(p).opacity(t)   // 纸色长成海报底色,别等落定才突然变
            } else {
                Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).opacity(t)
            }
            if case .photo(let p, _) = a.leaf {
                let img = images.images[p.id]
                let size = CGSize(width: lerp(s.width - 14, screen.width, t),
                                  height: lerp(s.height - 44, imageHeight(img, screen: screen), t))
                Group {
                    if let img {
                        BinderSlice(image: img, focus: lerp(images.focus[p.id] ?? 0.5, 0.5, t), size: size)
                    } else {
                        StopoverK.ink.opacity(0.1).frame(width: size.width, height: size.height)
                    }
                }
                .offset(x: lerp(7, 0, t), y: lerp(14, 0, t))
            } else if case .note(let n) = a.leaf {
                noteColumn(n.text, w: s.width, h: s.height).opacity(1 - t)
            }
        }
        .frame(width: w, height: h)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 9 * (1 - t), topTrailingRadius: 9 * (1 - t), style: .continuous))
        .overlay(alignment: .topLeading) {
            if case .photo(let p, let fig) = a.leaf {
                tab(line1: String(format: "FIG.%02d", fig), line2: Self.clock(p.taken), tone: tone, y: a.tabY).opacity(1 - t * 3)
            } else if case .note = a.leaf {
                tab(line1: "NOTE", line2: "随记", tone: tone, y: a.tabY).opacity(1 - t * 3)
            }
        }
        .offset(x: x, y: y)
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
    }

    private func toneOf(_ a: Active) -> (paper: Color, ink: Color) {
        switch a.leaf {
        case .note: (Color(UIColor(hex: 0xF3EFE3)), StopoverK.ink)
        case .add: (StopoverK.dune, StopoverK.ink)
        case .gate: (StopoverK.harbor, StopoverK.paper)
        case .talk: (BinderK.night, BinderK.nightInk)
        default: BinderK.tones[a.tone]
        }
    }

    private func settledPage(_ a: Active, screen: CGSize, insets: EdgeInsets) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
            Group {
                switch a.leaf {
                case .photo(let p, let fig):
                    photoPage(p, fig: fig, screen: screen)
                case .note(let n):
                    notePage(n, insets: insets)
                case .add:
                    plainPage(kicker: "ADD A LEAF", title: "再夹一页", insets: insets) { addButtons }
                case .gate:
                    plainPage(kicker: "GATE", title: "递给\(store.config.partner)", insets: insets) { gatePage }
                case .talk:
                    plainPage(kicker: "COMMENTS", title: "\(store.config.partner)说", insets: insets) { talkPage }
                default:
                    EmptyView()
                }
            }
            .frame(width: screen.width, alignment: .leading)
            Spacer(minLength: 0)
            footer(a, insets: insets)
            }
            .frame(minHeight: screen.height)
            .background(alignment: .bottomTrailing) {
                // 海报底下那个特别大的编号,和底色只差一点点
                // 横图下面空得多,数字跟着放大把空当撑住
                if case .photo(let p, let fig) = a.leaf {
                    let free = screen.height - imageHeight(images.images[p.id], screen: screen) - 300
                    Text(String(format: "%02d", fig))
                        .font(.system(size: min(280, max(190, free)), weight: .black)).fontWidth(.expanded)
                        .foregroundStyle(StopoverK.paper.opacity(0.07))
                        .lineLimit(1).fixedSize()
                        .offset(x: 12, y: -insets.bottom - 40)
                }
            }
            .clipped()
            .background { BinderScrollHook(onOffset: { o in if o.y < -90, settled { close() } }) }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea()
        .background {
            if case .photo(let p, _) = a.leaf {
                posterTone(p)
                    .overlay(Image(uiImage: BinderK.grain).resizable(resizingMode: .tile).allowsHitTesting(false))
                    .ignoresSafeArea()
            } else {
                Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).ignoresSafeArea()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { close() } label: {
                Text("×").font(StopoverK.latin(24, italic: false)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(StopoverK.ink.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16).padding(.top, insets.top + 6)
            .opacity(textIn ? 1 : 0)
        }
        // 整页是 ignoresSafeArea 的,系统不会替它让键盘,自己来
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
            let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            keyboardH = max(0, screen.height - end.minY)
            scrollThread(proxy)
        }
        .onChange(of: threadFocus) { _, _ in scrollThread(proxy) }
        }
    }

    private func scrollThread(_ proxy: ScrollViewProxy) {
        guard keyboardH > 0, let k = threadFocus else { return }
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end:" + k, anchor: .bottom) } }
    }

    /// 这张照片 / 这段随记的对话: 每次递它出去单独一组,直接在它下面说的另成一组。一条都没有就不画
    @ViewBuilder
    private func threads(type: String, id: Int, label: String, poster: Bool = false) -> some View {
        if sharing {
            let shares = store.shares.filter { s in s.items.contains { $0.type == type && $0.id == id } }
                .sorted { $0.created > $1.created }
            let loose = store.comments("\(type):\(id)").sorted { $0.created < $1.created }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(shares) { s in
                    threadCard(ThreadGroup(key: "share:\(s.id)", share: s,
                                           msgs: store.comments("share:\(s.id)").sorted { $0.created < $1.created },
                                           headWhat: s.items.count > 1 ? "\(s.items.count) 样" : label,
                                           whereOf: { _ in nil }, store: store, city: trip.city,
                                           onFocus: { threadFocus = $0 }, onPoster: poster), key: "share:\(s.id)")
                }
                if !loose.isEmpty {
                    threadCard(ThreadGroup(key: "\(type):\(id)", share: nil, msgs: loose, headWhat: "",
                                           whereOf: { _ in nil }, store: store, city: trip.city,
                                           looseTitle: "在这下面说的",
                                           onFocus: { threadFocus = $0 }, onPoster: poster), key: "\(type):\(id)")
                }
            }
        }
    }

    private func threadCard(_ g: ThreadGroup, key: String) -> some View {
        VStack(spacing: 0) {
            g
            Color.clear.frame(height: threadFocus == key && keyboardH > 0 ? keyboardH + 12 : 0).id("end:" + key)
        }
    }

    private func posterTone(_ p: StopoverPhoto) -> Color { images.tones[p.id] ?? BinderK.night }

    /// 城名铺满一行时的字号和大写字母高度(超宽黑体,短名字也别大得离谱)
    private func posterName(_ name: String, width: CGFloat) -> (size: CGFloat, font: UIFont) {
        let base = UIFont.systemFont(ofSize: 100, weight: .black, width: .expanded)
        let m = (name as NSString).size(withAttributes: [.font: base]).width
        let size = min(132, 100 * width / max(m, 1))
        return (size, UIFont.systemFont(ofSize: size, weight: .black, width: .expanded))
    }

    /// 海报内页: 底色取自照片,城名跨在照片和色块交界上。
    /// 配文三种长度三种放法还是杂志版定的: 短句做大标题,中等正文,长段首字放大
    private func photoPage(_ raw: StopoverPhoto, fig: Int, screen: CGSize) -> some View {
        let p = store.photos.first { $0.id == raw.id } ?? raw
        let cap = p.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = !cap.isEmpty && cap.count <= 16 && !cap.contains("\n")
        let long = cap.count > 90
        let img = images.images[p.id]
        let size = CGSize(width: screen.width, height: imageHeight(img, screen: screen))
        let name = (store.cities[trip.city]?.en ?? "").uppercased()
        let nameW = screen.width - 28
        let pn = posterName(name, width: nameW)
        let total = store.photos(trip: trip.id).count
        let ink = StopoverK.paper
        return VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let img { BinderSlice(image: img, focus: 0.5, size: size) }
                else { StopoverK.ink.opacity(0.1).frame(width: size.width, height: size.height) }
                WikiImage(url: StopoverStore.photoURL(p.id, w: 1600)).frame(width: size.width, height: size.height).clipped()
                // 照片底下慢慢融进底色
                LinearGradient(stops: [.init(color: posterTone(p).opacity(0), location: 0),
                                       .init(color: posterTone(p).opacity(0.55), location: 0.6),
                                       .init(color: posterTone(p), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: min(190, size.height * 0.36))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(textIn ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            // 字高的一半咬进照片。行框比大写字母高,要按字体度量把字母本身摆正
            Text(name)
                .font(.system(size: pn.size, weight: .black)).fontWidth(.expanded)
                .foregroundStyle(ink)
                .lineLimit(1).fixedSize()
                .offset(y: -(pn.font.ascender + pn.font.descender - pn.font.capHeight) / 2)
                .frame(width: nameW, height: pn.font.capHeight, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, -pn.font.capHeight * 0.5)
                .opacity(textIn ? 1 : 0)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "FIG. %02d / %02d", fig, total))
                        .font(StopoverK.mono(11, .medium)).tracking(1.1).foregroundStyle(ink.opacity(0.75))
                    Spacer()
                    Button { editPhoto(p) } label: {
                        Text(cap.isEmpty ? "写配文" : "改这张").font(.system(size: 13)).foregroundStyle(ink)
                            .underline(true, color: ink.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                if short {
                    Text(cap).font(StopoverK.serif(29, .black)).foregroundStyle(ink).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                } else if long {
                    BinderDropCap(text: cap, color: UIColor(ink), capColor: ink)
                } else if !cap.isEmpty {
                    Text(cap).font(StopoverK.serif(19)).foregroundStyle(ink).lineSpacing(11)
                        .fixedSize(horizontal: false, vertical: true)
                }
                threads(type: "photo", id: p.id, label: "这张照片", poster: true).padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.top, 16)
            .opacity(textIn ? 1 : 0)
        }
    }

    /// 跨天才说第几天
    private func posterDay(_ p: StopoverPhoto) -> (label: String, value: String) {
        guard let ts = p.taken else { return ("DATE", "——") }
        let cal = Calendar.current
        let days = Array(Set(store.photos(trip: trip.id).compactMap(\.taken).map { cal.startOfDay(for: Date(timeIntervalSince1970: $0)) })).sorted()
        let d = Date(timeIntervalSince1970: ts)
        let c = cal.dateComponents([.month, .day], from: d)
        let value = "\(c.month ?? 0).\(c.day ?? 0)"
        guard days.count > 1, let i = days.firstIndex(of: cal.startOfDay(for: d)) else { return ("DATE", value) }
        return ("DAY \(i + 1)", value)
    }

    private func posterCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(StopoverK.mono(9, .medium)).tracking(1.2).opacity(0.65)
            Text(value).font(StopoverK.mono(13, .medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(StopoverK.paper)
    }

    private func notePage(_ raw: StopoverNote, insets: EdgeInsets) -> some View {
        let n = store.notes.first { $0.id == raw.id } ?? raw
        return VStack(alignment: .leading, spacing: 18) {
            Text("NOTE · " + (Self.stamp(n.created) ?? "")).font(StopoverK.mono(11, .medium)).tracking(1.1).foregroundStyle(StopoverK.ink2)
            BinderDropCap(text: n.text)
            HStack(spacing: 18) {
                if sharing { Button("递这段") { shareNote(n) } }
                Button("改") { editNote(n) }
            }
            .font(.system(size: 13)).foregroundStyle(StopoverK.harbor)
            threads(type: "note", id: n.id, label: "这段随记")
        }
        .padding(.horizontal, 22).padding(.top, insets.top + 64)
        .opacity(textIn ? 1 : 0)
    }

    private func plainPage<C: View>(kicker: String, title: String, insets: EdgeInsets, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(kicker).font(StopoverK.mono(11, .medium)).tracking(1.6).foregroundStyle(StopoverK.ink2)
            Text(title).font(StopoverK.serif(36, .black)).foregroundStyle(StopoverK.ink)
            content()
        }
        .padding(.horizontal, 20).padding(.top, insets.top + 64)
        .opacity(textIn ? 1 : 0)
    }

    private var addButtons: some View {
        VStack(spacing: 12) {
            addButton("写一段", "夹一张字纸") { close(); newNote() }
            addButton("加照片", "从手机选") { close(); addPhoto() }
        }
    }

    private func addButton(_ t: String, _ sub: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t).font(StopoverK.serif(19, .semibold)).foregroundStyle(StopoverK.ink)
                Text(sub).font(.system(size: 12.5)).foregroundStyle(StopoverK.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(StopoverK.harbor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footer(_ a: Active, insets: EdgeInsets) -> some View {
        var poster: StopoverPhoto?
        if case .photo(let p, _) = a.leaf { poster = p }
        let line = poster == nil ? StopoverK.harbor : StopoverK.paper
        return VStack(spacing: 22) {
            Button { close() } label: {
                Text("插回去").font(StopoverK.serif(15)).foregroundStyle(line)
                    .padding(.horizontal, 24).frame(minHeight: 42)
                    .overlay(Capsule().strokeBorder(line.opacity(0.4)))
            }
            .buttonStyle(.plain)
            if let p = poster {
                let day = posterDay(p)
                let c = store.cities[trip.city]
                HStack(alignment: .top, spacing: 18) {
                    posterCell(day.label, day.value)
                    posterCell("TIME", Self.clock(p.taken) ?? "——")
                    Spacer(minLength: 0)
                    if let c { posterCell("WHERE", Self.coords(c.lat, c.lng)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .overlay(alignment: .top) { StopoverK.paper.opacity(0.3).frame(height: 1) }
            } else {
                HStack {
                    Text((store.cities[trip.city]?.en ?? "").uppercased())
                    Spacer()
                }
                .font(StopoverK.mono(11, .medium)).tracking(1.1).foregroundStyle(StopoverK.ink2)
            }
        }
        .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, insets.bottom + 14)
        .opacity(textIn ? 1 : 0)
    }

    // MARK: 时间

    static func coords(_ lat: Double, _ lng: Double) -> String {
        String(format: "%.2f°%@ %.2f°%@", abs(lat), lat >= 0 ? "N" : "S", abs(lng), lng >= 0 ? "E" : "W")
    }

    static func clock(_ ts: Double?) -> String? {
        guard let ts else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: ts))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func stamp(_ ts: Double?) -> String? {
        guard let ts else { return nil }
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: Date(timeIntervalSince1970: ts))
        return String(format: "%d.%d %02d:%02d", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}

/// 长段: 首字放大,字绕着走(挖洞的 UITextView 用睡前故事那份)
private struct BinderDropCap: View {
    let text: String
    var color = UIColor(StopoverK.body)
    var capColor = StopoverK.ink
    private let size: CGFloat = 17
    private let spacing: CGFloat = 10

    var body: some View {
        let f = UIFont(name: "STSongti-SC-Regular", size: size) ?? .systemFont(ofSize: size)
        let side = ceil(f.lineHeight * 2 + spacing)
        var rest = text
        let cap = rest.isEmpty ? "" : String(rest.removeFirst())
        let paragraphs = rest.components(separatedBy: "\n").filter { !$0.isEmpty }
        return ZStack(alignment: .topLeading) {
            WrappedText(paragraphs: paragraphs.isEmpty ? [""] : paragraphs, font: f, color: color,
                        lineSpacing: spacing, paraSpacing: 14, hole: CGSize(width: side + 6, height: side))
            Text(cap).font(StopoverK.serif(side * 0.92, .black)).foregroundStyle(capColor)
                .frame(width: side, height: side)
        }
    }
}

/// 挖一块洞、字绕着走的正文
private struct WrappedText: UIViewRepresentable {
    let paragraphs: [String]
    let font: UIFont
    let color: UIColor
    let lineSpacing: CGFloat
    let paraSpacing: CGFloat
    let hole: CGSize

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = lineSpacing
        ps.paragraphSpacing = paraSpacing
        ps.alignment = .justified
        ps.lineBreakStrategy = .pushOut
        let text = NSAttributedString(string: paragraphs.joined(separator: "\n"), attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: ps, .kern: 0.6,
        ])
        if tv.attributedText != text { tv.attributedText = text }
        let path = UIBezierPath(rect: CGRect(origin: .zero, size: hole))
        if tv.textContainer.exclusionPaths.first?.bounds != path.bounds {
            tv.textContainer.exclusionPaths = hole == .zero ? [] : [path]
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width - 56
        let s = tv.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        // +1: 像素取整会把框压矮零点几,最后一行放不下时 TextKit 就整行不排
        return CGSize(width: w, height: max(s.height + 1, hole.height))
    }
}
