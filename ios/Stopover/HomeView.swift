import SwiftUI
import simd

// The globe page: three map styles, pins and arcs, stars, legend, search, dice; tapping a city opens its card.

/// Five colours + three typefaces (the card doesn't follow the globe style)
enum StopoverK {
    static let paper = Color(UIColor(hex: 0xE6E2DA))
    static let harbor = Color(UIColor(hex: 0x3F5F86))
    static let sky = Color(UIColor(hex: 0x6F9FC8))
    static let dune = Color(UIColor(hex: 0xD8CBB2))
    static let clay = Color(UIColor(hex: 0xCFC9C3))
    static let ink = Color(UIColor(hex: 0x1F2A38))
    static let ink2 = Color(UIColor(hex: 0x4F5D6E))
    static let body = Color(UIColor(hex: 0x26323F))
    static let red = Color(UIColor(hex: 0xd8262f))
    static let gold = Color(UIColor(hex: 0x7d5a10))

    /// Chinese serif: the system's on-demand Songti SC (see `Songti`); falls back to the system font until it arrives
    static func serif(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        let names: [String]
        switch w {
        case .heavy, .black: names = ["STSongti-SC-Black", "STSongti-SC-Bold"]
        case .semibold, .bold: names = ["STSongti-SC-Bold"]
        default: names = ["STSongti-SC-Regular"]
        }
        for n in names { if let f = UIFont(name: n, size: size) { return Font(f) } }
        return .system(size: size, weight: w, design: .serif)
    }
    /// Latin italic: Instrument Serif (bundled, OFL)
    static func latin(_ size: CGFloat, italic: Bool = true) -> Font {
        .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: size)
    }
    /// Ticket monospace: IBM Plex Mono (bundled, OFL)
    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .custom(w == .semibold || w == .bold ? "IBMPlexMono-SemiBold" : w == .medium ? "IBMPlexMono-Medium" : "IBMPlexMono", size: size)
    }

    /// Card paper: linen + two offset layers of fine dots
    static let paperTile: UIImage = {
        let n: CGFloat = 35
        return UIGraphicsImageRenderer(size: CGSize(width: n, height: n)).image { ctx in
            UIColor(hex: 0xE6E2DA).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
            UIColor(hex: 0x3F5F86).withAlphaComponent(0.07).setFill()
            for x in stride(from: 0, to: n, by: 5) { for y in stride(from: 0, to: n, by: 5) {
                ctx.cgContext.fillEllipse(in: CGRect(x: x + 2, y: y + 2, width: 1.1, height: 1.1)) } }
            UIColor(hex: 0x4F5D6E).withAlphaComponent(0.06).setFill()
            for x in stride(from: 0, to: n, by: 7) { for y in stride(from: 0, to: n, by: 7) {
                ctx.cgContext.fillEllipse(in: CGRect(x: x + 5.5, y: y + 0.5, width: 1.1, height: 1.1)) } }
        }
    }()
}

struct HomeView: View {
    @StateObject private var store = StopoverStore.shared
    @State private var settings = !UserDefaults.standard.bool(forKey: "serverSet")
    @State private var songti = Songti.installed
    @AppStorage("stopover.style") private var styleRaw = StopoverStyle.marble.rawValue
    @State private var selected: StopoverCity?
    @State private var searching = false
    @State private var inbox = false
    @State private var diceMenu = false
    @State private var kick = 0
    @State private var ticker: StopoverCity?

    private var style: StopoverStyle { StopoverStyle(rawValue: styleRaw) ?? .marble }
    private var fg: Color { style.isDark ? Color(UIColor(hex: 0xe8edf5)) : StopoverK.ink }

