import Foundation

// Data layer for the open-source Stopover server (server/stopover.py).
// Static city data: /data/cities.json (cached on disk, re-fetched on every launch) and /data/city/<id>.json.
// Everything else comes from GET /api/state; writes re-fetch it.
// Display names, home and default origins come from /api/config — nothing personal is hard-coded here.

struct StopoverCity: Identifiable, Equatable {
    let id: String
    let name: String
    let en: String
    let country: String
    let lat: Double
    let lng: Double
    let hasProfile: Bool   // the "extra" cities have no page yet
}

struct StopoverCheckin: Identifiable, Equatable {
    let id: Int
    let city: String
    let origin: String?
    let dest: String?
    let dateStart: String?
    let dateEnd: String?
    let remark: String?
}

struct StopoverNote: Identifiable, Equatable {
    let id: Int
    let tripId: Int
    let text: String
    let updated: Double
}

struct StopoverPhoto: Identifiable, Equatable {
    let id: Int
    let tripId: Int
    let caption: String
    let tag: String?
}

struct StopoverComment: Identifiable, Equatable {
    let id: Int
    let target: String   // city:<id> / trip:<id> / photo:<id> / note:<id> / share:<id>
    let who: String      // "me" | "partner"
    let text: String
    let replyTo: Int?
    let created: Double
}

/// One thing handed over (by me or by the partner). items: trip / photo / note (with id), city, sight / food (city + i)
struct StopoverShare: Identifiable, Equatable {
    struct Item: Equatable { let type: String; let id: Int?; let city: String?; let i: Int? }
    let id: Int
    let who: String          // "me" | "partner"
    let items: [Item]
    let note: String
    let status: String       // pending / sent
    let created: Double
    let readAt: Double?
}

struct StopoverWish: Equatable {
    let city: String
    let by: String     // "me" | "partner"
    let note: String
    var created: Double = 0
}

struct StopoverConfig: Equatable {
    var me = "我"
    var partner = "TA"
    var homeLabel = "家"
    var originDomestic: String?
    var originAbroad: String?
    var domestic: Set<String> = ["China", "Hong Kong S.A.R.", "Macao S.A.R", "Taiwan"]
    var tags = ["美食", "风景", "名胜", "艺术品", "个人照片"]
    /// features.share = false hides handing over / conversations / inbox (for people who only keep their own log)
    var share = true
    var pushAPNs = false

    /// "me" / "partner" → display name
    func name(_ who: String) -> String { who == "partner" ? partner : me }
}

@MainActor
final class StopoverStore: ObservableObject {
    static let shared = StopoverStore()

    /// Server address, set on first launch (Settings). Default: a server running on this Mac.
    static let defaultServer = "http://localhost:8000"
    static var serverString: String {
        get { UserDefaults.standard.string(forKey: "server") ?? defaultServer }
        set { UserDefaults.standard.set(newValue, forKey: "server") }
    }
    static var base: URL { URL(string: serverString) ?? URL(string: defaultServer)! }

    @Published private(set) var cities: [String: StopoverCity] = [:]
    @Published private(set) var countryZh: [String: String] = [:]
    @Published private(set) var checkins: [StopoverCheckin] = []
    @Published private(set) var notes: [StopoverNote] = []
    @Published private(set) var photos: [StopoverPhoto] = []
    @Published private(set) var wishes: [StopoverWish] = []
    @Published private(set) var comments: [StopoverComment] = []
    @Published private(set) var shares: [StopoverShare] = []
    @Published private(set) var config = StopoverConfig()
    @Published private(set) var failure: String?
    /// One-line message (saved / server error detail); the page shows it and clears it
    @Published var toast: String?

