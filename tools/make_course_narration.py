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
                for b in c.get("scene", {}).get("beats", []):   # the guide robot's lines in story mode
                    add(b.get("cap", ""))
    for q in course["quiz"]:
        add(q.get("why", ""))
    for t in ("Amazing work! You finished this lesson.",
              "Well done for finishing! Watch it again any time to collect more stars."):
        add(t)
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
    sem = asyncio.Semaphore(6)       # a few requests in parallel
    done = [0]

    async def one(t, k):
        async with sem:
            for attempt in range(4):
                try:
                    await synth(t, os.path.join(OUT, k + ".mp3"), os.path.join(OUT, k + ".json"))
                    break
                except Exception as e:
                    if attempt == 3:
                        print("  FAILED", k, e, flush=True)
                    await asyncio.sleep(2 + attempt * 3)
            done[0] += 1
            if done[0] % 50 == 0 or done[0] == len(todo):
                print("  %d/%d" % (done[0], len(todo)), flush=True)

    await asyncio.gather(*(one(t, k) for t, k in todo))
    print("done")


if __name__ == "__main__":
    asyncio.run(main())