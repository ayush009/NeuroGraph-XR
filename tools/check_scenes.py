"""Validates _slides/scenes/L*.json against data/aie_course.json (every card has a valid scene)."""
import json, os, sys, glob
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL = {"flow", "cycle", "stack", "tokens", "bars", "vectors", "attention", "compare", "curve", "grid", "tree",
       "timeline", "network", "scale", "chat", "funnel"}
CURVES = {"decay", "power", "log", "sigmoid", "sin", "linear", "exp", "ushape", "bell", "quad", "step"}
PATTERNS = {"causal", "causal_soft", "diag", "band", "window", "full", "random", "sparse"}
BAD = ["→", "e.g.", "(", ")", "*", "#", "`", "lecturer", "professor"]


def check_scene(cid, s):
    p = []
    t = s.get("t")
    if t not in TPL:
        return ["bad template %r" % t]
    items = s.get("items", [])
    beats = s.get("beats", [])
    if not (2 <= len(beats) <= 6):
        p.append("beats=%d" % len(beats))
    if t not in ("network", "grid", "curve") and len(items) < 2:
        p.append("too few items")
    for i, it in enumerate(items):
        if not isinstance(it, dict):
            p.append("item %d not object" % i); continue
        if len(str(it.get("l", ""))) > (115 if t == "chat" else 30):
            p.append("label too long: %r" % it.get("l"))
        if len(str(it.get("tip", ""))) > 160:
            p.append("tip too long (%d)" % len(it["tip"]))
        if t == "vectors" and not all(isinstance(it.get(k), (int, float)) and -1.2 <= it.get(k) <= 1.2 for k in ("x", "y")):
            p.append("vector item %d needs x,y in [-1,1]" % i)
        if t in ("bars", "scale") and not isinstance(it.get("v"), (int, float)):
            p.append("%s item %d needs numeric v" % (t, i))
        if t == "tree" and i > 0 and not (isinstance(it.get("p"), int) and -1 <= it["p"] < i):
            p.append("tree item %d bad parent" % i)
        if t == "compare" and it.get("side") not in (0, 1):
            p.append("compare item %d side" % i)
        if t == "chat" and it.get("who") not in ("sys", "user", "ai", "tool", "doc"):
            p.append("chat who %r" % it.get("who"))
    if t == "curve" and s.get("f") not in CURVES:
        p.append("curve f %r" % s.get("f"))
    if t == "curve" and "f2" in s and s["f2"] not in CURVES:
        p.append("curve f2 %r" % s.get("f2"))
    if t == "grid" and s.get("pattern", "full") not in PATTERNS:
        p.append("grid pattern %r" % s.get("pattern"))
    if t == "network":
        L = s.get("layers", [])
        if not (2 <= len(L) <= 7 and all(isinstance(x, int) and 1 <= x <= 9 for x in L)):
            p.append("network layers %r" % L)
    if t == "attention":
        for l in s.get("links", []):
            if not (isinstance(l, list) and len(l) == 3 and l[0] < len(items) and l[1] < len(items)):
                p.append("bad link %r" % (l,))
    for bi, b in enumerate(beats):
        cap = str(b.get("cap", ""))
        w = len(cap.split())
        if not (5 <= w <= 32):
            p.append("beat %d caption %d words" % (bi, w))
        for bad in BAD:
            hit = (bad in cap.lower()) if bad.isalpha() else (bad in cap)
            if hit:
                p.append("beat %d caption has %r" % (bi, bad))
        if len(str(b.get("note", ""))) > 34:
            p.append("beat %d note too long" % bi)
        limit = max(len(items), len(s.get("layers", [])), int(s.get("rows", 0)))
        for h in b.get("hi", []):
            if not isinstance(h, int) or h >= limit:
                p.append("beat %d hi %r out of range" % (bi, h))
        if "show" in b and not isinstance(b["show"], int):
            p.append("beat %d show not int" % bi)
    if beats and items and beats[-1].get("show", len(items)) < len(items):
        p.append("last beat does not show all items")
    return p


def main():
    course = json.load(open(os.path.join(ROOT, "data", "aie_course.json"), encoding="utf-8"))
    only = sys.argv[1:]
    total = bad = missing = 0
    tpl_count = {}
    for ch in course["chapters"]:
        for l in ch["lessons"]:
            if only and l["id"] not in only:
                continue
            path = os.path.join(ROOT, "_slides", "scenes", "L%s.json" % l["id"])
            if not os.path.exists(path):
                print("L%s: FILE MISSING" % l["id"])
                missing += len(l["cards"])
                continue
            try:
                sc = json.load(open(path, encoding="utf-8"))
            except Exception as e:
                print("L%s: INVALID JSON %s" % (l["id"], e))
                missing += len(l["cards"])
                continue
            for c in l["cards"]:
                total += 1
                s = sc.get(c["id"])
                if s is None:
                    print("L%s %s: no scene" % (l["id"], c["id"]))
                    missing += 1
                    continue
                tpl_count[s.get("t")] = tpl_count.get(s.get("t"), 0) + 1
                pr = check_scene(c["id"], s)
                if pr:
                    bad += 1
                    print("L%s %s: %s" % (l["id"], c["id"], "; ".join(pr)))
            extra = set(sc) - {c["id"] for c in l["cards"]}
            if extra:
                print("L%s: unknown card ids %s" % (l["id"], sorted(extra)))
    print("cards checked=%d  with problems=%d  missing=%d" % (total, bad, missing))
    print("templates:", dict(sorted(tpl_count.items(), key=lambda x: -x[1])))
    sys.exit(1 if (bad or missing) else 0)


if __name__ == "__main__":
    main()
