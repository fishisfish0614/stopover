#!/usr/bin/env python3
"""Fill var/stopover.db with a few made-up trips, hand-overs and a short conversation, so the globe isn't empty on first run.
    python3 server/seed_demo.py              (refuses to touch a database that already has trips)
    python3 server/seed_demo.py --no-photos  (skip fetching the four demo photos from Wikimedia Commons)"""
import json, os, re, sys, time, urllib.parse, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stopover as S
S.init()
with S.db() as c:
    if c.execute("SELECT COUNT(*) FROM checkins").fetchone()[0]: sys.exit("var/stopover.db already has trips; not touching it.")
    now = time.time()
    def trip(city, origin, dest=None, date=None, remark=None, notes=()):
        tid = c.execute("INSERT INTO checkins(city,origin,dest,date_start,remark,created,updated) VALUES(?,?,?,?,?,?,?)",
                        (city, origin, dest, date, remark, now, now)).lastrowid
        wrote = time.mktime(time.strptime((date or "") + "-03 21:30" if date and len(date) == 7 else "2022-05-03 21:30", "%Y-%m-%d %H:%M"))   # notes dated on the trip, not today
        for n in notes: c.execute("INSERT INTO notes(trip_id,text,created,updated) VALUES(?,?,?,?)", (tid, n, wrote, wrote))
        return tid
    trip("shanghai", None)
    kyoto = trip("kyoto", "shanghai", None, "2023-04", "第一次见到满山的樱花。", ["清晨的伏见稻荷几乎没有人，鸟居一座接一座往山上走。"])
    trip("nara-city", "kyoto", "shanghai", "2023-04", None, ["鹿会鞠躬，前提是你手里有仙贝。"])
    lisbon = trip("lisbon", "shanghai", None, "2024-10", "坡太陡了。")
    porto = trip("porto", "lisbon", "shanghai", "2024-10", None, ["杜罗河边的傍晚，桥上的灯一盏一盏亮起来。"])
    trip("xi-an", "shanghai", None, "2022")
    for city, by, note in (("reykjavk", "me", "想看极光"), ("reykjavk", "partner", "想和你一起看"), ("istanbul", "partner", ""), ("kyoto", "me", "秋天再去一次")):
        c.execute("INSERT OR REPLACE INTO wishes(city,by,note,created) VALUES(?,?,?,?)", (city, by, note, now))

    # v2 demo: I handed the Kyoto ticket over and the partner answered twice; the partner handed me two things (one read, one not yet)
    def share(who, items, note, ago, read=False):
        t = now - ago
        return c.execute("INSERT INTO shares(created,who,items,note,status,sent,img,read_at,key,taken_at) VALUES(?,?,?,?,'sent',?,1,?,?,?)",
                         (t, who, json.dumps(items, ensure_ascii=False), note, t + 120, t + 600 if read else None, S.new_key(), t + 120 if who == "me" else None)).lastrowid
    def say(who, target, text, ago, reply_to=None):
        t = now - ago; done = t + 120 if who == "me" else None
        return c.execute("INSERT INTO comments(target,who,text,reply_to,created,key,sent,taken_at) VALUES(?,?,?,?,?,?,?,?)",
                         (target, who, text, reply_to, t, S.new_key(), done, done)).lastrowid
    d1 = share("me", [{"type": "trip", "id": kyoto}], "这张票给你。", 3 * 86400)
    c1 = say("partner", f"share:{d1}", "伏见稻荷那条路，下次我们从山脚一直走到山顶。", 3 * 86400 - 3600)
    c2 = say("me", f"share:{d1}", "好，要清晨去，人少。", 3 * 86400 - 7200, c1)
    say("partner", f"share:{d1}", "那就定在秋天，红叶的时候。", 3 * 86400 - 9000, c2)
    share("partner", [{"type": "city", "city": "istanbul"}], "海峡两边各住一晚？", 2 * 86400, read=True)
    share("partner", [{"type": "food", "city": "lisbon", "i": 0}], "下次替你尝一口。", 5 * 3600)
print("Demo trips written to var/stopover.db")

# Demo photos: fetched from Wikimedia Commons at seed time (the repo itself ships no photos), each keeps its own license.
PHOTOS = [(kyoto, "FUS - Senbon torii path at Fushimi Inari-taisha, Kyoto, Japan, 2015.jpg", "2023-04-03 07:10", "千本鸟居，一座接一座。"),
          (kyoto, "Cherry Blossom @ Philosopher's Path ,Kyoto - panoramio.jpg", "2023-04-04 15:40", "哲学之道，花瓣落在水面上。"),
          (lisbon, "Electrico 28, Lisbon (10994871254).jpg", "2024-10-12 11:20", "28 路电车爬坡的声音。"),
          (porto, "Porto, Dom Luís I Bridge at dusk (48296732001).jpg", "2024-10-15 19:05", "")]
if "--no-photos" in sys.argv: sys.exit()
def commons(params):
    u = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({**params, "format": "json"})
    return json.load(urllib.request.urlopen(urllib.request.Request(u, headers=S.UA), timeout=30))
credits = []
for tid, name, taken, caption in PHOTOS:
    try:
        r = commons({"action": "query", "titles": "File:" + name, "prop": "imageinfo", "iiprop": "url|extmetadata", "iiurlwidth": 1600,
                     "iiextmetadatafilter": "LicenseShortName|Artist"})
        ii = next(iter(r["query"]["pages"].values()))["imageinfo"][0]; m = ii["extmetadata"]
        raw = urllib.request.urlopen(urllib.request.Request(ii["thumburl"], headers=S.UA), timeout=60).read()
        pid = S.save_photo(tid, raw, name)["photo"]["id"]
        with S.db() as c:
            c.execute("UPDATE photos SET caption=?, taken=? WHERE id=?", (caption, time.mktime(time.strptime(taken, "%Y-%m-%d %H:%M")), pid))
        artist = re.sub(r"<[^>]+>", "", m.get("Artist", {}).get("value", "")).strip()
        credits.append(f"p:{pid}  {name} — {artist}, {m.get('LicenseShortName', {}).get('value', '')} — {ii['descriptionurl']}")
    except Exception as e:
        print(f"  skipped a demo photo ({name}): {e}")
if credits:
    open(os.path.join(S.VAR, "demo-photo-credits.txt"), "w").write("\n".join(credits) + "\n")
    print(f"{len(credits)} demo photos from Wikimedia Commons (credits in var/demo-photo-credits.txt):"); print("\n".join("  " + x for x in credits))
