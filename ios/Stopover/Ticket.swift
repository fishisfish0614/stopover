import SwiftUI

// 经停 · 登机牌。纯文字、不盖章。
// 长卷里每「来过」一次一张票,点整张进「这一次」:上半深色整张票 + 撕口,下面随记 / 照片 / GATE / \(StopoverStore.shared.config.partner)说。
// 这一步只做显示;改日期备注、改出发地终点、写随记、加照片、递出、删掉这一次下一步接。

private enum TK {
    static let card = Color(UIColor(hex: 0xF4F1EB))
    static let night = Color(UIColor(hex: 0x1F2A38))
    static let label = Color(UIColor(hex: 0x6F9FC8))
    static let labelDark = Color(UIColor(hex: 0x93abc8))
    static let sub = Color(UIColor(hex: 0x5b6675))
    static let subDark = Color(UIColor(hex: 0xb9c6d6))
    static let yy = Color(UIColor(hex: 0x3e6a9e))
    static let here = Color(UIColor(hex: 0x9fc3ea))
}

/// 票面小标签 DATE / SEAT…
private func tkLabel(_ t: String, dark: Bool = false) -> some View {
    Text(t).font(StopoverK.mono(9.5, .medium)).tracking(1.7).foregroundStyle(dark ? TK.labelDark : TK.label)
}

private func tkValue(_ t: String, dark: Bool = false, size: CGFloat = 13) -> some View {
    Text(t).font(StopoverK.mono(size, .medium)).tracking(0.4).foregroundStyle(dark ? .white : StopoverK.ink)
}

/// 航线: HEI ····●···· PAL;有终点三段 FIR ··●·· VEN ··●·· HEI(中间那座海港蓝,终点下写「回到…」)
struct TicketRoute: View {
    let trip: StopoverCheckin
    @ObservedObject var store: StopoverStore
    var dark = false

    var body: some View {
        let three = trip.dest != nil && store.cities[trip.dest!] != nil
        let size: CGFloat = dark ? (three ? 30 : 40) : (three ? 21 : 28)
        let small: CGFloat = dark ? 13 : (three ? 11 : 12)
        HStack(alignment: .top, spacing: 8) {
            if let o = trip.origin, o != trip.city, let oc = store.cities[o] {
                code(store.code3(o), oc.name, size: size, small: small)
            } else if !three {
                VStack(alignment: .leading, spacing: 5) {
                    Text("起点").font(StopoverK.serif(dark ? 22 : 18, .semibold)).foregroundStyle(dark ? .white : StopoverK.ink)
                    Text("就从这里出发").font(StopoverK.serif(small)).foregroundStyle(dark ? TK.subDark : TK.sub)
                }
                .fixedSize()
            }
            if trip.origin != nil || !three { dash(size) }
            code(store.code3(trip.city), store.cities[trip.city]?.name ?? "", size: size, small: small,
                 tint: three ? (dark ? TK.here : StopoverK.harbor) : nil)
            if three, let d = trip.dest, let dc = store.cities[d] {
                dash(size)
                code(store.code3(d), "回到" + dc.name, size: size, small: small)
            }
        }
    }

    private func code(_ c: String, _ name: String, size: CGFloat, small: CGFloat, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(c).font(StopoverK.mono(size, .semibold)).foregroundStyle(tint ?? (dark ? .white : StopoverK.ink))
            Text(name).font(StopoverK.serif(small)).foregroundStyle(dark ? TK.subDark : TK.sub).lineLimit(1)
        }
        .fixedSize()
    }

    /// 虚线上一颗圆点,很慢地从出发地滑向目的地,到头淡出再从起点来
    private func dash(_ size: CGFloat) -> some View {
        ZStack {
            Line().stroke(dark ? TK.labelDark : StopoverK.harbor, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 1)
            GeometryReader { g in
                TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                    let period = 5.5
                    let t = (tl.date.timeIntervalSinceReferenceDate + Double(trip.id) * 0.77).truncatingRemainder(dividingBy: period) / period
                    let fade = min(1, min(t, 1 - t) / 0.12)
                    Circle().fill(dark ? .white : StopoverK.harbor).frame(width: 7, height: 7)
                        .shadow(color: (dark ? Color.white : StopoverK.harbor).opacity(0.6), radius: 3)
                        .opacity(fade)
                        .position(x: g.size.width * t, y: g.size.height / 2)
                }
            }
        }
        .frame(minWidth: 10, maxWidth: .infinity)
        .frame(height: size * 0.75)
    }
}

private struct Line: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
}

/// 一小段条码: 按票号撒种子生成,每张票都不一样
private struct Barcode: View {
    let seed: Int
    var body: some View {
        Canvas { ctx, size in
            var r = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 97)
            func next(_ n: UInt64) -> CGFloat { r = r &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((r >> 33) % n) }
            var x: CGFloat = 0
            while x < size.width {
                let w = 1 + next(3)          // 条 1~3pt
                ctx.fill(Path(CGRect(x: x, y: 0, width: min(w, size.width - x), height: size.height)), with: .color(StopoverK.ink))
                x += w + 1 + next(3)         // 空 1~3pt
            }
        }
        .frame(height: 28).opacity(0.5)
    }
}

