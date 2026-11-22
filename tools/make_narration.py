"""Creates natural-sounding narration files (+ exact word timings) for the guided tour.

1. Run the app once, press D, and hold Space until the tour ends (this records every spoken line).
2. Run:  python tools/make_narration.py
   It reads the recorded lines and writes, for every line:
     assets/narration/<id>.mp3   (neural voice, needs internet ONCE)
     assets/narration/<id>.json  (time of every spoken word, so concepts can pop exactly when named)
3. Open the project in Godot so the new files are imported. Re-export.

Change VOICE / RATE below to change the narrator.   Use  --force  to re-create existing files.
"""
import asyncio, json, os, sys
import edge_tts

VOICE = "en-US-AvaNeural"      # alternatives: en-US-AndrewNeural, en-GB-SoniaNeural, en-US-EmmaNeural
RATE = "-6%"                   # slightly slower = clearer for learners

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "narration")
SRC = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "GNSS_Demo-v2", "narration_lines.json")


async def synth(text, mp3_path, json_path):
    comm = edge_tts.Communicate(text, VOICE, rate=RATE, boundary="WordBoundary")
    audio = bytearray()
    words = []
    async for ch in comm.stream():
        if ch["type"] == "audio":
            audio += ch["data"]
        elif ch["type"] == "WordBoundary":
            words.append({"t": round(ch["offset"] / 1e7, 3), "w": ch["text"]})
    with open(mp3_path, "wb") as f:
        f.write(audio)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(words, f)


async def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv
    lines = json.load(open(args[0] if args else SRC, encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    for key, text in lines.items():
        mp3 = os.path.join(OUT, key + ".mp3")
        js = os.path.join(OUT, key + ".json")
        if os.path.exists(mp3) and os.path.exists(js) and not force:
            continue
        await synth(text, mp3, js)
        print("made", key, "-", text[:60])
    print("done:", len(lines), "lines")

asyncio.run(main())
