#!/usr/bin/env python3
"""Write one city page with DeepSeek, using Wikipedia + Wikivoyage as source material.

    python3 pipeline/citygen.py <city_id> [fast|good]

The server runs this as a subprocess when someone taps "整理这座城的资料" on a city
that has no page yet. Steps:
  1. Wikidata: find the zh / en Wikipedia and Wikivoyage articles (same name, within 40 km)
  2. DeepSeek writes dek / history / culture / pull / sights / foods as JSON
     (Chinese cities are written without feeding Wikipedia text — DeepSeek's content
     filter rejects some zh-wiki material, and it knows these cities well anyway)
  3. Images: the article thumbnail for each sight / food; if missing, Wikidata P18 or a
     Commons file search (sights must be within 25 km; foods must look like food).
     Sources more than 150 km away are dropped — a near-namesake is usually the wrong place.
  4. Cover photos from the zh article's media list, city outline from Nominatim (OSM)
Writes web/data/city/<id>.json, moves the city from "extra" to "cities" in
web/data/cities.json (same id), and reports progress in <STATUS_DIR>/<id>.json.

Env: DEEPSEEK_API_KEY (required), DEEPSEEK_MODEL_FAST / DEEPSEEK_MODEL_GOOD (optional),
     STOPOVER_CONTACT (an email for the Wikimedia / Nominatim User-Agent, optional).
City text is derived from Wikipedia / Wikivoyage and is CC BY-SA 4.0 (see web/data/LICENSE).
"""
import fcntl, json, math, os, re, sys, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.environ.get("STOPOVER_WEB_DATA", os.path.join(ROOT, "web", "data"))
STATUS_DIR = os.environ.get("STOPOVER_STATUS_DIR", "/tmp/stopover_gen")
UA = {"User-Agent": f"stopover/1.0 ({os.environ.get('STOPOVER_CONTACT', 'https://github.com/fishisfish0614/stopover')})"}
MODELS = {"fast": os.environ.get("DEEPSEEK_MODEL_FAST", "deepseek-flash"),
          "good": os.environ.get("DEEPSEEK_MODEL_GOOD", "deepseek-v4-pro")}
CN = {"China", "Hong Kong S.A.R.", "Macao S.A.R", "Taiwan"}
COMMONS, WD = "https://commons.wikimedia.org/w/api.php", "https://www.wikidata.org/w/api.php"

try:
    from opencc import OpenCC          # pip install opencc-python-reimplemented
    T2S = OpenCC("t2s").convert
except Exception:
    T2S = lambda s: s


# ---------- small helpers ----------
def get(u, tries=3):
    for k in range(tries):
        try: return json.loads(urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=40).read())
        except Exception:
            if k == tries - 1: raise
            time.sleep(2 + 3 * k)

def km(a, b):
    R = math.pi / 180; x = math.sin((b[0]-a[0])*R/2)**2 + math.cos(a[0]*R)*math.cos(b[0]*R)*math.sin((b[1]-a[1])*R/2)**2
    return 12742 * math.asin(math.sqrt(x))

def t2s_all(o):
    if isinstance(o, str): return T2S(o)
    if isinstance(o, list): return [t2s_all(x) for x in o]
    if isinstance(o, dict): return {k: t2s_all(v) for k, v in o.items()}
    return o