/// 深色票面的防伪底纹: 几十道很细的海港蓝波浪线叠在一起(扭索纹),近看才发现
private struct Guilloche: View {
    var body: some View {
        Canvas { ctx, size in
            let lines = 26
            for k in 0..<lines {
                let y0 = size.height * CGFloat(k) / CGFloat(lines - 1)
                let ph = CGFloat(k) * 0.42
                var p = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    let y = y0 + 9 * sin(x / 23 + ph) + 5 * sin(x / 9.5 - ph * 1.7)
                    x == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                    x += 2
                }
                ctx.stroke(p, with: .color(StopoverK.harbor.opacity(0.32)), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 长卷里的一张票
struct BoardingPass: View {
    let trip: StopoverCheckin
    let seat: Int
    @ObservedObject var store: StopoverStore
    /// 撕票台上(照 jal-co/boarding-pass 的撕法,MIT): tear = 撕开多少(0~1,只进不退),
    /// detach = 撕下后落到票旁边多少(0~1),hand = 撕下后跟着手指的偏移
    var tear: Double = 0
    var detach: Double = 0
    var hand: CGSize = .zero
    var stubGesture: AnyGesture<Void>? = nil

    var body: some View {
        let ps = store.photos(trip: trip.id), ns = store.notes(trip: trip.id)
        let date = store.dateText(trip)
        let blank = date == nil && (trip.remark ?? "").isEmpty && ps.isEmpty && ns.isEmpty
        let cm = store.commentCount(trip: trip)
        let foot = !(trip.remark ?? "").isEmpty || cm > 0
        let nibs = TearEdge.nibs(seed: trip.id)
        // 存根以左下角为轴,撕得越开掀得越多,最多 4°;撕下后落到票旁边歪 2°
        let angle = 4 * tear * (1 - detach) + 2 * detach
        // 票身和存根各自带底色、各自圆角,存根才能单独撕下来(整张一起裁圆角的话存根飞不出去)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { tkLabel("STOPOVER · 经停"); Spacer(); tkLabel("NO. \(store.ticketNo(trip))") }
                    TicketRoute(trip: trip, store: store)
                    HStack(alignment: .top, spacing: 16) {
                        meta("DATE", date ?? "——")
                        if !ps.isEmpty { meta("PHOTOS", "\(ps.count)") }
                        if !ns.isEmpty { meta("NOTES", "\(ns.count)") }
                        if let k = store.km(trip.origin, trip.city), trip.origin != trip.city { meta("KM", k.formatted(.number.locale(Locale(identifier: "en_US")))) }
                    }
                }
                .padding(.leading, 16).padding(.trailing, 12).padding(.top, 14).padding(.bottom, 12)
                .opacity(blank ? 0.75 : 1)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(TK.card)
                .clipShape(TearEdge(stub: false, tear: tear, nibs: nibs, roundBottom: !foot))
                // 存根: 左边一道虚线,上下各咬一个半圆缺口
                VStack(alignment: .leading) {
                    tkLabel("SEAT")
                    Text(String(format: "%02d", seat)).font(StopoverK.mono(22, .semibold)).foregroundStyle(StopoverK.harbor)
                    Spacer(minLength: 8)
                    Barcode(seed: trip.id)
                }
                .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 14)
                .frame(width: 74)
                .frame(maxHeight: .infinity)
                .background(TK.card)
                .overlay(alignment: .leading) {
                    VLine().stroke(StopoverK.harbor.opacity(0.28), style: StrokeStyle(lineWidth: 2, dash: [5, 4])).frame(width: 2)
                        .opacity(1 - tear)
                }
                .clipShape(TearEdge(stub: true, tear: tear, nibs: nibs, roundBottom: !foot))
                .shadow(color: StopoverK.ink.opacity(0.18 * (tear * 0.5 + detach * 0.5)), radius: 8 * (tear + detach), y: 4 * (tear + detach))
                .rotationEffect(.degrees(angle), anchor: .bottomLeading)
                .offset(x: hand.width + 24 * detach, y: hand.height + 8 * detach)
                .contentShape(Rectangle())
                .gesture(stubGesture)
            }
            .fixedSize(horizontal: false, vertical: true)
            // 虚线上还没断的小纸桥: 连着票身和(掀开的)存根
            .overlay {
                if tear > 0, tear < 1 {
                    GeometryReader { g in
                        TearEdge.bridges(edgeX: g.size.width - 74, height: g.size.height, tear: tear, angle: angle)
                            .fill(TK.card)
                    }
                    .allowsHitTesting(false)
                }
            }
            if foot {
                VStack(alignment: .leading, spacing: 0) {
                    if let r = trip.remark, !r.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            tkLabel("REMARKS · 备注")
                            Text(r).font(StopoverK.serif(15)).foregroundStyle(StopoverK.ink).lineSpacing(5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
                        .overlay(alignment: .top) { Rectangle().fill(StopoverK.harbor.opacity(0.14)).frame(height: 1) }
                    }
                    if cm > 0 {
                        Text("\(StopoverStore.shared.config.partner)说了 \(cm) 句").font(StopoverK.serif(12.5)).foregroundStyle(TK.yy)
                            .padding(.horizontal, 16).padding(.bottom, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TK.card, in: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous))
            }
        }
        .compositingGroup()
        .shadow(color: StopoverK.ink.opacity(0.06), radius: 0, y: 1)
        .shadow(color: StopoverK.ink.opacity(0.10), radius: 11, y: 8)
    }

    private func meta(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { tkLabel(l); tkValue(v) }
    }
}

/// 撕票台: 背景压暗,票从长卷里原来的位置飞到屏幕中间放大;
/// 手指拖右边存根,跟着走,拖够了就撕下飞走 → 进「这一次」;没拖够松手弹回;点暗处取消,票飞回原位
struct TearStage: View {
    let trip: StopoverCheckin
    let seat: Int
    let from: CGRect          // 票在屏幕上原来的位置(全局坐标)
    @ObservedObject var store: StopoverStore
    @Environment(\.dismiss) private var dismiss
    @State private var up = false
    @State private var tear = 0.0
    @State private var detach = 0.0
    @State private var hand: CGSize = .zero
    @State private var page = false
    @State private var nudge = false
    @State private var start: Double?     // 这一下拖动开始时撕到哪(松手不退,下次接着撕)
    @State private var anchor: CGPoint?   // 撕断那一刻手指在哪,之后存根跟着手走
    @State private var broken = 0
    private let tearDistance: CGFloat = 90   // 拖多远撕完: 仓库票高 280 撕完拉 120,按比例我们这张矮票 ~70;140 拉一大下才撕一半
    private let tick = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            // 撕票台按整块屏幕的坐标摆(票原来的位置是全局坐标),所以这一层不留安全区
            GeometryReader { g in
                let w = from.width
                let scale = min(1.12, (g.size.width - 24) / max(1, w))
                let center = CGPoint(x: g.size.width / 2, y: g.size.height * 0.42)
                ZStack {
                    Color.black.opacity(up && !page ? 0.5 : 0)
                        .contentShape(Rectangle())
                        .onTapGesture { cancel() }
                    if !page {
                        BoardingPass(trip: trip, seat: seat, store: store, tear: tear, detach: detach, hand: hand,
                                     stubGesture: AnyGesture(stubDrag(scale).map { _ in () }))
                            .frame(width: w)
                            .scaleEffect(up ? scale : 1)
                            .position(up ? center : CGPoint(x: from.midX, y: from.midY))
                        hint.position(x: center.x, y: center.y + from.height * scale / 2 + 44)
                            .opacity(up && tear < 1 ? 1 : 0)
                    }
                }
            }
            .ignoresSafeArea()
            // 「这一次」正常留安全区
            if page {
                TripPage(tripId: trip.id, store: store).transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onAppear {
            tick.prepare()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { up = true }
            withAnimation(.easeInOut(duration: 0.7).repeatForever().delay(0.5)) { nudge = true }
        }
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Text(tear > 0 ? "接着撕" : "按住存根，顺着虚线往下拉").font(StopoverK.serif(15))
            Image(systemName: "arrow.down").font(.system(size: 13, weight: .semibold))
                .offset(y: nudge ? 4 : -1)
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    /// 照 jal-co/boarding-pass: 撕的进度 = 往右下拉的距离(右 0.65 + 下 0.35),只进不退;
    /// 撕断以后存根跟着手走,松手落在票旁边
    private func stubDrag(_ scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if start == nil { start = tear }
                if let a = anchor {
                    hand = CGSize(width: v.location.x - a.x, height: v.location.y - a.y)
                    return
                }
                // 手势坐标已经是票里的(缩放前),不用再除。仓库是右 0.65 + 下 0.35,
                // 但我们的存根贴着屏幕右边,往右只够拉 ~50pt;改成右、下(上也行)各一半,顺着虚线往下拉就能撕
                let d = max(0, max(0, v.translation.width) * 0.6 + abs(v.translation.height) * 0.6 - 4)
                var next = min(1, max(tear, (start ?? 0) + Double(d / tearDistance)))
                if next >= 0.9 { next = 1 }
                #if DEBUG
                print("[tear] t=\(v.translation) d=\(d) next=\(next)")
                #endif   // 最后一截不让人卡着: 毛边都撕满了还差一点没断,看着像卡住
                tear = next
                // 每断一根纸桥轻轻一震
                let n = Int(next * 14)
                if n > broken { broken = n; tick.impactOccurred(intensity: 0.55); tick.prepare() }
                if next >= 1, anchor == nil {
                    anchor = v.location
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
            }
            .onEnded { _ in
                start = nil
                guard tear >= 1 else { return }   // 没撕完就停在那,下次接着撕
                anchor = nil
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { hand = .zero; detach = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    withAnimation(.easeOut(duration: 0.4)) { page = true }
                }
            }
    }

    private func cancel() {
        guard tear < 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { up = false; tear = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { dismiss() }
        }
    }
}

/// 撕口(照 jal-co/boarding-pass 的 tear.ts,MIT): 虚线是一格格「切口 5pt + 纸桥 4pt」;
/// 撕开的部分(从上往下)切口边变成参差毛边,票身和存根用同一组毛刺,两边对得上;
/// 上下两个半圆缺口真挖空。票身裁右边、存根裁左边
struct TearEdge: Shape {
    let stub: Bool
    var tear: Double
    let nibs: [CGFloat]
    var roundBottom = true
    static let top: CGFloat = 6, pitch: CGFloat = 9, cut: CGFloat = 5, notch: CGFloat = 9, amp: CGFloat = 1.8, corner: CGFloat = 12

