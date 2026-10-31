import SwiftUI

// MARK: - 长卷底部「我们的对话」
// 每一次递送单独一组: 组头 + 附言 + 挂在 share:<id> 下的来回;
// 不属于哪次递送的(城市 / 某一次 / 照片 / 随记下)归「平时说的」一组。最新的一组在最上面,一组都没有整块不画。
// 每组底下一个输入框: 递送组发 share:<id>,平时组发 city:<id>;点了某条「回复」就沿用那条的 target + reply_to。

struct StopoverThreads: View {
    let city: String
    @ObservedObject var store: StopoverStore
    @State private var names: [Int: String] = [:]

    private struct Group: Identifiable {
        let key: String              // share:N / city:ID
        let share: StopoverShare?
        let msgs: [StopoverComment]
        let last: Double
        var id: String { key }
    }

    private func cityOf(_ it: StopoverShare.Item) -> String? {
        if let c = it.city { return c }
        switch it.type {
        case "trip": return store.checkins.first { $0.id == it.id }?.city
        case "photo": return store.photos.first { $0.id == it.id }.flatMap { p in store.checkins.first { $0.id == p.tripId }?.city }
        case "note": return store.notes.first { $0.id == it.id }.flatMap { n in store.checkins.first { $0.id == n.tripId }?.city }
        default: return nil
        }
    }

    private func cityOf(target t: String) -> String? {
        let p = t.split(separator: ":", maxSplits: 1).map(String.init)
        guard p.count == 2 else { return nil }
        if p[0] == "city" { return p[1] }
        return cityOf(.init(type: p[0], id: Int(p[1]), city: nil, i: nil))
    }

    /// 平时组里挂在某一次/照片/随记下的,名字后面加小字
    private func whereOf(_ t: String) -> String? {
        let p = t.split(separator: ":", maxSplits: 1).map(String.init)
        guard p.count == 2, p[0] != "city", let v = Int(p[1]) else { return nil }
        let tid = p[0] == "trip" ? v : p[0] == "photo" ? store.photos.first { $0.id == v }?.tripId : store.notes.first { $0.id == v }?.tripId
        let n = (store.trips(city).firstIndex { $0.id == tid } ?? 0) + 1
        return "在第 \(n) 次\(p[0] == "photo" ? "的照片" : p[0] == "note" ? "的随记" : "")下"
    }

    private var groups: [Group] {
        var out: [Group] = []
        for x in store.shares where x.items.contains(where: { cityOf($0) == city }) {
            let msgs = store.comments("share:\(x.id)").sorted { $0.created < $1.created }
            out.append(Group(key: "share:\(x.id)", share: x, msgs: msgs, last: max(x.created, msgs.map(\.created).max() ?? 0)))
        }
        let loose = store.comments.filter { !$0.target.hasPrefix("share:") && cityOf(target: $0.target) == city }
            .sorted { $0.created < $1.created }
        if !loose.isEmpty { out.append(Group(key: "city:\(city)", share: nil, msgs: loose, last: loose.map(\.created).max() ?? 0)) }
        return out.sorted { $0.last > $1.last }
    }

    var body: some View {
        let gs = groups
        if !gs.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("我们的对话").font(StopoverK.serif(15, .black)).tracking(4.5).foregroundStyle(StopoverK.ink)
                    Text("\(gs.count) 组").font(StopoverK.latin(16)).foregroundStyle(StopoverK.ink2)
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                .overlay(alignment: .top) { Rectangle().fill(StopoverK.ink).frame(height: 1) }
                ForEach(gs) { g in
                    ThreadGroup(key: g.key, share: g.share, msgs: g.msgs, headWhat: g.share.map { what($0) } ?? "",
                                whereOf: { g.share == nil ? whereOf($0.target) : nil }, store: store, city: city)
                }
            }
            .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 4)
            .task(id: gs.count) {
                for g in gs { if let s = g.share, names[s.id] == nil { names[s.id] = await itemLabel(s) } }
            }
        }
    }

    /// 组头「递了什么」: 整张票 / 这座城 / 景点「X」/ 1 段随记 + 2 张照片
    private func what(_ s: StopoverShare) -> String {
        let its = s.items.filter { cityOf($0) == city }
        if its.contains(where: { $0.type == "trip" }) { return "整张票" }
        if its.contains(where: { $0.type == "city" }) { return "这座城" }
        if its.contains(where: { $0.type == "sight" || $0.type == "food" }) { return names[s.id] ?? (its[0].type == "sight" ? "一个景点" : "一道菜") }
        let n = its.filter { $0.type == "note" }.count, p = its.filter { $0.type == "photo" }.count
        return [n > 0 ? "\(n) 段随记" : nil, p > 0 ? "\(p) 张照片" : nil].compactMap { $0 }.joined(separator: " + ")
    }

    private func itemLabel(_ s: StopoverShare) async -> String {
        guard let it = s.items.first(where: { ($0.type == "sight" || $0.type == "food") && $0.city == city }), let i = it.i,
              let j = await store.profile(city), let list = j[it.type == "sight" ? "sights" : "foods"] as? [[String: Any]], i < list.count
        else { return "" }
        return "\(it.type == "sight" ? "景点" : "美食")「\(list[i]["name"] as? String ?? "")」"
    }
}