    private var citiesLoaded = false

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("stopover-cities.json")
    }

    /// cities.json changes when a page is generated or a place is added, so it's fetched every launch;
    /// the disk copy only makes the globe appear instantly.
    func load() async {
        if !citiesLoaded, let d = try? Data(contentsOf: Self.cacheURL) { parseCities(d) }
        if let d = await get("data/cities.json") {
            parseCities(d)
            try? d.write(to: Self.cacheURL)
        }
        await reloadState()
    }

    func reloadState() async {
        guard let d = await get("api/state"),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        if let c = j["config"] as? [String: Any] { config = Self.parseConfig(c) }
        checkins = (j["checkins"] as? [[String: Any]] ?? []).compactMap { c in
            guard let id = c["id"] as? Int, let city = c["city"] as? String else { return nil }
            return StopoverCheckin(id: id, city: city, origin: c["origin"] as? String, dest: c["dest"] as? String,
                                   dateStart: c["date_start"] as? String, dateEnd: c["date_end"] as? String,
                                   remark: c["remark"] as? String)
        }
        notes = (j["notes"] as? [[String: Any]] ?? []).compactMap { n in
            guard let id = n["id"] as? Int, let t = n["trip_id"] as? Int else { return nil }
            return StopoverNote(id: id, tripId: t, text: n["text"] as? String ?? "",
                                updated: (n["updated"] as? Double) ?? (n["created"] as? Double) ?? 0)
        }
        photos = (j["photos"] as? [[String: Any]] ?? []).compactMap { p in
            guard let id = p["id"] as? Int, let t = p["trip_id"] as? Int else { return nil }
            return StopoverPhoto(id: id, tripId: t, caption: p["caption"] as? String ?? "", tag: p["tag"] as? String)
        }
        comments = (j["comments"] as? [[String: Any]] ?? []).compactMap { c in
            guard let id = c["id"] as? Int, let t = c["target"] as? String else { return nil }
            return StopoverComment(id: id, target: t, who: c["who"] as? String ?? "me", text: c["text"] as? String ?? "",
                                   replyTo: c["reply_to"] as? Int, created: c["created"] as? Double ?? 0)
        }
        shares = (j["shares"] as? [[String: Any]] ?? []).compactMap { x in
            guard let id = x["id"] as? Int else { return nil }
            let items = (x["items"] as? [[String: Any]] ?? []).compactMap { it -> StopoverShare.Item? in
                guard let t = it["type"] as? String else { return nil }
                return .init(type: t, id: it["id"] as? Int, city: it["city"] as? String, i: it["i"] as? Int)
            }
            return StopoverShare(id: id, who: x["who"] as? String ?? "me", items: items, note: x["note"] as? String ?? "",
                                 status: x["status"] as? String ?? "", created: x["created"] as? Double ?? 0,
                                 readAt: x["read_at"] as? Double)
        }
        wishes = (j["wishes"] as? [[String: Any]] ?? []).compactMap { w in
            guard let city = w["city"] as? String, let by = w["by"] as? String else { return nil }
            return StopoverWish(city: city, by: by, note: (w["note"] as? String) ?? "", created: (w["created"] as? Double) ?? 0)
        }
    }

    private static func parseConfig(_ c: [String: Any]) -> StopoverConfig {
        var x = StopoverConfig()
        if let s = c["me"] as? String, !s.isEmpty { x.me = s }
        if let s = c["partner"] as? String, !s.isEmpty { x.partner = s }
        if let h = c["home"] as? [String: Any], let l = h["label"] as? String { x.homeLabel = l }
        if let o = c["default_origin"] as? [String: Any] {
            x.originDomestic = o["domestic"] as? String
            x.originAbroad = o["abroad"] as? String
        }
        if let d = c["domestic_countries"] as? [String] { x.domestic = Set(d) }
        if let t = c["tags"] as? [String], !t.isEmpty { x.tags = t }
        if let f = c["features"] as? [String: Any] {
            x.share = f["share"] as? Bool ?? true
            x.pushAPNs = f["push_apns"] as? Bool ?? false
        }
        return x
    }

    /// City page; nil for cities without one
    func profile(_ id: String) async -> [String: Any]? {
        guard cities[id]?.hasProfile == true, let d = await get("data/city/\(id).json") else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    func countryName(_ en: String) -> String { countryZh[en] ?? en }

    var visitCounts: [String: Int] { checkins.reduce(into: [:]) { $0[$1.city, default: 0] += 1 } }

    // MARK: - Wishes (gold = me; the partner's blue star is display-only in the app)

    func setWish(_ city: String, on: Bool, note: String = "") async {
        if on {
            _ = await write("PUT", "api/wish/\(city)", ["by": "me", "note": note])
        } else {
            _ = await write("DELETE", "api/wish/\(city)?by=me", nil)
        }
        await reloadState()
    }

    // MARK: - Trips / notes

    /// Default origin: domestic vs abroad, from /api/config
    func defaultOrigin(for city: String) -> String? {
        config.domestic.contains(cities[city]?.country ?? "") ? config.originDomestic : config.originAbroad
    }

    private var homes: [String] { [config.originDomestic, config.originAbroad].compactMap { $0 } }

    /// Origin choices: default, current, then visited cities by distance (the next stop of a trip
    /// usually starts from a nearby previous one). At most 7.
    func originChoices(for city: String, current: String?) -> [(id: String, tag: String)] {
        var seen: Set<String> = [city], out: [(String, String)] = []
        func add(_ id: String?, _ tag: String) {
            guard let id, !seen.contains(id), cities[id] != nil else { return }
            seen.insert(id); out.append((id, tag))
        }
        add(defaultOrigin(for: city), "默认")
        add(current, "现在")
        for t in checkins.sorted(by: { (km($0.city, city) ?? .max) < (km($1.city, city) ?? .max) }) where out.count < 7 { add(t.city, "") }
        return out
    }

    /// End-point choices: current, home(s), then visited cities by distance. At most 8.
    func destChoices(for city: String, current: String?) -> [(id: String, tag: String)] {
        var seen: Set<String> = [city], out: [(String, String)] = []
        func add(_ id: String?, _ tag: String) {
            guard let id, !seen.contains(id), cities[id] != nil else { return }
            seen.insert(id); out.append((id, tag))
        }
        add(current, "现在")
        add(defaultOrigin(for: city), config.homeLabel)
        for h in homes { add(h, config.homeLabel) }
        for t in checkins.sorted(by: { (km($0.city, city) ?? .max) < (km($1.city, city) ?? .max) }) where out.count < 8 { add(t.city, "") }
        return out
    }

    /// Check in once; origin == city means "no line"
    func checkin(_ city: String, origin: String) async {
        guard let j = await write("POST", "api/checkin/\(city)", ["origin": origin]) else { return }
        await reloadState()
        let n = trips(city).count
        let o = ((j["checkin"] as? [String: Any])?["origin"] as? String).flatMap { $0 == city ? nil : cities[$0] }
        toast = o.map { "打卡！\(n > 1 ? "第 \(n) 次，" : "")红线从\($0.name)连过来了" } ?? "打卡！\(n > 1 ? "第 \(n) 次" : "")"
    }

    /// Only the fields passed change; NSNull / "" clears
    @discardableResult
    func updateTrip(_ id: Int, _ fields: [String: Any], done: String = "记下了 ✓") async -> Bool {
        guard await write("PUT", "api/trip/\(id)", fields) != nil else { return false }
        await reloadState(); toast = done; return true
    }

    func deleteTrip(_ id: Int) async -> Bool {
        guard let j = await write("DELETE", "api/trip/\(id)", nil) else { return false }
        await reloadState()
        let kids = (j["reset_children"] as? [String] ?? []).map { cities[$0]?.name ?? $0 }
        toast = kids.isEmpty ? "删掉了" : "取消了；从这里出发的\(kids.joined(separator: "、"))改回默认出发地"
        return true
    }

    func addNote(trip: Int, _ text: String) async -> Bool {
        guard await write("POST", "api/trip/\(trip)/note", ["text": text]) != nil else { return false }
        await reloadState(); toast = "记下了 ✓"; return true
    }

    func editNote(_ id: Int, _ text: String) async -> Bool {
        guard await write("PUT", "api/note/\(id)", ["text": text]) != nil else { return false }
        await reloadState(); toast = "记下了 ✓"; return true
    }

    func deleteNote(_ id: Int) async -> Bool {
        guard await write("DELETE", "api/note/\(id)", nil) != nil else { return false }
        await reloadState(); toast = "删掉了"; return true
    }

    // MARK: - Handing over to the partner (merged for two minutes, then delivered by the server)

    /// img only matters for city / sight / food; trip photos are always attached
    func share(_ items: [[String: Any]], note: String = "", img: Bool? = nil, done: String) async -> Bool {
        var body: [String: Any] = ["items": items, "note": note]
        if let img { body["img"] = img }
        guard await write("POST", "api/share", body) != nil else { return false }
        await reloadState(); toast = done; return true
    }

    /// Only pending ones can be taken back
    func unshare(_ id: Int) async {
        guard await write("DELETE", "api/share/\(id)", nil) != nil else { return }
        await reloadState(); toast = "撤回了"
    }

    /// Mine, still pending, touching this trip (the whole ticket / its notes / its photos)
    func pendingShares(trip t: Int) -> [StopoverShare] {
        let ns = Set(notes(trip: t).map(\.id)), ps = Set(photos(trip: t).map(\.id))
        return shares.filter { s in
            s.who != "partner" && s.status == "pending" && s.items.contains { it in
                (it.type == "trip" && it.id == t) || (it.type == "note" && ns.contains(it.id ?? -1)) || (it.type == "photo" && ps.contains(it.id ?? -1))
            }
        }
    }

    // MARK: - Comments / inbox

    func comments(_ target: String) -> [StopoverComment] { comments.filter { $0.target == target } }

    func comment(_ target: String, _ text: String, replyTo: Int?) async -> Bool {
        var body: [String: Any] = ["target": target, "text": text]
        if let replyTo { body["reply_to"] = replyTo }
        guard await write("POST", "api/comment", body) != nil else { return false }
        await reloadState(); toast = "回好了"; return true
    }

    /// Only my own
    func deleteComment(_ id: Int) async {
        guard await write("DELETE", "api/comment/\(id)", nil) != nil else { return }
        await reloadState()
    }

    /// How many lines the partner said under this trip (ticket, photos, notes)
    func commentCount(trip t: StopoverCheckin) -> Int {
        comments("trip:\(t.id)").count
            + photos(trip: t.id).reduce(0) { $0 + comments("photo:\($1.id)").count }
            + notes(trip: t.id).reduce(0) { $0 + comments("note:\($1.id)").count }
    }

    var fromPartner: [StopoverShare] { shares.filter { $0.who == "partner" }.sorted { $0.created > $1.created } }
    /// Everything either of you handed over, newest first (the 往来 page). A wish the partner added
    /// is stored as a wish, not a share, but reads like a hand-over, so it's folded in as a read-only row (negative id)
    var allShares: [StopoverShare] {
        let theirs = wishes.filter { $0.by == "partner" }.enumerated().map { i, w in
            StopoverShare(id: -(i + 1), who: "partner", items: [.init(type: "city", id: nil, city: w.city, i: nil)],
                          note: w.note, status: "sent", created: w.created, readAt: w.created)
        }
        return (shares + theirs).sorted { $0.created > $1.created }
    }
    var unreadFromPartner: Int { fromPartner.filter { $0.readAt == nil }.count }

    func markRead(_ id: Int) async {
        _ = await write("PUT", "api/share/\(id)/read", nil, quiet: true)
        await reloadState()
    }

    /// City name / sight name / dish name for an inbox row
    func itemName(_ it: StopoverShare.Item) async -> String {
        guard let c = it.city else { return "" }
        let city = cities[c]?.name ?? c
        guard it.type == "sight" || it.type == "food", let i = it.i,
              let j = await profile(c), let list = j[it.type == "sight" ? "sights" : "foods"] as? [[String: Any]],
              i < list.count else { return city }
        return "\(city)的\(it.type == "sight" ? "景点" : "美食")「\(list[i]["name"] as? String ?? "")」"
    }

    /// After opening a card from the inbox: which sight to pop / dish to expand
    @Published var cardFocus: (city: String, kind: String, i: Int)?

    // MARK: - Push (optional): register the device token if the server has APNs set up

    func registerPush(token: String, sandbox: Bool) async {
        _ = await write("POST", "api/push/apns", ["token": token, "env": sandbox ? "sandbox" : "production"], quiet: true)
    }

    // MARK: - Photos (stored by the server; it dedups by sha256 itself)

    var photoTags: [String] { config.tags }

    /// Multipart upload of the original file (HEIC is fine — the server reads it)
    func upload(trip: Int, data: Data, filename: String, mime: String) async -> Bool {
        let b = "----stopover\(UUID().uuidString)"
        var body = Data()
        body.append("--\(b)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(b)--\r\n".data(using: .utf8)!)
        var req = URLRequest(url: Self.base.appendingPathComponent("api/trip/\(trip)/upload"))
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("multipart/form-data; boundary=\(b)", forHTTPHeaderField: "Content-Type")
        guard let (_, r) = try? await URLSession.shared.upload(for: req, from: body) else { return false }
        return (r as? HTTPURLResponse)?.statusCode ?? 0 < 300
    }

    func updatePhoto(_ id: Int, _ fields: [String: Any]) async -> Bool {
        guard await write("PUT", "api/photo/\(id)", fields) != nil else { return false }
        await reloadState(); return true
    }

    func deletePhoto(_ id: Int) async -> Bool {
        guard await write("DELETE", "api/photo/\(id)", nil) != nil else { return false }
        await reloadState(); toast = "取下了"; return true
    }

    static func photoURL(_ id: Int, w: Int) -> URL {
        URL(string: "\(base.absoluteString)/api/photo/img/\(id)?w=\(w)")!
    }

    // MARK: - Writing a page for a city that has none (pipeline/citygen.py)

    struct Gen: Equatable { var status: String; var stage: String; var msg: String }
    @Published private(set) var gens: [String: Gen] = [:]
    private var polling: Set<String> = []

    /// Ask first when opening a city without a page — it may already be in progress
    func checkGen(_ id: String) async {
        guard let j = await write("GET", "api/city/\(id)/gen", nil, quiet: true) else { return }
        apply(id, j)
    }

    func startGen(_ id: String, pro: Bool) async {
        guard let j = await write("POST", "api/city/\(id)/gen", pro ? ["pro": true] : [:]) else { return }
        apply(id, j)
    }

    private func apply(_ id: String, _ j: [String: Any]) {
        let g = Gen(status: j["status"] as? String ?? "none", stage: j["stage"] as? String ?? "", msg: j["msg"] as? String ?? "")
        gens[id] = g
        if g.status == "done" { finishGen(id, entry: j["entry"] as? [String: Any]); return }
        if g.status == "running", !polling.contains(id) { poll(id) }
    }

    /// Polling lives here so it keeps going if the card is closed; a toast says when it's ready
    private func poll(_ id: String) {
        polling.insert(id)
        Task {
            defer { polling.remove(id) }
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(2.5))
                guard let j = await write("GET", "api/city/\(id)/gen", nil, quiet: true) else { continue }
                let st = j["status"] as? String ?? "none"
                gens[id] = Gen(status: st, stage: j["stage"] as? String ?? "", msg: j["msg"] as? String ?? "")
                if st == "done" { finishGen(id, entry: j["entry"] as? [String: Any]); return }
                if st != "running" { return }
            }
        }
    }

    /// `entry` is a cities[] item; the id doesn't change, so check-ins and stars stay attached
    private func finishGen(_ id: String, entry: [String: Any]?) {
        if let e = entry, let la = e["la"] as? Double, let lo = e["lo"] as? Double {
            cities[id] = StopoverCity(id: id, name: (e["n"] as? String) ?? id, en: (e["e"] as? String) ?? "",
                                      country: (e["c"] as? String) ?? "", lat: la, lng: lo, hasProfile: true)
        } else if let c = cities[id] {
            cities[id] = StopoverCity(id: c.id, name: c.name, en: c.en, country: c.country, lat: c.lat, lng: c.lng, hasProfile: true)
        }
        toast = "\(cities[id]?.name ?? "")的资料整理好了"
    }

    // MARK: - Places that aren't on the map (Wikidata)

    struct Place: Identifiable {
        let qid: String, name: String, desc: String, country: String
        let exists: String?, existsName: String?
        var id: String { qid }
    }

    /// `exists` = there's already a city within a few km; jump to it instead of adding
    func placeSearch(_ q: String) async -> [Place]? {
        var c = URLComponents(string: Self.base.appendingPathComponent("api/place/search").absoluteString)!
        c.queryItems = [.init(name: "q", value: q)]
        guard let (d, r) = try? await URLSession.shared.data(from: c.url!), (r as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return (j["items"] as? [[String: Any]] ?? []).compactMap {
            guard let qid = $0["qid"] as? String else { return nil }
            return Place(qid: qid, name: $0["name"] as? String ?? "", desc: $0["desc"] as? String ?? "",
                         country: $0["country"] as? String ?? "", exists: $0["exists"] as? String, existsName: $0["exists_name"] as? String)
        }
    }

    func addPlace(_ qid: String) async -> String? {
        guard let j = await write("POST", "api/place", ["qid": qid]), let id = j["id"] as? String,
              let c = j["city"] as? [Any], c.count >= 5, let la = c[2] as? Double, let lo = c[3] as? Double else { return nil }
        cities[id] = StopoverCity(id: id, name: c[0] as? String ?? id, en: c[1] as? String ?? "",
                                  country: c[4] as? String ?? "", lat: la, lng: lo, hasProfile: false)
        toast = "「\(cities[id]!.name)」加到地图上了"
        return id
    }

    /// For search: strip diacritics + lowercase
    static func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased() }

    // MARK: - Ticket helpers

    func trips(_ city: String) -> [StopoverCheckin] { checkins.filter { $0.city == city } }
    func notes(trip: Int) -> [StopoverNote] { notes.filter { $0.tripId == trip } }
    func photos(trip: Int) -> [StopoverPhoto] { photos.filter { $0.tripId == trip } }

    /// Ticket number: position among all check-ins
    func ticketNo(_ t: StopoverCheckin) -> String { String(format: "%03d", (checkins.firstIndex { $0.id == t.id } ?? 0) + 1) }

    /// Three-letter code: first word of the English name, diacritics stripped, first three letters
    func code3(_ id: String?) -> String {
        guard let id, let en = cities[id]?.en else { return "···" }
        let first = en.split(whereSeparator: { " ,-".contains($0) }).first.map(String.init) ?? ""
        let letters = first.folding(options: .diacriticInsensitive, locale: nil).lowercased().filter { ("a"..."z").contains($0) }
        return letters.isEmpty ? "···" : String(letters.prefix(3)).uppercased()
    }

    /// Great-circle distance in km
    func km(_ a: String?, _ b: String?) -> Int? {
        guard let a, let b, let p = cities[a], let q = cities[b] else { return nil }
        let r = Double.pi / 180
        let d = pow(sin((q.lat - p.lat) * r / 2), 2) + cos(p.lat * r) * cos(q.lat * r) * pow(sin((q.lng - p.lng) * r / 2), 2)
        return Int((12742 * asin(sqrt(d))).rounded())
    }

    /// "2019-08" → "2019.08"; with an end date "2019.08 – 2019.09"
    func dateText(_ t: StopoverCheckin) -> String? {
        guard let s = t.dateStart, !s.isEmpty else { return nil }
        let f = { (d: String) in d.replacingOccurrences(of: "-", with: ".") }
        if let e = t.dateEnd, !e.isEmpty, e != s { return "\(f(s)) – \(f(e))" }
        return f(s)
    }

    // MARK: - HTTP

    private func get(_ path: String) async -> Data? {
        var req = URLRequest(url: URL(string: path, relativeTo: Self.base.appendingPathComponent("/"))!)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            failure = "连不上服务器（\(Self.serverString)），去设置里看看地址"
            return nil
        }
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { failure = "服务器没接住，一会儿再试"; return nil }
        failure = nil
        return data
    }

    /// Success returns {"ok":true,…}; a 4xx {"detail": "…"} is shown as a toast and nil is returned
    private func write(_ method: String, _ path: String, _ body: [String: Any]?, quiet: Bool = false) async -> [String: Any]? {
        var req = URLRequest(url: URL(string: path, relativeTo: Self.base.appendingPathComponent("/"))!)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { if !quiet { toast = "没连上，一会儿再试" }; return nil }
        let j = (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
        guard (r as? HTTPURLResponse)?.statusCode ?? 0 < 300 else {
            if !quiet { toast = "没存上：" + ((j["detail"] as? String) ?? "服务器没接住") }
            return nil
        }
        return j
    }

    private func parseCities(_ d: Data) {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        var out: [String: StopoverCity] = [:]
        for c in j["cities"] as? [[String: Any]] ?? [] {
            guard let id = c["id"] as? String, let la = c["la"] as? Double, let lo = c["lo"] as? Double else { continue }
            out[id] = StopoverCity(id: id, name: (c["n"] as? String) ?? id, en: (c["e"] as? String) ?? "",
                                   country: (c["c"] as? String) ?? "", lat: la, lng: lo, hasProfile: true)
        }
        // extra: [zh name, en name, lat, lng, country]; id is "n_<en name>_<lat>" with lat formatted like JS
        for e in j["extra"] as? [[Any]] ?? [] {
            guard e.count >= 5, let n = e[0] as? String, let en = e[1] as? String,
                  let la = e[2] as? Double, let lo = e[3] as? Double else { continue }
            let id = "n_\(en)_\(Self.jsNumber(la))"
            out[id] = StopoverCity(id: id, name: n, en: en, country: (e[4] as? String) ?? "", lat: la, lng: lo, hasProfile: false)
        }
        cities = out
        countryZh = j["cz"] as? [String: String] ?? [:]
        citiesLoaded = !out.isEmpty
    }

    private static func jsNumber(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
}
