import SwiftUI

// 顺序: 版头大图(图渐隐进纸)→ 历史时间轴 → 文化(引言压顶)→ 景点轮播 → 美食展开列表 → 看完了递给\(StopoverStore.shared.config.partner) → 想去 → 出处。

struct StopoverProfile {
    struct Item: Identifiable {
        let id: Int
        let name: String
        let orig: String
        let intro: String
        let img: URL?
        let imgRatio: CGFloat
        let src: URL?
        var origShown: String? { orig.isEmpty || orig == name ? nil : orig }
    }
    let dek: String
    let history: [String]
    let culture: [String]
    let pull: String
    let sights: [Item]
    let foods: [Item]
    let hero: URL?
    let model: String

    init(_ j: [String: Any]) {
        func paras(_ k: String) -> [String] {
            ((j[k] as? String) ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        func items(_ k: String) -> [Item] {
            (j[k] as? [[String: Any]] ?? []).enumerated().map { i, d in
                let img = d["img"] as? [String: Any]
                let w = img?["w"] as? Double ?? 4, h = img?["h"] as? Double ?? 3
                return Item(id: i, name: d["name"] as? String ?? "", orig: d["orig"] as? String ?? "",
                            intro: d["intro"] as? String ?? "", img: (img?["u"] as? String).flatMap(URL.init(string:)),
                            imgRatio: CGFloat(w / max(1, h)), src: (d["src"] as? String).flatMap(URL.init(string:)))
            }
        }
        dek = j["dek"] as? String ?? ""
        history = paras("history")
        culture = paras("culture")
        pull = (j["pull"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
        sights = items("sights")
        foods = items("foods")
        hero = ((j["hero"] as? [[String: Any]])?.first?["u"] as? String).flatMap(URL.init(string:))
        model = ((j["credit"] as? [String: Any])?["model"] as? String ?? "").contains("pro") ? "v4-pro" : "flash"
    }

    static func era(_ p: String) -> (y: String, head: String, rest: String) {
        let pat = #"(公元前\s*\d{1,4}\s*年|前\s*\d{1,2}\s*世纪|\d{1,2}\s*世纪(初|末|中叶|后期|前期)?|\d{3,4}\s*年代|\d{3,4}\s*年)"#
        let y = p.range(of: pat, options: .regularExpression).map { p[$0].replacingOccurrences(of: " ", with: "") } ?? "—"
        var first = p
        if let r = p.rangeOfCharacter(from: CharacterSet(charactersIn: "。！？")) { first = String(p[..<r.upperBound]) }
        first = first.trimmingCharacters(in: .whitespaces)
        if first.count > 34 { return (y, String(first.prefix(32)) + "…", p) }
        let rest = String(p.dropFirst(first.count)).trimmingCharacters(in: .whitespaces)
        return (y, first, rest.isEmpty ? p : rest)
    }
}

struct StopoverCityCard: View {
    let city: StopoverCity
    @ObservedObject var store: StopoverStore
    var close: () -> Void
    @State private var profile: StopoverProfile?
    @State private var loaded = false
    @State private var openHistory: Set<Int> = [0]
    @State private var cultureMore = false
    @State private var sightIndex: Int? = 0
    @State private var openFood: Set<Int> = []
    @State private var sight: StopoverProfile.Item?

    private var visits: Int { store.visitCounts[city.id] ?? 0 }
    /// 现场整理完以后 store 里那份会变成有资料的,这里的 city 是点开时的快照
    private var hasProfile: Bool { store.cities[city.id]?.hasProfile ?? city.hasProfile }
    @State private var genPro = false
    @State private var openTrip: Int?
    /// 从往来跳来的: 不走撕票,直接进那一次
    @State private var directTrip = false
    @State private var directLeaf: String?
    @State private var ticketFrames: [Int: CGRect] = [:]
    @State private var pickingOrigin = false
    @State private var sharing: ShareWhat?

    struct ShareWhat: Identifiable {
        let name: String
        let item: [String: Any]
        var id: String { name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    // × 跟着版头一起滚走,不压后面的轮播
                    .overlay(alignment: .topTrailing) {
                        Button(action: close) {
                            Text("×").font(StopoverK.latin(24, italic: false)).foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(StopoverK.ink.opacity(0.55), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 22).padding(.trailing, 14)
                    }
                if let p = profile {
                    sections(p)
                } else if !hasProfile {
                    genSection
                    mine
                    if store.config.share { StopoverThreads(city: city.id, store: store) }
                } else {
                    section {
                        Text(loaded ? "这一页没翻开，一会儿再来看看。" : "正在翻开这一页……")
                            .font(StopoverK.serif(14.5)).foregroundStyle(StopoverK.ink2).lineSpacing(10)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).ignoresSafeArea())
        .task(id: "\(city.id)|\(hasProfile)") {
            loaded = false
            if hasProfile {
                profile = await store.profile(city.id).map(StopoverProfile.init)
                // 递来的景点 / 菜: 直接弹那张景点、展开那道菜
                if let f = store.cardFocus, f.city == city.id, let p = profile {
                    store.cardFocus = nil
                    try? await Task.sleep(for: .seconds(0.5))
                    if f.kind == "sight", f.i < p.sights.count { sight = p.sights[f.i] }
                    if f.kind == "food", f.i < p.foods.count { withAnimation { openFood.insert(f.i) } }
                }
            } else {
                await store.checkGen(city.id)
            }
            loaded = true
            // 资料拉完再盖全屏: 盖上去会取消这个 task,拉到一半长卷就空了
            if let f = store.tripFocus, store.checkins.first(where: { $0.id == f.trip })?.city == city.id {
                store.tripFocus = nil
                // 等抽屉出来再盖,不然被转场吞掉
                try? await Task.sleep(for: .seconds(0.4))
                directTrip = true; directLeaf = f.leaf
                openTrip = f.trip
            }
        }
        .fullScreenCover(item: Binding(get: { openTrip.map(TripID.init) }, set: { openTrip = $0?.id })) { t in
            if directTrip {
                TripPage(tripId: t.id, store: store, focusLeaf: directLeaf)
            } else if let trip = store.checkins.first(where: { $0.id == t.id }) {
                TearStage(trip: trip, seat: (store.trips(city.id).firstIndex { $0.id == t.id } ?? 0) + 1,
                          from: ticketFrames[t.id] ?? .zero, store: store)
                    .presentationBackground(.clear)
            }
        }
        .sheet(item: $sharing) { w in
            ShareThingSheet(name: w.name, item: w.item, store: store)
                .presentationDetents([.medium])
                .presentationBackground(StopoverK.paper)
        }
        .sheet(item: $sight) { s in
            SightSheet(item: s, store: store, city: city.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    // MARK: - 版头

    private var kicker: String {
        let lat = String(format: "%.2f°%@", abs(city.lat), city.lat >= 0 ? "N" : "S")
        let lng = String(format: "%.2f°%@", abs(city.lng), city.lng >= 0 ? "E" : "W")
        let came = visits > 1 ? "● 来过 \(visits) 次 · " : visits == 1 ? "● 来过 · " : ""
        return came + lat + " · " + lng
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker).font(StopoverK.mono(10, .medium)).tracking(1.6).foregroundStyle(StopoverK.ink2)
            Text(city.name).font(StopoverK.serif(city.name.count > 5 ? 44 : 56, .black))
                .foregroundStyle(StopoverK.ink).minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text([city.en == city.name ? nil : city.en, city.country.isEmpty ? nil : city.country].compactMap { $0 }.joined(separator: " · "))
                .font(StopoverK.latin(23)).foregroundStyle(StopoverK.ink2)
            if let d = profile?.dek, !d.isEmpty {
                Text(d).font(StopoverK.serif(17)).foregroundStyle(StopoverK.ink).lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
        }
        .padding(.horizontal, 22).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var header: some View {
        if let u = profile?.hero {
            // 图铺满、往下渐隐进纸色,城名压在渐隐那截上
            ZStack(alignment: .bottomLeading) {
                Color.clear.frame(height: 440).overlay { WikiImage(url: u) }.clipped()
                    // 3 往下拉过头时图从底边往上撑大(滚到顶带惯性回弹时看得到;抽屉手势在顶上会先接走下拉)
                    .visualEffect { c, g in
                        let pull = max(0, g.frame(in: .scrollView).minY)
                        return c.scaleEffect(1 + pull / 440, anchor: .bottom)
                    }
                LinearGradient(stops: [
                    .init(color: Color(red: 10 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.25), location: 0),
                    .init(color: .clear, location: 0.22), .init(color: .clear, location: 0.36),
                    .init(color: StopoverK.paper.opacity(0.62), location: 0.58),
                    .init(color: StopoverK.paper.opacity(0.9), location: 0.76), .init(color: StopoverK.paper, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                titleBlock
            }
        } else {
            titleBlock.padding(.top, 60)
        }
    }

    // MARK: - 各段

    @ViewBuilder
    private func sections(_ p: StopoverProfile) -> some View {
        if !p.history.isEmpty {
            section { sectionHead("历史", "History · 点开"); timeline(p.history) }
        }
        if !p.culture.isEmpty || !p.pull.isEmpty {
            section {
                sectionHead("文化", "Culture")
                if !p.pull.isEmpty {
                    Text("“\(p.pull)”").font(StopoverK.serif(21, .semibold)).foregroundStyle(StopoverK.harbor)
                        .lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                        .overlay(alignment: .top) { Rectangle().fill(StopoverK.harbor).frame(height: 3) }
                        .overlay(alignment: .bottom) { Rectangle().fill(StopoverK.harbor).frame(height: 1) }
                        .padding(.top, 6).padding(.bottom, 14)
                }
                ForEach(Array((cultureMore ? p.culture : Array(p.culture.prefix(1))).enumerated()), id: \.offset) { _, t in
                    para(t).padding(.bottom, 12)
                }
                if p.culture.count > 1 {
                    linkButton(cultureMore ? "收起" : "读下去 ›") { withAnimation(.easeInOut(duration: 0.25)) { cultureMore.toggle() } }
                }
            }
        }
        if !p.sights.isEmpty { sightsSection(p.sights) }
        if !p.foods.isEmpty {
            section {
                sectionHead("美食", "To eat · 点开")
                ForEach(p.foods) { f in foodRow(f) }
                if store.config.share { HStack(spacing: 10) {
                    Text("看完了？").font(StopoverK.latin(16)).foregroundStyle(StopoverK.ink2)
                    pill("把\(city.name)递给\(StopoverStore.shared.config.partner)", plane: true, style: .soft) {
                        sharing = ShareWhat(name: city.name, item: ["type": "city", "city": city.id])
                    }
                }
                .padding(.top, 18).padding(.bottom, 6) }
            }
        }
        section {
            sectionHead("想去", wishLine ?? "Not yet")
            wishButton
        }
        mine
        if store.config.share { StopoverThreads(city: city.id, store: store) }
        colophon(p)
    }

    private func section<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { c() }
            .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 4)
    }

    private func sectionHead(_ zh: String, _ en: String, count: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(zh).font(StopoverK.serif(15, .black)).tracking(4.5).foregroundStyle(StopoverK.ink)
            Text(en).font(StopoverK.latin(16)).foregroundStyle(StopoverK.ink2)
            Spacer(minLength: 0)
            if let count { Text(count).font(StopoverK.mono(12, .medium)).foregroundStyle(StopoverK.ink2) }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(StopoverK.ink).frame(height: 1) }
        .padding(.bottom, 14)
    }

    private func para(_ t: String) -> some View {
        Text(t).font(StopoverK.serif(15.5)).foregroundStyle(StopoverK.body)
            .lineSpacing(10).fixedSize(horizontal: false, vertical: true)
    }

    private func linkButton(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 14)).foregroundStyle(StopoverK.harbor).underline(true, color: StopoverK.harbor)
                .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: 我的经停(每来过一次一张登机牌)

    @ViewBuilder private var mine: some View {
        let ts = store.trips(city.id)
        section {
            sectionHead("我的经停", ts.isEmpty ? "Not yet" : "\(ts.count) 次")
            ForEach(Array(ts.enumerated()), id: \.element.id) { i, t in
                Button {
                    var tx = Transaction(); tx.disablesAnimations = true
                    directTrip = false
                    withTransaction(tx) { openTrip = t.id }
                } label: {
                    BoardingPass(trip: t, seat: i + 1, store: store)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ticketFrames[t.id] = $0 }
                        // 票飞上去的时候原位空着
                        .opacity(openTrip == t.id ? 0 : 1)
                }
                .buttonStyle(PressScale())
                    .padding(.bottom, 16)
            }
            // 记一次「来过」: 不要日期,只选从哪儿出发,红线从那儿连过来;来过几次点几次
            if ts.isEmpty {
                pill("来过\(city.name)", style: .solid) { pickingOrigin = true }
                Text("只是打个卡，不用写日期。点了选从哪儿出发，红线就从那儿连过来。来过几次就点几次。")
                    .font(StopoverK.serif(13)).foregroundStyle(StopoverK.ink2).lineSpacing(5).padding(.top, 8)
            } else {
                pill("＋ 又来了一次", style: .soft) { pickingOrigin = true }
            }
        }
        .sheet(isPresented: $pickingOrigin) {
            CityChips(question: "这一次从哪儿出发到\(city.name)？", choices: store.originChoices(for: city.id, current: nil),
                      current: nil, store: store, ghost: [("不连线", city.id)]) { id in
                await store.checkin(city.id, origin: id ?? city.id)
            }
            .presentationDetents([.medium])
            .presentationBackground(StopoverK.paper)
        }
    }

    // MARK: 现场整理(没资料的城)

    private static let genSteps = [("wiki", "翻维基"), ("write", "写正文"), ("images", "配图"), ("save", "存下来")]

    private var genSection: some View {
        let g = store.gens[city.id]
        return section {
            if g?.status == "running" {
                let cur = Self.genSteps.firstIndex { $0.0 == g?.stage } ?? 0
                sectionHead("资料", "整理中")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(Self.genSteps.enumerated()), id: \.offset) { j, st in
                        HStack(spacing: 8) {
                            if j < cur { Text("✓") } else if j == cur { ProgressView().controlSize(.mini).tint(StopoverK.ink) } else { Text("·") }
                            Text(st.1)
                        }
                        .font(StopoverK.serif(15, j == cur ? .semibold : .regular))
                        .foregroundStyle(j < cur ? Color(UIColor(hex: 0x3F7A4F)) : j == cur ? StopoverK.ink : Color(UIColor(hex: 0x8a93a0)))
                    }
                }
                .padding(.top, 6).padding(.bottom, 10)
                hint("大约一分钟。可以先关掉卡片去看别的，好了会告诉你。")
            } else {
                sectionHead("资料", "Not yet")
                Text("这座城还没有资料。").font(StopoverK.serif(14.5)).foregroundStyle(StopoverK.ink2)
                if g?.status == "error" {
                    Text(g?.msg.isEmpty == false ? g!.msg : "没整理成").font(StopoverK.serif(14.5, .bold))
                        .foregroundStyle(Color(UIColor(hex: 0x9a2a22))).padding(.top, 4)
                }
                Toggle(isOn: $genPro) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("认真写").font(StopoverK.serif(15, .semibold)).foregroundStyle(StopoverK.ink)
                        Text("用更好的模型，贵一点；不勾就是快写").font(.system(size: 12)).foregroundStyle(StopoverK.ink2)
                    }
                }
                .tint(StopoverK.harbor)
                .padding(.vertical, 12)
                pill("整理这座城的资料", style: .solid) { Task { await store.startGen(city.id, pro: genPro) } }
                hint("大约一分钟，整理好的会一直留着，以后点开就有。").padding(.top, 8)
            }
        }
    }

    private func hint(_ t: String) -> some View {
        Text(t).font(.system(size: 12.5)).foregroundStyle(StopoverK.ink2)
    }

    // MARK: 历史

    private func timeline(_ paras: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(paras.enumerated()), id: \.offset) { i, t in
                let e = StopoverProfile.era(t), open = openHistory.contains(i)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(e.y).font(StopoverK.mono(13, .medium)).foregroundStyle(StopoverK.harbor)
                            .frame(minWidth: 58, alignment: .leading)
                        Text(e.head).font(StopoverK.serif(16.5, .semibold)).foregroundStyle(StopoverK.ink)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text(open ? "−" : "+").font(.system(size: 18)).foregroundStyle(StopoverK.ink2)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { if open { openHistory.remove(i) } else { openHistory.insert(i) } } }
                    if open {
                        para(e.rest).padding(.bottom, 8).transition(.opacity)
                    }
                }
                .padding(.bottom, 10)
                .overlay(alignment: .topLeading) {
                    Circle().fill(open ? StopoverK.harbor : StopoverK.paper)
                        .overlay(Circle().stroke(StopoverK.harbor, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .offset(x: -23, y: 15)
                }
            }
        }
        .padding(.leading, 26)
        .background(alignment: .leading) {
            Rectangle().fill(StopoverK.harbor.opacity(0.35)).frame(width: 1).padding(.vertical, 8).padding(.leading, 8)
        }
    }

    // MARK: 景点轮播(居中吸附,两侧露出邻卡)

    private func sightsSection(_ S: [StopoverProfile.Item]) -> some View {
        let cur = sightIndex ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            sectionHead("景点", "To see · 左右滑", count: String(format: "%02d / %02d", cur + 1, S.count))
                .padding(.horizontal, 22)
            GeometryReader { g in
                let w = min(300, g.size.width * 0.78)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(S) { s in
                            Button { sight = s } label: { sightCard(s, width: w) }
                                .buttonStyle(.plain)
                                .id(s.id)
                                // 2 景深: 两边的卡缩到九成、压暗,滑到正中再放大变亮
                                .scrollTransition(.interactive, axis: .horizontal) { c, ph in
                                    c.scaleEffect(1 - 0.08 * abs(ph.value))
                                        .brightness(-0.12 * abs(ph.value))
                                }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 6).padding(.bottom, 10)
                }
                .contentMargins(.horizontal, (g.size.width - w) / 2, for: .scrollContent)
                .scrollClipDisabled()   // 不然卡片阴影被裁出一道方边
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $sightIndex)
                .overlay {
                    HStack {
                        if cur > 0 { arrow("‹") { step(-1, S.count) } }
                        Spacer()
                        if cur < S.count - 1 { arrow("›") { step(1, S.count) } }
                    }
                    .padding(.horizontal, 8)
                    .offset(y: -12)
                }
            }
            .frame(height: 420)
            HStack(spacing: 6) {
                ForEach(S) { s in
                    Capsule().fill(s.id == cur ? StopoverK.harbor : StopoverK.ink.opacity(0.2))
                        .frame(width: s.id == cur ? 22 : 8, height: 8)
                        .onTapGesture { withAnimation { sightIndex = s.id } }
                }
            }
            .frame(maxWidth: .infinity).padding(.top, 12)
            .animation(.easeInOut(duration: 0.3), value: cur)
        }
        .padding(.top, 24).padding(.bottom, 4)
    }

    private func step(_ d: Int, _ n: Int) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { sightIndex = min(n - 1, max(0, (sightIndex ?? 0) + d)) }
    }

    private func arrow(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 26)).foregroundStyle(StopoverK.ink)
                .frame(width: 44, height: 44)
                .background(StopoverK.paper.opacity(0.92), in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func sightCard(_ s: StopoverProfile.Item, width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let u = s.img {
                // 图放大 1.12 留出余量,跟着滑动反方向挪一点 = 视差
                Color.clear.overlay {
                    WikiImage(url: u).scaleEffect(1.12)
                        .scrollTransition(.interactive, axis: .horizontal) { c, ph in c.offset(x: -ph.value * width * 0.12) }
                }
                .clipped()
                LinearGradient(stops: [.init(color: .clear, location: 0.5),
                                       .init(color: Color(red: 10 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.85), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [StopoverK.sky, StopoverK.harbor], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(StopoverK.serif(23, .black)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let o = s.origShown { Text(o).font(StopoverK.latin(16)).foregroundStyle(.white.opacity(0.85)).lineLimit(1) }
                Text("点开看介绍 ›").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)).padding(.top, 6)
            }
            .padding(16)
        }
        .frame(width: width, height: 400)
        .background(StopoverK.clay)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        // 整张卡都能点
        .contentShape(RoundedRectangle(cornerRadius: 2))
        .shadow(color: StopoverK.ink.opacity(0.18), radius: 13, y: 10)
    }

    // MARK: 美食

    private func foodRow(_ f: StopoverProfile.Item) -> some View {
        let open = openFood.contains(f.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Group {
                    if let u = f.img { WikiImage(url: u) }
                    else {
                        StopoverK.clay.overlay {
                            Text(String((f.origShown ?? f.name).prefix(1))).font(StopoverK.latin(20)).foregroundStyle(StopoverK.ink2)
                        }
                    }
                }
                .frame(width: 52, height: 52).clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.name).font(StopoverK.serif(17, .black)).foregroundStyle(StopoverK.ink)
                    if let o = f.origShown { Text(o).font(StopoverK.latin(15)).foregroundStyle(StopoverK.ink2).lineLimit(1) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .light))
                    .foregroundStyle(StopoverK.ink2).rotationEffect(.degrees(open ? 180 : 0))
            }
            .frame(minHeight: 64).padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.3)) { if open { openFood.remove(f.id) } else { openFood.insert(f.id) } } }
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    if let u = f.img {
                        WikiImage(url: u).aspectRatio(f.imgRatio, contentMode: .fit).frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(f.name).font(StopoverK.serif(26, .black)).foregroundStyle(StopoverK.ink)
                        if let o = f.origShown { Text(o).font(StopoverK.latin(19)).foregroundStyle(StopoverK.ink2) }
                        Text(f.intro).font(StopoverK.serif(16)).foregroundStyle(StopoverK.ink).lineSpacing(9)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                        if store.config.share { pill("递给\(StopoverStore.shared.config.partner)", plane: true, style: .soft) {
                            sharing = ShareWhat(name: f.name, item: ["type": "food", "city": city.id, "i": f.id])
                        }
                        .padding(.top, 4) }
                    }
                    .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 20)
                }
                .background(StopoverK.dune)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(StopoverK.ink.opacity(0.14)).frame(height: 1) }
    }

    // MARK: 想去

    private var wishLine: String? {
        let ws = store.wishes.filter { $0.city == city.id }
        guard !ws.isEmpty else { return nil }
        let mine = ws.contains { $0.by != "partner" }, theirs = ws.contains { $0.by == "partner" }
        return mine && theirs ? "★ 你们都想去" : theirs ? "★ \(StopoverStore.shared.config.partner)想去" : "★ \(StopoverStore.shared.config.me)想去"
    }

    private var wishButton: some View {
        let mine = store.wishes.first { $0.city == city.id && $0.by != "partner" }
        let notes = store.wishes.filter { $0.city == city.id && !$0.note.isEmpty }.map { "\(store.config.name($0.by))：\($0.note)" }
        return VStack(alignment: .leading, spacing: 10) {
            if !notes.isEmpty {
                Text(notes.joined(separator: "　")).font(StopoverK.serif(14)).foregroundStyle(StopoverK.ink2).lineSpacing(8)
            }
            pill(mine != nil ? "不想去了" : visits > 0 ? "还想再去" : "想去", star: true, style: .star) {
                Task { await store.setWish(city.id, on: mine == nil) }
            }
        }
    }

    // MARK: 小件

    enum PillStyle { case soft, star, solid }

    private func pill(_ t: String, plane: Bool = false, star: Bool = false, style: PillStyle, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if plane { Image(systemName: "paperplane").font(.system(size: 14)) }
                if star { Text("★").font(.system(size: 16)).foregroundStyle(Color(UIColor(hex: 0xc08a1a))) }
                Text(t).font(.system(size: 14)).tracking(0.5)
            }
            .foregroundStyle(style == .soft ? StopoverK.harbor : style == .star ? StopoverK.gold : StopoverK.paper)
            .padding(.horizontal, 16).frame(minHeight: 42)
            .background(Capsule().fill(style == .soft ? StopoverK.harbor.opacity(0.12)
                                       : style == .star ? Color(UIColor(hex: 0xc08a1a)).opacity(0.14) : StopoverK.harbor))
        }
        .buttonStyle(.plain)
    }

    private func colophon(_ p: StopoverProfile) -> some View {
        Text("资料：维基百科 · Wikivoyage　整理：DeepSeek（\(p.model)）\n图片：Wikimedia Commons，点开景点可看原条目")
            .font(StopoverK.mono(10)).tracking(0.4).foregroundStyle(StopoverK.ink2).lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(StopoverK.ink).frame(height: 2) }
            .padding(.horizontal, 22).padding(.top, 28).padding(.bottom, 40)
    }
}

