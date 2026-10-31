#!/usr/bin/env python3
"""Stopover server: a small FastAPI + SQLite backend that also serves the web app.

    pip install -r server/requirements.txt
    cp server/config.example.json server/config.json      # names, home, default origins, clocks
    python3 server/stopover.py                             # → http://localhost:8000

Data lives in var/ (git-ignored): var/stopover.db and var/photos/.
City pages are static files in web/data/; pipeline/citygen.py writes new ones on demand.

There is no login. Run it on your own machine or behind your own auth.
"""
import hashlib, io, json, os, re, sqlite3, subprocess, sys, threading, time, urllib.parse, urllib.request
from contextlib import contextmanager
from fastapi import FastAPI, HTTPException, Body, UploadFile, File, Form
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import uvicorn

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, "web")
VAR = os.environ.get("STOPOVER_VAR", os.path.join(ROOT, "var"))
DB = os.path.join(VAR, "stopover.db")
PHOTOS = os.path.join(VAR, "photos")
CITIES_JSON = os.path.join(WEB, "data", "cities.json")
CITY_DIR = os.path.join(WEB, "data", "city")
CFG_FILE = os.environ.get("STOPOVER_CONFIG", os.path.join(ROOT, "server", "config.json"))
GEN_PY = os.path.join(ROOT, "pipeline", "citygen.py")
GEN_DIR = os.path.join(VAR, "gen")
TAGS = ["美食", "风景", "名胜", "艺术品", "个人照片"]
UA = {"User-Agent": f"stopover/1.0 ({os.environ.get('STOPOVER_CONTACT', 'https://github.com/fishisfish0614/stopover')})"}

app = FastAPI(title="stopover")
_lock = threading.Lock()

def cfg():
    """Read every time, so edits to config.json apply without a restart."""
    for f in (CFG_FILE, os.path.join(ROOT, "server", "config.example.json")):
        try: return json.load(open(f))
        except FileNotFoundError: continue
    return {}

@contextmanager
def db():
    c = sqlite3.connect(DB, timeout=10); c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    try:
        with c: yield c
    finally: c.close()        # sqlite3's own `with` commits but never closes — that leaks a file handle per request

