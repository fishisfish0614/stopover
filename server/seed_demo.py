#!/usr/bin/env python3
"""Fill var/stopover.db with a few made-up trips so the globe isn't empty on first run.
    python3 server/seed_demo.py          (refuses to touch a database that already has trips)"""
import os, sys, time
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
    trip("shanghai", None)
    trip("kyoto", "shanghai", None, "2023-04", "第一次见到满山的樱花。", ["清晨的伏见稻荷几乎没有人，鸟居一座接一座往山上走。"])
    trip("nara-city", "kyoto", "shanghai", "2023-04", None, ["鹿会鞠躬，前提是你手里有仙贝。"])
    trip("lisbon", "shanghai", None, "2024-10", "坡太陡了。")
    trip("porto", "lisbon", "shanghai", "2024-10", None, ["杜罗河边的傍晚，桥上的灯一盏一盏亮起来。"])
    trip("xi-an", "shanghai", None, "2022")
    for city, by, note in (("reykjavk", "me", "想看极光"), ("reykjavk", "partner", "想和你一起看"), ("istanbul", "partner", ""), ("kyoto", "me", "秋天再去一次")):
        c.execute("INSERT OR REPLACE INTO wishes(city,by,note,created) VALUES(?,?,?,?)", (city, by, note, now))
print("Demo trips written to var/stopover.db")
