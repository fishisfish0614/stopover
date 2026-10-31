#!/usr/bin/env python3
"""stopover — the partner's command line for 经停 Stopover (standard library only).

    export STOPOVER_URL=http://127.0.0.1:8000          # where the server is
    export STOPOVER_PARTNER_KEY=...                    # config.json → partner_key
    python3 cli/stopover.py look 京都

It is only an HTTP client: every command calls POST /api/partner/tool, the same tools the MCP server (/mcp) exposes.
Writes answer in one line (✓ / ✗). Images are saved to $STOPOVER_OUT (default: a temp folder) and the path is printed.

  inbox  | 收件箱 | 新      [--peek]              what was handed to you / replies to you (marks them read unless --peek)
  look   | 看      <ref>                          directory: 城市名 / t:编号 / p:编号 / n:编号 / d:编号
  read   | 读      <ref> [历史|文化|全部]          full text: 城市名 / s:城市/编号 / f:城市/编号 / n:编号
  img    | 图      <ref>                          image: p:编号 / 城市名 / s:城市/编号 / f:城市/编号
  say    | 说      <to> "话" [回 c:编号]           to = d:编号 / 城市名 / t: / n: / p:
  wish   | 想去    [城市 ["理由"]]                 no city = both wish lists
  unwish | 不想去  <城市>
  share  | 递      <城市 | s:城市/编号 | f:城市/编号> ["附言"] [--no-image]
  been   | 去过     wander | 逛     gen | 整理 <城市>
"""
import base64, json, os, re, sys, tempfile, time, urllib.error, urllib.request

URL = os.environ.get("STOPOVER_URL", "http://127.0.0.1:8000").rstrip("/")
KEY = os.environ.get("STOPOVER_PARTNER_KEY", "")
OUT = os.environ.get("STOPOVER_OUT") or os.path.join(tempfile.gettempdir(), "stopover")

def die(msg): print(f"✗ {msg}"); sys.exit(1)

def tool(name, args):
    if not KEY: die("先设置 STOPOVER_PARTNER_KEY（服务端 config.json 里的 partner_key）")
    req = urllib.request.Request(f"{URL}/api/partner/tool", method="POST", data=json.dumps({"name": name, "args": args}, ensure_ascii=False).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r: return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try: msg = json.loads(e.read()).get("detail")
        except Exception: msg = e.code
        die(msg)
    except Exception as e: die(f"经停服务没连上（{URL}）：{e}")

def show(r, name="img"):
    text = r.get("text", "")
    img = r.get("image")
    if img:
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, re.sub(r"[^\w\-]+", "_", name)[:60] + ".jpg")
        open(path, "wb").write(base64.b64decode(img["data"]))
        text += f"\n→ 图在 {path}"
    print(text)
    if not r.get("ok", True): sys.exit(1)

def need(a, n, usage):
    if len(a) < n: die(usage)

def c_inbox(a): show(tool("inbox", {"peek": "--peek" in a}))
def c_look(a): need(a, 1, "look 什么？城市名 / t:编号 / p:编号 / n:编号 / d:编号"); show(tool("look", {"ref": a[0]}), a[0])
def c_read(a):
    need(a, 1, "read 什么？城市名 / s:城市/编号 / f:城市/编号 / n:编号")
    show(tool("read", {"ref": a[0], **({"section": a[1]} if len(a) > 1 else {})}))
def c_img(a): need(a, 1, "img 什么？p:编号 / 城市名 / s:城市/编号 / f:城市/编号"); show(tool("img", {"ref": a[0]}), a[0])
def c_say(a):
    need(a, 2, 'say <对象> "话" [回 c:编号]')
    args = {"to": a[0], "text": a[1]}
    rest = a[2:]
    for i, x in enumerate(rest):
        m = re.fullmatch(r"(?:reply_to=|--reply=)?(c:\d+|\d+)", x)
        if x in ("回", "reply", "--reply", "reply_to") and i + 1 < len(rest): args["reply_to"] = rest[i + 1]; break
        if m and (x.startswith(("c:", "reply_to=", "--reply=")) or i > 0): args["reply_to"] = m.group(1); break
    show(tool("say", args))
def c_wish(a):
    if not a: return show(tool("wishes", {}))
    show(tool("wish", {"city": a[0], "note": a[1] if len(a) > 1 else ""}))
def c_unwish(a): need(a, 1, "unwish 哪座？"); show(tool("unwish", {"city": a[0]}))
def c_wishes(a): show(tool("wishes", {}))
def c_share(a):
    need(a, 1, "share 什么？城市名 / s:城市/编号 / f:城市/编号")
    words = [x for x in a if x != "--no-image"]
    show(tool("share", {"ref": words[0], "note": words[1] if len(words) > 1 else "", "with_image": "--no-image" not in a}))
def c_been(a): show(tool("been", {}))
def c_wander(a): show(tool("wander", {}))
def c_gen(a):
    need(a, 1, "gen 哪座？")
    for _ in range(60):                    # 等它写完（通常 30~90 秒），中途不出声
        r = tool("gen", {"city": a[0]})
        if not r.get("text", "").startswith("…"): return show(r)
        time.sleep(4)
    show(r)

CMDS = {}
for names, fn in ((("inbox", "收件箱", "新"), c_inbox), (("look", "看"), c_look), (("read", "读"), c_read), (("img", "图"), c_img),
                  (("say", "说"), c_say), (("wish", "想去"), c_wish), (("unwish", "不想去"), c_unwish), (("wishes", "清单"), c_wishes),
                  (("share", "递"), c_share), (("been", "去过"), c_been), (("wander", "逛"), c_wander), (("gen", "整理"), c_gen)):
    for n in names: CMDS[n] = fn

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in CMDS:
        if len(sys.argv) >= 2: print(f"✗ 没有「{sys.argv[1]}」这个命令，用法如下：")
        print(__doc__.split("\n\n", 3)[3].strip("\n")); sys.exit(0 if len(sys.argv) < 2 else 1)
    CMDS[sys.argv[1]](sys.argv[2:])