def init():
    os.makedirs(PHOTOS, exist_ok=True); os.makedirs(GEN_DIR, exist_ok=True)
    with db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS checkins(id INTEGER PRIMARY KEY AUTOINCREMENT, city TEXT, origin TEXT, dest TEXT,
            date_start TEXT, date_end TEXT, remark TEXT, created REAL, updated REAL);
        CREATE INDEX IF NOT EXISTS ck_city ON checkins(city);
        CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id INTEGER, text TEXT, created REAL, updated REAL);
        CREATE TABLE IF NOT EXISTS photos(id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id INTEGER, file TEXT, sha256 TEXT,
            caption TEXT DEFAULT '', tag TEXT, w INTEGER, h INTEGER, taken REAL, created REAL);
        CREATE TABLE IF NOT EXISTS wishes(city TEXT, by TEXT, note TEXT DEFAULT '', created REAL, PRIMARY KEY(city, by));
        CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL, act TEXT, city TEXT, data TEXT);
        """)

def log(c, act, city, data=None):
    c.execute("INSERT INTO events(ts,act,city,data) VALUES(?,?,?,?)", (time.time(), act, city, json.dumps(data or {}, ensure_ascii=False)))

_cities = {"mtime": 0}
def cities():
    """city id → {name, country}; reloads when cities.json changes (citygen / place add)."""
    m = os.path.getmtime(CITIES_JSON)
    if m != _cities["mtime"]:
        d = json.load(open(CITIES_JSON)); mp = {}
        for x in d["cities"]: mp[x["id"]] = {"name": x["n"], "country": x["c"]}
        for name, en, lat, lng, country in d["extra"]: mp[f"n_{en}_{lat}"] = {"name": name, "country": country}
        _cities.update(mtime=m, map=mp)
    return _cities["map"]

def check_city(city):
    if city not in cities(): raise HTTPException(404, f"没有这座城：{city}")

def default_origin(city):
    o = cfg().get("default_origin") or {}
    dom = set(cfg().get("domestic_countries") or [])
    v = o.get("domestic") if cities().get(city, {}).get("country") in dom else o.get("abroad")
    return None if v == city else v

def norm_city(city, v):
    v = v or None
    if v == city: return None
    if v: check_city(v)
    return v

def trip_row(c, tid):
    r = c.execute("SELECT * FROM checkins WHERE id=?", (tid,)).fetchone()
    if r is None: raise HTTPException(404, "没有这一次")
    return dict(r)

# ---------- read ----------
@app.get("/api/config")
def get_config():
    c = cfg()
    return {k: c.get(k) for k in ("me", "partner", "home", "default_origin", "domestic_countries", "clocks", "tags")} | {"tags": TAGS}

@app.get("/api/state")
def state():
    with db() as c:
        ck = [dict(r) for r in c.execute("SELECT * FROM checkins ORDER BY id")]
        nt = [dict(r) for r in c.execute("SELECT * FROM notes ORDER BY trip_id, id")]
        ph = [dict(r) for r in c.execute("SELECT id, trip_id, caption, tag, w, h, taken, created FROM photos ORDER BY trip_id, COALESCE(taken, created), id")]
        ws = [dict(r) for r in c.execute("SELECT * FROM wishes ORDER BY created")]
    return {"checkins": ck, "notes": nt, "photos": ph, "wishes": ws, "config": get_config()}

# ---------- trips (每一次「来过」) ----------
@app.post("/api/checkin/{city}")
def checkin(city: str, body: dict = Body(default={})):
    check_city(city)
    origin = norm_city(city, body.get("origin")) if body.get("origin") else default_origin(city)
    with _lock, db() as c:
        now = time.time()
        tid = c.execute("INSERT INTO checkins(city,origin,created,updated) VALUES(?,?,?,?)", (city, origin, now, now)).lastrowid
        log(c, "checkin", city, {"id": tid, "origin": origin})
        return {"ok": True, "checkin": trip_row(c, tid)}

@app.put("/api/trip/{tid}")
def edit_trip(tid: int, body: dict = Body(default={})):
    with _lock, db() as c:
        t = trip_row(c, tid)
        for k in ("origin", "dest"):
            if k in body: c.execute(f"UPDATE checkins SET {k}=? WHERE id=?", (norm_city(t["city"], body.get(k)), tid))
        for k in ("date_start", "date_end", "remark"):
            if k in body:
                v = (body.get(k) or "").strip()[: 60 if k == "remark" else 10] or None
                if v and k != "remark" and not re.fullmatch(r"\d{4}(-\d{2}(-\d{2})?)?", v): raise HTTPException(400, "日期写成 2019 / 2019-08 / 2019-08-03")
                c.execute(f"UPDATE checkins SET {k}=? WHERE id=?", (v, tid))
        c.execute("UPDATE checkins SET updated=? WHERE id=?", (time.time(), tid))
        log(c, "trip", t["city"], {"id": tid, **body})
        return {"ok": True, "checkin": trip_row(c, tid)}

@app.delete("/api/trip/{tid}")
def delete_trip(tid: int):
    with _lock, db() as c:
        t = trip_row(c, tid); city = t["city"]
        c.execute("DELETE FROM checkins WHERE id=?", (tid,)); c.execute("DELETE FROM notes WHERE trip_id=?", (tid,))
        c.execute("DELETE FROM photos WHERE trip_id=?", (tid,))          # photo files stay in var/photos
        moved = []
        if not c.execute("SELECT 1 FROM checkins WHERE city=?", (city,)).fetchone():
            for r in c.execute("SELECT id, city FROM checkins WHERE origin=?", (city,)).fetchall():
                c.execute("UPDATE checkins SET origin=? WHERE id=?", (default_origin(r["city"]), r["id"])); moved.append(r["city"])
            c.execute("UPDATE checkins SET dest=NULL WHERE dest=?", (city,))
        log(c, "uncheck", city, {"id": tid, "reset_children": moved})
    return {"ok": True, "reset_children": moved}

# ---------- notes (随记) ----------
def note_row(c, nid):
    r = c.execute("SELECT * FROM notes WHERE id=?", (nid,)).fetchone()
    if r is None: raise HTTPException(404, "没有这段随记")
    return dict(r)

@app.post("/api/trip/{tid}/note")
def add_note(tid: int, body: dict = Body(default={})):
    text = (body.get("text") or "").strip()[:5000]
    if not text: raise HTTPException(400, "随记是空的")
    with _lock, db() as c:
        trip_row(c, tid); now = time.time()
        nid = c.execute("INSERT INTO notes(trip_id,text,created,updated) VALUES(?,?,?,?)", (tid, text, now, now)).lastrowid
        return {"ok": True, "note": note_row(c, nid)}

@app.put("/api/note/{nid}")
def edit_note(nid: int, body: dict = Body(default={})):
    text = (body.get("text") or "").strip()[:5000]
    if not text: raise HTTPException(400, "随记是空的，要删请用删除")
    with _lock, db() as c:
        note_row(c, nid); c.execute("UPDATE notes SET text=?, updated=? WHERE id=?", (text, time.time(), nid))
        return {"ok": True, "note": note_row(c, nid)}

@app.delete("/api/note/{nid}")
def delete_note(nid: int):
    with _lock, db() as c: note_row(c, nid); c.execute("DELETE FROM notes WHERE id=?", (nid,))
    return {"ok": True}

# ---------- photos (stored locally in var/photos, thumbnails made on upload) ----------
def photo_row(c, pid):
    r = c.execute("SELECT * FROM photos WHERE id=?", (pid,)).fetchone()
    if r is None: raise HTTPException(404, "没有这张照片")
    return dict(r)

@app.post("/api/photo/check")
def photo_check(body: dict = Body(default={})):
    want = set((body.get("sha256") or [])[:200])
    with db() as c:
        hits = {r["sha256"]: {"file": r["file"]} for r in c.execute("SELECT sha256, file FROM photos") if r["sha256"] in want}
    return {"hits": hits}

@app.post("/api/trip/{tid}/upload")
async def upload(tid: int, file: UploadFile = File(...)):
    from PIL import Image, ImageOps
    try:
        import pillow_heif; pillow_heif.register_heif_opener()
    except Exception: pass
    raw = await file.read()
    if len(raw) > 40 * 1024 * 1024: raise HTTPException(413, "照片太大（超过 40MB）")
    sha = hashlib.sha256(raw).hexdigest()
    with db() as c:
        trip_row(c, tid)
        ex = c.execute("SELECT * FROM photos WHERE sha256=? AND trip_id=?", (sha, tid)).fetchone()
        if ex: return {"ok": True, "photo": dict(ex), "dedup": True}
        same = c.execute("SELECT file FROM photos WHERE sha256=?", (sha,)).fetchone()
    try:
        im = Image.open(io.BytesIO(raw)); taken = None
        try:
            dt = im.getexif().get_ifd(0x8769).get(0x9003) or im.getexif().get(0x0132)
            if dt: taken = time.mktime(time.strptime(dt[:19], "%Y:%m:%d %H:%M:%S"))
        except Exception: pass
        im = ImageOps.exif_transpose(im)
    except Exception: raise HTTPException(400, "认不出这张图片")
    name = same["file"] if same else f"{sha[:12]}_{re.sub(r'[^\w.\-]+', '_', os.path.basename(file.filename or 'photo.jpg'))[-60:]}"
    if not same:
        open(os.path.join(PHOTOS, name), "wb").write(raw)
        for w in (600, 1600):
            x = im.copy(); x.thumbnail((w, w * 4)); x.convert("RGB").save(os.path.join(PHOTOS, f"{w}_{name}.jpg"), "JPEG", quality=85)
    with _lock, db() as c:
        pid = c.execute("INSERT INTO photos(trip_id,file,sha256,w,h,taken,created) VALUES(?,?,?,?,?,?,?)",
                        (tid, name, sha, im.width, im.height, taken, time.time())).lastrowid
        return {"ok": True, "photo": photo_row(c, pid), "dedup": bool(same)}

@app.get("/api/photo/img/{pid}")
def photo_img(pid: int, w: int = 600):
    with db() as c: r = photo_row(c, pid)
    f = os.path.join(PHOTOS, f"{1600 if w > 600 else 600}_{r['file']}.jpg")
    if not os.path.exists(f): raise HTTPException(404, "缩略图丢了")
    return FileResponse(f, media_type="image/jpeg", headers={"Cache-Control": "private, max-age=2592000"})

@app.put("/api/photo/{pid}")
def edit_photo(pid: int, body: dict = Body(default={})):
    with _lock, db() as c:
        photo_row(c, pid)
        if "caption" in body: c.execute("UPDATE photos SET caption=? WHERE id=?", ((body.get("caption") or "")[:1000], pid))
        if "tag" in body:
            t = body.get("tag") or None
            if t and t not in TAGS: raise HTTPException(400, "标签只能是 " + "/".join(TAGS))
            c.execute("UPDATE photos SET tag=? WHERE id=?", (t, pid))
        return {"ok": True, "photo": photo_row(c, pid)}

@app.delete("/api/photo/{pid}")
def delete_photo(pid: int):
    with _lock, db() as c: photo_row(c, pid); c.execute("DELETE FROM photos WHERE id=?", (pid,))
    return {"ok": True}

# ---------- wishes (想去：我 / 同行的人，各一颗星) ----------
@app.put("/api/wish/{city}")
def wish(city: str, body: dict = Body(default={})):
    check_city(city)
    by = body.get("by", "me")
    if by not in ("me", "partner"): raise HTTPException(400, "by 只能是 me 或 partner")
    note = (body.get("note") or "")[:200]
    with _lock, db() as c:
        c.execute("INSERT INTO wishes(city,by,note,created) VALUES(?,?,?,?) ON CONFLICT(city,by) DO UPDATE SET note=excluded.note", (city, by, note, time.time()))
    return {"ok": True}

@app.delete("/api/wish/{city}")
def unwish(city: str, by: str = "me"):
    with _lock, db() as c: n = c.execute("DELETE FROM wishes WHERE city=? AND by=?", (city, by)).rowcount
    return {"ok": True, "removed": n}

# ---------- write a page for a city that has none (pipeline/citygen.py) ----------
_gen = {"cid": None, "proc": None}
def gen_status(cid):
    try: return json.load(open(os.path.join(GEN_DIR, f"{cid}.json")))
    except Exception: return None

@app.post("/api/city/{cid}/gen")
def city_gen(cid: str, body: dict = Body(default={})):
    check_city(cid)
    if os.path.exists(os.path.join(CITY_DIR, cid + ".json")): return {"status": "done", "stage": "done"}
    if not os.environ.get("DEEPSEEK_API_KEY"): raise HTTPException(503, "服务器没配 DEEPSEEK_API_KEY，整理不了")
    p = _gen["proc"]
    if p and p.poll() is None:
        if _gen["cid"] == cid: return {"status": "running", **(gen_status(cid) or {})}
        raise HTTPException(409, f"正在整理{cities().get(_gen['cid'], {}).get('name', '')}，等它好了再来")
    with db() as c: n = c.execute("SELECT COUNT(*) FROM events WHERE act='gen' AND ts>?", (time.time() - 86400,)).fetchone()[0]
    if n >= (cfg().get("gen") or {}).get("daily_max", 20): raise HTTPException(429, f"今天已经整理了 {n} 座，明天再来")
    tier = "good" if body.get("pro") else "fast"
    json.dump({"stage": "start", "msg": "准备中", "ts": time.time()}, open(os.path.join(GEN_DIR, f"{cid}.json"), "w"))
    env = os.environ | {"STOPOVER_STATUS_DIR": GEN_DIR}
    _gen.update(cid=cid, proc=subprocess.Popen([sys.executable, GEN_PY, cid, tier], env=env,
                stdout=open(os.path.join(VAR, "gen.log"), "a"), stderr=subprocess.STDOUT, start_new_session=True))
    with _lock, db() as c: log(c, "gen", cid, {"tier": tier})
    return {"status": "running", "stage": "start", "msg": "准备中"}

@app.get("/api/city/{cid}/gen")
def city_gen_status(cid: str):
    s = gen_status(cid)
    if os.path.exists(os.path.join(CITY_DIR, cid + ".json")): return {"status": "done", **(s or {}), "stage": "done"}
    if not s: return {"status": "none"}
    p = _gen["proc"]
    if s["stage"] not in ("done", "error") and not (p and p.poll() is None and _gen["cid"] == cid):
        return {"status": "error", **s, "stage": "error", "msg": "整理中断了，再点一次试试"}
    return {"status": "error" if s["stage"] == "error" else "running", **s}

# ---------- add a place that isn't on the map (Wikidata) ----------
WD = "https://www.wikidata.org/w/api.php"
COUNTRY_FIX = {"People's Republic of China": "China", "United States": "United States of America", "Republic of China": "Taiwan",
               "Hong Kong": "Hong Kong S.A.R.", "Macau": "Macao S.A.R", "Czech Republic": "Czechia", "Kingdom of the Netherlands": "Netherlands",
               "Kingdom of Denmark": "Denmark", "Russian Federation": "Russia", "Republic of Korea": "South Korea"}
def wd(params):
    return json.loads(urllib.request.urlopen(urllib.request.Request(WD + "?" + urllib.parse.urlencode({"format": "json", **params}), headers=UA), timeout=20).read())
def _lab(ent, *langs):
    for l in langs:
        v = (ent.get("labels") or {}).get(l)
        if v: return v["value"]
    return ""
def place_entities(ids):
    e = wd({"action": "wbgetentities", "props": "claims|labels|descriptions", "languages": "zh-cn|zh-hans|zh|en", "ids": "|".join(ids)})["entities"]
    out, cids = [], set()
    for i in ids:
        ent = e.get(i) or {}; cl = ent.get("claims", {})
        try: co = cl["P625"][0]["mainsnak"]["datavalue"]["value"]
        except Exception: continue
        try: c_ = cl["P17"][0]["mainsnak"]["datavalue"]["value"]["id"]; cids.add(c_)
        except Exception: c_ = None
        desc = next((ent["descriptions"][l]["value"] for l in ("zh-cn", "zh-hans", "zh", "en") if l in (ent.get("descriptions") or {})), "")
        name = _lab(ent, "zh-cn", "zh-hans", "zh", "en")
        out.append({"qid": i, "name": name, "en": _lab(ent, "en") or name, "desc": desc, "lat": round(co["latitude"], 3), "lng": round(co["longitude"], 3), "_c": c_})
    if cids:
        ce = wd({"action": "wbgetentities", "props": "labels", "languages": "en", "ids": "|".join(cids)})["entities"]
        for x in out: lab = _lab(ce.get(x["_c"]) or {}, "en"); x["country"] = COUNTRY_FIX.get(lab, lab)
    for x in out: x.pop("_c", None); x.setdefault("country", "")
    return out

@app.get("/api/place/search")
def place_search(q: str):
    q = q.strip()[:60]
    if not q: return {"items": []}
    lang = "en" if re.fullmatch(r"[\x00-\x7f]+", q) else "zh"
    try:
        ids = [x["id"] for x in wd({"action": "wbsearchentities", "language": lang, "uselang": "zh", "limit": 12, "search": q}).get("search", [])]
        items = place_entities(ids) if ids else []
    except Exception as e: raise HTTPException(502, f"维基数据没连上：{e}")
    idx = json.load(open(CITIES_JSON)); mp = cities()
    near = [(x["id"], x["la"], x["lo"]) for x in idx["cities"]] + [(f"n_{x[1]}_{x[2]}", x[2], x[3]) for x in idx["extra"]]
    for it in items:
        hit = next((i for i, la, lo in near if abs(la - it["lat"]) < .05 and abs(lo - it["lng"]) < .05), None)
        if hit: it["exists"], it["exists_name"] = hit, mp.get(hit, {}).get("name", "")
    return {"items": items[:8]}

@app.post("/api/place")
def place_add(body: dict = Body(default={})):
    import fcntl
    qid = body.get("qid") or ""
    if not re.fullmatch(r"Q\d+", qid): raise HTTPException(400, "缺维基数据编号")
    it = (place_entities([qid]) or [None])[0]
    if not it: raise HTTPException(404, "这个条目没有坐标，加不了")
    en = it["en"].replace("/", " "); cid = f"n_{en}_{it['lat']}"; row = [it["name"], en, it["lat"], it["lng"], it["country"]]
    with open(os.path.join(os.path.dirname(CITIES_JSON), ".cities.lock"), "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        cj = json.load(open(CITIES_JSON))
        if not any(f"n_{x[1]}_{x[2]}" == cid for x in cj["extra"]) and not any(x["id"] == cid for x in cj["cities"]):
            cj["extra"].append(row); tmp = CITIES_JSON + ".tmp"
            json.dump(cj, open(tmp, "w"), ensure_ascii=False, separators=(",", ":")); os.replace(tmp, CITIES_JSON)
    return {"ok": True, "id": cid, "city": row}

@app.get("/api/health")
def health():
    return {"ok": True, "cities": len(cities())}

app.mount("/", StaticFiles(directory=WEB, html=True), name="web")

if __name__ == "__main__":
    init()
    uvicorn.run(app, host=os.environ.get("STOPOVER_HOST", "127.0.0.1"), port=int(os.environ.get("STOPOVER_PORT", "8000")), log_level="warning")