    var animatableData: Double { get { tear } set { tear = newValue } }

    static func nibs(seed: Int) -> [CGFloat] {
        var r = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 7)
        return (0..<80).map { _ in
            r = r &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double(r >> 11) / Double(1 << 53)) * 2 - 1
        }
    }

    /// 毛刺: 切口那 5pt 是直的(本来就切开了),纸桥那 4pt 撕出来是参差的
    private func nib(_ y: CGFloat) -> CGFloat {
        let k = (y - Self.top) / Self.pitch
        guard k >= 0 else { return 0 }
        let within = y - Self.top - floor(k) * Self.pitch
        if within < Self.cut { return 0 }
        return nibs[Int(k) % nibs.count]
    }

    func path(in r: CGRect) -> Path {
        let edgeX = stub ? r.minX : r.maxX, outerX = stub ? r.maxX : r.minX
        let front = CGFloat(tear) * r.height
        let n = Self.notch, c = Self.corner, rb = roundBottom ? c : 0
        var pts: [CGPoint] = []
        // 上缺口(圆心在虚线顶端)
        for i in 0...6 {
            let a = Double.pi / 2 * Double(i) / 6
            pts.append(CGPoint(x: edgeX + (stub ? 1 : -1) * n * cos(a), y: r.minY + n * sin(a)))
        }
        var y = r.minY + n
        while y <= r.maxY - n {
            let off = y <= r.minY + front ? nib(y - r.minY) * Self.amp : 0
            pts.append(CGPoint(x: edgeX + off, y: y))
            y += 1
        }
        for i in 0...6 {
            let a = Double.pi / 2 * Double(6 - i) / 6
            pts.append(CGPoint(x: edgeX + (stub ? 1 : -1) * n * cos(a), y: r.maxY - n * sin(a)))
        }
        var p = Path()
        p.move(to: CGPoint(x: (outerX + edgeX) / 2, y: r.minY))
        p.addLines([CGPoint(x: (outerX + edgeX) / 2, y: r.minY)] + pts)
        // 外侧两个圆角
        p.addArc(tangent1End: CGPoint(x: outerX, y: r.maxY), tangent2End: CGPoint(x: outerX, y: r.minY), radius: rb)
        p.addArc(tangent1End: CGPoint(x: outerX, y: r.minY), tangent2End: CGPoint(x: edgeX, y: r.minY), radius: c)
        p.closeSubpath()
        return p
    }

    /// 还没断的纸桥: 从票身的虚线连到掀开后存根的左边(存根绕左下角转 angle 度);撕到哪断到哪
    static func bridges(edgeX: CGFloat, height H: CGFloat, tear: Double, angle: Double) -> Path {
        let count = Int((H - top) / pitch)
        let broken = Int(tear * Double(count))
        let a = angle * .pi / 180, sn = CGFloat(sin(a)), cs = CGFloat(cos(a))
        var p = Path()
        for i in broken..<max(broken, count) {
            let y0 = top + CGFloat(i) * pitch + cut, h = pitch - cut
            guard y0 > notch, y0 + h < H - notch else { continue }
            let tx = edgeX + (H - y0) * sn, ty = H + (y0 - H) * cs
            let bx = edgeX + (H - y0 - h) * sn, by = H + (y0 + h - H) * cs
            p.move(to: CGPoint(x: edgeX - 1, y: y0))
            p.addLine(to: CGPoint(x: tx + 1, y: ty))
            p.addLine(to: CGPoint(x: bx + 1, y: by))
            p.addLine(to: CGPoint(x: edgeX - 1, y: y0 + h))
            p.closeSubpath()
        }
        return p
    }
}

/// 虚线上下两个半圆缺口: 真挖空(不是画纸色圆点),票浮在暗处时也是洞
private struct Notched: View {
    let edge: HorizontalEdge
    var body: some View {
        Rectangle()
            .overlay(alignment: edge == .leading ? .topLeading : .topTrailing) {
                Circle().frame(width: 18, height: 18).offset(x: edge == .leading ? -9 : 9, y: -9).blendMode(.destinationOut)
            }
            .overlay(alignment: edge == .leading ? .bottomLeading : .bottomTrailing) {
                Circle().frame(width: 18, height: 18).offset(x: edge == .leading ? -9 : 9, y: 9).blendMode(.destinationOut)
            }
            .compositingGroup()
    }
}

private struct VLine: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.midX, y: 0)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)) } }
}

/// 「这一次」整页
struct TripPage: View {
    let tripId: Int
    @ObservedObject var store: StopoverStore
    /// 进来就抽出这一页(BinderLeaf.id),往来跳过来用
    var focusLeaf: String? = nil
    @State private var gridTouched = false
    @Environment(\.dismiss) private var dismiss
    @State private var photo: StopoverPhoto?
    @State private var sheet: TripSheet?
    @State private var confirmOff = false
    @State private var leaving = false
    // 递给\(StopoverStore.shared.config.partner): gateOpen = 展开二选一;sel != nil = 正在挑几段、几张
    @State private var gateOpen = false
    @State private var sel: (n: Set<Int>, p: Set<Int>)?
    @State private var sendNote = ""
    @State private var sending = false
    // 活页夹是默认;老网格留着: 票右上角能切,挑几段几张也走它
    @AppStorage("stopover.tripGrid") private var gridMode = false

    enum TripSheet: Identifiable {
        case info, origin, dest, newNote, note(StopoverNote), addPhoto
        var id: String {
            switch self {
            case .info: "info"; case .origin: "origin"; case .dest: "dest"; case .newNote: "new"; case .addPhoto: "photo"
            case .note(let n): "note\(n.id)"
            }
        }
    }

