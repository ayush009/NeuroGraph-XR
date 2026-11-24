"""Creates the natural-voice narration files for the AI Engineering course mode.

Reads data/aie_course.json and, for every lesson card's spoken line and every quiz
explanation, writes:
    assets/narration/<id>.mp3    neural voice (needs internet ONCE)
    assets/narration/<id>.json   word timings
The file name is md5(text)[:12] - exactly what the app looks up (see _narr_key in ds_viewer.gd).

Run:  python tools/make_course_narration.py            (skips files that already exist)
      python tools/make_course_narration.py --force    (re-create everything)
"""
import asyncio, hashlib, json, os, sys
import edge_tts

VOICE = "en-US-AvaNeural"      # same narrator as the guided tour
RATE = "-4%"                   # a little slower for course material

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "narration")
COURSE = os.path.join(ROOT, "data", "aie_course.json")


def key_of(text: str) -> str:
    return hashlib.md5(text.encode("utf-8")).hexdigest()[:12]


def collect() -> "list[str]":
    """Every line the app speaks in course mode, in a stable order."""
    course = json.load(open(COURSE, encoding="utf-8"))
    lines, seen = [], set()

    def add(t: str) -> None:
        t = (t or "").strip()
        if t and t not in seen:
            seen.add(t)
            lines.append(t)

    for ch in course["chapters"]:
        for l in ch["lessons"]:
            for c in l["cards"]:
                add(c.get("say", ""))
    for q in course["quiz"]:
        add(q.get("why", ""))
    return lines


async def synth(text: str, mp3: str, js: str) -> None:
    comm = edge_tts.Communicate(text, VOICE, rate=RATE, boundary="WordBoundary")
    audio = bytearray()
    words = []
    async for ch in comm.stream():
        if ch["type"] == "audio":
            audio += ch["data"]
        elif ch["type"] == "WordBoundary":
            words.append({"t": round(ch["offset"] / 1e7, 3), "w": ch["text"]})
    with open(mp3, "wb") as f:
        f.write(audio)
    with open(js, "w", encoding="utf-8") as f:
        json.dump(words, f)


async def main() -> None:
    force = "--force" in sys.argv
    lines = collect()
    os.makedirs(OUT, exist_ok=True)
    todo = []
    for t in lines:
        k = key_of(t)
        if force or not os.path.exists(os.path.join(OUT, k + ".mp3")):
            todo.append((t, k))
    print("course lines: %d   to create: %d   (voice %s)" % (len(lines), len(todo), VOICE))
    for i, (t, k) in enumerate(todo, 1):
        await synth(t, os.path.join(OUT, k + ".mp3"), os.path.join(OUT, k + ".json"))
        print("  %3d/%d  %s  %s" % (i, len(todo), k, t[:70].encode("ascii", "replace").decode()), flush=True)
    print("done")


if __name__ == "__main__":
    asyncio.run(main())