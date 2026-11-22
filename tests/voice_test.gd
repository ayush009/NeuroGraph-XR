extends Node
## Voice-question test: real microphone recording + full speech -> text -> GraphRAG -> Ollama answer.

var v: Node


func _ready() -> void:
	v = (load("res://ds_main.tscn") as PackedScene).instantiate()
	v.preview_vr_ui = true   # keep the headset out of this test
	add_child(v)
	await get_tree().create_timer(1.0).timeout
	v.intro.begin_leave()
	await get_tree().create_timer(1.0).timeout
	v.menu_panel.visible = false
	print("input devices: ", AudioServer.get_input_device_list(), "  using: ", AudioServer.input_device)
	# 1) the real microphone path: hold to speak for 1.5 s
	v._voice_start()
	print("recording=", v.voice_rec, "  ask panel open=", v.ask_on, "  button='", v.voice_btn.text, "'")
	var peak: float = -200.0
	for i in 90:
		await get_tree().process_frame
		peak = maxf(peak, AudioServer.get_bus_peak_volume_left_db(v.mic_bus, 0))
	print("listening text:\n", v.answer_label.text)
	v._voice_stop()
	var wav: AudioStreamWAV = v.mic_rec.get_recording()
	print("mic recorded: ", snappedf(wav.get_length(), 0.01) if wav else -1.0, " s   peak level ", snappedf(peak, 0.1), " dB")
	print("after release: ", v.answer_label.text.split("\n")[0], "   stt_busy=", v._stt_busy)
	while v._stt_busy:
		await get_tree().process_frame
	print("room-noise result: ", v.answer_label.text.split("\n")[0])
	while v._ai_busy:
		await get_tree().process_frame
	# 2) a spoken question (recorded voice file) through the same upload code
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("user://test_voice_question.wav")
	var url: String = v.STT_URL + "?prompt=" + v._stt_glossary().uri_encode()
	var t0: int = Time.get_ticks_msec()
	v.stt_http.request_raw(url, PackedStringArray(["Content-Type: audio/wav"]), HTTPClient.METHOD_POST, bytes)
	v._stt_busy = true
	while v._stt_busy:
		await get_tree().process_frame
	print("\nspeech->text in ", Time.get_ticks_msec() - t0, " ms:  ", v.answer_label.text.split("\n")[0])
	print("retrieved concepts: ", v.highlighted)
	while v._ai_busy:
		await get_tree().process_frame
	print("AI answer after ", Time.get_ticks_msec() - t0, " ms:\n", v.answer_label.text)
	# 3) the spoken answer
	var t1: int = Time.get_ticks_msec()
	print("sentence chunks queued: ", v._say_chunks.size() + (1 if v._say_inflight != "" else 0), "   status: ", v.status_label.text)
	while not v.answer_player.playing and Time.get_ticks_msec() - t1 < 15000:
		await get_tree().process_frame
	print("voice started ", Time.get_ticks_msec() - t1, " ms after the text appeared   playing=", v.answer_player.playing,
		"   first clip ", snappedf(v.answer_player.stream.get_length(), 0.1) if v.answer_player.stream else 0.0, " s   music=", snappedf(v.music_player.volume_db, 0.1), " dB")
	var clips: int = 1
	var last: Object = v.answer_player.stream
	while v._answer_speaking() and Time.get_ticks_msec() - t1 < 60000:
		await get_tree().process_frame
		if v.answer_player.stream != last:
			last = v.answer_player.stream
			clips += 1
	print("spoken answer finished after ", (Time.get_ticks_msec() - t1) / 1000.0, " s, ", clips, " clips, no gaps check: queue empty=", v._say_audio.is_empty())
	# 4) interrupt: speak again, then press the mic -> the voice must stop
	v._speak_answer("This is a long sentence that should be interrupted. And here is another one to keep it busy for a while.")
	while not v.answer_player.playing:
		await get_tree().process_frame
	v._voice_start()
	await get_tree().process_frame
	print("interrupt by pressing the mic: still speaking=", v._answer_speaking())
	v._voice_stop()
	# 5) a typed question must stay silent
	v._ask("What is attention?")
	while v._ai_busy:
		await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	print("typed question spoken? ", v._answer_speaking())
