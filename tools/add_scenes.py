"""Injects the animated story scenes (_slides/scenes/L*.json) into data/aie_course.json, in place."""
import json, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, "data", "aie_course.json")
course = json.load(open(P, encoding="utf-8"))
n = miss = 0
for ch in course["chapters"]:
    for l in ch["lessons"]:
        sp = os.path.join(ROOT, "_slides", "scenes", "L%s.json" % l["id"])
        sc = json.load(open(sp, encoding="utf-8")) if os.path.exists(sp) else {}
        for c in l["cards"]:
            if c["id"] in sc:
                c["scene"] = sc[c["id"]]
                n += 1
            else:
                miss += 1
json.dump(course, open(P, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("scenes added: %d   cards without scene: %d" % (n, miss))
