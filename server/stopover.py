#!/usr/bin/env python3
"""Stopover server: a small FastAPI + SQLite backend that also serves the web app.

    pip install -r server/requirements.txt
    cp server/config.example.json server/config.json      # names, home, default origins, clocks, partner
    python3 server/stopover.py                             # → http://localhost:8000

Data lives in var/ (git-ignored): var/stopover.db, var/photos/, var/vapid.json.
City pages are static files in web/data/; pipeline/citygen.py writes new ones on demand.
Environment: STOPOVER_VAR (data dir), STOPOVER_CONFIG (config file), STOPOVER_HOST / STOPOVER_PORT.

Who is calling:
  - a request carrying `Authorization: Bearer <partner_key>` (config.partner_key, when set) is the partner;
  - everything else is "me". There is no login: run it locally or behind your own auth.
The partner (often an AI companion) can read everything, comment, star, and hand things to me;
it cannot edit my trips, notes or photos. It talks to the server through /mcp, /api/partner/* or cli/stopover.py.
"""
import base64, hashlib, hmac, io, json, os, random, re, secrets, sqlite3, subprocess, sys, threading, time, urllib.parse, urllib.request
from contextlib import contextmanager
from fastapi import FastAPI, HTTPException, Body, UploadFile, File, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
import uvicorn

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, "web")
VAR = os.environ.get("STOPOVER_VAR", os.path.join(ROOT, "var"))
DB = os.path.join(VAR, "stopover.db")
PHOTOS = os.path.join(VAR, "photos")
CACHE = os.path.join(VAR, "cache")
CITIES_JSON = os.path.join(WEB, "data", "cities.json")
CITY_DIR = os.path.join(WEB, "data", "city")
CFG_FILE = os.environ.get("STOPOVER_CONFIG", os.path.join(ROOT, "server", "config.json"))
GEN_PY = os.path.join(ROOT, "pipeline", "citygen.py")
GEN_DIR = os.path.join(VAR, "gen")
TAGS = ["美食", "风景", "名胜", "艺术品", "个人照片"]
UA = {"User-Agent": f"stopover/2.0 ({os.environ.get('STOPOVER_CONTACT', 'https://github.com/fishisfish0614/stopover')})"}
VERSION = "2.0"

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
    os.makedirs(PHOTOS, exist_ok=True); os.makedirs(GEN_DIR, exist_ok=True); os.makedirs(CACHE, exist_ok=True)
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
        CREATE TABLE IF NOT EXISTS comments(id INTEGER PRIMARY KEY AUTOINCREMENT, target TEXT, who TEXT, text TEXT, reply_to INTEGER, created REAL);
        CREATE INDEX IF NOT EXISTS cm_target ON comments(target);
        CREATE TABLE IF NOT EXISTS shares(id INTEGER PRIMARY KEY AUTOINCREMENT, created REAL, who TEXT, items TEXT, note TEXT,
            status TEXT DEFAULT 'pending', sent REAL);
        CREATE TABLE IF NOT EXISTS push_subs(id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT, ident TEXT UNIQUE, data TEXT, env TEXT, created REAL);
        """)
        # columns added in v2 (also upgrades databases made by earlier builds)
        for table, cols in (("shares", (("img", "INTEGER DEFAULT 1"), ("read_at", "REAL"), ("err", "TEXT"), ("tries", "INTEGER DEFAULT 0"),
                                        ("key", "TEXT"), ("taken_at", "REAL"))),
                            ("comments", (("key", "TEXT"), ("sent", "REAL"), ("tries", "INTEGER DEFAULT 0"), ("taken_at", "REAL")))):
            have = [r[1] for r in c.execute(f"PRAGMA table_info({table})")]
            for col, typ in cols:
                if col not in have: c.execute(f"ALTER TABLE {table} ADD COLUMN {col} {typ}")
            for r in c.execute(f"SELECT id FROM {table} WHERE key IS NULL").fetchall():
                c.execute(f"UPDATE {table} SET key=? WHERE id=?", (new_key(), r[0]))

def new_key(): return secrets.token_urlsafe(12)

def log(c, act, city, data=None):
    c.execute("INSERT INTO events(ts,act,city,data) VALUES(?,?,?,?)", (time.time(), act, city, json.dumps(data or {}, ensure_ascii=False)))

_cities = {"mtime": 0}
def _load_cities():
    m = os.path.getmtime(CITIES_JSON)
    if m != _cities["mtime"]:
        d = json.load(open(CITIES_JSON)); mp = {}
        for x in d["cities"]: mp[x["id"]] = {"name": x["n"], "en": x.get("e") or x["n"], "country": x["c"], "has": 1}
        for name, en, lat, lng, country in d["extra"]: mp[f"n_{en}_{lat}"] = {"name": name, "en": en, "country": country, "has": 0}
        _cities.update(mtime=m, map=mp, cz=d.get("cz") or {})
    return _cities
def cities():
    """city id → {name, en, country, has}; reloads when cities.json changes (citygen / place add)."""
    return _load_cities()["map"]
def country_zh(en): return _load_cities()["cz"].get(en, en or "")
def cname(city): return cities().get(city, {}).get("name", city)

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

# ---------- who is calling: me (no key) / partner (Bearer partner_key) ----------
def partner_key(): return str(cfg().get("partner_key") or "").strip()
def nm(w):
    c = cfg()
    return (c.get("partner") or "TA") if w == "partner" else (c.get("me") or "我")

def ident(request):
    k = partner_key()
    if not k: return "me"
    h = request.headers.get("authorization") or ""
    if h[:7].lower() == "bearer " and hmac.compare_digest(h[7:].strip().encode(), k.encode()): return "partner"
    return "me"

def who(request): return getattr(request.state, "who", "me")

ME_ONLY = ("/api/checkin", "/api/trip", "/api/photo", "/api/note", "/api/place", "/api/push")   # writes only I can make
@app.middleware("http")
async def _who_gate(request, call_next):
    w = ident(request); request.state.who = w
    p = request.url.path
    if w == "partner" and request.method not in ("GET", "HEAD") and p.startswith(ME_ONLY) and p != "/api/photo/check":
        return JSONResponse({"detail": f"这是{nm('me')}的经停：{nm('partner')}只能看、留言、点星、递东西"}, status_code=403)
    return await call_next(request)

def need_partner(request):
    if who(request) != "partner":
        raise HTTPException(401, "需要 partner 钥匙（Authorization: Bearer <partner_key>）" if partner_key() else "服务端没有设置 partner_key")

# ---------- read ----------
def features():
    f = cfg().get("features") or {}
    return {"share": f.get("share", True) is not False, "push_apns": apns_ok(), "push_web": web_push_ok()}

@app.get("/api/config")
def get_config():
    c = cfg()
    return {k: c.get(k) for k in ("me", "partner", "home", "default_origin", "domestic_countries", "clocks")} | {"tags": TAGS, "features": features()}

def share_out(r):
    return {k: r[k] for k in ("id", "created", "who", "note", "status", "sent", "img", "read_at", "err", "key")} | {"items": json.loads(r["items"])}

@app.get("/api/state")
def state():
    with db() as c:
        ck = [dict(r) for r in c.execute("SELECT * FROM checkins ORDER BY id")]
        nt = [dict(r) for r in c.execute("SELECT * FROM notes ORDER BY trip_id, id")]
        ph = [dict(r) for r in c.execute("SELECT id, trip_id, caption, tag, w, h, taken, created FROM photos ORDER BY trip_id, COALESCE(taken, created), id")]
        ws = [dict(r) for r in c.execute("SELECT * FROM wishes ORDER BY created")]
        cm = [dict(r) for r in c.execute("SELECT id, target, who, text, reply_to, created, key FROM comments ORDER BY id")]
        sh = [share_out(r) for r in c.execute("SELECT * FROM shares ORDER BY id")]
    return {"checkins": ck, "notes": nt, "photos": ph, "wishes": ws, "comments": cm, "shares": sh, "config": get_config()}

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
        pids = [r[0] for r in c.execute("SELECT id FROM photos WHERE trip_id=?", (tid,))]
        nids = [r[0] for r in c.execute("SELECT id FROM notes WHERE trip_id=?", (tid,))]
        c.execute("DELETE FROM checkins WHERE id=?", (tid,)); c.execute("DELETE FROM notes WHERE trip_id=?", (tid,))
        c.execute("DELETE FROM photos WHERE trip_id=?", (tid,))          # photo files stay in var/photos
        for t_ in [f"trip:{tid}"] + [f"photo:{p}" for p in pids] + [f"note:{n}" for n in nids]: c.execute("DELETE FROM comments WHERE target=?", (t_,))
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
    with _lock, db() as c:
        note_row(c, nid); c.execute("DELETE FROM notes WHERE id=?", (nid,)); c.execute("DELETE FROM comments WHERE target=?", (f"note:{nid}",))
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

def photo_file(c, pid, w=600):
    r = photo_row(c, pid)
    f = os.path.join(PHOTOS, f"{1600 if w > 600 else 600}_{r['file']}.jpg")
    return f if os.path.exists(f) else None

_secret = {}
def secret():
    """签名照片外链用的密钥：第一次要用时生成在 var/secret（0600，git 忽略）"""
    if "k" not in _secret:
        f = os.path.join(VAR, "secret")
        with _vapid_lock:
            if not os.path.exists(f):
                fd = os.open(f, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, "w") as fh: fh.write(secrets.token_hex(32))
            _secret["k"] = open(f).read().strip().encode()
    return _secret["k"]

def photo_sig(pid, w): return hmac.new(secret(), f"photo:{int(pid)}:{int(w)}".encode(), hashlib.sha256).hexdigest()[:32]

@app.get("/api/photo/img/{pid}")
def photo_img(pid: int, w: int = 600, s: str = None):
    """带 s= 的是发给伴侣 / webhook / 卡片的签名外链（绑定 pid 和 w），签名不对 403；不带 s 的视为在 me 自己的鉴权后面"""
    if s is not None and not hmac.compare_digest(s, photo_sig(pid, w)): raise HTTPException(403, "照片链接签名不对")
    with db() as c: f = photo_file(c, pid, w)
    if not f: raise HTTPException(404, "缩略图丢了")
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
    with _lock, db() as c:
        photo_row(c, pid); c.execute("DELETE FROM photos WHERE id=?", (pid,)); c.execute("DELETE FROM comments WHERE target=?", (f"photo:{pid}",))
    return {"ok": True}

# ---------- wishes (想去：我 / 同行的人，各一颗星；谁的星由身份决定) ----------
def wish_by(request, asked):
    w = who(request); asked = asked or w
    if asked not in ("me", "partner"): raise HTTPException(400, "by 只能是 me 或 partner")
    if asked == w: return w
    if w == "me" and not partner_key(): return asked          # v1 compatibility: no partner_key → the web/API may write either star
    raise HTTPException(403, f"只能改自己的星星（你是 {w}）")

def set_wish(by, city, note):
    check_city(city); note = (note or "")[:200]
    with _lock, db() as c:
        c.execute("INSERT INTO wishes(city,by,note,created) VALUES(?,?,?,?) ON CONFLICT(city,by) DO UPDATE SET note=excluded.note", (city, by, note, time.time()))
        log(c, "wish", city, {"by": by})
    if by == "partner": push_me("wish", {"city": city, "target": ""}, city=cname(city), note=note)

def del_wish(by, city):
    with _lock, db() as c: return c.execute("DELETE FROM wishes WHERE city=? AND by=?", (city, by)).rowcount

@app.put("/api/wish/{city}")
def wish(city: str, request: Request, body: dict = Body(default={})):
    set_wish(wish_by(request, body.get("by")), city, body.get("note"))
    return {"ok": True}

@app.delete("/api/wish/{city}")
def unwish(city: str, request: Request, by: str = None):
    return {"ok": True, "removed": del_wish(wish_by(request, by), city)}

# ---------- 递送 shares：me → partner（合并后经 inject webhook / 收件箱），partner → me（直接送到 + 推送） ----------
def share_row(c, sid):
    r = c.execute("SELECT * FROM shares WHERE id=?", (sid,)).fetchone()
    if r is None: raise HTTPException(404, "没有这次递送")
    return dict(r)

def clean_items(c, items):
    if not isinstance(items, list) or not items or len(items) > 100: raise HTTPException(400, "没选东西")
    out = []
    for it in items:
        t = (it or {}).get("type")
        try:
            if t == "photo": photo_row(c, int(it["id"])); out.append({"type": "photo", "id": int(it["id"])})
            elif t == "note": note_row(c, int(it["id"])); out.append({"type": "note", "id": int(it["id"])})
            elif t == "trip": trip_row(c, int(it["id"])); out.append({"type": "trip", "id": int(it["id"])})
            elif t == "city": check_city(it.get("city", "")); out.append({"type": "city", "city": it["city"]})
            elif t in ("sight", "food"): check_city(it.get("city", "")); out.append({"type": t, "city": it["city"], "i": int(it.get("i", 0))})
            else: raise HTTPException(400, f"不认识的类型：{t}")
        except (KeyError, TypeError, ValueError): raise HTTPException(400, f"这一样缺编号：{it}")
    return out

def add_share(w, items, note="", img=True):
    note = (note or "").strip()[:500]
    with _lock, db() as c:
        clean = clean_items(c, items)
        if w == "partner" and any(it["type"] in ("trip", "photo", "note") for it in clean):
            raise HTTPException(400, f"{nm('partner')}能递的是城市 / 景点 / 美食")
        st, now = ("sent", time.time()) if w == "partner" else ("pending", None)
        sid = c.execute("INSERT INTO shares(created,who,items,note,status,sent,img,key) VALUES(?,?,?,?,?,?,?,?)",
                        (time.time(), w, json.dumps(clean, ensure_ascii=False), note, st, now, 1 if img else 0, new_key())).lastrowid
        log(c, "share", "", {"id": sid, "by": w, "n": len(clean)})
    if w == "partner":
        it = clean[0]; push_me("share", {"city": it.get("city", ""), "target": "", "share_id": sid}, what=item_label(it), note=note)
    else: _deliver_kick.set()
    return sid, st

@app.post("/api/share")
def share(request: Request, body: dict = Body(default={})):
    sid, st = add_share(who(request), body.get("items"), body.get("note"), body.get("img", True))
    return {"ok": True, "id": sid, "status": st}

@app.put("/api/share/{sid}/read")
def share_read(sid: int):
    """me 点开了 partner 递来的那一样 → 已读（收件处的小红点）"""
    with _lock, db() as c:
        share_row(c, sid); c.execute("UPDATE shares SET read_at=? WHERE id=? AND read_at IS NULL", (time.time(), sid))
    return {"ok": True}

@app.delete("/api/share/{sid}")
def unshare(sid: int, request: Request):
    """撤回：只能撤自己的、还没送出去的"""
    with _lock, db() as c:
        n = c.execute("DELETE FROM shares WHERE id=? AND status='pending' AND who=?", (sid, who(request))).rowcount
        if n: log(c, "unshare", "", {"id": sid})
    return {"ok": True, "removed": n}

# ---------- 对话 comments：挂在城市 / 某一次 / 随记 / 照片 / 某次递送下 ----------
def check_target(c, t):
    k, _, v = (t or "").partition(":")
    try:
        if k == "city": check_city(v)
        elif k == "trip": trip_row(c, int(v))
        elif k == "photo": photo_row(c, int(v))
        elif k == "note": note_row(c, int(v))
        elif k == "share": share_row(c, int(v))
        else: raise HTTPException(400, "target 是 city:/trip:/note:/photo:/share: 加编号")
    except ValueError: raise HTTPException(400, f"target 写错了：{t}")

def add_comment(w, target, text, reply_to=None):
    text = (text or "").strip()[:2000]
    if not text: raise HTTPException(400, "话是空的")
    with _lock, db() as c:
        check_target(c, target)
        if reply_to:
            try: reply_to = int(str(reply_to).split(":")[-1])
            except ValueError: raise HTTPException(400, "reply_to 是评论编号")
            if not c.execute("SELECT 1 FROM comments WHERE id=?", (reply_to,)).fetchone(): raise HTTPException(404, f"没有 c:{reply_to} 这条")
        cid = c.execute("INSERT INTO comments(target,who,text,reply_to,created,key) VALUES(?,?,?,?,?,?)",
                        (target, w, text, reply_to or None, time.time(), new_key())).lastrowid
        log(c, "comment", target, {"id": cid, "by": w})
        r = dict(c.execute("SELECT id, target, who, text, reply_to, created FROM comments WHERE id=?", (cid,)).fetchone())
        label, city = target_label(c, target, "me"), target_city(c, target)
    if w == "partner": push_me("comment", {"city": city or "", "target": target}, where=label, text=text)
    else: _deliver_kick.set()
    return r

@app.post("/api/comment")
def comment(request: Request, body: dict = Body(default={})):
    return {"ok": True, "comment": add_comment(who(request), body.get("target") or "", body.get("text"), body.get("reply_to"))}

@app.delete("/api/comment/{cid}")
def comment_del(cid: int, request: Request):
    with _lock, db() as c:
        n = c.execute("DELETE FROM comments WHERE id=? AND who=?", (cid, who(request))).rowcount   # 只能删自己的
        if n: log(c, "uncomment", "", {"id": cid})
    return {"ok": True, "removed": n}

# ---------- 文字描述：标签、条目、递送摘要（推送 / inject / 收件箱 / MCP 共用） ----------
def cut(t, n): t = re.sub(r"\s+", " ", t or "").strip(); return t if len(t) <= n else t[:n] + "…"

def city_page(city):
    if not re.fullmatch(r"[\w\-.]+", city or ""): return {}
    try: return json.load(open(os.path.join(CITY_DIR, city + ".json")))
    except Exception: return {}

def public(): return str(cfg().get("public_url") or "").rstrip("/")
def abs_url(path):
    """path relative to the site root → absolute with public_url, or left relative"""
    if re.match(r"https?://", path): return path
    p = public(); return f"{p}/{path}" if p else path

def trip_label(c, tid):
    t = trip_row(c, tid); ts = [r["id"] for r in c.execute("SELECT id FROM checkins WHERE city=? ORDER BY id", (t["city"],))]
    return f"{cname(t['city'])} · 第{ts.index(tid) + 1}次" if len(ts) > 1 else cname(t["city"])

def item_city(c, it):
    if it.get("city"): return it["city"]
    try:
        if it["type"] == "trip": return trip_row(c, it["id"])["city"]
        if it["type"] == "photo": return trip_row(c, photo_row(c, it["id"])["trip_id"])["city"]
        if it["type"] == "note": return trip_row(c, note_row(c, it["id"])["trip_id"])["city"]
    except HTTPException: return ""
    return ""

def target_city(c, t):
    k, _, v = (t or "").partition(":")
    if k == "city": return v
    if k == "share":
        try: return item_city(c, json.loads(share_row(c, int(v))["items"])[0])
        except (HTTPException, IndexError, ValueError): return ""
    try: return item_city(c, {"type": k, "id": int(v)})
    except (ValueError, KeyError): return ""

def sf_item(it):
    pg = city_page(it["city"]); arr = pg.get("sights" if it["type"] == "sight" else "foods") or []
    return arr[it["i"]] if 0 <= it["i"] < len(arr) else {}

def item_label(it):
    if it["type"] == "city": return f"一座城：{cname(it['city'])}"
    return f"{cname(it['city'])}的{'景点' if it['type'] == 'sight' else '美食'}「{sf_item(it).get('name', '')}」"

def share_what(c, items):
    k = {}
    for it in items: k[it["type"]] = k.get(it["type"], 0) + 1
    if len(items) == 1 and items[0]["type"] in ("city", "sight", "food"):
        it = items[0]
        return "这座城" if it["type"] == "city" else f"{'景点' if it['type'] == 'sight' else '美食'}「{sf_item(it).get('name', '')}」"
    if k.get("trip") and len(items) == 1: return "整张票"
    if set(k) <= {"trip", "note", "photo"}:
        return " + ".join(x for x in ["整张票" if k.get("trip") else "", f"{k['note']} 段随记" if k.get("note") else "", f"{k['photo']} 张照片" if k.get("photo") else ""] if x)
    return f"{len(items)} 样"

def share_label(c, r):
    items = json.loads(r["items"]); w = share_what(c, items); city = cname(item_city(c, items[0]))
    return city if w == "这座城" else f"{city}的{w}"

def target_label(c, t, view):
    """where a comment hangs, worded for the reader `view` (me / partner)"""
    k, _, v = (t or "").partition(":")
    try:
        if k == "city": return cname(v)
        if k == "trip": return trip_label(c, int(v))
        if k == "photo": p = photo_row(c, int(v)); return f"{trip_label(c, p['trip_id'])}的照片" + (f"「{cut(p['caption'], 12)}」" if p["caption"] else "")
        if k == "note": n = note_row(c, int(v)); return f"{trip_label(c, n['trip_id'])}的随记「{cut(n['text'], 12)}」"
        if k == "share":
            r = share_row(c, int(v)); owner = "你" if r["who"] == view else nm(r["who"])
            return f"{owner}递的「{share_label(c, r)}」"
    except (HTTPException, ValueError, IndexError): pass
    return t

def short_ref(t):
    k, _, v = t.partition(":")
    return cname(v) if k == "city" else {"trip": "t:", "photo": "p:", "note": "n:", "share": "d:"}.get(k, "") + v

def wiki_img(it):
    pg = city_page(it["city"])
    if it["type"] == "city":   # 没题图的城用第一张有图的景点顶上
        h = (pg.get("hero") or [{}])[0]
        return h.get("u") or next(((x.get("img") or {}).get("u") for x in pg.get("sights") or [] if x.get("img")), None)
    return (sf_item(it).get("img") or {}).get("u")

def wiki_ref(it):
    if it["type"] == "city": return cname(it["city"])
    return f"{'s' if it['type'] == 'sight' else 'f'}:{cname(it['city'])}/{it['i'] + 1}"

def photo_url(pid, w=600): return abs_url(f"api/photo/img/{pid}?w={w}&s={photo_sig(pid, w)}")

def describe(c, it, want_img, imgs, mx):
    """一样东西 → 几行给 partner 读的文字；要附的图（绝对链接）塞进 imgs（最多 mx 张）"""
    L, M = [], nm("me")
    def add(u):
        if not u: return False
        if u in imgs: return True
        if len(imgs) >= mx: return False
        imgs.append(u); return True
    t = it["type"]
    if t == "trip":
        tr = trip_row(c, it["id"]); o, d = cities().get(tr["origin"] or "", {}).get("name"), cities().get(tr["dest"] or "", {}).get("name")
        L.append("· " + " · ".join(x for x in [trip_label(c, tr["id"]), (tr["date_start"] or "").replace("-", "."), f"从{o}出发" if o else "", f"回到{d}" if d else ""] if x) + f"（t:{tr['id']}）")
        if tr["remark"]: L.append(f"  备注：{tr['remark']}")
        ns = [dict(r) for r in c.execute("SELECT id, text FROM notes WHERE trip_id=? ORDER BY id", (tr["id"],))]
        if ns: L.append(f"  随记 {len(ns)} 段：" + "／".join(f"「{cut(n['text'], 60)}」(n:{n['id']})" for n in ns[:3]) + ("……" if len(ns) > 3 else ""))
        ps = [dict(r) for r in c.execute("SELECT id, caption FROM photos WHERE trip_id=? ORDER BY COALESCE(taken, created), id", (tr["id"],))]
        if ps:
            got = [p for p in ps if add(photo_url(p["id"]))]
            L.append(f"  照片 {len(ps)} 张" + (f"（附了 {len(got)} 张）" if got else "") + "：" + "　".join(f"p:{p['id']}" + (f"「{cut(p['caption'], 20)}」" if p["caption"] else "") for p in ps))
        L.append(f"  → 目录：look t:{tr['id']}" + ("　随记全文：read n:编号" if ns else "") + ("　照片：img p:编号" if ps else ""))
    elif t == "note":
        n = note_row(c, it["id"])
        L.append(f"· {trip_label(c, n['trip_id'])}的一段随记（n:{n['id']}）："); L.append("  「" + cut(n["text"], 600) + "」")
    elif t == "photo":
        p = photo_row(c, it["id"]); ok = add(photo_url(p["id"]))
        L.append(f"· {trip_label(c, p['trip_id'])}的照片 p:{p['id']}" + ("（附图）" if ok else f"（图：img p:{p['id']}）") + (f"「{p['caption']}」" if p["caption"] else ""))
    else:
        pg = city_page(it["city"]); ok = add(wiki_img(it)) if want_img else False
        img_part = "（附图）" if ok else f"（图：img {wiki_ref(it)}）"
        if t == "city":
            co = cities().get(it["city"], {})
            L.append(f"· 一座城：{cname(it['city'])}（{co.get('en', '')}{' · ' + country_zh(co.get('country')) if co.get('country') else ''}）{img_part}")
            if pg.get("dek"): L.append(f"  {pg['dek']}")
            L.append(f"  → 目录：look {cname(it['city'])}" + (f"　历史和文化：read {cname(it['city'])}" if pg else f"　还没有资料：gen {cname(it['city'])}"))
        else:
            x = sf_item(it)
            L.append(f"· {cname(it['city'])}的{'景点' if t == 'sight' else '美食'}「{x.get('name', '')}」{(' ' + x['orig']) if x.get('orig') and x.get('orig') != x.get('name') else ''}{img_part}")
            if x.get("intro"): L.append(f"  {cut(x['intro'], 90)}")
            L.append(f"  → 全文：read {wiki_ref(it)}")
    return L

def digest(c, shs, rps, mx):
    """me 递的 + me 回的话 → (正文, 图片链接, 卡片, shares, replies)，给 partner 看"""
    M = nm("me"); imgs, lines, cards, so, ro = [], [], [], [], []
    if shs:
        refs = [it for r in shs for it in json.loads(r["items"])]
        lines.append(f"{M}递给你{f' {len(refs)} 样' if len(refs) > 1 else ''}：")
        for r in shs:
            for it in json.loads(r["items"]):
                try: lines += describe(c, it, bool(r["img"]), imgs, mx)
                except HTTPException: lines.append("· （有一样已经被删掉了）")
            if r["note"]: lines.append(f"  {M}说：{r['note']}")
            lines.append(f"  回这一样：say d:{r['id']} \"…\"")
            cd = share_card(c, r); cards.append({"url": cd["url"], "json": cd})
            so.append({"id": r["id"], "created": r["created"], "items": json.loads(r["items"]), "note": r["note"] or "", "card": cd["url"]})
    if rps:
        if lines: lines.append("")
        lines.append(f"{M}回你的话：")
        for m in rps:
            where = target_label(c, m["target"], "partner")
            q = c.execute("SELECT who, text FROM comments WHERE id=?", (m["reply_to"],)).fetchone() if m["reply_to"] else None
            lines.append(f"· 在{where}（c:{m['id']}）" + (f"，回{'你' if q['who'] == 'partner' else '自己'}的「{cut(q['text'], 20)}」" if q else "") + f"：{m['text']}")
            lines.append(f"  → 回：say {short_ref(m['target'])} \"…\" reply_to=c:{m['id']}")
            cd = comment_card(c, m); cards.append({"url": cd["url"], "json": cd})
            ro.append({"id": m["id"], "created": m["created"], "target": m["target"], "where": where, "text": m["text"], "reply_to": m["reply_to"], "card": cd["url"]})
    return "\n".join(lines), imgs, cards, so, ro

# ---------- 卡片：一张递送 / 一句话 → 小卡片（JSON + 可 iframe 的 HTML），给聊天前端用 ----------
def city_sub(city):
    co = cities().get(city, {}); pg = city_page(city)
    return " · ".join(x for x in [pg.get("en") or co.get("en", ""), country_zh(co.get("country") or pg.get("country", ""))] if x)

def share_card(c, r):
    items = json.loads(r["items"]); first = items[0]; city = item_city(c, first); P = nm("partner")
    w = share_what(c, items); image = ""
    t = first["type"]
    if t in ("trip", "photo", "note"):
        tid = first["id"] if t == "trip" else (photo_row(c, first["id"])["trip_id"] if t == "photo" else note_row(c, first["id"])["trip_id"])
        tr = trip_row(c, tid)
        if w == "整张票":
            sub = "整张票" + (f" · {tr['date_start'].replace('-', '.')}" if tr["date_start"] else "")
            p = c.execute("SELECT id FROM photos WHERE trip_id=? ORDER BY COALESCE(taken, created), id LIMIT 1", (tid,)).fetchone()
            image = photo_url(p["id"]) if p else ""
        else:
            sub = w; ph = next((x for x in items if x["type"] == "photo"), None); image = photo_url(ph["id"]) if ph else ""
    elif len(items) == 1:
        sub = city_sub(city) if t == "city" else w
        image = (wiki_img(first) or "") if r["img"] else ""
    else:
        sub = f"{cname(city)} · {len(items)} 样"; image = (wiki_img(first) or "") if r["img"] else ""
    me = r["who"] == "me"
    return {"kind": "share", "id": r["id"], "who": r["who"], "theme": "light" if me else "dark",
            "eyebrow": f"STOPOVER · 递给{P}" if me else f"STOPOVER · {P}递给你", "title": cname(city), "subtitle": sub,
            "body": r["note"] or "", "image": image or None, "link": abs_url(f"?city={urllib.parse.quote(city)}"), "city": city,
            "url": abs_url(f"card/share/{r['id']}?k={r['key']}")}

def comment_card(c, m):
    P, t = nm("partner"), m["target"]; k, _, v = t.partition(":"); city = target_city(c, t); mine = m["who"] == "me"
    q = c.execute("SELECT who, text FROM comments WHERE id=?", (m["reply_to"],)).fetchone() if m["reply_to"] else None
    if q: sub = f"回{'你' if q['who'] == 'me' else P}：「{cut(q['text'], 24)}」"   # worded for me's chat view
    elif k == "share":
        try: owner = share_row(c, int(v))["who"]
        except (HTTPException, ValueError): owner = ""
        sub = "接着递的这一样" if owner == m["who"] else ("回你递的这一样" if owner == "me" else f"回{P}递的这一样")
    else: sub = {"trip": "在这一次下面说", "photo": "在这张照片下面说", "note": "在这段随记下面说", "city": "在这座城下面说"}.get(k, "")
    image = photo_url(int(v)) if k == "photo" else None
    return {"kind": "comment", "id": m["id"], "who": m["who"], "theme": "light" if mine else "dark",
            "eyebrow": f"STOPOVER · 回{P}" if mine else f"STOPOVER · {P}说", "title": cname(city) if city else t, "subtitle": sub,
            "body": m["text"], "image": image, "link": abs_url(f"?city={urllib.parse.quote(city)}") if city else abs_url(""), "city": city, "target": t,
            "url": abs_url(f"card/comment/{m['id']}?k={m['key']}")}

def _keyed(c, table, rid, k):
    r = c.execute(f"SELECT * FROM {table} WHERE id=?", (rid,)).fetchone()
    if r is None or not k or not r["key"] or not hmac.compare_digest(str(k), r["key"]): raise HTTPException(403, "卡片钥匙不对")
    return dict(r)

def esc(s): return str(s or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")
GLOBE_SVG = ('<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round">'
             '<circle cx="12" cy="12" r="8.5"/><ellipse cx="12" cy="12" rx="3.6" ry="8.5"/><path d="M3.8 9h16.4M3.8 15h16.4"/></svg>')
def card_html(d, theme=None):
    th = theme if theme in ("light", "dark") else d["theme"]
    return f"""<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(d['title'])} · Stopover</title><meta name="robots" content="noindex">
