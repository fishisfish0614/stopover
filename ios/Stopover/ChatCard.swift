import SwiftUI

// MARK: - A chat card for one hand-over / one message
// This app has no chat page; this view is for your own chat front end (where your partner lives) to show
// what was handed over or said in Stopover. It draws the server's card JSON — the same fields as the
// iframe card at /card/share/{id}?k=… — so the web card and this one say the same thing:
//   - the webhook (inject.url) carries `cards: [{url, json}]`: decode `json` and pass it to `StopoverChatCard(card:)`
//     (set the server's `public_url` so image / link are absolute, or pass `base:`)
//   - or keep just the card url and use `StopoverRemoteCard(url:)`, which fetches /api/share/{id}/card?k=…
// Copy this file into your project; it only needs `StopoverK` (colours / fonts) and `WikiImage` from Kit.swift / HomeView.swift.

/// The server's card JSON (`GET /api/share/{id}/card?k=…`, `GET /api/comment/{id}/card?k=…`)
struct StopoverCard: Decodable, Identifiable, Hashable {
    let kind: String          // "share" = something handed over, "comment" = something said
    let id: Int
    let who: String           // "me" / "partner"
    let theme: String         // "light" for me, "dark" for the partner — override with `StopoverChatCard(theme:)`
    let eyebrow: String       // 「STOPOVER · 递给TA」— names come from the server's config
    let title: String         // the city
    let subtitle: String      // 「整张票 · 2025.03」/「在这张照片下面说」
    let body: String          // the note that came with it, or what was said
    let image: String?        // a signed photo thumbnail or a Wikimedia image; nil = draw the globe
    let link: String          // opens the city in the web page
    let city: String?
    let target: String?       // comment cards: trip:7 / photo:4 / note:2 / city:… / share:…
    let url: String           // the iframe card

    var key: String { "\(kind):\(id)" }

    /// `image` / `link` are relative when the server has no `public_url`; pass the server's root to resolve them
    func resolve(_ s: String?, base: URL?) -> URL? {
        guard let s, !s.isEmpty else { return nil }
        return URL(string: s, relativeTo: base)?.absoluteURL
    }

    /// Card page url (`/card/share/4?k=…`) → its JSON (`/api/share/4/card?k=…`) and the server's root
    static func split(_ cardURL: URL) -> (json: URL, root: URL)? {
        guard var c = URLComponents(url: cardURL, resolvingAgainstBaseURL: true) else { return nil }
        let p = c.path.split(separator: "/").map(String.init)
        guard let i = p.lastIndex(of: "card"), p.count >= i + 3,
              ["share", "comment"].contains(p[i + 1]) else { return nil }
        let prefix = p[..<i].map { "/" + $0 }.joined()
        c.path = prefix + "/api/\(p[i + 1])/\(p[i + 2])/card"
        guard let json = c.url else { return nil }
        c.path = prefix + "/"; c.query = nil
        guard let root = c.url else { return nil }
        return (json, root)
    }

    static func load(from cardURL: URL) async throws -> StopoverCard {
        guard let u = split(cardURL)?.json else { throw URLError(.badURL) }
        let (d, r) = try await URLSession.shared.data(from: u)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }   // 403 = wrong key
        return try JSONDecoder().decode(StopoverCard.self, from: d)
    }
}

struct StopoverChatCard: View {
    let card: StopoverCard
    /// "light" / "dark"; nil = what the server picked (light for me, dark for the partner)
    var theme: String? = nil
    /// The server's root, for relative `image` / `link` (only needed when `public_url` isn't set)
    var base: URL? = nil
    /// nil = open `card.link` in the browser
    var onTap: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @State private var imgFailed = false

    private var dark: Bool { (theme ?? card.theme) == "dark" }
    private var fill: Color { Color(UIColor(hex: dark ? 0x23252B : 0xFDF6D8)) }
    private var ink: Color { Color(UIColor(hex: dark ? 0xF2F2F4 : 0x22252B)) }

    var body: some View {
        Button {
            if let onTap { onTap() } else if let u = card.resolve(card.link, base: base) { openURL(u) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    thumb
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.eyebrow).font(StopoverK.mono(9.5, .medium)).tracking(1.3)
                            .foregroundStyle(ink.opacity(0.55)).lineLimit(1)
                        Text(card.title).font(StopoverK.serif(17, .semibold)).foregroundStyle(ink).lineLimit(2)
                        if !card.subtitle.isEmpty {
                            Text(card.subtitle).font(.system(size: 12)).foregroundStyle(ink.opacity(0.6)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if !card.body.isEmpty {
                    Text(card.body).font(StopoverK.serif(15.5)).lineSpacing(4).foregroundStyle(ink).lineLimit(6)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
            .frame(maxWidth: 360, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var thumb: some View {
        if let u = card.resolve(card.image, base: base), !imgFailed {
            WikiImage(url: u, onFail: { imgFailed = true })
                .frame(width: 36, height: 52).clipShape(Capsule())
                .frame(width: 44)   // same column as the globe, so titles line up across cards
        } else {
            Circle().fill(Color(UIColor(hex: 0x3B5B8A))).frame(width: 44, height: 44)
                .overlay { Image(systemName: "globe.asia.australia").font(.system(size: 21, weight: .light)).foregroundStyle(.white) }
        }
    }
}

/// Just the card url from the webhook / `/api/state` → fetch the JSON and draw it. Nothing is drawn if the key is wrong.
struct StopoverRemoteCard: View {
    let url: URL
    var theme: String? = nil
    var onTap: ((StopoverCard) -> Void)? = nil
    @State private var card: StopoverCard?

    var body: some View {
        Group {
            if let card {
                StopoverChatCard(card: card, theme: theme, base: StopoverCard.split(url)?.root, onTap: onTap.map { f in { f(card) } })
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(StopoverK.ink.opacity(0.06))
                    .frame(maxWidth: 360).frame(height: 72)
            }
        }
        .task(id: url) { card = try? await StopoverCard.load(from: url) }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        StopoverChatCard(card: StopoverCard(kind: "share", id: 1, who: "me", theme: "light", eyebrow: "STOPOVER · 递给TA",
                                            title: "洛杉矶", subtitle: "整张票 · 2025.03", body: "这张票给你。", image: nil,
                                            link: "", city: "los-angeles", target: nil, url: ""))
        StopoverChatCard(card: StopoverCard(kind: "comment", id: 4, who: "partner", theme: "dark", eyebrow: "STOPOVER · TA说",
                                            title: "洛杉矶", subtitle: "在这张照片下面说", body: "这张的颜色好像橘子汽水。", image: nil,
                                            link: "", city: "los-angeles", target: "photo:4", url: ""))
    }
    .padding()
}