    var body: some View {
        ZStack {
            StopoverGlobe(style: style, marks: marks, places: places,
                          focus: selected.map { SIMD2($0.lat, $0.lng) }, kick: kick,
                          covered: searching || inbox,
                          onTap: pick)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                if selected == nil {
                    HStack(alignment: .bottom) {
                        legend
                        dice
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .overlay {
            // While the dice roll, city names flash past and stop on the one rolled
            if let t = ticker {
                VStack(spacing: 4) {
                    Text(t.name).font(StopoverK.serif(34, .black)).foregroundStyle(fg)
                    Text(t.en).font(StopoverK.latin(18)).foregroundStyle(fg.opacity(0.75))
                }
                // No backing box: the name floats on the globe, a soft shadow keeps it readable
                .shadow(color: (style.isDark ? Color.black : StopoverK.paper).opacity(0.9), radius: 6)
                .shadow(color: (style.isDark ? Color.black : StopoverK.paper).opacity(0.6), radius: 14)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .sheet(isPresented: $inbox) {
            StopoverInbox(store: store) { id in
                if let c = store.cities[id] {
                    selected = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { selected = c }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $searching) {
            StopoverSearch(store: store) { id in
                if let c = store.cities[id] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { selected = c }
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $settings) {
            ServerSettings { Task { await store.load() } }
                .presentationDetents([.medium])
                .preferredColorScheme(.light)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopoverOpenCity)) { n in
            // Tapped a push: fly to that city once the store has it
            if let id = n.object as? String, let c = store.cities[id] {
                selected = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { selected = c }
            }
        }
        .stopoverToast(store)
        .id(songti)   // re-render once Songti has downloaded
        .preferredColorScheme(style.isDark ? .dark : .light)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: selected)
        .task {
            Songti.request { songti = true }
            await store.load()
        }
        // City card: a real drawer — at half height the globe still turns and other cities are tappable
        .sheet(item: $selected) { c in
            StopoverCityCard(city: c, store: store, close: { selected = nil })
                .presentationDetents([.fraction(0.55), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.55)))
                .presentationCornerRadius(26)
                .presentationBackground(StopoverK.paper)
                .preferredColorScheme(.light)
        }
    }

    // MARK: -

    /// Cities to label when zoomed in: all of them, visited first, then those with a page (the globe picks by zoom and spacing)
    private var places: [GlobeController.Place] {
        let v = store.visitCounts
        return store.cities.values.map {
            GlobeController.Place(id: $0.id, name: $0.name, lat: $0.lat, lng: $0.lng,
                                  rank: v[$0.id] != nil ? 0 : $0.hasProfile ? 1 : 2)
        }
    }

    private var marks: StopoverMarks {
        var m = StopoverMarks()
        let counts = store.visitCounts
        m.pins = counts.keys.sorted().compactMap { id in
            guard let c = store.cities[id] else { return nil }
            return .init(id: id, name: c.name, lat: c.lat, lng: c.lng, count: counts[id] ?? 1)
        }
        for k in store.checkins {
            guard let to = store.cities[k.city] else { continue }
            if let o = k.origin, o != k.city, let from = store.cities[o] {
                m.arcs.append(.init(from: SIMD2(from.lat, from.lng), to: SIMD2(to.lat, to.lng)))
            }
            if let d = k.dest, d != k.city, let end = store.cities[d] {
                m.arcs.append(.init(from: SIMD2(to.lat, to.lng), to: SIMD2(end.lat, end.lng)))
            }
        }
        var byCity: [String: (Bool, Bool)] = [:]
        for w in store.wishes {
            var v = byCity[w.city] ?? (false, false)
            if w.by == "partner" { v.1 = true } else { v.0 = true }
            byCity[w.city] = v
        }
        m.stars = byCity.keys.sorted().compactMap { id in
            guard let c = store.cities[id], let v = byCity[id] else { return nil }
            return .init(lat: c.lat, lng: c.lng, hers: v.0, his: v.1)
        }
        return m
    }

    /// Tap on the ground: nearest city; too far (scaled by zoom) counts as tapping nothing
    private func pick(lat: Double, lng: Double, distance: Double) {
        let limit = max(0.5, 1.8 * (distance - 1))
        let visited = store.visitCounts
        let p = GlobeMath.unit(lat, lng)
        var best: (StopoverCity, Double)?
        for c in store.cities.values {
            var d = acos(max(-1, min(1, simd_dot(p, GlobeMath.unit(c.lat, c.lng))))) * 180 / .pi
            // Visited / has-a-page cities win ties
            if visited[c.id] != nil { d *= 0.6 } else if !c.hasProfile { d *= 1.3 }
            if d < limit, d < (best?.1 ?? .infinity) { best = (c, d) }
        }
        guard let c = best?.0 else { selected = nil; return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selected = c
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(StopoverStyle.allCases, id: \.self) { s in
                    Button { styleRaw = s.rawValue } label: {
                        Text(s.title)
                            .font(StopoverK.serif(13, .semibold))
                            .foregroundStyle(s == style ? (style.isDark ? Color.black : StopoverK.paper) : fg.opacity(0.75))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(s == style ? (style.isDark ? fg : StopoverK.harbor) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            // From the partner: unread count on the badge (hidden when features.share is off)
            if store.config.share {
                Button { inbox = true } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(fg)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if store.unreadFromPartner > 0 {
                                Text("\(store.unreadFromPartner)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    .frame(minWidth: 16, minHeight: 16).background(Circle().fill(Color(UIColor(hex: 0xd8262f))))
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Button { searching = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(fg)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            Button { settings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(fg)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .overlay(alignment: .bottom) {
            if let f = store.failure {
                Text(f).font(StopoverK.serif(13)).foregroundStyle(fg)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(y: 44)
            }
        }
    }

    private var legend: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                legendRow(Circle().fill(Color(style.pin)).frame(width: 8, height: 8), "来过 · \(store.visitCounts.count) 座城")
                legendRow(Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color(style.star)), "\(store.config.me)想去")
                legendRow(Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color(style.star2)), "\(store.config.partner)想去")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
        }
    }

    // MARK: - Dice (bottom right; a random city: all / not yet visited / our stars)

    private var dice: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if diceMenu {
                VStack(alignment: .leading, spacing: 0) {
                    Text("从哪里骰？").font(StopoverK.serif(13, .semibold)).foregroundStyle(fg.opacity(0.8))
                        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                    ForEach([("all", "所有城市"), ("new", "没去过的"), ("star", "我们的星星")], id: \.0) { k, t in
                        Button { roll(k) } label: {
                            Text(t).font(StopoverK.serif(15)).foregroundStyle(fg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 140)
                .padding(.bottom, 4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
            }
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { diceMenu.toggle() } } label: {
                Image(systemName: "die.face.5")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(fg)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
                    .rotationEffect(.degrees(diceMenu ? 20 : 0))
            }
            .buttonStyle(.plain)
        }
    }

    /// The globe swings away, names flash past, it settles on one, flies there and opens the card
    private func roll(_ scope: String) {
        let visited = Set(store.checkins.map(\.city))
        var pool: [String]
        switch scope {
        case "star": pool = Array(Set(store.wishes.map(\.city)))
        case "new": pool = store.cities.values.filter { $0.hasProfile && !visited.contains($0.id) }.map(\.id)
        default: pool = store.cities.values.filter(\.hasProfile).map(\.id)
        }
        pool = pool.filter { store.cities[$0] != nil && $0 != selected?.id }
        withAnimation { diceMenu = false }
        guard let hit = pool.randomElement(), let c = store.cities[hit] else {
            store.toast = "这个范围里没有可以骰的城市"
            return
        }
        selected = nil
        kick += 1
        let tick = UISelectionFeedbackGenerator()
        for i in 0...16 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) {
                let x = i == 16 ? c : (pool.randomElement().flatMap { store.cities[$0] } ?? c)
                withAnimation(.easeOut(duration: 0.08)) { ticker = x }
                tick.selectionChanged()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation { ticker = nil }
            selected = c
        }
    }

    private func legendRow(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 8) {
            mark.frame(width: 12)
            Text(text).font(StopoverK.serif(12)).foregroundStyle(fg.opacity(0.85))
        }
    }

}

enum GlobeMath {
    static func unit(_ lat: Double, _ lng: Double) -> SIMD3<Double> {
        let la = lat * .pi / 180, lo = lng * .pi / 180
        return SIMD3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))
    }
}