def deepseek(prompt, model):
    key = os.environ.get("DEEPSEEK_API_KEY")
    if not key: raise RuntimeError("DEEPSEEK_API_KEY is not set")
    body = json.dumps({"model": model, "max_tokens": 6000, "thinking": {"type": "disabled"},   # no reasoning: it eats the token budget
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    req = urllib.request.Request("https://api.deepseek.com/chat/completions", data=body,
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    d = json.loads(urllib.request.urlopen(req, timeout=300).read())
    return (d.get("choices") or [{}])[0].get("message", {}).get("content") or None

def parse(out):
    out = re.sub(r"^```(json)?|```$", "", out.strip(), flags=re.M).strip()
    return json.loads(re.sub(r",\s*([}\]])", r"\1", out), strict=False)

def extract(lang, title, chars):
    q = get(f"https://{lang}.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&format=json&redirects=1"
            + ("&variant=zh-cn" if lang == "zh" else "") + "&titles=" + urllib.parse.quote(title))
    return list(q["query"]["pages"].values())[0].get("extract", "")[:chars]

def sect(wt, name):
    m = re.search(r"^==\s*" + name + r"\s*==\s*$(.*?)(?=^==[^=])", wt, re.S | re.M); return m.group(1) if m else ""

def wsum(title, lang="zh"):
    try:
        s = get(f"https://{lang}.wikipedia.org/api/rest_v1/page/summary/" + urllib.parse.quote(title.replace(" ", "_")))
        return None if s.get("type") == "disambiguation" else s
    except Exception: return None

def nominatim(q):
    try:
        n = get("https://nominatim.openstreetmap.org/search?format=json&polygon_geojson=1&polygon_threshold=0.0006&limit=4&q=" + urllib.parse.quote(q))
    except Exception: return None, None
    b = next((x for x in n if x.get("geojson", {}).get("type") in ("Polygon", "MultiPolygon")), None)
    return (b["geojson"], [float(x) for x in b["boundingbox"]]) if b else (None, None)


# ---------- prompts ----------
SCHEMA = """只输出一个 JSON 对象，不要 markdown 代码块，结构：
{{"dek":"一句20字以内的副标题，点出这座城的气质",
"history":"历史，3段，共350-450字，段落之间用\\n\\n分隔，按时间推进，要有具体的人、年份、事件",
"culture":"文化，2段，共250-320字，用\\n\\n分隔",
"pull":"从历史或文化里提炼的一句引语，25字以内",
"sights":[{{"name":"中文名","orig":"当地原文名","wiki":"中文维基百科条目的准确标题","wiki_en":"英文维基条目标题","intro":"70-100字介绍：它是什么、为什么值得去、一个具体细节"}}],
"foods":[{{"name":"中文名","orig":"当地原文名","wiki":"中文维基条目标题(没有就写空字符串)","wiki_en":"英文维基条目标题","intro":"50-80字：是什么、怎么吃、哪里吃"}}]}}
sights 给5个，选这座城最有代表性的景点。foods 给4个，必须是这座城或所在地区的特色菜、点心、饮品（一道菜/一种食物，有自己的维基条目），不要餐馆、市场、食堂或泛称的外来快餐。"""
VOICE = "语气：克制、具体、有画面，像杂志专栏，不要导游腔、不要感叹号、不要\"不容错过\"这类套话。一律用简体中文。"
PROMPT = ("你在为一本中文旅行杂志写城市专页「{zh}」。下面是维基百科中文条目和英文 Wikivoyage 的「See」「Eat」原文素材。"
          "只依据素材和公认常识写，不确定的数字和年份宁可不写，绝不编造。" + VOICE + "\n\n" + SCHEMA +
          "\n\n【维基百科】\n{ext}\n\n【Wikivoyage See】\n{see}\n\n【Wikivoyage Eat】\n{eat}")
PROMPT_CN = ("你在为一本中文旅行杂志写城市专页「{zh}」。这次没有附素材，请凭你对这座城市的可靠了解来写。"
             "只写你有把握的事实，不确定的人名、数字、年份宁可不写，绝不编造。" + VOICE + "\n" + SCHEMA +
             "\n注意：如果这是一座相对小众的城市，篇幅按你真正有把握的内容来：history 2–3 段、200–400 字，culture 1–2 段，"
             "景点和美食各 3–5 个。可写的不多就写短，不要硬凑，不要编。")
STRICT = """

【硬性要求——逐条遵守】
1. 篇幅：history 3 段、合计 350–450 字；culture 2 段、合计 250–320 字；景点 intro 70–100 字；美食 intro 50–80 字；dek ≤20 字；pull ≤25 字。
2. 每一段最多出现 2 个数字（年份也算）。不写人口、面积、排名、统计数据。
3. 只写有把握的事实。素材里没有、你也不确定的人名、年份、建筑名一律不写。
4. 景点和美食必须真实存在且属于这座城或所在地区；name、orig、intro 说的是同一样东西。
5. 少用"位于""是……的重要……""素有……之称"这类百科腔，不要导游腔，不要感叹号。
6. 一律简体中文。"""
LIGHT = """

【这座城的素材不多】篇幅按素材来，不要硬凑：history 写 2 段、合计 180–300 字；culture 写 1–2 段、合计 120–250 字；景点、美食各 3–5 个，宁少勿编。"""


# ---------- images ----------
FOODISH = re.compile(r"(dish|food|cuisine|dessert|pastry|cake|bread|sausage|cheese|soup|stew|snack|sweet|beverage|drink|wine|beer|noodle|dumpling|sandwich|salad|sauce|biscuit|pie|tart|meat|fish|seafood|菜|食|料理|点心|甜|糕|饼|面|粉|汤|酒|饮|肠|肉|鱼|饭|茶|酱|小吃|包子|饺)", re.I)

def norm(s):
    return re.sub(r"[\s\-_'’.,()（）·]+", "", (s or "").lower())

def info(fname, w):
    try:
        q = get(f"{COMMONS}?action=query&format=json&formatversion=2&prop=imageinfo&iiprop=size|url&iiurlwidth={w}&titles=" + urllib.parse.quote("File:" + fname))
        ii = (q["query"]["pages"][0].get("imageinfo") or [{}])[0]
        u = ii.get("thumburl") or ii.get("url")
        if not u or re.search(r"\.(svg|tif|tiff|pdf|djvu)", u, re.I): return None
        return {"u": u, "w": ii.get("thumbwidth") or ii.get("width"), "h": ii.get("thumbheight") or ii.get("height")}
    except Exception: return None

def fname_of(url):
    m = re.match(r"https?://(?:upload|thumb)\.wikimedia\.org/wikipedia/[^/]+/(?:thumb/)?[0-9a-f]/[0-9a-f]{2}/([^/?]+)", (url or "").split("?")[0])
    return urllib.parse.unquote(m.group(1)) if m else None

def p18(term, lang, kind, lat, lng):
    """Wikidata entity whose label matches exactly; sights must be within 25 km, foods must be described as food."""
    if not term: return None
    r = get(f"{WD}?action=wbsearchentities&format=json&limit=7&language={lang}&uselang={lang}&search=" + urllib.parse.quote(term))
    hits = [x for x in r.get("search", []) if norm((x.get("match") or {}).get("text")) == norm(term)]
    if kind == "foods": hits = [x for x in hits if FOODISH.search(x.get("description") or "")]
    if not hits: return None
    e = get(f"{WD}?action=wbgetentities&format=json&props=claims&ids=" + "|".join(x["id"] for x in hits[:4]))
    for x in hits[:4]:
        cl = e.get("entities", {}).get(x["id"], {}).get("claims", {})
        if kind == "sights":
            try:
                co = cl["P625"][0]["mainsnak"]["datavalue"]["value"]
                if km((co["latitude"], co["longitude"]), (lat, lng)) > 25: continue
            except Exception: continue
        f = (cl.get("P18") or [{}])[0].get("mainsnak", {}).get("datavalue", {}).get("value")
        if f and re.search(r"\.jpe?g$", f, re.I): return f
    return None

def commons(term, kind, city_en):
    if not term or len(norm(term)) < 4: return None
    r = get(f"{COMMONS}?action=query&format=json&list=search&srnamespace=6&srlimit=10&srsearch=" + urllib.parse.quote(f'intitle:"{term}" filetype:bitmap'))
    for x in r.get("query", {}).get("search", []):
        t = x["title"].split(":", 1)[-1]
        if not re.search(r"\.jpe?g$", t, re.I) or norm(term) not in norm(t) or re.search(r"(map|logo|flag|coat|wappen|menu|sign)", t, re.I): continue
        if kind == "sights" and norm(city_en) not in norm(t): continue
        return t
    return None


# ---------- main ----------
def st(cid, stage, msg="", **k):
    os.makedirs(STATUS_DIR, exist_ok=True)
    json.dump({"stage": stage, "msg": msg, "ts": time.time(), **k}, open(f"{STATUS_DIR}/{cid}.json", "w"), ensure_ascii=False)

def main(cid, tier):
    st(cid, "start", "准备中")
    idx = json.load(open(f"{DATA}/cities.json"))
    if any(x["id"] == cid for x in idx["cities"]): return st(cid, "done", "已经有资料了")
    hit = next((x for x in idx["extra"] if f"n_{x[1]}_{x[2]}" == cid), None)
    if not hit: return st(cid, "error", "地图上没有这座城")
    zh, en, lat, lng, country = hit

    st(cid, "wiki", "正在翻维基")
    t = {}
    if country not in CN:
        try:
            r = get(f"{WD}?action=wbsearchentities&format=json&language=en&limit=10&search=" + urllib.parse.quote(en))
            ids = [x["id"] for x in r.get("search", [])]
            ents = get(f"{WD}?action=wbgetentities&format=json&props=claims|sitelinks&ids=" + "|".join(ids))["entities"] if ids else {}
            for i in ids:
                cl, sl = ents[i].get("claims", {}), ents[i].get("sitelinks", {})
                try: co = cl["P625"][0]["mainsnak"]["datavalue"]["value"]
                except Exception: continue
                if km((co["latitude"], co["longitude"]), (lat, lng)) > 40: continue
                t = {"zh": (sl.get("zhwiki") or {}).get("title"), "en": (sl.get("enwiki") or {}).get("title"), "voy": (sl.get("enwikivoyage") or {}).get("title")}
                break
        except Exception: pass
        t.setdefault("en", en)

    st(cid, "write", "正在整理（DeepSeek）")
    model = MODELS["good" if tier == "good" else "fast"]
    if country in CN: prompt = PROMPT_CN.format(zh=zh)
    else:
        cap = 14000 if tier == "good" else 6000
        ext = T2S(extract("zh", t["zh"], cap)) if t.get("zh") else ""
        if len(ext) < 400 and t.get("en"): ext = (ext + "\n\n" + extract("en", t["en"], 12000))[:16000]
        wt = ""
        if t.get("voy"):
            try: wt = get("https://en.wikivoyage.org/w/api.php?action=parse&prop=wikitext&format=json&formatversion=2&redirects=1&page=" + urllib.parse.quote(t["voy"]))["parse"]["wikitext"]
            except Exception: pass
        see, eat = re.sub(r"\s+", " ", sect(wt, "See"))[:5000], re.sub(r"\s+", " ", sect(wt, "Eat"))[:3000]
        prompt = PROMPT.format(zh=zh, ext=ext, see=see, eat=eat) + (STRICT if tier != "good" else "") + (LIGHT if len(ext) + len(see) + len(eat) < 4000 else "")
    d = None
    for _ in range(2):
        out = deepseek(prompt, model)
        if not out: continue
        try:
            d = t2s_all(parse(out))
            if d.get("history") and d.get("sights") and d.get("foods"): break
        except Exception: d = None
    if not d: return st(cid, "error", "DeepSeek 没写出来，过一会儿再试")

    st(cid, "images", "正在配图")
    used = set()
    def items(g):
        out = []
        for it in d.get(g) or []:
            s = (it.get("wiki") and wsum(it["wiki"])) or (it.get("wiki_en") and wsum(it["wiki_en"], "en")) or {}
            src, co = s.get("content_urls", {}).get("desktop", {}).get("page"), s.get("coordinates")
            if g == "sights" and co and km((co["lat"], co["lon"]), (lat, lng)) > 150: s, src = {}, None
            f = fname_of((s.get("thumbnail") or {}).get("source")); im = info(f, 960) if f else None
            if not im:
                try:
                    for term, lang in ((it.get("wiki"), "zh"), (it.get("name"), "zh"), (it.get("wiki_en"), "en"), (it.get("orig"), "en")):
                        f = p18(term, lang, g, lat, lng)
                        if f: break
                    f = f or commons(it.get("orig"), g, en) or commons(it.get("wiki_en"), g, en)
                    im = info(f, 960) if f else None
                except Exception: im = None
            if im and im["u"] in used: im = None
            if im: used.add(im["u"])
            out.append({"name": it.get("name", ""), "orig": it.get("orig", ""), "intro": it.get("intro", ""), "img": im, "src": src})
        return out
    sights, foods = items("sights"), items("foods")
    hero = []
    hero_t = t.get("zh") or (zh if country in CN else None)
    if hero_t:
        try:
            ml = get("https://zh.wikipedia.org/api/rest_v1/page/media-list/" + urllib.parse.quote(hero_t.replace(" ", "_")))
            for it in ml.get("items", []):
                if it.get("type") != "image": continue
                src = (it.get("srcset") or [{}])[0].get("src") or ""
                f = fname_of("https:" + src if src.startswith("//") else src)
                if not f or re.search(r"(svg|png|Flag|Coat|Wappen|Map|map|Locator|logo|Seal|Emblem|[Cc]ollage|[Mm]ontage)", f): continue
                im = info(f, 1280)
                if im and im["w"] >= im["h"] * 1.2 and im["u"] not in used: hero.append(im); used.add(im["u"])
                if len(hero) >= 2: break
        except Exception: pass
    outline, bbox = nominatim(f"{t.get('en') or en}, {country}")

    st(cid, "save", "存下来")
    page = {"id": cid, "name": zh, "en": re.sub(r",.*$", "", en), "country": country, "lat": lat, "lng": lng,
            "dek": d.get("dek", ""), "history": d.get("history", ""), "culture": d.get("culture", ""), "pull": d.get("pull", ""),
            "sights": sights, "foods": foods, "hero": hero, "outline": outline,
            "credit": {"model": model, "wiki": t or None, "generated": time.strftime("%Y-%m-%d")}}
    entry = {"id": cid, "n": zh, "e": page["en"], "c": country, "la": round(lat, 4), "lo": round(lng, 4), "b": bbox, "t": "g"}
    os.makedirs(f"{DATA}/city", exist_ok=True)
    json.dump(page, open(f"{DATA}/city/{cid}.json", "w"), ensure_ascii=False, separators=(",", ":"))
    with open(f"{DATA}/.cities.lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        cj = json.load(open(f"{DATA}/cities.json"))
        cj["extra"] = [x for x in cj["extra"] if f"n_{x[1]}_{x[2]}" != cid]
        if not any(x["id"] == cid for x in cj["cities"]): cj["cities"].append(entry)
        tmp = f"{DATA}/cities.json.tmp"; json.dump(cj, open(tmp, "w"), ensure_ascii=False, separators=(",", ":")); os.replace(tmp, f"{DATA}/cities.json")
    st(cid, "done", "整理好了", entry=entry, sights=len(sights), foods=len(foods))

if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit(__doc__)
    cid = sys.argv[1]
    try: main(cid, sys.argv[2] if len(sys.argv) > 2 else "fast")
    except Exception as e:
        st(cid, "error", f"出错了：{type(e).__name__} {str(e)[:120]}"); raise
