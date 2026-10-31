import SwiftUI

// 经停 · 搜索。
// 有字时搜城市和国家(中英文,不分大小写和变音符号);最下面「找不到？在地图上加上「X」」去维基数据找。
// 两种用法: 主页上点结果 = 打开那座城;选出发地 / 终点时点结果 = 把它填进去

struct StopoverSearch: View {
    @ObservedObject var store: StopoverStore
    /// 选出发地 / 终点时的提示(「选出发地 · 去威尼斯」);nil = 主页搜索
    var pickHint: String? = nil
    let pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var q = ""
    @State private var tab = 0          // 0 按国家找 · 1 去过的 · 2 想去的
    @State private var country: String?
    @State private var places: (q: String, items: [StopoverStore.Place]?)?
    @State private var placesLoading = false
    @State private var adding: String?
    @FocusState private var focused: Bool

    private var all: [StopoverCity] { Array(store.cities.values) }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if q.isEmpty && country == nil { tabs }
            if let h = pickHint {
                Text(h).font(StopoverK.mono(11, .medium)).tracking(1).foregroundStyle(StopoverK.harbor)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 8)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) { results }
                    .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).ignoresSafeArea())
        .onAppear { focused = true }
    }

    private var bar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(StopoverK.ink2)
            TextField(pickHint == nil ? "搜城市或国家，中文英文都行" : "搜出发地，比如 上海", text: $q)
                .font(StopoverK.serif(16)).foregroundStyle(StopoverK.ink)
                .focused($focused).submitLabel(.search)
                .onSubmit { if let first = cityHits.first { choose(first.id) } }
                .onChange(of: q) { _, _ in country = nil }
            Button { dismiss() } label: {
                Text("×").font(.system(size: 22)).foregroundStyle(StopoverK.ink2).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(UIColor(hex: 0xF4F1EB)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16).padding(.top, 18)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Array(["按国家找", "去过的", "想去的"].enumerated()), id: \.offset) { i, t in
                Button { tab = i } label: {
                    Text(t).font(StopoverK.serif(14, tab == i ? .semibold : .regular))
                        .foregroundStyle(tab == i ? StopoverK.ink : StopoverK.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Rectangle().fill(tab == i ? StopoverK.harbor : .clear).frame(height: 2) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    // MARK: - 结果

    @ViewBuilder private var results: some View {
        if !q.trimmingCharacters(in: .whitespaces).isEmpty {
            queryResults
        } else if let c = country {
            let list = all.filter { $0.country == c }
                .sorted { ($0.hasProfile ? 0 : 1, $0.name) < ($1.hasProfile ? 0 : 1, $1.name) }
            Button { country = nil } label: {
                Text("‹ 所有国家").font(.system(size: 14)).foregroundStyle(StopoverK.harbor).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            group("\(store.countryName(c)) · \(list.count) 座")
            ForEach(list) { cityRow($0) }
        } else if tab == 1 {
            been
        } else if tab == 2 {
            wishes
        } else {
            countries
        }
    }

    private var fq: String { StopoverStore.fold(q.trimmingCharacters(in: .whitespaces)) }

    private var cityHits: [StopoverCity] {
        let raw = q.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return [] }
        let f = fq
        func starts(_ c: StopoverCity) -> Bool { c.name.hasPrefix(raw) || StopoverStore.fold(c.en).hasPrefix(f) }
        return all.filter { $0.name.contains(raw) || StopoverStore.fold($0.en).contains(f) }
            .sorted { ($0.hasProfile ? 0 : 1, starts($0) ? 0 : 1, $0.name) < ($1.hasProfile ? 0 : 1, starts($1) ? 0 : 1, $1.name) }
    }

    @ViewBuilder private var queryResults: some View {
        let raw = q.trimmingCharacters(in: .whitespaces)
        let countryHits = Set(all.map(\.country)).filter { !$0.isEmpty && (store.countryName($0).contains(raw) || StopoverStore.fold($0).contains(fq)) }.sorted()
        let cities = cityHits
        if !countryHits.isEmpty {
            group("国家")
            ForEach(countryHits.prefix(6), id: \.self) { n in
                row(store.countryName(n), sub: n, badge: "\(all.filter { $0.country == n }.count) 座 ›") { country = n; q = "" }
            }
        }
        if !cities.isEmpty {
            group("城市")
            ForEach(cities.prefix(40)) { cityRow($0) }
        }
        if countryHits.isEmpty && cities.isEmpty {
            Text("没找到「\(raw)」。可以试试英文名，或者换个写法。").font(StopoverK.serif(14)).foregroundStyle(StopoverK.ink2).padding(.vertical, 14)
        }
        placeBlock(raw)
    }

    @ViewBuilder private func placeBlock(_ raw: String) -> some View {
        if let p = places, p.q == raw {
            if let items = p.items {
                if items.isEmpty {
                    hint("维基数据里也没找到「\(raw)」。换个写法试试，比如加上「县」「镇」，或者用英文名。")
                } else {
                    group("在地图上加上哪一个？")
                    ForEach(items) { it in
                        if let ex = it.exists {
                            row(it.name, sub: "地图上已经有了：\(it.existsName ?? "就在附近")", badge: nil) { choose(ex) }
                        } else {
                            row(it.name, sub: [it.desc, store.countryName(it.country)].filter { !$0.isEmpty }.joined(separator: " · "),
                                badge: adding == it.qid ? "加着…" : "加上") {
                                guard adding == nil else { return }
                                adding = it.qid
                                Task {
                                    if let id = await store.addPlace(it.qid) { choose(id) }
                                    adding = nil
                                }
                            }
                        }
                    }
                }
            } else {
                hint("维基数据没连上，过一会儿再试")
            }
        } else if placesLoading {
            hint("正在维基数据里找「\(raw)」…")
        } else {
            row("找不到？在地图上加上「\(raw)」", sub: "去维基数据里找这个地方", badge: nil, accent: true) {
                placesLoading = true
                Task {
                    let items = await store.placeSearch(raw)
                    places = (raw, items)
                    placesLoading = false
                }
            }
        }
    }

    private var countries: some View {
        var cnt: [String: (n: Int, h: Int)] = [:]
        for c in all where !c.country.isEmpty {
            cnt[c.country, default: (0, 0)].n += 1
            if c.hasProfile { cnt[c.country, default: (0, 0)].h += 1 }
        }
        let ns = cnt.keys.sorted { (cnt[$0]!.h, cnt[$0]!.n) > (cnt[$1]!.h, cnt[$1]!.n) }
        return VStack(alignment: .leading, spacing: 0) {
            group("按国家找 · \(ns.count) 个国家")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(ns, id: \.self) { n in
                    Button { country = n } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.countryName(n)).font(StopoverK.serif(15, .semibold)).foregroundStyle(StopoverK.ink).lineLimit(1)
                            Text(cnt[n]!.h > 0 ? "\(cnt[n]!.h) 座有资料" : "\(cnt[n]!.n) 座").font(.system(size: 11)).foregroundStyle(StopoverK.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color(UIColor(hex: 0xF4F1EB)), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var been: some View {
        let cnt = store.visitCounts.filter { store.cities[$0.key] != nil }
        if cnt.isEmpty {
            hint("还没打过卡。点开一座城，在「我的经停」里点「来过」。")
        } else {
            let groups = Dictionary(grouping: cnt.keys) { store.cities[$0]?.country ?? "" }
            let gs = groups.keys.sorted { groups[$0]!.count > groups[$1]!.count }
            group("来过 \(cnt.count) 座城 · \(store.checkins.count) 次")
            ForEach(gs, id: \.self) { n in
                HStack(spacing: 6) {
                    Text(store.countryName(n)).font(StopoverK.serif(14, .semibold)).foregroundStyle(StopoverK.ink)
                    Text("\(groups[n]!.count)").font(StopoverK.mono(11)).foregroundStyle(StopoverK.ink2)
                }
                .padding(.top, 14).padding(.bottom, 8)
                ChipFlow(spacing: 6) {
                    ForEach(groups[n]!.sorted(), id: \.self) { id in
                        Button { choose(id) } label: {
                            HStack(spacing: 4) {
                                Text(store.cities[id]?.name ?? id).font(StopoverK.serif(14))
                                if cnt[id]! > 1 { Text("\(cnt[id]!) 次").font(.system(size: 10)).foregroundStyle(StopoverK.sky) }
                            }
                            .foregroundStyle(StopoverK.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Color(UIColor(hex: 0xF4F1EB))))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var wishes: some View {
        var by: [String: [String: String]] = [:]
        let _ = store.wishes.forEach { w in if store.cities[w.city] != nil { by[w.city, default: [:]][w.by == "partner" ? "partner" : "me"] = w.note } }
        if by.isEmpty {
            hint("还没有星星。点开一座城，在「想去」里点亮。")
        } else {
            let grp: [(String, ([String: String]) -> Bool)] = [("你们都想去", { $0.count == 2 }),
                                                               ("\(StopoverStore.shared.config.me)想去", { $0.keys.sorted() == ["me"] }),
                                                               ("\(StopoverStore.shared.config.partner)想去", { $0.keys.sorted() == ["partner"] })]
            ForEach(grp, id: \.0) { g in
                let ids = by.keys.filter { g.1(by[$0]!) }.sorted()
                if !ids.isEmpty {
                    HStack(spacing: 6) {
                        Text(g.0).font(StopoverK.serif(14, .semibold)).foregroundStyle(StopoverK.ink)
                        Text("\(ids.count)").font(StopoverK.mono(11)).foregroundStyle(StopoverK.ink2)
                    }
                    .padding(.top, 14).padding(.bottom, 4)
                    ForEach(ids, id: \.self) { id in
                        row(store.cities[id]?.name ?? id, sub: by[id]!.values.filter { !$0.isEmpty }.joined(separator: " / "), badge: nil) { choose(id) }
                    }
                }
            }
        }
    }

    // MARK: - 小件

    private func choose(_ id: String) {
        dismiss()
        pick(id)
    }

    private func group(_ t: String) -> some View {
        Text(t).font(StopoverK.mono(11, .medium)).tracking(1).foregroundStyle(StopoverK.ink2)
            .padding(.top, 16).padding(.bottom, 6)
    }

    private func hint(_ t: String) -> some View {
        Text(t).font(StopoverK.serif(14)).foregroundStyle(StopoverK.ink2).lineSpacing(5).padding(.vertical, 14)
    }

    private func cityRow(_ c: StopoverCity) -> some View {
        row(c.name, sub: c.en == c.name ? "" : c.en, badge: c.hasProfile ? "有资料" : nil) { choose(c.id) }
    }

    private func row(_ title: String, sub: String, badge: String?, accent: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if accent {
                    // 「找不到？在地图上加上…」: 标题和说明上下两行,不挤一行
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(StopoverK.serif(16, .semibold)).foregroundStyle(StopoverK.harbor)
                        Text(sub).font(.system(size: 12.5)).foregroundStyle(StopoverK.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(title).font(StopoverK.serif(16)).foregroundStyle(StopoverK.ink)
                        if !sub.isEmpty { Text(sub).font(sub.contains(where: { $0 > "\u{2E80}" }) ? .system(size: 12.5) : StopoverK.latin(15))
                            .foregroundStyle(StopoverK.ink2).lineLimit(1) }
                        Spacer(minLength: 0)
                        if let badge { Text(badge).font(.system(size: 11)).foregroundStyle(StopoverK.sky) }
                    }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(StopoverK.ink.opacity(0.08)).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 往来 (all / mine / partner's)

/// Everything handed over: a city / sight / dish / ticket / photo / note · time · note · unread dot on the partner's.
/// 点一条 = 标已读 + 打开那座城(景点就弹那张景点,菜就展开那道菜)
struct StopoverInbox: View {
    @ObservedObject var store: StopoverStore
    let open: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var names: [Int: String] = [:]
    @State private var who = ""   // "" all / "me" / "partner"
    private var list: [StopoverShare] { who.isEmpty ? store.allShares : store.allShares.filter { $0.who == who } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("往来").font(StopoverK.serif(18, .semibold)).foregroundStyle(StopoverK.ink)
                Spacer()
                HStack(spacing: 14) {
                    filter("", "全部")
                    filter("me", "\(store.config.me)递的")
                    filter("partner", "\(store.config.partner)递的")
                }
                .padding(.trailing, 14)
                Button { dismiss() } label: { Text("×").font(.system(size: 22)).foregroundStyle(StopoverK.ink2) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if list.isEmpty {
                        Text(who == "partner" ? "\(store.config.partner)还没递过东西。" : "还没有往来。").font(StopoverK.serif(14)).foregroundStyle(StopoverK.ink2).padding(.vertical, 20)
                    }
                    ForEach(list) { x in row(x) }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .background(Image(uiImage: StopoverK.paperTile).resizable(resizingMode: .tile).ignoresSafeArea())
        .onAppear { if store.unreadFromPartner > 0 { who = "partner" } }
        .task {
            for x in store.allShares { if let it = x.items.first { names[x.id] = await store.itemName(it) } }
        }
    }

    private func filter(_ w: String, _ label: String) -> some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { who = w } } label: {
            VStack(spacing: 3) {
                Text(label).font(StopoverK.serif(14, who == w ? .semibold : .regular))
                    .foregroundStyle(who == w ? StopoverK.ink : StopoverK.ink2)
                Capsule().fill(who == w ? StopoverK.ink : .clear).frame(width: 14, height: 2)
            }
            .overlay(alignment: .topTrailing) {
                if w == "partner", store.unreadFromPartner > 0 {
                    Circle().fill(Color(UIColor(hex: 0xd8262f))).frame(width: 6, height: 6).offset(x: 6, y: -2)
                }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ x: StopoverShare) -> some View {
        let it = x.items.first
        let kinds = ["city": "一座城", "sight": "一个景点", "food": "一道菜", "trip": "一张票", "photo": "一张照片", "note": "一段话"]
        let kind = x.id < 0 ? "想和你去" : (x.items.count > 1 ? "\(x.items.count) 样 · " : "") + (kinds[it?.type ?? ""] ?? "一样东西")
        let mine = x.who == "me"
        return Button {
            guard let it, let c = it.city else { return }
            if !mine, x.id > 0 { Task { await store.markRead(x.id) } }
            if it.type == "sight" || it.type == "food", let i = it.i { store.cardFocus = (c, it.type, i) }
            dismiss()
            open(c)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(mine ? store.config.me : store.config.partner)递的 · \(kind) · \(TripPage.ago(x.created))").font(StopoverK.mono(10, .medium)).tracking(1.2)
                        .foregroundStyle(StopoverK.sky)
                    Text(names[x.id].flatMap { $0.isEmpty ? nil : $0 } ?? store.cities[it?.city ?? ""]?.name ?? kind).font(StopoverK.serif(17, .semibold))
                        .foregroundStyle(StopoverK.ink)
                    if !x.note.isEmpty {
                        Text("“\(x.note)”").font(StopoverK.serif(14)).foregroundStyle(StopoverK.ink2)
                    }
                }
                Spacer()
                if !mine, x.readAt == nil { Circle().fill(Color(UIColor(hex: 0xd8262f))).frame(width: 8, height: 8).padding(.top, 6) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor(hex: 0xF4F1EB)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