private struct ThreadGroup: View {
    let key: String
    let share: StopoverShare?
    let msgs: [StopoverComment]
    let headWhat: String
    let whereOf: (StopoverComment) -> String?
    @ObservedObject var store: StopoverStore
    let city: String
    @State private var replyTo: StopoverComment?
    @State private var text = ""
    @State private var busy = false
    @State private var confirmDel: Int?

    private let yy = Color(UIColor(hex: 0x3e6a9e)), me = Color(UIColor(hex: 0x9a6a12))

    var body: some View {
        let by = Dictionary(uniqueKeysWithValues: msgs.map { ($0.id, $0) })
        VStack(alignment: .leading, spacing: 0) {
            // 组头
            if let s = share {
                let mine = s.who != "partner"
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(mine ? "你递给\(StopoverStore.shared.config.partner)" : "\(StopoverStore.shared.config.partner)递给你").font(StopoverK.mono(10, .medium)).tracking(1.2).foregroundStyle(StopoverK.sky)
                    Text(headWhat).font(StopoverK.serif(15, .semibold)).foregroundStyle(StopoverK.ink)
                    Spacer(minLength: 0)
                    Text(TripPage.ago(s.created) + (mine && s.status == "pending" ? " · 两分钟内送到" : ""))
                        .font(.system(size: 11)).foregroundStyle(Color(UIColor(hex: 0x8a93a0)))
                }
                .padding(.bottom, 6)
                if !s.note.isEmpty { line(who: StopoverStore.shared.config.name(s.who), text: s.note, extra: nil, time: nil, c: nil) }
            } else {
                Text("平时说的").font(StopoverK.mono(10, .medium)).tracking(1.2).foregroundStyle(StopoverK.sky).padding(.bottom, 6)
            }
            ForEach(msgs) { m in
                line(who: StopoverStore.shared.config.name(m.who), text: m.text,
                     extra: [m.replyTo.flatMap { by[$0] }.map { "回复 \(StopoverStore.shared.config.name($0.who))" }, whereOf(m)].compactMap { $0 }.joined(separator: " · "),
                     time: m.created, c: m)
            }
            // 输入框
            VStack(alignment: .leading, spacing: 6) {
                if let r = replyTo {
                    HStack {
                        Text("回复 \(StopoverStore.shared.config.name(r.who))：「\(String(r.text.prefix(20)))\(r.text.count > 20 ? "…" : "")」").font(.system(size: 12)).foregroundStyle(StopoverK.sky)
                            .lineLimit(1)
                        Spacer()
                        Button("不回了") { replyTo = nil }.font(.system(size: 12)).foregroundStyle(StopoverK.harbor)
                    }
                }
                HStack(spacing: 8) {
                    TextField(replyTo.map { "回复 \(StopoverStore.shared.config.name($0.who))…" } ?? (share != nil ? "回复这次…" : "接着说…"), text: $text, axis: .vertical)
                        .font(StopoverK.serif(15)).lineLimit(1...5)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(UIColor(hex: 0xF4F1EB)), in: RoundedRectangle(cornerRadius: 8))
                        .onChange(of: text) { _, v in if v.count > 2000 { text = String(v.prefix(2000)) } }
                    Button {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        busy = true
                        // 平时组: 回某条就挂那条的 target,不然挂城市;递送组一律 share:<id>
                        let target = share != nil ? key : (replyTo?.target ?? key)
                        Task {
                            if await store.comment(target, t, replyTo: replyTo?.id) { text = ""; replyTo = nil }
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
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(StopoverK.harbor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func line(who: String, text: String, extra: String?, time: Double?, c: StopoverComment?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text(who + " ").font(StopoverK.serif(14.5, .bold)).foregroundColor(who == StopoverStore.shared.config.partner ? yy : me)
             + Text(extra.map { $0.isEmpty ? "" : $0 + " " } ?? "").font(.system(size: 12)).foregroundColor(StopoverK.sky)
             + Text(text).font(StopoverK.serif(14.5)).foregroundColor(StopoverK.ink))
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            if let time, let c {
                HStack(spacing: 14) {
                    Text(TripPage.ago(time)).font(.system(size: 11)).foregroundStyle(Color(UIColor(hex: 0x8a93a0)))
                    if c.who == "partner" {
                        Button("回复") { replyTo = c }
                    } else {
                        Button(confirmDel == c.id ? "确认删？" : "删") {
                            if confirmDel != c.id { confirmDel = c.id; return }
                            Task { await store.deleteComment(c.id); confirmDel = nil }
                        }
                    }
                }
                .font(.system(size: 12)).foregroundStyle(StopoverK.harbor)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
