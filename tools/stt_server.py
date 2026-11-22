"""Local speech-to-text server for NeuroGraph XR voice questions (offline, runs on the CPU).

Godot starts this automatically. Manual start:  python tools/stt_server.py
Needs once:  pip install faster-whisper   (the model, ~150 MB, downloads on first start)

POST /transcribe?prompt=<glossary>   body = WAV/MP3 bytes   ->  {"text": "..."}
POST /speak                          body = UTF-8 text      ->  MP3 audio (same neural voice as the tour)
GET  /health                                                 ->  {"ok": true, "ready": bool}
POST /shutdown                                               ->  stops this server (a newer one takes over)

Options:  --parent <pid>   exit automatically when that process (the game) ends
"""
import json, os, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = 11435
MODEL_NAME = os.environ.get("NG_STT_MODEL", "base.en")   # small.en = more accurate, slower
LOG = os.path.join(tempfile.gettempdir(), "neurograph_stt.log")

TTS_VOICE = "en-US-AvaNeural"   # same narrator as the guided tour
TTS_RATE = "-4%"
model = None
lock = threading.Lock()


def speak_mp3(text):
    """Neural voice via edge-tts (needs internet). Returns MP3 bytes."""
    import asyncio, edge_tts

    async def run():
        audio = bytearray()
        async for ch in edge_tts.Communicate(text, TTS_VOICE, rate=TTS_RATE).stream():
            if ch["type"] == "audio":
                audio += ch["data"]
        return bytes(audio)

    return asyncio.run(run())


def log(*a):
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(time.strftime("%H:%M:%S ") + " ".join(str(x) for x in a) + "\n")


def load_model():
    global model
    from faster_whisper import WhisperModel
    t = time.time()
    model = WhisperModel(MODEL_NAME, device="cpu", compute_type="int8", cpu_threads=4)
    log("model", MODEL_NAME, "loaded in %.1fs" % (time.time() - t))


def load_audio(path):
    """WAV -> 16 kHz mono float32 with numpy only (no ffmpeg / PyAV needed). Other formats: None."""
    import wave
    import numpy as np
    try:
        with wave.open(path, "rb") as w:
            ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            raw = w.readframes(n)
    except (wave.Error, EOFError):
        return None
    if sw == 2:
        a = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    elif sw == 1:
        a = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    elif sw == 4:
        a = np.frombuffer(raw, dtype=np.int32).astype(np.float32) / 2147483648.0
    else:
        return None
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    if sr != 16000 and len(a) > 1:
        t_new = np.arange(0, len(a) * 16000 // sr) * (sr / 16000.0)
        a = np.interp(t_new, np.arange(len(a)), a).astype(np.float32)
    peak = float(np.abs(a).max()) if len(a) else 0.0
    if 0.0 < peak < 0.5:            # quiet headset mic: normalise so Whisper hears it clearly
        a = a * (0.5 / peak)
    return a


MIN_LOGPROB = -1.05     # below this the model is guessing (background talk, noise, another language)
MAX_NO_SPEECH = 0.6


def transcribe(path, prompt):
    audio = load_audio(path)
    src = audio if audio is not None else path
    kw = dict(language="en", beam_size=1, initial_prompt=prompt or None, condition_on_previous_text=False)
    try:
        segs, _ = model.transcribe(src, vad_filter=True, **kw)
        segs = list(segs)
    except Exception as e:          # VAD unavailable -> plain transcription
        log("vad failed:", e)
        segs, _ = model.transcribe(src, **kw)
        segs = list(segs)
    kept, dropped = [], []
    for sg in segs:
        ok = sg.avg_logprob >= MIN_LOGPROB and sg.no_speech_prob <= MAX_NO_SPEECH
        (kept if ok else dropped).append("%r(lp=%.2f ns=%.2f)" % (sg.text.strip(), sg.avg_logprob, sg.no_speech_prob))
    text = " ".join(sg.text.strip() for sg in segs if sg.avg_logprob >= MIN_LOGPROB and sg.no_speech_prob <= MAX_NO_SPEECH)
    log("kept:", kept, " dropped:", dropped)
    return text.strip()


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if urlparse(self.path).path == "/health":
            self._json(200, {"ok": True, "ready": model is not None})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/shutdown":
            self._json(200, {"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        if u.path == "/speak":
            n = int(self.headers.get("Content-Length", 0))
            text = self.rfile.read(n).decode("utf-8", "replace").strip()[:2500]
            try:
                t = time.time()
                mp3 = speak_mp3(text)
                if not mp3:
                    raise RuntimeError("no audio returned")
                log("speak %.2fs  %d chars -> %d bytes" % (time.time() - t, len(text), len(mp3)))
                self.send_response(200)
                self.send_header("Content-Type", "audio/mpeg")
                self.send_header("Content-Length", str(len(mp3)))
                self.end_headers()
                self.wfile.write(mp3)
            except Exception as e:
                log("speak error:", e)
                self._json(500, {"error": str(e)})
            return
        if u.path != "/transcribe":
            return self._json(404, {"error": "not found"})
        n = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(n)
        prompt = parse_qs(u.query).get("prompt", [""])[0][:600]
        while model is None:        # first request right after start-up: wait for the model
            time.sleep(0.2)
        fd, path = tempfile.mkstemp(suffix=".wav")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
            t = time.time()
            with lock:
                text = transcribe(path, prompt)
            log("%.2fs  %d bytes  -> %r" % (time.time() - t, n, text))
            self._json(200, {"text": text})
        except Exception as e:
            log("error:", e)
            self._json(500, {"error": str(e)})
        finally:
            try:
                os.remove(path)
            except OSError:
                pass

    def log_message(self, *a):
        pass


def warm_voice():
    """The very first edge-tts call pays for imports, DNS and TLS (~5 s). Do it now, during the intro."""
    try:
        t = time.time()
        speak_mp3("Ready.")
        log("voice warmed up in %.1fs" % (time.time() - t))
    except Exception as e:
        log("voice warm-up failed (offline? the game will use the system voice):", e)


def process_alive(pid):
    """Windows-safe check (os.kill(pid, 0) would TERMINATE the process on Windows)."""
    import ctypes
    k = ctypes.windll.kernel32
    h = k.OpenProcess(0x1000, False, pid)          # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return False
    code = ctypes.c_ulong()
    k.GetExitCodeProcess(h, ctypes.byref(code))
    k.CloseHandle(h)
    return code.value == 259                        # STILL_ACTIVE


def watch_parent(pid, srv):
    while process_alive(pid):
        time.sleep(2.0)
    log("game process", pid, "ended - shutting down")
    srv.shutdown()


def bind():
    """Take the port. If an older server holds it (e.g. left over from a crashed run), ask it to stop."""
    import urllib.request
    for attempt in range(25):
        try:
            return ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
        except OSError:
            if attempt == 0:
                try:
                    urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:%d/shutdown" % PORT, data=b"", method="POST"), timeout=2)
                    log("asked the old server to stop")
                except Exception:
                    pass
            time.sleep(0.2)
    return None


if __name__ == "__main__":
    srv = bind()
    if srv is None:
        log("port", PORT, "busy - giving up")
        sys.exit(0)
    if "--parent" in sys.argv:
        ppid = int(sys.argv[sys.argv.index("--parent") + 1])
        threading.Thread(target=watch_parent, args=(ppid, srv), daemon=True).start()
    threading.Thread(target=load_model, daemon=True).start()
    threading.Thread(target=warm_voice, daemon=True).start()
    log("listening on", PORT)
    srv.serve_forever()
    log("stopped")
