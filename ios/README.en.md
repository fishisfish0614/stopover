# Stopover · iOS

[中文](README.md) · **English**

A native SwiftUI client for `server/stopover.py` in this same repository.

## Run

1. Start the server first (see the [root README](../README.en.md)):
   ```sh
   pip install -r server/requirements.txt
   python3 server/seed_demo.py   # optional: a few made-up demo trips
   python3 server/stopover.py    # → http://localhost:8000
   ```
2. Open `ios/Stopover.xcodeproj` in Xcode 16 or later, pick an iPhone simulator and Run. Requires iOS 17+.
   To install on a device, choose your own Team under *Signing & Capabilities* and change the Bundle Identifier (default `com.example.stopover`) to one of your own.
3. On first launch the app asks for the server address. If the simulator and the server are on the same Mac, keep the default `http://localhost:8000`;
   on a device, use your computer's LAN address, e.g. `http://192.168.1.10:8000`. You can change it later with the gear in the top-right corner of the globe page.

## What's in it

The globe (three styles — Blue Marble (蓝石), Night Flight (夜航) and Old Map (旧图) — with red dots for places you've been, red arcs and shooting stars from where you set off, stars for places you want to go, and city names as you zoom in);
city pages (history timeline / culture / sights carousel / food); a boarding pass for every visit (tear off the stub to open the trip (这一次));
editable dates and remarks / origin / next stop, notes, photos, wishlist stars, search (by country / where you've been / where you want to go; places it can't find can be added from Wikidata),
the dice, and writing up a page on the spot for cities without one (the server needs `DEEPSEEK_API_KEY`).

The two-person part (shown when `features.share` in the server's `/api/config` is true; turn it off and it's hidden entirely, leaving just your own log):
"Hand it over" (递给TA) a city / a sight / a dish / a whole ticket / a few notes and photos (anything handed over within two minutes is merged into one message, and you can take it back until it's delivered);
an inbox of what your partner hands you with unread dots; "Our conversation" (我们的对话) at the bottom of each city card (one thread per hand-over, plus "just talking" (平时说的)); and replies to your partner's comments.

Names (`me` / `partner`, e.g. 「我」「TA」), the default origin and home are all read from the server's `/api/config`; nothing is hard-coded in the app.
The app always speaks as *me* and sends no auth header; the partner side (an AI companion, say) calls the same API with the key the server gave it.

## Push (optional, off by default)

Without push the app builds and runs as-is in the simulator and on a device, no paid developer account needed. To get notified when your partner hands you something or replies:

1. You need a paid Apple Developer account. In Xcode, choose your Team, change the Bundle Identifier, then
   *Signing & Capabilities* → *+ Capability* → **Push Notifications**.
2. Configure an APNs key on the server (see the [root README](../README.en.md) / `server/config.example.json`); `features.push_apns` in `/api/config` becomes true.
3. A "Push" (推送) toggle appears in the app settings (the gear on the globe page). Turning it on asks for notification permission and reports the device token to `POST /api/push/apns`.
   Tapping a notification opens that city (the payload's `route` is `stopover`, with `city`).

Debug builds register as sandbox; Release / TestFlight builds register as production.

## Assets

- `Resources/stopover_marble.jpg`: NASA Visible Earth *Blue Marble* (public domain)
- `Resources/stopover_night.jpg`, `stopover_sky.jpg`: same as `web/tex/` (see `THIRD_PARTY.md` in the repo root)
- `Resources/stopover_countries.json`: Natural Earth (public domain)
- Fonts: Instrument Serif and IBM Plex Mono, SIL Open Font License 1.1 (license texts in `Resources/OFL-*.txt`)
- The Chinese serif is the system's on-demand Songti SC (宋体-简), not bundled
- The tear-the-stub gesture is based on jal-co/boarding-pass (MIT, see `THIRD_PARTY.md` in the repo root)