private struct TripID: Identifiable { let id: Int }

/// 票按下去微微一缩
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

/// 景点详情: 上面黑底整图(不裁),下面纸色正文 + 原条目 + 递给\(StopoverStore.shared.config.partner)
private struct SightSheet: View {
    let item: StopoverProfile.Item
    @ObservedObject var store: StopoverStore
    let city: String
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let u = item.img {
                    WikiImage(url: u, fit: true)
                        .aspectRatio(item.imgRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name).font(StopoverK.serif(26, .black)).foregroundStyle(StopoverK.ink)
                    if let o = item.origShown {
                        Text(o).font(StopoverK.latin(18)).foregroundStyle(StopoverK.ink2).padding(.top, 2)
                    }
                    Text(item.intro).font(StopoverK.serif(16)).foregroundStyle(StopoverK.ink).lineSpacing(9)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                    HStack {
                        if let src = item.src {
                            Link(destination: src) {
                                Text("维基原条目 ↗").font(.system(size: 15)).foregroundStyle(StopoverK.harbor)
                                    .underline(true, color: StopoverK.harbor)
                            }
                        }
                        Spacer()
                        if StopoverStore.shared.config.share { Button { sharing = true } label: {
                            HStack(spacing: 7) { Image(systemName: "paperplane"); Text("递给\(StopoverStore.shared.config.partner)") }
                                .font(.system(size: 15)).foregroundStyle(StopoverK.paper)
                                .padding(.horizontal, 20).frame(minHeight: 46)
                                .background(Capsule().fill(StopoverK.harbor))
                                .shadow(color: StopoverK.harbor.opacity(0.28), radius: 7, y: 4)
                        }
                        .buttonStyle(.plain) }
                    }
                    .padding(.top, 22)
                }
                .padding(22)
            }
        }
        .background(Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Text("×").font(StopoverK.latin(24, italic: false)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(StopoverK.ink.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain).padding(16)
        }
        .sheet(isPresented: $sharing) {
            ShareThingSheet(name: item.name, item: ["type": "sight", "city": city, "i": item.id], store: store)
                .presentationDetents([.medium])
                .presentationBackground(StopoverK.paper)
        }
        .stopoverToast(store)
    }
}

