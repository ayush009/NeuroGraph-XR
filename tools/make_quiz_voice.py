"""Creates the natural quiz voice (same narrator as the guided tour).

Reads data/*_quiz.json and, for every question, voices exactly the sentences the app speaks
(see _quiz_lines() and QUIZ_WRONG_LINE in scripts/ds_viewer.gd - keep the two in sync):
    question  ->  the question text
    correct   ->  "Correct! " + say
    second    ->  "Yes, that's it. " + say
    reveal    ->  "The answer is " + say_name + ". " + say
plus the one shared "try again" line.

Run:  python tools/make_quiz_voice.py        (needs internet once; --force re-creates files)
Then open the project in Godot so the new mp3 files are imported, and re-export.
After editing a question's text in the JSON, just run this again - only new lines are made.
"""
import asyncio, glob, hashlib, json, os, sys
import edge_tts

VOICE = "en-US-AvaNeural"
RATE = "-6%"
WRONG_LINE = "Not quite. Have another look, and try again."

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT = os.path.join(ROOT, "assets", "narration")


def key(text: str) -> str:   # must match _narr_key() in ds_viewer.gd (md5, first 12 hex chars)
    return hashlib.md5(text.encode("utf-8")).hexdigest()[:12]


def lines_for(q: dict) -> list:
    say = q.get("say", q.get("why", ""))
    nm = q.get("say_name", "")
    return [
        q["q"],
        "Correct! " + say,
        "Yes, that's it. " + say,
        ("The answer is " + nm + ". " + say) if nm else say,
    ]


async def synth(text: str, mp3: str) -> None:
    audio = bytearray()
    async for ch in edge_tts.Communicate(text, VOICE, rate=RATE).stream():
        if ch["type"] == "audio":
            audio += ch["data"]
    with open(mp3, "wb") as f:
        f.write(audio)


async def main() -> None:
    force = "--force" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    texts = [WRONG_LINE]
    for p in sorted(glob.glob(os.path.join(ROOT, "data", "*_quiz.json"))):
        for q in json.load(open(p, encoding="utf-8"))["questions"]:
            texts += lines_for(q)
    texts = list(dict.fromkeys(texts))   # unique, keep order
    made = 0
    for t in texts:
        mp3 = os.path.join(OUT, key(t) + ".mp3")
        if os.path.exists(mp3) and not force:
            continue
        for attempt in range(3):
            try:
                await synth(t, mp3)
                break
            except Exception as e:   # network hiccup: retry
                print("retry", attempt + 1, e)
                await asyncio.sleep(2)
        made += 1
        print("made", key(t), "-", t[:70])
    print(f"done: {len(texts)} quiz lines, {made} new")


asyncio.run(main())
