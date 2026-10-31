#!/usr/bin/env python3
"""Fill var/stopover.db with a few made-up trips, hand-overs and a short conversation, so the globe isn't empty on first run.
    python3 server/seed_demo.py          (refuses to touch a database that already has trips)"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stopover as S
S.init()
with S.db() as c:
    if c.execute("SELECT COUNT(*) FROM checkins").fetchone()[0]: sys.exit("var/stopover.db already has trips; not touching it.")
    now = time.time()
    def trip(city, origin, dest=None, date=None, remark=None, notes=()):
        tid = c.execute("INSERT INTO checkins(city,origin,dest,date_start,remark,created,updated) VALUES(?,?,?,?,?,?,?)",
                        (city, origin, dest, date, remark, now, now)).lastrowid
        for n in notes: c.execute("INSERT INTO notes(trip_id,text,created,updated) VALUES(?,?,?,?)", (tid, n, now, now))
        return tid
    trip("shanghai", None)
    kyoto = trip("kyoto", "shanghai", None, "2023-04", "第一次见到满山的樱花。", ["清晨的伏见稻荷几乎没有人，鸟居一座接一座往山上走。"])
    trip("nara-city", "kyoto", "shanghai", "2023-04", None, ["鹿会鞠躬，前提是你手里有仙贝。"])
    trip("lisbon", "shanghai", None, "2024-10", "坡太陡了。")
    trip("porto", "lisbon", "shanghai", "2024-10", None, ["杜罗河边的傍晚，桥上的灯一盏一盏亮起来。"])
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