    var body: some View {
        if let t = store.checkins.first(where: { $0.id == tripId }) {
            content(t).stopoverToast(store)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ t: StopoverCheckin) -> some View {
        let trips = store.trips(t.city)
        let n = (trips.firstIndex { $0.id == t.id } ?? 0) + 1
        return Group {
            // 跳过来要看那一页,网格模式也先走活页夹;手动切过就按手动的
            if (gridMode && (focusLeaf == nil || gridTouched)) || sel != nil {
                gridContent(t, n: n, trips: trips)
            } else {
                StopoverBinderPage(
                    trip: t, store: store,
                    focusLeaf: focusLeaf,
                    ticket: AnyView(darkPass(t, n: n)),
                    gatePage: AnyView(VStack(alignment: .leading, spacing: 12) {
                        gateArea(t, ns: store.notes(trip: t.id), ps: store.photos(trip: t.id))
                        pendingBox(t)
                    }),
                    talkPage: AnyView(talkBody(t)),
                    editPhoto: { photo = $0 },
                    editNote: { sheet = .note($0) },
                    shareNote: { x in
                        Task { await store.share([["type": "note", "id": x.id]], done: "这段递出了，两分钟内会送到\(store.config.partner)那") }
                    },
                    newNote: { sheet = .newNote },
                    addPhoto: { sheet = .addPhoto },
                    sharing: store.config.share
                )
            }
        }
        .preferredColorScheme(.dark)   // 只为了状态栏字变白;页面颜色都是写死的
        .sheet(item: $photo) { p in
            PhotoBig(photo: p, trip: t, seat: n, store: store)
                .presentationDetents([.large])
        }
        .sheet(item: $sheet) { which in
            tripSheet(which, t)
        }
    }

    @ViewBuilder private func talkBody(_ t: StopoverCheckin) -> some View {
        let cs = store.comments("trip:\(t.id)")
        if cs.isEmpty {
            Text("这张票上\(store.config.partner)还没说什么。").font(StopoverK.serif(15)).foregroundStyle(StopoverK.ink2)
        } else {
            CommentBlock(comments: cs, target: "trip:\(t.id)", store: store)
        }
    }

    /// 老的网格页
    private func gridContent(_ t: StopoverCheckin, n: Int, trips: [StopoverCheckin]) -> some View {
        let ns = store.notes(trip: t.id), ps = store.photos(trip: t.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                darkPass(t, n: n)
                if let sl = sel {
                    let k = sl.n.count + sl.p.count, full = k == ns.count + ps.count
                    HStack(spacing: 14) {
                        Text(k > 0 ? "选了 " + [sl.n.isEmpty ? nil : "\(sl.n.count) 段", sl.p.isEmpty ? nil : "\(sl.p.count) 张"].compactMap { $0 }.joined(separator: "、")
                                   : "点随记或照片，选要递的")
                            .font(StopoverK.serif(14)).foregroundStyle(StopoverK.ink)
                        Spacer()
                        Button(full ? "全不选" : "全选") {
                            sel = full ? ([], []) : (Set(ns.map(\.id)), Set(ps.map(\.id)))
                        }
                        Button("取消") { withAnimation { sel = nil } }
                    }
                    .font(.system(size: 13.5)).foregroundStyle(StopoverK.harbor)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(StopoverK.harbor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                subHead("随记", ns.isEmpty ? "还没有" : "\(ns.count) 段")
                ForEach(ns) { x in noteCard(x) }
                if sel == nil { Button { sheet = .newNote } label: { addSmall("＋ 写一段") }.buttonStyle(.plain) }
                subHead("照片", ps.isEmpty ? "还没有" : "\(ps.count) 张 · 点开看大图")
                if ps.isEmpty {
                    Button { sheet = .addPhoto } label: { addSmall("＋ 加照片") }.buttonStyle(.plain)
                    Text("不放照片也行，有随记就够了。").font(.system(size: 12.5)).foregroundStyle(StopoverK.ink2)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(ps) { p in photoCell(p) }
                        if sel == nil { Button { sheet = .addPhoto } label: { addCell }.buttonStyle(.plain) }
                    }
                }
                gateArea(t, ns: ns, ps: ps).padding(.top, 10)
                pendingBox(t)
                comments("trip:\(t.id)")
                // 点两次确认;4 秒没点第二下就算了
                Button {
                    if !confirmOff {
                        withAnimation { confirmOff = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { confirmOff = false } }
                        return
                    }
                    guard !leaving else { return }
                    leaving = true
                    Task { if await store.deleteTrip(t.id) { dismiss() } else { leaving = false } }
                } label: {
                    Text(confirmOff ? (ps.isEmpty && ns.isEmpty ? "再点一次确认" : "随记和照片也会一起取下，再点一次确认")
                         : trips.count > 1 ? "删掉这一次" : "取消来过")
                        .font(.system(size: 14)).foregroundStyle(Color(UIColor(hex: 0x9a2a22)))
                        .underline(true, color: Color(UIColor(hex: 0x9a2a22)).opacity(0.5))
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .background(Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).ignoresSafeArea())
    }

    private func tripSheet(_ which: TripSheet, _ t: StopoverCheckin) -> some View {
            Group {
                switch which {
                case .info: TripInfoForm(trip: t, store: store)
                case .origin:
                    CityChips(question: "那一次从哪儿出发到\(store.cities[t.city]?.name ?? "")？",
                              choices: store.originChoices(for: t.city, current: t.origin ?? t.city), current: t.origin, store: store,
                              ghost: [("不连线", t.city)]) { id in
                        await store.updateTrip(t.id, ["origin": id ?? t.city],
                                               done: id == nil || id == t.city ? "改好了：这次不连线" : "改好了：从\(store.cities[id!]?.name ?? "")出发")
                    }
                case .dest:
                    CityChips(question: "这一趟最后回到哪儿？", choices: store.destChoices(for: t.city, current: t.dest),
                              current: t.dest, store: store, ghost: t.dest == nil ? [] : [("不设终点", nil)]) { id in
                        await store.updateTrip(t.id, ["dest": id ?? NSNull()],
                                               done: id.flatMap { store.cities[$0] }.map { "回到\($0.name)，线连上了" } ?? "终点去掉了")
                    }
                case .newNote: NoteEditor(store: store, tripId: t.id, note: nil)
                case .note(let x): NoteEditor(store: store, tripId: t.id, note: x)
                case .addPhoto: AddPhotoSheet(trip: t, store: store)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(StopoverK.paper)
    }

    /// 上半深色整张票,底边一排小半圆撕口
    private func darkPass(_ t: StopoverCheckin, n: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                tkLabel("BOARDING PASS · 第 \(n) 次", dark: true)
                Spacer()
                if sel == nil {
                    Button { gridTouched = true; withAnimation(.easeOut(duration: 0.2)) { gridMode.toggle() } } label: {
                        Image(systemName: gridMode ? "rectangle.split.3x1" : "square.grid.3x3")
                            .font(.system(size: 15)).foregroundStyle(Color(UIColor(hex: 0xcbd5e2))).frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
                Button { dismiss() } label: {
                    Text("×").font(.system(size: 24)).foregroundStyle(Color(UIColor(hex: 0xcbd5e2))).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            TicketRoute(trip: t, store: store, dark: true)
            HStack(alignment: .top) {
                cell("DATE", store.dateText(t) ?? "——")
                cell("DISTANCE", store.km(t.origin, t.city).flatMap { t.origin == t.city ? nil : $0 }
                        .map { $0.formatted(.number.locale(Locale(identifier: "en_US"))) + " km" } ?? "——")
                cell("SEAT", String(format: "%02d", n))
            }
            if let r = t.remark, !r.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    tkLabel("REMARKS · 备注", dark: true)
                    Text(r).font(StopoverK.serif(16)).foregroundStyle(.white).lineSpacing(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .overlay(alignment: .top) {
                    Line().stroke(TK.labelDark.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
                }
            }
            HStack(spacing: 20) {
                Button { sheet = .info } label: {
                    editLink((t.remark ?? "").isEmpty ? (t.dateStart == nil ? "补日期 · 加一句备注" : "加一句备注") : "改日期和备注")
                }
                Button { sheet = .origin } label: { editLink("改出发地") }
                Button { sheet = .dest } label: { editLink(t.dest == nil ? "加终点" : "改终点") }
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 4)
        .background(Guilloche())
        // 深色往上多铺一截: 接进状态栏,往下拉过头也不露纸,而且跟着票一起滚
        .background(TK.night.padding(.top, -600))
        .overlay(alignment: .bottom) { tear.offset(y: 6) }
        .padding(.horizontal, -18)
        .padding(.bottom, 10)
    }

    private var tear: some View {
        Canvas { ctx, size in
            var x: CGFloat = 8
            while x < size.width + 8 {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 5.5, y: 0.5, width: 11, height: 11)), with: .color(StopoverK.paper))
                x += 16
            }
        }
        .frame(height: 12)
    }

    private func cell(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { tkLabel(l, dark: true); tkValue(v, dark: true, size: 14) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editLink(_ t: String) -> some View {
        Text(t).font(.system(size: 14)).foregroundStyle(TK.subDark).underline(true, color: TK.subDark.opacity(0.5))
    }

    private func subHead(_ zh: String, _ right: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(zh).font(StopoverK.serif(15, .semibold)).tracking(3.6).foregroundStyle(StopoverK.ink)
            Spacer()
            Text(right).font(StopoverK.mono(12)).tracking(0.5).foregroundStyle(TK.sub)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(StopoverK.harbor.opacity(0.18)).frame(height: 1) }
        .padding(.top, 10)
    }

    private func noteCard(_ x: StopoverNote) -> some View {
        let on = sel?.n.contains(x.id) ?? false
        return HStack(alignment: .top, spacing: 12) {
            if sel != nil { check(on).padding(.top, 2) }
            VStack(alignment: .leading, spacing: 8) {
                Text(x.text).font(StopoverK.serif(15)).foregroundStyle(StopoverK.ink).lineSpacing(9)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(sel != nil && !on ? 0.65 : 1)
                if sel == nil {
                    HStack(spacing: 16) {
                        Text(Self.ago(x.updated) + " 记").font(StopoverK.serif(12)).foregroundStyle(Color(UIColor(hex: 0x8a93a0)))
                        Button {
                            Task { await store.share([["type": "note", "id": x.id]], done: "这段递出了，两分钟内会送到\(StopoverStore.shared.config.partner)那") }
                        } label: { link("递这段") }.buttonStyle(.plain)
                        Button { sheet = .note(x) } label: { link("改") }.buttonStyle(.plain)
                    }
                    comments("note:\(x.id)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(TK.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { if on { RoundedRectangle(cornerRadius: 10).strokeBorder(StopoverK.harbor, lineWidth: 1.5) } }
        .contentShape(Rectangle())
        .onTapGesture {
            guard var sl = sel else { return }
            if on { sl.n.remove(x.id) } else { sl.n.insert(x.id) }
            sel = sl
        }
    }

    private func check(_ on: Bool) -> some View {
        Circle().strokeBorder(on ? .white : StopoverK.harbor, lineWidth: 2)
            .background(Circle().fill(on ? StopoverK.harbor : .clear))
            .overlay { if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
            .frame(width: 22, height: 22)
    }

    // MARK: 递给\(StopoverStore.shared.config.partner)

    /// GATE: 平时一个按钮;点开二选一(递整张票 / 挑几段、几张);挑的时候变成「附一句话 + 递出 N 样」
    @ViewBuilder private func gateArea(_ t: StopoverCheckin, ns: [StopoverNote], ps: [StopoverPhoto]) -> some View {
        if let sl = sel {
            let k = sl.n.count + sl.p.count
            VStack(spacing: 10) {
                noteField
                Button {
                    sending = true
                    let items: [[String: Any]] = sl.n.sorted().map { ["type": "note", "id": $0] } + sl.p.sorted().map { ["type": "photo", "id": $0] }
                    Task {
                        if await store.share(items, note: sendNote.trimmingCharacters(in: .whitespacesAndNewlines),
                                             done: "递出 \(k) 样，两分钟内会送到\(StopoverStore.shared.config.partner)那") {
                            withAnimation { sel = nil }; sendNote = ""
                        }
                        sending = false
                    }
                } label: { gate(k > 0 ? "递出 \(k) 样" : "递出") }
                .buttonStyle(.plain).disabled(k == 0 || sending).opacity(k == 0 ? 0.5 : 1)
            }
        } else if gateOpen {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    sending = true
                    Task {
                        if await store.share([["type": "trip", "id": t.id]], done: "整张票递出了，两分钟内会送到\(StopoverStore.shared.config.partner)那") { gateOpen = false }
                        sending = false
                    }
                } label: { gate("递整张票", sub: "备注、\(ns.count) 段随记、\(ps.count) 张照片一起") }
                .buttonStyle(.plain).disabled(sending)
                if ns.count + ps.count > 0 {
                    Button { withAnimation { gateOpen = false; sel = ([], []) } } label: { gate("挑几段、几张", soft: true) }
                        .buttonStyle(.plain)
                }
                Button("先不递") { withAnimation { gateOpen = false } }
                    .font(.system(size: 14)).foregroundStyle(StopoverK.harbor).padding(.top, 2)
            }
        } else {
            Button { withAnimation { gateOpen = true } } label: {
                gate(ns.count + ps.count > 0 ? "递整张票，或挑几段、几张" : "把这张票递给\(StopoverStore.shared.config.partner)")
            }
            .buttonStyle(.plain)
        }
    }

    private var noteField: some View {
        TextField("", text: $sendNote, prompt: Text("附一句话给\(StopoverStore.shared.config.partner)（选填）").foregroundStyle(StopoverK.ink2.opacity(0.7)))
                .foregroundStyle(StopoverK.ink).tint(StopoverK.harbor)
            .font(StopoverK.serif(15)).padding(12)
            .background(TK.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(StopoverK.ink.opacity(0.1)))
            .onChange(of: sendNote) { _, v in if v.count > 500 { sendNote = String(v.prefix(500)) } }
    }

    /// 待送达: 写明递了什么,送到之前都能撤回
    @ViewBuilder private func pendingBox(_ t: StopoverCheckin) -> some View {
        let pend = store.pendingShares(trip: t.id)
        if !pend.isEmpty {
            let ns = Set(store.notes(trip: t.id).map(\.id)), ps = Set(store.photos(trip: t.id).map(\.id))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(pend) { x in
                    let tr = x.items.filter { $0.type == "trip" && $0.id == t.id }.count
                    let n = x.items.filter { $0.type == "note" && ns.contains($0.id ?? -1) }.count
                    let p = x.items.filter { $0.type == "photo" && ps.contains($0.id ?? -1) }.count
                    let what = [tr > 0 ? "整张票" : nil, n > 0 ? "\(n) 段随记" : nil, p > 0 ? "\(p) 张照片" : nil].compactMap { $0 }.joined(separator: " + ")
                    HStack(alignment: .firstTextBaseline) {
                        Text("待送达 · \(what)" + (x.note.isEmpty ? "" : " · “\(x.note)”"))
                            .font(StopoverK.serif(14)).foregroundStyle(StopoverK.ink)
                        Spacer()
                        Button("撤回") { Task { await store.unshare(x.id) } }
                            .font(.system(size: 13.5)).foregroundStyle(StopoverK.harbor)
                    }
                }
                Text("两分钟内连着递的会合成一条送过去；送到之前都能撤回。").font(.system(size: 12)).foregroundStyle(StopoverK.ink2)
            }
            .padding(14)
            .background(Color(UIColor(hex: 0xD8CBB2)).opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func link(_ t: String) -> some View {
        Text(t).font(.system(size: 12.5)).foregroundStyle(StopoverK.harbor).underline(true, color: StopoverK.harbor)
    }

    private func addSmall(_ t: String) -> some View {
        Text(t).font(StopoverK.serif(14)).foregroundStyle(StopoverK.harbor)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TK.label, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private func photoCell(_ p: StopoverPhoto) -> some View {
        let on = sel?.p.contains(p.id) ?? false
        return Button {
            if var sl = sel {
                if on { sl.p.remove(p.id) } else { sl.p.insert(p.id) }
                sel = sl
            } else { photo = p }
        } label: {
            Color(UIColor(hex: 0xD8CBB2)).aspectRatio(1, contentMode: .fit)
                .overlay { WikiImage(url: StopoverStore.photoURL(p.id, w: 600)) }
                .overlay(alignment: .bottomLeading) {
                    if !p.caption.isEmpty {
                        Text(p.caption).font(StopoverK.serif(11)).foregroundStyle(.white).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6).padding(.top, 14).padding(.bottom, 4)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    let c = store.comments("photo:\(p.id)").count
                    if c > 0 {
                        Text("\(c)").font(StopoverK.mono(10)).foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18).background(StopoverK.harbor, in: Capsule()).padding(4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .topLeading) { if sel != nil { check(on).padding(6) } }
                .opacity(sel != nil && !on ? 0.6 : 1)
                .scaleEffect(on ? 0.92 : 1)
                .animation(.easeOut(duration: 0.15), value: on)
        }
        .buttonStyle(.plain)
    }

    private var addCell: some View {
        Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 2) {
                    Text("＋").font(.system(size: 22))
                    Text("加照片").font(StopoverK.serif(12))
                }
                .foregroundStyle(StopoverK.harbor)
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(TK.label, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    /// 登机口按钮(递出下一步接)
    private func gate(_ title: String, sub: String? = nil, soft: Bool = false) -> some View {
        GateLabel(title: title, sub: sub, soft: soft)
    }

    @ViewBuilder private func comments(_ target: String) -> some View {
        let cs = store.comments(target)
        if !cs.isEmpty { CommentBlock(comments: cs, target: target, store: store) }
    }

    static func ago(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts), c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: d)
        return String(format: "%d.%d %02d:%02d", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - 「这一次」里的几张小表

private struct FormHead: View {
    let title: String
    var body: some View {
        Text(title).font(StopoverK.serif(18, .semibold)).foregroundStyle(StopoverK.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func formField(_ label: String, _ text: Binding<String>, placeholder: String, limit: Int? = nil, date: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(label).font(.system(size: 12.5)).foregroundStyle(StopoverK.ink2)
        // 页面压着深色模式,系统默认的提示字在浅底上看不见,要写死颜色
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(StopoverK.ink2.opacity(0.7)))
            .font(StopoverK.serif(16)).foregroundStyle(StopoverK.ink)
            .tint(StopoverK.harbor)
            .keyboardType(date ? .numbersAndPunctuation : .default)
            .autocorrectionDisabled(date)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(TK.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(StopoverK.ink.opacity(0.12)))
            .onChange(of: text.wrappedValue) { _, v in if let limit, v.count > limit { text.wrappedValue = String(v.prefix(limit)) } }
    }
}

private func solidPill(_ t: String, busy: Bool = false, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(busy ? "存着…" : t).font(.system(size: 15)).foregroundStyle(StopoverK.paper)
            .padding(.horizontal, 22).frame(minHeight: 44)
            .background(Capsule().fill(StopoverK.harbor))
    }
    .buttonStyle(.plain).disabled(busy)
}

/// 服务端只认 2019 / 2019-08 / 2019-08-03。手写的 2019.8.3、2019/8/3、2019年8月3日、20190803 都翻译过去。
/// 空着回 "";看不懂回 nil
enum TripDateInput {
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        if s.count == 8, s.allSatisfy(\.isNumber) {
            s = "\(s.prefix(4))-\(s.dropFirst(4).prefix(2))-\(s.suffix(2))"
        }
        let parts = s.split(whereSeparator: { ".。．/／-－—–年月日 ".contains($0) }).map(String.init)
        guard (1...3).contains(parts.count), parts[0].count == 4,
              let nums = Optional(parts.compactMap { Int($0) }), nums.count == parts.count else { return nil }
        if nums.count >= 2, !(1...12).contains(nums[1]) { return nil }
        if nums.count == 3 {
            let c = DateComponents(year: nums[0], month: nums[1], day: nums[2])
            guard Calendar(identifier: .gregorian).date(from: c) != nil, (1...31).contains(nums[2]),
                  c.isValidDate(in: Calendar(identifier: .gregorian)) else { return nil }
        }
        return ([String(format: "%04d", nums[0])] + nums.dropFirst().map { String(format: "%02d", $0) }).joined(separator: "-")
    }
}

/// 改日期和备注: 日期记得就写,不记得就空着;备注一句话 ≤60 字,印在票上
struct TripInfoForm: View {
    let trip: StopoverCheckin
    @ObservedObject var store: StopoverStore
    @Environment(\.dismiss) private var dismiss
    @State private var start = ""
    @State private var end = ""
    @State private var remark = ""
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormHead(title: "日期记得就写，不记得就空着")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    formField("从", $start, placeholder: "2019.8.3", date: true)
                    formField("到", $end, placeholder: "选填", date: true)
                }
                Text("只记得年或月也行：2019、2019.8").font(.system(size: 12)).foregroundStyle(StopoverK.ink2)
            }
            formField("票面备注 · 一句话，印在登机牌上（可以空着）", $remark, placeholder: "比如：第一次见地中海", limit: 60)
            HStack(spacing: 18) {
                solidPill("保存", busy: busy) {
                    guard let from = TripDateInput.normalize(start), let to = TripDateInput.normalize(end) else {
                        problem = "这个日期我看不懂，写成 2019.8.3 这样试试"
                        return
                    }
                    problem = nil
                    busy = true
                    Task {
                        let ok = await store.updateTrip(trip.id, ["date_start": from, "date_end": to,
                                                                  "remark": remark.trimmingCharacters(in: .whitespaces)])
                        busy = false
                        // 失败的提示在表单后面的页面上,会被挡住,这里也说一声
                        if ok { dismiss() } else { problem = store.toast ?? "没存上，一会儿再试" }
                    }
                }
                Button("先不了") { dismiss() }.font(.system(size: 14)).foregroundStyle(StopoverK.harbor)
            }
            if let problem {
                Text(problem).font(.system(size: 13)).foregroundStyle(Color(UIColor(hex: 0x9a2a22)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(22)
        .onAppear { start = trip.dateStart ?? ""; end = trip.dateEnd ?? ""; remark = trip.remark ?? "" }
    }
}

/// 选城: 出发地 / 终点 / 记一次经停共用一套小胶囊
struct CityChips: View {
    let question: String
    let choices: [(id: String, tag: String)]
    let current: String?
    @ObservedObject var store: StopoverStore
    var ghost: [(label: String, value: String?)] = []
    let pick: (String?) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormHead(title: question)
            ChipFlow(spacing: 8) {
                ForEach(choices, id: \.id) { c in
                    chip(store.cities[c.id]?.name ?? c.id, tag: c.tag, on: c.id == current) { go(c.id) }
                }
                chip("搜别的城…", tag: "", on: false, ghost: true) { searching = true }
                ForEach(ghost, id: \.label) { g in chip(g.label, tag: "", on: false, ghost: true) { go(g.value) } }
            }
            Button("先不了") { dismiss() }.font(.system(size: 14)).foregroundStyle(StopoverK.harbor)
            Spacer()
        }
        .padding(22)
        // 搜出来的城(也能现加地图上没有的地方)直接填进去
        .sheet(isPresented: $searching) {
            StopoverSearch(store: store, pickHint: question) { id in go(id) }
                .presentationDetents([.large])
        }
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
    }

    private func go(_ v: String?) {
        busy = true
        Task { await pick(v); dismiss() }
    }

    private func chip(_ t: String, tag: String, on: Bool, ghost: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(t).font(StopoverK.serif(15))
                if !tag.isEmpty { Text(tag).font(.system(size: 11)).foregroundStyle(on ? StopoverK.paper.opacity(0.8) : TK.label) }
            }
            .foregroundStyle(on ? StopoverK.paper : ghost ? StopoverK.ink2 : StopoverK.ink)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(on ? StopoverK.harbor : ghost ? Color.clear : TK.card))
            .overlay(Capsule().strokeBorder(ghost ? StopoverK.ink2.opacity(0.4) : StopoverK.ink.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: ghost ? [4, 3] : [])))
        }
        .buttonStyle(.plain)
    }
}

/// 写一段 / 改一段随记(改里面能删,点两次确认)
struct NoteEditor: View {
    @ObservedObject var store: StopoverStore
    let tripId: Int
    let note: StopoverNote?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = false
    @State private var confirmDel = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormHead(title: note == nil ? "写一段随记" : "改随记")
            TextEditor(text: $text)
                .font(StopoverK.serif(16)).foregroundStyle(StopoverK.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(TK.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("这一趟，想记下点什么…长短都行").font(StopoverK.serif(16)).foregroundStyle(StopoverK.ink2.opacity(0.6))
                            .padding(.horizontal, 15).padding(.vertical, 18).allowsHitTesting(false)
                    }
                }
                .focused($focused)
                .frame(minHeight: 160)
            HStack(spacing: 18) {
                solidPill(note == nil ? "记下" : "保存", busy: busy) {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { store.toast = "还没写呢"; return }
                    busy = true
                    Task {
                        let ok = note == nil ? await store.addNote(trip: tripId, String(t.prefix(5000)))
                                             : await store.editNote(note!.id, String(t.prefix(5000)))
                        busy = false
                        if ok { dismiss() }
                    }
                }
                Button(note == nil ? "先不写" : "先不改") { dismiss() }.font(.system(size: 14)).foregroundStyle(StopoverK.harbor)
                Spacer()
                if let n = note {
                    Button(confirmDel ? "确认删？" : "删掉这段") {
                        if !confirmDel { confirmDel = true; return }
                        busy = true
                        Task { if await store.deleteNote(n.id) { dismiss() } else { busy = false } }
                    }
                    .font(.system(size: 14)).foregroundStyle(Color(UIColor(hex: 0x9a2a22)))
                }
            }
        }
        .padding(22)
        .onAppear { text = note?.text ?? ""; focused = true }
    }
}

/// 登机口按钮: 「GATE · 递给\(StopoverStore.shared.config.partner)」小字 + 大字 + →;soft = 浅蓝底(挑几段、几张)
struct GateLabel: View {
    let title: String
    var sub: String? = nil
    var soft = false
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GATE · 递给\(StopoverStore.shared.config.partner)").font(StopoverK.mono(9.5, .medium)).tracking(1.7)
                    .foregroundStyle(soft ? TK.label : Color(UIColor(hex: 0xcbd9ea)))
                Text(title).font(StopoverK.serif(16, .semibold)).tracking(1).foregroundStyle(soft ? StopoverK.ink : .white)
                if let sub { Text(sub).font(StopoverK.serif(12)).foregroundStyle(soft ? StopoverK.ink2 : Color(UIColor(hex: 0xcbd9ea))) }
            }
            Spacer()
            Text("→").font(StopoverK.mono(20, .semibold)).foregroundStyle(soft ? StopoverK.harbor : .white)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(soft ? StopoverK.harbor.opacity(0.12) : StopoverK.harbor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 递城市 / 景点 / 美食: 「附上图片」开关(默认开)+ 附一句话 + 递出
struct ShareThingSheet: View {
    let name: String
    let item: [String: Any]
    @ObservedObject var store: StopoverStore
    @Environment(\.dismiss) private var dismiss
    @State private var img = true
    @State private var note = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("把「\(name)」递给\(StopoverStore.shared.config.partner)").font(StopoverK.serif(18, .semibold)).foregroundStyle(StopoverK.ink)
                Spacer()
                Button { dismiss() } label: { Text("×").font(.system(size: 22)).foregroundStyle(StopoverK.ink2) }.buttonStyle(.plain)
            }
            Toggle(isOn: $img) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("附上图片").font(StopoverK.serif(15, .semibold)).foregroundStyle(StopoverK.ink)
                    Text("附了\(StopoverStore.shared.config.partner)直接看到（压缩过）；不附就只给链接，想看自己取").font(.system(size: 12)).foregroundStyle(StopoverK.ink2)
                }
            }
            .tint(StopoverK.harbor)
            TextField("", text: $note, prompt: Text("附一句话（选填）").foregroundStyle(StopoverK.ink2.opacity(0.7)))
                .foregroundStyle(StopoverK.ink).tint(StopoverK.harbor)
                .font(StopoverK.serif(15)).padding(12)
                .background(TK.card, in: RoundedRectangle(cornerRadius: 10))
            Button {
                busy = true
                Task {
                    if await store.share([item], note: note.trimmingCharacters(in: .whitespacesAndNewlines), img: img,
                                         done: "把「\(name)」递出了，两分钟内会送到\(StopoverStore.shared.config.partner)那") { dismiss() }
                    busy = false
                }
            } label: { GateLabel(title: busy ? "递着…" : "递出") }
            .buttonStyle(.plain).disabled(busy)
            Spacer()
        }
        .padding(22)
    }
}

struct CommentBlock: View {
    let comments: [StopoverComment]
    let target: String
    @ObservedObject var store: StopoverStore
    var title = "\(StopoverStore.shared.config.partner)说"
    /// 正在回哪一条
    @State private var replyTo: StopoverComment?
    @State private var text = ""
    @State private var busy = false
    @State private var confirmDel: Int?
    @FocusState private var focused: Bool

    var body: some View {
        let by = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })
        VStack(alignment: .leading, spacing: 4) {
            if !title.isEmpty { Text(title).font(StopoverK.serif(13)).foregroundStyle(TK.yy) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(comments) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        (Text(StopoverStore.shared.config.name(c.who) + " ").font(StopoverK.serif(14.5, .bold))
                            .foregroundColor(c.who == "partner" ? TK.yy : Color(UIColor(hex: 0x9a6a12)))
                         + Text(c.replyTo.flatMap { by[$0] }.map { "回复 \(StopoverStore.shared.config.name($0.who)) " } ?? "").font(.system(size: 12)).foregroundColor(TK.label)
                         + Text(c.text).font(StopoverK.serif(14.5)).foregroundColor(StopoverK.ink))
                            .lineSpacing(5)
                        HStack(spacing: 14) {
                            Text(TripPage.ago(c.created)).font(.system(size: 11)).foregroundStyle(Color(UIColor(hex: 0x8a93a0)))
                            if c.who == "partner" {
                                Button("回复") { replyTo = c; focused = true }
                            } else {
                                Button(confirmDel == c.id ? "确认删？" : "删") {
                                    if confirmDel != c.id { confirmDel = c.id; return }
                                    Task { await store.deleteComment(c.id); confirmDel = nil }
                                }
                            }
                        }
                        .font(.system(size: 12)).foregroundStyle(StopoverK.harbor)
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        Line().stroke(StopoverK.harbor.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
                    }
                }
                if let r = replyTo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("回复 \(StopoverStore.shared.config.name(r.who))：").font(.system(size: 12)).foregroundStyle(TK.label)
                            Spacer()
                            Button("不回了") { replyTo = nil; text = "" }.font(.system(size: 12)).foregroundStyle(StopoverK.harbor)
                        }
                        HStack(spacing: 8) {
                            TextField("", text: $text, prompt: Text("回复 \(StopoverStore.shared.config.name(r.who))…").foregroundStyle(StopoverK.ink2.opacity(0.7)), axis: .vertical)
                                .foregroundStyle(StopoverK.ink).tint(StopoverK.harbor)
                                .font(StopoverK.serif(15)).lineLimit(1...5)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(TK.card, in: RoundedRectangle(cornerRadius: 8))
                                .focused($focused)
                                .onChange(of: text) { _, v in if v.count > 2000 { text = String(v.prefix(2000)) } }
                            Button {
                                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !t.isEmpty else { return }
                                busy = true
                                Task {
                                    if await store.comment(target, t, replyTo: r.id) { replyTo = nil; text = "" }
                                    busy = false
                                }
                            } label: {
                                Text(busy ? "发着…" : "发").font(.system(size: 14)).foregroundStyle(StopoverK.harbor)
                                    .padding(.horizontal, 14).frame(minHeight: 36)
                                    .background(Capsule().fill(StopoverK.harbor.opacity(0.12)))
                            }
                            .buttonStyle(.plain).disabled(busy)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(StopoverK.harbor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.top, 4)
    }
}

/// 照片大图: 大图 + 一条细票签(HEI → PAL · SEAT 01 · 2019.07)+ 配文 + \(StopoverStore.shared.config.partner)说
private struct PhotoBig: View {
    let photo: StopoverPhoto
    let trip: StopoverCheckin
    let seat: Int
    @ObservedObject var store: StopoverStore
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var capState = ""      // 还没保存 / 保存中… / ✓ 已记下
    @State private var confirmOff = false
    @State private var sendOpen = false
    @State private var sendNote = ""

    /// 改完配文/标签后 store 里那份会变,以它为准
    private var cur: StopoverPhoto { store.photos.first { $0.id == photo.id } ?? photo }

    var body: some View {
        let dirty = caption.trimmingCharacters(in: .whitespacesAndNewlines) != cur.caption
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WikiImage(url: StopoverStore.photoURL(photo.id, w: 1600), fit: true)
                    .frame(maxWidth: .infinity).background(Color.black)
                VStack(alignment: .leading, spacing: 12) {
                    Text([trip.origin.flatMap { $0 == trip.city ? nil : store.code3($0) + " → " } ?? "", store.code3(trip.city),
                          " · SEAT ", String(format: "%02d", seat), store.dateText(trip).map { " · " + $0 } ?? "",
                          ].joined())
                        .font(StopoverK.mono(11, .medium)).tracking(1.5).foregroundStyle(Color(UIColor(hex: 0x6F9FC8)))
                    // 配文: 改了显示「还没保存」+「保存配文」,存好「✓ 已记下」
                    TextEditor(text: $caption)
                        .font(StopoverK.serif(16)).foregroundStyle(StopoverK.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(UIColor(hex: 0xF4F1EB)), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topLeading) {
                            if caption.isEmpty {
                                Text("给这张写段配文…").font(StopoverK.serif(16)).foregroundStyle(StopoverK.ink2.opacity(0.6))
                                    .padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
                            }
                        }
                    HStack {
                        Text(dirty ? "还没保存" : capState).font(.system(size: 12.5))
                            .foregroundStyle(dirty ? Color(UIColor(hex: 0x9a6a12)) : Color(UIColor(hex: 0x3F7A4F)))
                        Spacer()
                        if dirty {
                            Button {
                                capState = "保存中…"
                                let v = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                                Task { capState = await store.updatePhoto(photo.id, ["caption": v]) ? (v.isEmpty ? "配文清空了" : "✓ 已记下") : "没存上，再点一次保存" }
                            } label: {
                                Text("保存配文").font(.system(size: 13)).foregroundStyle(StopoverK.harbor)
                                    .padding(.horizontal, 14).frame(minHeight: 34)
                                    .background(Capsule().fill(StopoverK.harbor.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // 标签单选,再点一次取消
                    ChipFlow(spacing: 6) {
                        ForEach(store.photoTags, id: \.self) { tg in
                            let on = cur.tag == tg
                            Button {
                                Task {
                                    if await store.updatePhoto(photo.id, ["tag": on ? NSNull() : tg]) {
                                        store.toast = on ? "标签去掉了" : "标成「\(tg)」✓"
                                    }
                                }
                            } label: {
                                Text(tg).font(.system(size: 13)).foregroundStyle(on ? StopoverK.paper : StopoverK.harbor)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Capsule().fill(on ? StopoverK.harbor : StopoverK.harbor.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    sendBlock.padding(.top, 6)
                    let cs = store.comments("photo:\(photo.id)")
                    if !cs.isEmpty { CommentBlock(comments: cs, target: "photo:\(photo.id)", store: store) }
                    Button {
                        if !confirmOff {
                            withAnimation { confirmOff = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { confirmOff = false } }
                            return
                        }
                        Task { if await store.deletePhoto(photo.id) { dismiss() } }
                    } label: {
                        Text(confirmOff ? "再点一次确认（相册里那张还在）" : "取下这张")
                            .font(.system(size: 14)).foregroundStyle(Color(UIColor(hex: 0x9a2a22)))
                            .underline(true, color: Color(UIColor(hex: 0x9a2a22)).opacity(0.5))
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Text("×").font(StopoverK.latin(24, italic: false)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(StopoverK.ink.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain).padding(16)
        }
        .stopoverToast(store)
        .onAppear { caption = cur.caption; capState = cur.caption.isEmpty ? "" : "✓ 已记下" }
    }

    /// 只递这一张: 先把没存的配文存了,再附一句话递出;在路上的能撤回
    @ViewBuilder private var sendBlock: some View {
        let pend = store.shares.first { $0.status == "pending" && $0.who != "partner" && $0.items.count == 1
            && $0.items[0].type == "photo" && $0.items[0].id == photo.id }
        if let pend {
            HStack(alignment: .firstTextBaseline) {
                Text("这张在路上" + (pend.note.isEmpty ? "" : " · “\(pend.note)”")).font(StopoverK.serif(14)).foregroundStyle(StopoverK.ink)
                Spacer()
                Button("撤回") { Task { await store.unshare(pend.id) } }.font(.system(size: 13.5)).foregroundStyle(StopoverK.harbor)
            }
            .padding(14)
            .background(Color(UIColor(hex: 0xD8CBB2)).opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        } else if sendOpen {
            VStack(alignment: .leading, spacing: 10) {
                TextField("", text: $sendNote, prompt: Text("附一句话给\(StopoverStore.shared.config.partner)（选填）").foregroundStyle(StopoverK.ink2.opacity(0.7)))
                .foregroundStyle(StopoverK.ink).tint(StopoverK.harbor)
                    .font(StopoverK.serif(15)).padding(12)
                    .background(Color(UIColor(hex: 0xF4F1EB)), in: RoundedRectangle(cornerRadius: 10))
                Button {
                    Task {
                        let v = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                        if v != cur.caption { _ = await store.updatePhoto(photo.id, ["caption": v]) }
                        if await store.share([["type": "photo", "id": photo.id]], note: sendNote.trimmingCharacters(in: .whitespacesAndNewlines),
                                             done: "递出了，两分钟内会送到\(StopoverStore.shared.config.partner)那") { sendOpen = false; sendNote = "" }
                    }
                } label: { GateLabel(title: "递出这一张") }
                .buttonStyle(.plain)
                Button("先不递") { sendOpen = false }.font(.system(size: 14)).foregroundStyle(StopoverK.harbor)
            }
        } else {
            Button { sendOpen = true } label: { GateLabel(title: "只递这一张") }.buttonStyle(.plain)
        }
    }
}
