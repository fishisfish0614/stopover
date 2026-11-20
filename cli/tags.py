#!/usr/bin/env python3
"""stopover tags — let the partner act by writing tags in its reply instead of calling tools (standard library only).

Every tool call costs the model one more round trip (and re-reads its whole context). With tags it just writes
what it wants to do inside its normal reply; your chat app strips the tags before showing the reply and runs them.

    [jt 说 d:2]话[/jt]            [jt 说 p:4 回 c:7]话[/jt]       say    (说 / say — the only one with a body)
    [jt 想去 京都 理由]            [jt 不想去 京都]                wish / unwish (想去 / wish, 不想去 / unwish)
    [jt 递 京都]                   [jt 递 s:京都/2 附言]            share  (递 / share)

Looking and reading stay tools (look / read / img / inbox): those need an answer back in the same turn.
Set "hints": "tags" in server/config.json so the server's "→ reply like this" hints are written as tags too.

    echo "$reply" | python3 cli/tags.py            # clean reply → stdout, one ✓/✗ line per tag → stderr
    echo "$reply" | python3 cli/tags.py --json     # {"text": clean reply, "results": [{tag, ok, out}]}
    echo "$reply" | python3 cli/tags.py --dry      # parse only, run nothing

From Python:  from tags import strip, parse, run   — parse(text) → (clean, actions); run(actions) → [(ok, out)].
Feed the result lines back to the partner on its next turn when something failed, so it can fix the tag.
A tag inside `inline code` is left alone, and a 说 tag whose [/jt] never comes runs up to the end of the reply.
"""
import contextlib, io, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stopover  # noqa: E402  (the CLI next to this file: STOPOVER_URL / STOPOVER_PARTNER_KEY)

VERBS = {"说": "say", "say": "say", "想去": "wish", "wish": "wish", "不想去": "unwish", "unwish": "unwish", "递": "share", "share": "share"}
_OPEN = re.compile(r"\[jt\s+([^\]\n]{1,120})\]")
_CLOSE = "[/jt]"


def parse(text):
    """reply → (reply without tags, [{"verb", "args", "text"}]). Unknown verbs are kept as actions so run() can explain."""
    out, acts, pos = [], [], 0
    text = text or ""
    for m in _OPEN.finditer(text):
        if m.start() < pos or text[:m.start()].count("`") % 2: continue
        words = m.group(1).split()
        verb = VERBS.get(words[0], words[0])
        out.append(text[pos:m.start()])
        if verb == "say":
            j = text.find(_CLOSE, m.end())
            body, pos = (text[m.end():j], j + len(_CLOSE)) if j >= 0 else (text[m.end():], len(text))
        else:
            body, pos = "", m.end()
        acts.append({"verb": verb, "args": words[1:], "text": body.strip()})
    out.append(text[pos:])
    return re.sub(r"[ \t]+\n", "\n", "".join(out)).strip(), acts


def strip(text): return parse(text)[0]


def to_tool(a):
    """one action → (tool name, args) or raise ValueError with how to write it"""
    v, p, t = a["verb"], a["args"], a["text"]
    if v == "say":
        if len(p) not in (1, 3) or (len(p) == 3 and p[1] not in ("回", "reply")) or not t:
            raise ValueError("写成 [jt 说 对象]话[/jt] 或 [jt 说 对象 回 c:7]话[/jt]")
        return "say", {"to": p[0], "text": t} | ({"reply_to": p[2]} if len(p) == 3 else {})
    if v in ("wish", "share") and p:
        return v, {("city" if v == "wish" else "ref"): p[0], "note": " ".join(p[1:])}
    if v == "unwish" and len(p) == 1:
        return "unwish", {"city": p[0]}
    raise ValueError("只认 [jt 说 对象]话[/jt] / [jt 想去 城市 理由] / [jt 不想去 城市] / [jt 递 对象 附言]；看和读还用工具")


def run(acts):
    res = []
    for a in acts:
        try: name, args = to_tool(a)
        except ValueError as e: res.append((False, f"✗ {e}")); continue
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf): r = stopover.tool(name, args)   # the CLI prints ✗… and exits on errors
        except SystemExit: res.append((False, buf.getvalue().strip() or "✗ 经停服务出错了")); continue
        res.append((bool(r.get("ok", True)), r.get("text", "")))
    return res


if __name__ == "__main__":
    clean, acts = parse(sys.stdin.read())
    res = [] if "--dry" in sys.argv else run(acts)
    if "--json" in sys.argv:
        print(json.dumps({"text": clean, "actions": acts, "results": [{"ok": ok, "out": o} for ok, o in res]}, ensure_ascii=False))
    else:
        print(clean)
        for line in ([o for _, o in res] if res else [f"· {a['verb']} {' '.join(a['args'])}" for a in acts]): print(line, file=sys.stderr)
    sys.exit(0 if all(ok for ok, _ in res) else 1)