<style>
html,body{{margin:0;padding:0;background:transparent}}
.c{{display:block;box-sizing:border-box;width:100%;max-width:360px;border-radius:20px;padding:14px 16px 16px;text-decoration:none;
  font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Noto Sans SC","Hiragino Sans GB",system-ui,sans-serif;-webkit-font-smoothing:antialiased}}
.light{{background:#fdf6d8;color:#22252b}}.dark{{background:#23252b;color:#f2f2f4}}
.h{{display:flex;align-items:center;gap:12px}}
.g{{flex:none;width:44px;height:44px;border-radius:50%;background:#3b5b8a;display:flex;align-items:center;justify-content:center}}.g svg{{width:26px;height:26px}}
.t{{min-width:0;display:flex;flex-direction:column;gap:2px}}
.e{{font-size:10.5px;font-weight:500;letter-spacing:.14em;text-transform:uppercase;opacity:.55;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}}
.n{{font-size:18px;font-weight:500;line-height:1.3;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}}
.s{{font-size:13px;line-height:1.35;opacity:.6;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}}
.b{{margin:12px 0 0;font-size:16px;line-height:1.5;white-space:pre-wrap;word-break:break-word}}
</style>
<a class="c {th}" href="{esc(d['link'])}" target="_blank" rel="noopener"><div class="h"><span class="g">{GLOBE_SVG}</span>
<div class="t"><span class="e">{esc(d['eyebrow'])}</span><span class="n">{esc(d['title'])}</span>{f'<span class="s">{esc(d["subtitle"])}</span>' if d['subtitle'] else ''}</div></div>
{f'<p class="b">{esc(d["body"])}</p>' if d['body'] else ''}</a></html>"""

@app.get("/api/share/{sid}/card")
def share_card_json(sid: int, k: str = ""):
    with db() as c: return share_card(c, _keyed(c, "shares", sid, k))

@app.get("/card/share/{sid}", response_class=HTMLResponse)
def share_card_page(sid: int, k: str = "", theme: str = ""):
    with db() as c: return HTMLResponse(card_html(share_card(c, _keyed(c, "shares", sid, k)), theme))

@app.get("/api/comment/{cid}/card")
def comment_card_json(cid: int, k: str = ""):
    with db() as c: return comment_card(c, _keyed(c, "comments", cid, k))

@app.get("/card/comment/{cid}", response_class=HTMLResponse)
def comment_card_page(cid: int, k: str = "", theme: str = ""):
    with db() as c: return HTMLResponse(card_html(comment_card(c, _keyed(c, "comments", cid, k)), theme))

# ---------- inject webhook：me 递的 / 回的，安静 merge_seconds 秒后合成一条 POST 给 partner 的聊天程序 ----------
INJECT_DEF = {"url": "", "headers": {}, "merge_seconds": 120, "max_images": 9, "timeout": 30,
              "template": "〔经停 Stopover · 来自{me}〕\n{body}"}
def cfg_inject(): return INJECT_DEF | (cfg().get("inject") or {})

class _Safe(dict):
    def __missing__(self, k): return "{" + k + "}"

def _bg(fn, *a, **k): threading.Thread(target=fn, args=a, kwargs=k, daemon=True).start()

def post_json(url, body, headers=None, timeout=30):
    try:
        req = urllib.request.Request(url, data=json.dumps(body, ensure_ascii=False).encode(), method="POST",
                                     headers={"Content-Type": "application/json", "User-Agent": UA["User-Agent"], **(headers or {})})
        with urllib.request.urlopen(req, timeout=timeout) as r: r.read()
        return True, None
    except Exception as e: return False, f"{type(e).__name__}: {e}"[:300]

def deliver_due(force=False):
    """把 me 的「待送达」和新回的话合成一条。url 为空 = 不发，只进收件箱（GET /api/partner/inbox）"""
    ij = cfg_inject()
    with db() as c:
        shs = [dict(r) for r in c.execute("SELECT * FROM shares WHERE status='pending' AND who='me' ORDER BY id")]
        rps = [dict(r) for r in c.execute("SELECT * FROM comments WHERE who='me' AND sent IS NULL ORDER BY id")]
        if not shs and not rps: return 0
        if not force and time.time() - max(r["created"] for r in shs + rps) < float(ij["merge_seconds"]): return 0
        url = str(ij.get("url") or "").strip(); payload = None
        if url:
            body, imgs, cards, so, ro = digest(c, shs, rps, int(ij["max_images"]))
            text = str(ij["template"]).format_map(_Safe(me=nm("me"), partner=nm("partner"), body=body, n=len(shs) + len(rps)))
            payload = {"text": text, "shares": [{k: x[k] for k in ("id", "items", "note")} for x in so], "images": imgs, "cards": cards,
                       "replies": [{k: x[k] for k in ("id", "target", "where", "text", "reply_to")} for x in ro]}
    ok, err = post_json(url, payload, ij.get("headers"), float(ij["timeout"])) if url else (True, None)
    if not ok: print(f"[stopover] inject failed: {err}", flush=True)
    now = time.time()
    with _lock, db() as c:
        for r in shs:
            if ok or (r["tries"] or 0) >= 1:      # 成功；或第二次也失败 → 不再重试，留在收件箱里等 partner 来拉
                c.execute("UPDATE shares SET status='sent', sent=?, err=?, tries=tries+?, taken_at=? WHERE id=?",
                          (now, err, 0 if ok else 1, now if (ok and url) else None, r["id"]))
            else: c.execute("UPDATE shares SET err=?, tries=tries+1 WHERE id=?", (err, r["id"]))
        for m in rps:
            if ok or (m["tries"] or 0) >= 1:
                c.execute("UPDATE comments SET sent=?, tries=tries+?, taken_at=? WHERE id=?", (now, 0 if ok else 1, now if (ok and url) else None, m["id"]))
            else: c.execute("UPDATE comments SET tries=tries+1 WHERE id=?", (m["id"],))
        log(c, "deliver", "", {"shares": [r["id"] for r in shs], "replies": [r["id"] for r in rps], "ok": ok, "webhook": bool(url)})
    return len(shs) + len(rps) if ok else 0

_deliver_kick = threading.Event()
def _deliver_loop():
    while True:
        try: wait = max(1.0, min(30.0, float(cfg_inject()["merge_seconds"]) / 2))
        except Exception: wait = 30.0
        _deliver_kick.wait(timeout=wait); _deliver_kick.clear()
        try: deliver_due()
        except Exception as e: print(f"[stopover] deliver error: {e}", flush=True)

# ---------- partner 的收件箱：me 递来的、还没取走的 + me 回的话 ----------
def inbox_rows(c):
    shs = [dict(r) for r in c.execute("SELECT * FROM shares WHERE who='me' AND status='sent' AND taken_at IS NULL ORDER BY id")]
    rps = [dict(r) for r in c.execute("SELECT * FROM comments WHERE who='me' AND sent IS NOT NULL AND taken_at IS NULL ORDER BY id")]
    return shs, rps

def take(c, shs, rps):
    now = time.time()
    for r in shs: c.execute("UPDATE shares SET taken_at=? WHERE id=?", (now, r["id"]))
    for r in rps: c.execute("UPDATE comments SET taken_at=? WHERE id=?", (now, r["id"]))

@app.get("/api/partner/inbox")
def partner_inbox(request: Request, mark: int = 0):
    need_partner(request)
    with _lock, db() as c:
        shs, rps = inbox_rows(c)
        text, imgs, cards, so, ro = digest(c, shs, rps, int(cfg_inject()["max_images"]))
        per = []
        for x, r in zip(so, shs):   # 每一样各自渲染一段短文本 + 各自的图
            t, im, _, _, _ = digest(c, [r], [], 9); per.append(x | {"text": t, "images": im, "card": {"url": x["card"], "json": share_card(c, r)}})
        reps = [x | {"card": {"url": x["card"], "json": comment_card(c, m)}} for x, m in zip(ro, rps)]
        if mark: take(c, shs, rps)
    return {"count": len(shs) + len(rps), "text": text, "images": imgs, "shares": per, "replies": reps, "marked": bool(mark)}

# ---------- 推送给 me：partner 留言 / 递东西 / 点星 → Web Push + APNs ----------
PUSH_TEXT = {"comment": "{partner}在{where}下面说：{text}", "share": "{partner}递来{what}{note_part}", "wish": "{partner}想和你去{city}{note_part}"}
APNS_HOSTS = {"production": "https://api.push.apple.com", "sandbox": "https://api.sandbox.push.apple.com"}

def cfg_push(): return cfg().get("push") or {}
def web_push_ok():
    try: import pywebpush, py_vapid  # noqa: F401
    except Exception: return False
    return (cfg_push().get("web") or {}).get("enabled", True) is not False

def apns_cfg(): return cfg_push().get("apns") or {}
def apns_ok():
    a = apns_cfg()
    if not all(str(a.get(k) or "").strip() for k in ("key_path", "key_id", "team_id", "bundle_id")): return False
    if not os.path.isfile(os.path.expanduser(a["key_path"])): return False
    try: import httpx, jwt  # noqa: F401
    except Exception: return False
    return True

def b64u(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
_vapid_lock = threading.Lock()
def vapid():
    """VAPID 密钥对：第一次要用时生成，存在 var/vapid.json（git 忽略，0600）"""
    f = os.path.join(VAR, "vapid.json")
    with _vapid_lock:
        try: return json.load(open(f))
        except FileNotFoundError: pass
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        k = ec.generate_private_key(ec.SECP256R1())
        d = {"private_pem": k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode(),
             "public_key": b64u(k.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)), "created": time.time()}
        tmp = f + ".tmp"; fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as fh: json.dump(d, fh)
        os.replace(tmp, f)
        return d

def subs(kind):
    with db() as c: return [dict(r) for r in c.execute("SELECT * FROM push_subs WHERE kind=?", (kind,))]
def drop_sub(ident_):
    with _lock, db() as c: c.execute("DELETE FROM push_subs WHERE ident=?", (ident_,))

def send_web(title, body, data):
    from pywebpush import webpush, WebPushException
    from py_vapid import Vapid
    v = Vapid.from_pem(vapid()["private_pem"].encode()); sub_ = (cfg_push().get("web") or {}).get("vapid_subject") or "mailto:you@example.com"
    ok = 0
    for s in subs("web"):
        try:
            webpush(subscription_info=json.loads(s["data"]), data=json.dumps({"title": title, "body": body, "data": data}, ensure_ascii=False),
                    vapid_private_key=v, vapid_claims={"sub": sub_}, ttl=86400, timeout=15)
            ok += 1
        except WebPushException as e:
            code = getattr(e.response, "status_code", None)
            print(f"[stopover] web push failed {code}: {str(e)[:120]}", flush=True)
            if code in (404, 410): drop_sub(s["ident"])
        except Exception as e: print(f"[stopover] web push error: {e}", flush=True)
    return ok

_apns_jwt = {"iat": 0, "tok": "", "kid": ""}
def apns_token():
    a = apns_cfg()
    if time.time() - _apns_jwt["iat"] < 45 * 60 and _apns_jwt["kid"] == a["key_id"]: return _apns_jwt["tok"]
    import jwt
    iat = int(time.time())
    tok = jwt.encode({"iss": a["team_id"], "iat": iat}, open(os.path.expanduser(a["key_path"])).read(), algorithm="ES256", headers={"kid": a["key_id"]})
    _apns_jwt.update(iat=iat, tok=tok, kid=a["key_id"])
    return tok

def send_apns(title, body, custom):
    import httpx
    a = apns_cfg(); host_override = os.environ.get("STOPOVER_APNS_HOST") or a.get("host")   # host：只给测试用
    payload = {**custom, "aps": {"alert": {"title": title, "body": body}, "sound": "default"}}
    headers = {"authorization": f"bearer {apns_token()}", "apns-topic": a["bundle_id"], "apns-push-type": "alert", "apns-priority": "10"}
    ok = 0
    with httpx.Client(http2=True, timeout=15) as cl:
        for s in subs("apns"):
            host = (host_override or APNS_HOSTS.get(s["env"] or a.get("env") or "production", APNS_HOSTS["production"])).rstrip("/")
            try:
                r = cl.post(f"{host}/3/device/{s['ident']}", json=payload, headers=headers)
                if r.status_code == 200: ok += 1; continue
                try: reason = r.json().get("reason", "")
                except Exception: reason = ""
                print(f"[stopover] apns {r.status_code} {reason}", flush=True)
                if r.status_code == 410 or reason in ("Unregistered", "BadDeviceToken"): drop_sub(s["ident"])
            except Exception as e: print(f"[stopover] apns error: {e}", flush=True)
    return ok

def push_me(kind, custom, **fmt):
    """partner 做了什么 → 推到 me 的设备。custom 进 payload（点开直达那座城）"""
    note = fmt.pop("note", "") or ""
    body = cut(PUSH_TEXT[kind].format(partner=nm("partner"), note_part=f"：{note}" if note else "", **{k: cut(str(v), 60) for k, v in fmt.items()}), 120)
    title = cfg_push().get("title") or "经停"
    data = {"route": "stopover", **custom}
    def go():
        n = 0
        if web_push_ok() and subs("web"): n += send_web(title, body, data)
        if apns_ok() and subs("apns"): n += send_apns(title, body, data)
        if n: print(f"[stopover] pushed to {n} device(s): {body[:40]}", flush=True)
    _bg(go)

@app.get("/api/push/vapid")
def push_vapid():
    if not web_push_ok(): return {"ok": False, "reason": "web push not available (pip install pywebpush)"}
    return {"ok": True, "publicKey": vapid()["public_key"]}

@app.post("/api/push/web")
def push_web_add(body: dict = Body(default={})):
    s = body.get("subscription") or {}
    ep, keys = s.get("endpoint"), s.get("keys") or {}
    if not (isinstance(ep, str) and re.match(r"https?://", ep) and keys.get("p256dh") and keys.get("auth")): raise HTTPException(400, "subscription 要有 endpoint 和 keys.p256dh / keys.auth")
    if not web_push_ok(): return {"ok": False, "reason": "web push not available"}
    with _lock, db() as c:
        c.execute("INSERT INTO push_subs(kind,ident,data,env,created) VALUES('web',?,?,NULL,?) ON CONFLICT(ident) DO UPDATE SET data=excluded.data",
                  (ep, json.dumps({"endpoint": ep, "keys": {"p256dh": keys["p256dh"], "auth": keys["auth"]}}), time.time()))
    return {"ok": True}

@app.delete("/api/push/web")
def push_web_del(body: dict = Body(default={}), endpoint: str = ""):
    ep = endpoint or body.get("endpoint") or (body.get("subscription") or {}).get("endpoint") or ""
    with _lock, db() as c: n = c.execute("DELETE FROM push_subs WHERE kind='web' AND ident=?", (ep,)).rowcount
    return {"ok": True, "removed": n}

@app.post("/api/push/apns")
def push_apns_add(body: dict = Body(default={})):
    if not apns_ok(): return {"ok": False, "reason": "apns not configured"}
    tok, env = str(body.get("token") or "").strip(), body.get("env") or apns_cfg().get("env") or "production"
    if not re.fullmatch(r"[0-9a-fA-F]{32,200}", tok): raise HTTPException(400, "token 是设备 token 的十六进制串")
    if env not in APNS_HOSTS: raise HTTPException(400, "env 是 sandbox 或 production")
    with _lock, db() as c:
        c.execute("INSERT INTO push_subs(kind,ident,data,env,created) VALUES('apns',?,NULL,?,?) ON CONFLICT(ident) DO UPDATE SET env=excluded.env",
                  (tok.lower(), env, time.time()))
    return {"ok": True}

@app.delete("/api/push/apns")
def push_apns_del(body: dict = Body(default={}), token: str = ""):
    tok = (token or body.get("token") or "").strip().lower()
    with _lock, db() as c: n = c.execute("DELETE FROM push_subs WHERE kind='apns' AND ident=?", (tok,)).rowcount
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

# ---------- partner 的工具：MCP（POST /mcp）和 CLI（POST /api/partner/tool）共用 ----------
# 省 token：写操作只回一行 ✓/✗，不复述刚传的内容；长卷先给目录，再按节读。
class ToolErr(Exception): pass

def city_id(q):
    q0 = (q or "").strip(); ql = q0.lower(); C = cities()
    if not q0: raise ToolErr("要写城市名")
    if q0 in C: return q0
    hit = [k for k, v in C.items() if v["name"] == q0 or v["en"].lower() == ql]
    if not hit: hit = [k for k, v in C.items() if v["name"].startswith(q0) or v["en"].lower().startswith(ql)]
    if not hit and len(q0) >= 2:   # 简称：字按顺序出现就算
        def sub(a, b): it = iter(b); return all(ch in it for ch in a)
        hit = [k for k, v in C.items() if sub(q0, v["name"]) or sub(ql, v["en"].lower())]
    hit.sort(key=lambda k: (-C[k]["has"], len(C[k]["name"])))
    if not hit:
        cz = _load_cities()["cz"]
        en = next((e for e, z in cz.items() if z == q0 or e.lower() == ql), None)
        if en:
            names = [v["name"] for v in C.values() if v["country"] == en and v["has"]]
            raise ToolErr(f"「{q0}」是国家，要写城市名。那里有资料的城：{'、'.join(names[:12]) or '还没有'}")
        import difflib
        near = difflib.get_close_matches(q0, [v["name"] for v in C.values() if v["has"]], n=4, cutoff=0.4)
        raise ToolErr(f"没有叫「{q0}」的城" + (f"，像是：{'、'.join(near)}" if near else ""))
    if len(hit) > 1 and C[hit[0]]["name"] != q0 and C[hit[0]]["en"].lower() != ql:
        raise ToolErr("有好几座：" + "、".join(C[k]["name"] for k in hit[:6]) + "，写全一点")
    return hit[0]

def sf_ref(x):
    """s:京都/2 → {"type":"sight","city":"kyoto","i":1}"""
    m = re.fullmatch(r"([sf]):(.+)/(\d+)", (x or "").strip())
    if not m: return None
    cid = city_id(m.group(2)); k = "sight" if m.group(1) == "s" else "food"; i = int(m.group(3))
    arr = city_page(cid).get("sights" if k == "sight" else "foods") or []
    if not 1 <= i <= len(arr): raise ToolErr(f"{cname(cid)}的{'景点' if k == 'sight' else '美食'}只有 1~{len(arr)} 号，先 look {cname(cid)}")
    return {"type": k, "city": cid, "i": i - 1}

def to_target(x):
    x = (x or "").strip()
    m = re.fullmatch(r"([tnpd]):(\d+)", x)
    if m: return {"t": "trip", "n": "note", "p": "photo", "d": "share"}[m.group(1)] + ":" + m.group(2)
    if re.fullmatch(r"c:\d+", x): raise ToolErr("c: 是一句话的编号，要回它就写 reply_to=c:编号，对象写它挂的地方")
    return "city:" + city_id(x)

def _hm(ts): return time.strftime("%m.%d %H:%M", time.localtime(ts))
def _who_word(w): return "你" if w == "partner" else nm("me")

def _cms(c, target, n=3):
    rows = [dict(r) for r in c.execute("SELECT id, who, text FROM comments WHERE target=? ORDER BY id", (target,))][-n:]
    return [f"  c:{r['id']} {_who_word(r['who'])}：{cut(r['text'], 50)}" for r in rows]

def _trips(c, cid): return [dict(r) for r in c.execute("SELECT * FROM checkins WHERE city=? ORDER BY id", (cid,))]

def _photo_b64(path, side=1024):
    from PIL import Image
    im = Image.open(path).convert("RGB"); im.thumbnail((side, side)); b = io.BytesIO(); im.save(b, "JPEG", quality=80)
    return base64.b64encode(b.getvalue()).decode()

def _wiki_b64(url):
    os.makedirs(CACHE, exist_ok=True); f = os.path.join(CACHE, hashlib.sha1(url.encode()).hexdigest()[:20] + ".jpg")
    if not os.path.exists(f):
        from PIL import Image
        im = Image.open(io.BytesIO(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read())).convert("RGB")
        im.thumbnail((1024, 1024)); im.save(f, "JPEG", quality=80)
    return base64.b64encode(open(f, "rb").read()).decode()

def t_look(a):
    x = str(a.get("ref") or "").strip(); M = nm("me")
    if not x: raise ToolErr("look 什么？城市名 / t:编号 / p:编号 / n:编号 / d:编号")
    with db() as c:
        m = re.fullmatch(r"([tnpd]):(\d+)", x)
        if m and m.group(1) == "n": return t_read({"ref": x})
        if m and m.group(1) == "d":
            try: sh = share_row(c, int(m.group(2)))
            except HTTPException: raise ToolErr("没有这次递送")
            items = json.loads(sh["items"]); names = []
            for it in items:
                if it["type"] == "city": names.append(cname(it["city"]))
                elif it["type"] in ("sight", "food"): names.append(f"{wiki_ref(it)} {sf_item(it).get('name', '')}")
                else: names.append({"trip": "整张票", "photo": "照片", "note": "随记"}[it["type"]] + f"（{it['type'][0]}:{it['id']}）")
            out = [f"{'你' if sh['who'] == 'partner' else M}递的：{'、'.join(names)}　{_hm(sh['created'])}"]
            if sh["note"]: out.append(f"  附言：{sh['note']}")
            out += [f"  c:{r['id']} {_who_word(r['who'])}：{r['text']}" for r in c.execute("SELECT id, who, text FROM comments WHERE target=? ORDER BY id", (f"share:{sh['id']}",))]
            out.append(f"——\n回这一次：say d:{sh['id']} \"…\"（回某一句加 reply_to=c:编号）")
            return "\n".join(out), None
        if m and m.group(1) == "t":
            try: t = trip_row(c, int(m.group(2)))
            except HTTPException: raise ToolErr("没有这一次")
            o, d = (cname(t["origin"]) if t["origin"] else ""), (cname(t["dest"]) if t["dest"] else "")
            out = [f"{trip_label(c, t['id'])} · {(t['date_start'] or '没记日期').replace('-', '.')}" + (f" · 从{o}出发" if o else "") + (f" · 回到{d}" if d else "")]
            if t["remark"]: out.append(f"  备注：{t['remark']}")
            out += [f"  n:{n['id']}「{cut(n['text'], 60)}」" for n in c.execute("SELECT id, text FROM notes WHERE trip_id=? ORDER BY id", (t["id"],))]
            ps = [dict(r) for r in c.execute("SELECT id, caption FROM photos WHERE trip_id=? ORDER BY COALESCE(taken, created), id", (t["id"],))]
            if ps: out.append("  照片：" + "　".join(f"p:{p['id']}" + (f"「{cut(p['caption'], 16)}」" if p["caption"] else "") for p in ps))
            out += _cms(c, f"trip:{t['id']}")
            out.append(f"——\n随记全文：read n:编号　看照片：look p:编号　留言：say t:{t['id']} \"…\"")
            return "\n".join(out), None
        if m and m.group(1) == "p":
            try: p = photo_row(c, int(m.group(2)))
            except HTTPException: raise ToolErr("没有这张照片")
            f = photo_file(c, p["id"], 1600) or photo_file(c, p["id"], 600)
            out = [f"{trip_label(c, p['trip_id'])}的照片 p:{p['id']}" + (f"\n  配文：{p['caption']}" if p["caption"] else "")] + _cms(c, f"photo:{p['id']}")
            out.append(f"——\n留言：say p:{p['id']} \"…\"")
            return "\n".join(out), (_photo_b64(f) if f else None)
        cid = city_id(x); pg = city_page(cid); ts = _trips(c, cid); n_ = cname(cid); co = cities()[cid]
        if not pg:
            return f"【{n_}】{co['en']}　这座城还没有资料" + (f"　{M}来过 {len(ts)} 次" if ts else "") + f"\n——\n现场整理一页（约一分钟）：gen {n_}", None
        out = [f"【{n_}】{pg.get('en', co['en'])}{' · ' + country_zh(co['country']) if co.get('country') else ''}"]
        if pg.get("dek"): out.append(pg["dek"])
        if ts:
            out.append(f"{M}来过 {len(ts)} 次：")
            for i, t in enumerate(ts):
                nn = c.execute("SELECT COUNT(*) FROM notes WHERE trip_id=?", (t["id"],)).fetchone()[0]; pp = c.execute("SELECT COUNT(*) FROM photos WHERE trip_id=?", (t["id"],)).fetchone()[0]
                bits = [f"第{i + 1}次", (t["date_start"] or "").replace("-", "."), f"回到{cname(t['dest'])}" if t["dest"] else "", f"备注「{cut(t['remark'], 20)}」" if t["remark"] else "", f"随记{nn}段" if nn else "", f"照片{pp}张" if pp else ""]
                out.append(f"  t:{t['id']}  " + " · ".join(b for b in bits if b))
        else: out.append(f"{M}没来过。")
        ws = [dict(r) for r in c.execute("SELECT by, note FROM wishes WHERE city=?", (cid,))]
        if ws: out.append("想去：" + "　".join(_who_word(w["by"]) + (f"「{cut(w['note'], 20)}」" if w["note"] else "") for w in ws))
        if pg.get("sights"): out.append("景点：" + "　".join(f"s:{n_}/{i + 1} {s['name']}" for i, s in enumerate(pg["sights"])))
        if pg.get("foods"): out.append("美食：" + "　".join(f"f:{n_}/{i + 1} {f['name']}" for i, f in enumerate(pg["foods"])))
        shs = [dict(r) for r in c.execute("SELECT * FROM shares ORDER BY id")]
        shs = [r for r in shs if any(item_city(c, it) == cid for it in json.loads(r["items"]))][-5:]
        if shs: out.append("递过：" + "　".join(f"d:{r['id']} {_who_word(r['who'])}递的{share_what(c, json.loads(r['items']))}" for r in shs))
        cms = [dict(r) for r in c.execute("SELECT id, target, who, text FROM comments WHERE target NOT LIKE 'share:%' ORDER BY id")]
        cms = [r for r in cms if target_city(c, r["target"]) == cid][-4:]
        if cms: out.append("平时说的：" + "".join(f"\n  c:{r['id']} {_who_word(r['who'])}（{short_ref(r['target'])}）：{cut(r['text'], 50)}" for r in cms))
        out.append("——")
        if pg.get("history") or pg.get("culture"): out.append(f"历史和文化：read {n_}")
        if pg.get("sights") or pg.get("foods"): out.append(f"景点 / 美食全文：read s:{n_}/编号 · read f:{n_}/编号　图：img s:{n_}/编号")
        if ts: out.append("某一次：look t:编号")
        out.append(f"留言：say {n_} \"…\"　某次递送的对话：look d:编号")
        return "\n".join(out), None

SECTIONS = {"history": "history", "历史": "history", "culture": "culture", "文化": "culture", "all": "all", "全部": "all"}
def t_read(a):
    x = str(a.get("ref") or "").strip(); M = nm("me")
    if not x: raise ToolErr("read 什么？城市名 / s:城市/编号 / f:城市/编号 / n:编号")
    m = re.fullmatch(r"n:(\d+)", x)
    if m:
        with db() as c:
            try: n = note_row(c, int(m.group(1)))
            except HTTPException: raise ToolErr("没有这段随记")
            out = [f"【{trip_label(c, n['trip_id'])}的随记 · {M}写的】\n{n['text']}"] + _cms(c, f"note:{n['id']}")
        return "\n".join(out) + f"\n——\n留言：say n:{n['id']} \"…\"", None
    it = sf_ref(x)
    if it:
        s = sf_item(it); n_ = cname(it["city"])
        return (f"【{n_} · {s.get('name', '')}】" + (s["orig"] if s.get("orig") and s["orig"] != s.get("name") else "") + "\n" + (s.get("intro") or "（没有介绍）")
                + f"\n——\n图：img {wiki_ref(it)}　递给{M}：share {wiki_ref(it)} note=\"…\""), None
    cid = city_id(x); pg = city_page(cid); n_ = cname(cid)
    if not (pg.get("history") or pg.get("culture")): raise ToolErr(f"{n_}还没有资料。现场整理一页（约一分钟）：gen {n_}")
    sec = SECTIONS.get(str(a.get("section") or "").strip().lower())
    if not sec:   # 先给目录
        out = [f"【{n_}】{pg.get('dek', '')}"]
        for k, zh in (("history", "历史"), ("culture", "文化")):
            ps = [p for p in str(pg.get(k) or "").split("\n") if p.strip()]
            if ps: out.append(f"〔{zh}〕{len(ps)} 段，约 {sum(len(p) for p in ps)} 字：" + "".join(f"\n  {i + 1}. {cut(p, 40)}" for i, p in enumerate(ps)))
        if pg.get("pull"): out.append(f"〔引语〕{pg['pull']}")
        out.append(f"——\n读全文：read {n_} section=history / culture / all")
        return "\n".join(out), None
    out = [f"【{n_}】"]
    if sec in ("history", "all") and pg.get("history"): out.append("〔历史〕\n" + pg["history"])
    if sec in ("culture", "all") and pg.get("culture"): out.append("〔文化〕\n" + pg["culture"])
    out.append(f"——\n景点和美食：read s:{n_}/编号 / read f:{n_}/编号（编号见 look {n_}）")
    return "\n\n".join(out), None

def t_img(a):
    x = str(a.get("ref") or "").strip()
    if not x: raise ToolErr("img 什么？p:编号 / 城市名 / s:城市/编号 / f:城市/编号")
    m = re.fullmatch(r"p:(\d+)", x)
    if m:
        with db() as c:
            try: f = photo_file(c, int(m.group(1)), 1600) or photo_file(c, int(m.group(1)), 600)
            except HTTPException: raise ToolErr("没有这张照片")
        if not f: raise ToolErr("这张照片的缩略图丢了")
        return f"✓ p:{m.group(1)}", _photo_b64(f)
    it = sf_ref(x) or {"type": "city", "city": city_id(x)}
    url = wiki_img(it)
    if not url: raise ToolErr("这一项没有图")
    try: return f"✓ {wiki_ref(it)}", _wiki_b64(url)
    except Exception: return f"✓ 图取不到，链接：{url}", None

def t_say(a):
    tg = to_target(a.get("to") or a.get("ref")); text = str(a.get("text") or "")
    try: r = add_comment("partner", tg, text, a.get("reply_to") or None)
    except HTTPException as e: raise ToolErr(e.detail)
    return f"✓ c:{r['id']}", None

def t_wish(a):
    cid = city_id(a.get("city") or a.get("ref")); set_wish("partner", cid, a.get("note")); return f"✓ 点亮了 → {cname(cid)}", None

def t_unwish(a):
    cid = city_id(a.get("city") or a.get("ref"))
    return (f"✓ 收起了 → {cname(cid)}" if del_wish("partner", cid) else f"✗ {cname(cid)}本来就没点"), None

def t_wishes(a):
    M = nm("me"); by = {}
    with db() as c:
        for w in c.execute("SELECT city, by, note FROM wishes ORDER BY created"): by.setdefault(w["city"], {})[w["by"]] = w["note"]
        been = {r[0] for r in c.execute("SELECT DISTINCT city FROM checkins")}
    if not by: return "还没有人点星。\n——\n点亮：wish 城市名 note=\"理由\"", None
    def fmt(cid, d): return cname(cid) + (f"({M}来过)" if cid in been else "") + "".join(f"「{cut(v, 16)}」" for v in d.values() if v)
    both = [k for k, d in by.items() if len(d) == 2]; mine = [k for k, d in by.items() if list(d) == ["me"]]; his = [k for k, d in by.items() if list(d) == ["partner"]]
    out = ([f"都想去 {len(both)}：" + "　".join(fmt(k, by[k]) for k in both)] if both else []) + \
          [f"{M}想去 {len(mine)}：" + ("　".join(fmt(k, by[k]) for k in mine) or "（没有）"), f"你想去 {len(his)}：" + ("　".join(fmt(k, by[k]) for k in his) or "（没有）")]
    return "\n".join(out) + "\n——\n点亮：wish 城市名　收回：unwish 城市名", None

def t_share(a):
    x = str(a.get("ref") or "").strip()
    if re.fullmatch(r"[tnpd]:\d+", x): raise ToolErr(f"那是{nm('me')}的经停，递不了；能递的是城市 / s:城市/编号 / f:城市/编号")
    it = sf_ref(x) or {"type": "city", "city": city_id(x)}
    try: add_share("partner", [it], a.get("note"), a.get("with_image", True) is not False)
    except HTTPException as e: raise ToolErr(e.detail)
    return f"✓ 递给{nm('me')}了 → {cname(it['city'])}", None

def t_wander(a):
    cs = [k for k, v in cities().items() if v["has"]]
    if not cs: raise ToolErr("还没有城市资料")
    cid = random.choice(cs); pg = city_page(cid); n_ = cname(cid)
    out = [f"{n_}（{pg.get('en', '')}{' · ' + country_zh(cities()[cid]['country']) if cities()[cid].get('country') else ''}）"]
    if pg.get("dek"): out.append(f"  {pg['dek']}")
    if pg.get("sights"): s = random.choice(pg["sights"]); out.append(f"  {s['name']}：{cut(s.get('intro'), 50)}")
    out.append(f"——\n目录：look {n_}　想去：wish {n_}　递给{nm('me')}：share {n_}")
    return "\n".join(out), None

def t_gen(a):
    cid = city_id(a.get("city") or a.get("ref")); n_ = cname(cid)
    if city_page(cid): return f"✓ {n_}已经有资料：look {n_}", None
    try:
        r = city_gen_status(cid)
        if r.get("status") != "running": r = city_gen(cid, {})
    except HTTPException as e: raise ToolErr(e.detail)
    if r.get("status") == "done": return f"✓ {n_}整理好了：look {n_}", None
    return f"… 正在整理{n_}（{r.get('msg') or r.get('stage') or '准备中'}），约一分钟后 look {n_}", None

def t_been(a):
    M = nm("me")
    with db() as c: rows = [r[0] for r in c.execute("SELECT city FROM checkins")]
    if not rows: return f"{M}还没打过卡。", None
    cnt = {}
    for x in rows: cnt[x] = cnt.get(x, 0) + 1
    groups = {}
    for cid, n in cnt.items(): groups.setdefault(country_zh(cities().get(cid, {}).get("country")) or "其他", []).append(cname(cid) + (f"({n}次)" if n > 1 else ""))
    out = [f"{M}来过 {len(cnt)} 座城（{sum(cnt.values())} 次）："] + [f"  {g} {len(v)}：" + "　".join(v) for g, v in sorted(groups.items(), key=lambda kv: -len(kv[1]))]
    return "\n".join(out) + "\n——\n看某座城：look 城市名", None

def t_inbox(a):
    with _lock, db() as c:
        shs, rps = inbox_rows(c)
        if not shs and not rps: return "没有新的。", None
        text, imgs, cards, _, _ = digest(c, shs, rps, int(cfg_inject()["max_images"]))
        if not a.get("peek"): take(c, shs, rps)
    return text + ("\n——\n图片：" + "　".join(imgs) if imgs else ""), None

TOOLS = [
    ("inbox", "收件箱：me 递来的、回你的话（看完即标记已取）。Inbox: what the user handed you and replied, marks as read.", {"peek": {"type": "boolean", "description": "true = 只看不标记"}}, []),
    ("look", "看目录：城市名 / t:编号（某一次）/ p:编号（照片，带图）/ n:编号 / d:编号（某次递送和对话）。Directory view.", {"ref": {"type": "string"}}, ["ref"]),
    ("read", "读全文：城市名（先目录，section=history|culture|all 读整节）/ s:城市/编号 / f:城市/编号 / n:编号。Read full text.", {"ref": {"type": "string"}, "section": {"type": "string", "enum": ["history", "culture", "all"]}}, ["ref"]),
    ("img", "看图：p:编号 / 城市名 / s:城市/编号 / f:城市/编号（≤1024px）。Get an image.", {"ref": {"type": "string"}}, ["ref"]),
    ("say", "留言/回复：to = d:编号 / 城市名 / t: / n: / p:；reply_to = c:编号（可选）。Comment or reply.", {"to": {"type": "string"}, "text": {"type": "string"}, "reply_to": {"type": "string"}}, ["to", "text"]),
    ("wish", "点亮你的星：想和 me 去这座城。Star a city.", {"city": {"type": "string"}, "note": {"type": "string"}}, ["city"]),
    ("unwish", "收回你的星。Unstar a city.", {"city": {"type": "string"}}, ["city"]),
    ("wishes", "两个人想去的清单。Both wish lists.", {}, []),
    ("share", "递给 me：城市名 / s:城市/编号 / f:城市/编号，可附 note。Hand a city/sight/food to the user.", {"ref": {"type": "string"}, "note": {"type": "string"}, "with_image": {"type": "boolean"}}, ["ref"]),
    ("been", "me 去过的城（按国家）。Cities the user has been to.", {}, []),
    ("wander", "随机逛一座城。Random city.", {}, []),
    ("gen", "给没资料的城现场整理一页（约一分钟）。Write a page for a city.", {"city": {"type": "string"}}, ["city"]),
]
TOOL_FN = {"inbox": t_inbox, "look": t_look, "read": t_read, "img": t_img, "say": t_say, "wish": t_wish, "unwish": t_unwish,
           "wishes": t_wishes, "share": t_share, "been": t_been, "wander": t_wander, "gen": t_gen}
ALIAS = {"收件箱": "inbox", "新": "inbox", "看": "look", "读": "read", "图": "img", "说": "say", "想去": "wish", "不想去": "unwish",
         "清单": "wishes", "递": "share", "去过": "been", "逛": "wander", "整理": "gen"}

def run_tool(name, args):
    name = ALIAS.get(name, name); fn = TOOL_FN.get(name)
    if not fn: return f"✗ 没有 {name} 这个工具", None, True
    try:
        text, img = fn(args or {}); return text, img, False
    except ToolErr as e: return f"✗ {e}", None, True
    except HTTPException as e: return f"✗ {e.detail}", None, True

@app.post("/api/partner/tool")
def partner_tool(request: Request, body: dict = Body(default={})):
    """CLI 用：{name, args} → {ok, text, image?}（image = base64 JPEG）"""
    need_partner(request)
    text, img, err = run_tool(str(body.get("name") or ""), body.get("args") or {})
    return {"ok": not err, "text": text} | ({"image": {"mime": "image/jpeg", "data": img}} if img else {})

MCP_VERSIONS = ("2025-06-18", "2025-03-26", "2024-11-05")
def mcp_handle(m):
    if not isinstance(m, dict) or m.get("jsonrpc") != "2.0" or "method" not in m:
        return {"jsonrpc": "2.0", "id": m.get("id") if isinstance(m, dict) else None, "error": {"code": -32600, "message": "invalid request"}}
    mid, meth, p = m.get("id"), m["method"], m.get("params") or {}
    if mid is None: return None                                  # notification (e.g. notifications/initialized)
    def ok(res): return {"jsonrpc": "2.0", "id": mid, "result": res}
    if meth == "initialize":
        v = p.get("protocolVersion"); v = v if v in MCP_VERSIONS else MCP_VERSIONS[0]
        return ok({"protocolVersion": v, "capabilities": {"tools": {"listChanged": False}}, "serverInfo": {"name": "stopover", "version": VERSION}})
    if meth == "ping": return ok({})
    if meth == "tools/list":
        return ok({"tools": [{"name": n, "description": d, "inputSchema": {"type": "object", "properties": props, "required": req}} for n, d, props, req in TOOLS]})
    if meth == "tools/call":
        text, img, err = run_tool(str(p.get("name") or ""), p.get("arguments") or {})
        content = [{"type": "text", "text": text}] + ([{"type": "image", "data": img, "mimeType": "image/jpeg"}] if img else [])
        return ok({"content": content, "isError": err})
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"method not found: {meth}"}}

@app.post("/mcp")
async def mcp(request: Request):
    if who(request) != "partner":
        return JSONResponse({"jsonrpc": "2.0", "id": None, "error": {"code": -32001, "message": "partner key required"}}, status_code=401, headers={"WWW-Authenticate": "Bearer"})
    try: msg = await request.json()
    except Exception: return JSONResponse({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}}, status_code=400)
    batch = isinstance(msg, list)
    out = [r for r in [await run_in_threadpool(mcp_handle, x) for x in (msg if batch else [msg])] if r is not None]
    if not out: return Response(status_code=202)
    return JSONResponse(out if batch else out[0])

@app.api_route("/mcp", methods=["GET", "DELETE", "PUT"])
def mcp_other():
    return Response(status_code=405, headers={"Allow": "POST"})

@app.get("/api/health")
def health():
    return {"ok": True, "cities": len(cities())}

app.mount("/", StaticFiles(directory=WEB, html=True), name="web")

if __name__ == "__main__":
    init()
    threading.Thread(target=_deliver_loop, daemon=True).start()
    uvicorn.run(app, host=os.environ.get("STOPOVER_HOST", "127.0.0.1"), port=int(os.environ.get("STOPOVER_PORT", "8000")), log_level="warning")
