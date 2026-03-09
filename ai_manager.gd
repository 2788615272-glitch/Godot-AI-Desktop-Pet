extends Node
class_name AIManager

signal brain_wants_to_speak(text: String)
var consecutive_scene_count: int = 0  # 记录连续看你干同一件事的次数（疲劳度）
var death_count: int = 0              # 记录你的白给/死亡次数
#快脑
var fast_brain_http: HTTPRequest
# --- 长期记忆档案馆 ---
var long_term_memory: String = "这名玩家是个刚装上记忆系统的萌新。"
var memory_http: HTTPRequest
# --- 滚动记忆中枢 (Rolling Memory) ---
var short_term_memory: Array = []
const MAX_MEMORY_SIZE: int = 5     # 最多记住最近的 5 件事，防止脑子过载
var last_scene_type: String = ""   # 记录上一次在干嘛，用来防重复
# ==========================================
# ⚙️ 节点引用 (Node References)
# ==========================================
var asr_http: HTTPRequest
var tts_http: HTTPRequest
var eye_http: HTTPRequest
var brain_http: HTTPRequest
var watch_timer: Timer
var record_effect: AudioEffectRecord

@onready var ui_model_select = $"../UIManager/Panel/VBoxContainer/ModelSelect"
@onready var ui_api_key_input = $"../UIManager/Panel/VBoxContainer/APIKeyInput"

# ==========================================
# 🎛️ 面板可调参数 (Inspector Settings)
# ==========================================
@export_group("AI Vision Settings")
@export_group("AI Auto Mode")
@export var auto_mode: bool = true   # 开启后，AI 自己决定多快截一次图

# --- 线程变量（加在内部核心状态区） ---
var screenshot_thread: Thread
@export_range(0.5, 5.0, 0.1) var vision_interval: float = 1.5   # 视觉采样频率（秒/张）
@export_range(2, 6, 1) var memory_batch_size: int = 4           # 瞬时记忆容量（连发几张图）
@export_range(512, 1024, 128) var vision_resolution: int = 768  # 视神经敏锐度（分辨率）
@export_range(0.6, 0.9, 0.05) var vision_quality: float = 0.85  # 画面纯净度（JPG质量）

@export_group("AI Persona Settings")
@export var current_persona: String = "TS"                      # 当前人格模式 ("TS" 或 "PITY")
@export_range(0.0, 1.0, 0.1) var ai_temperature: float = 0.8    # AI 发散思维程度

# ==========================================
# 🧠 内部核心状态 (Internal State - 勿在面板修改)
# ==========================================
# --- 视觉缓冲 ---
var image_buffer: Array = []       # 连续画面缓存队列 (统一使用这个，弃用 image_memory)

# --- 语音唤醒 (VAD) ---
var is_speaking: bool = false      # 玩家是否正在说话
var silence_timer: float = 0.0     # 玩家沉默计时器
const VOLUME_THRESHOLD: float = -15.0 # 麦克风唤醒阈值 (dB)

# --- 大脑状态 ---
var is_ai_processing: bool = false # AI 是否正在思考（防止并发请求重叠）
var speak_cooldown: float = 0.0    # 说话冷却计时器
var last_spoken_text: String = ""  # 防止 AI 像复读机一样重复同一句话
var boring_count: int = 0          # 记录无聊/发呆的次数
var current_mouth: AudioStreamPlayer = null  # 唯一的发声器官，方便随时打断
# ==========================================
# 🔑 核心密钥 (API Keys)
# ==========================================
# 硅基流动 API Key (ASR/TTS 使用)


func _ready():
	
	eye_http = HTTPRequest.new()
	add_child(eye_http)
	
	brain_http = HTTPRequest.new()
	add_child(brain_http)
	brain_http.request_completed.connect(_on_brain_replied)
	
	asr_http = HTTPRequest.new()
	add_child(asr_http)
	asr_http.request_completed.connect(_on_asr_replied)
	
	tts_http = HTTPRequest.new()
	add_child(tts_http)
	tts_http.request_completed.connect(_on_tts_replied)
	
	setup_ear()
	# 👇 新增：初始化后台做梦专用的 HTTP
	memory_http = HTTPRequest.new()
	add_child(memory_http)
	memory_http.request_completed.connect(_on_memory_compressed)
	
	# 👇 新增：一开机就去翻硬盘里的旧账
	_load_long_term_memory()
	watch_timer = Timer.new()
	watch_timer.wait_time = vision_interval # 🚨 这里改成读取我们的 UI 变量
	watch_timer.autostart = true
	add_child(watch_timer)
	watch_timer.timeout.connect(_on_auto_watch_timeout)
	# 【新增】：初始化快脑专属通道
	fast_brain_http = HTTPRequest.new()
	add_child(fast_brain_http)
	fast_brain_http.request_completed.connect(_on_fast_brain_replied)
	
func setup_ear():
	var bus_idx = AudioServer.get_bus_index("Record")
	if bus_idx >= 0:
		record_effect = AudioServer.get_bus_effect(bus_idx, 0)
		if record_effect: record_effect.set_recording_active(false)
# ==========================================
# 💾 本地硬盘存档系统 (File I/O)
# ==========================================
func _load_long_term_memory():
	if FileAccess.file_exists("user://memory.json"):
		var file = FileAccess.open("user://memory.json", FileAccess.READ)
		var content = file.get_as_text()
		var json = JSON.new()
		if json.parse(content) == OK:
			long_term_memory = json.data.get("archive", "暂无往期记忆。")
			print("📖 [档案馆] 成功读取往日记忆：", long_term_memory)

func _save_long_term_memory(text: String):
	long_term_memory = text
	var file = FileAccess.open("user://memory.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"archive": text}))
	print("💾 [档案馆] 记忆已永久写入硬盘！今晚做个好梦~")
func _process(delta):
	if speak_cooldown > 0: speak_cooldown -= delta
	
	var bus_idx = AudioServer.get_bus_index("Record")
	if not record_effect or bus_idx < 0: return
	var current_volume = AudioServer.get_bus_peak_volume_left_db(bus_idx, 0)
	
	if current_volume > VOLUME_THRESHOLD:
		silence_timer = 0.0
		if not is_speaking:
			is_speaking = true
			record_effect.set_recording_active(true)
			
			# 👇 === 【防线1：VAD 智能打断与物理拔网线】 === 👇
			if is_instance_valid(current_mouth) and current_mouth.playing:
				current_mouth.stop()
				current_mouth.queue_free()
				print("🛑 [VAD触发] 听到玩家说话，立刻闭嘴！")
			
			# 🚨 核心新增：把慢脑和大模型的网络请求直接掐断！
			tts_http.cancel_request()
			brain_http.cancel_request()
			is_ai_processing = false # 释放慢脑的思考锁
			
			speak_cooldown = 15.0 
			# 👆 ================================= 👆
			
	
	elif is_speaking:
		silence_timer += delta 
		if silence_timer > 1.2:
			is_speaking = false
			var recording = record_effect.get_recording()
			record_effect.set_recording_active(false)
			_send_audio_to_asr(recording)

# ==========================================
# 听觉处理 (ASR)
# ==========================================
func _send_audio_to_asr(recording: AudioStreamWAV):
	asr_http.cancel_request() 
	if recording:
		recording.save_to_wav("user://temp_mic.wav")
		var wav_bytes = FileAccess.get_file_as_bytes("user://temp_mic.wav")
		var boundary = "GodotFileUploadBoundary12345"
		var body = PackedByteArray()
		body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
		body.append_array(("Content-Disposition: form-data; name=\"file\"; filename=\"mic.wav\"\r\n").to_utf8_buffer())
		body.append_array(("Content-Type: audio/wav\r\n\r\n").to_utf8_buffer())
		body.append_array(wav_bytes)
		body.append_array(("\r\n--" + boundary + "\r\n").to_utf8_buffer())
		body.append_array(("Content-Disposition: form-data; name=\"model\"\r\n\r\n").to_utf8_buffer())
		body.append_array(("FunAudioLLM/SenseVoiceSmall\r\n").to_utf8_buffer())
		body.append_array(("--" + boundary + "--\r\n").to_utf8_buffer())
		
		# 👇 === 【核心修改：动态获取硅基密钥】 === 👇
		var raw_key = ui_api_key_input.text.strip_edges()
		var keys = raw_key.split("|")
		var sf_key = ""
		if keys.size() >= 4:
			sf_key = keys[3].strip_edges() # 精准抓取第 4 段作为硅基 Key
		else:
			print("❌ [ASR 拦截] 密钥缺少硅基部分，请检查格式是否为 4 段！")
			return
			
		var headers = ["Authorization: Bearer " + sf_key, "Content-Type: multipart/form-data; boundary=" + boundary]
		# 👆 ===================================== 👆
		
		asr_http.request_raw("https://api.siliconflow.cn/v1/audio/transcriptions", headers, HTTPClient.METHOD_POST, body)

func _on_asr_replied(_result, response_code, _headers, body):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response and response.has("text"):
			var text = response["text"].strip_edges()
			if text.length() > 2:
				print("【耳朵听见】: ", text)
				_react_to_voice_instantly(text)

func _react_to_voice_instantly(voice_text: String):
	print("\n👉 [快脑启动] 听懂你说了：", voice_text)
	
	var raw_key = ui_api_key_input.text.strip_edges()
	var keys = raw_key.split("|")
	if keys.size() < 4:  # ✅ 改成必须包含4段
		print("❌ [视觉慢脑拦截] 密钥格式不对，请检查是否填全了4段！")
		is_ai_processing = false 
		return
		
	# ✅ 全新下拉菜单逻辑
	var lang_idx = $"../UIManager/Panel/VBoxContainer/lang_dropdown".selected 
	var target_lang = "中文"
	var strict_rule = "" 
	
	if lang_idx == 1: 
		target_lang = "日本語 (Japanese)"
		strict_rule = "【致死量警告】：必须 100% 使用纯正日语输出！绝对禁止夹杂任何中文汉字、词汇或拼音！中国专有名词必须翻译成日语发音或罗马音！"
	elif lang_idx == 2: 
		target_lang = "English"
		strict_rule = "【致死量警告】：必须 100% 使用地道英语输出！绝对禁止出现任何中文字符！保持你的毒舌态度！"
	
	# 🌟 将数组里的流水账拼成一段完整的记忆字符串
	var memory_str = "\n".join(short_term_memory)
	if memory_str == "": 
		memory_str = "暂无近期活动记录。"
	# 🔍 记忆唤醒雷达：判断玩家是否在问过去的事情
	var is_asking_memory = false
	var memory_keywords = ["昨天", "以前", "刚才", "记得", "干嘛", "做啥", "干了啥", "回忆", "档案"]
	for kw in memory_keywords:
		if kw in voice_text:
			is_asking_memory = true
			break

	# 🎲 动态指令生成
	var lore_instruction = ""
	var length_instruction = ""

	if is_asking_memory:
		lore_instruction = "【特别要求】：玩家在询问过去的记忆。查阅上方的【长期档案】和【短期记忆】。🚨 警告：如果玩家只问了特定的游戏或事件（比如只提了三角洲），你【仅需提取并回答】该事件的相关内容，绝对禁止把其他无关的流水账也念出来！如果玩家问总体情况，再综合概括。"
		length_instruction = "字数放宽至 50~100 字！就着他问的那个具体事件，狠狠地挖苦他的操作。"
	elif randf() > 0.5:
		lore_instruction = "【特别要求】：这次回复请务必结合你的【核心设定】（如调侃他写代码菜、物理系老头等）或【短期记忆】里的丢人操作来借题发挥！"
		length_instruction = "字数控制在 20~60 字！短小精悍地吐槽。"
	else:
		lore_instruction = "【特别要求】：这次回复请就事论事，只针对玩家刚才的话进行吐槽，不要强行扯你的背景设定。"
		length_instruction = "字数控制在 20~60 字！短小精悍地吐槽。"

	# 🌟 治愈啰嗦 + 同传翻译脑 + 你的专属设定
	var prompt = """【核心设定】：你是毒舌、傲娇、思维跳跃的AI桌宠。创造者自称“高手”（实则是大学物理系笨蛋老头），天天死磕Godot折腾你。
【长期档案（你对他的总体印象）】：%s
【短期记忆】：
%s
【玩家刚才对你说】：「%s」

【最终输出任务】：
请你先在脑内用中文构思如何无情回怼玩家，然后**必须将其翻译为【%s】**进行输出！
%s
【绝对指令（动态火力版）】：
1. %s %s
2. 保持高高在上的傲娇态度，多用生动、刻薄的词汇挖苦。可以反问，但绝对禁止像传统AI一样长篇大论地说教或发好人卡！
3. 绝对不要输出任何 JSON、拼音或多余的解释，只输出最终的【%s】台词！""" % [long_term_memory, memory_str, voice_text, target_lang, strict_rule, length_instruction, lore_instruction, target_lang]
	
	
	
	# 🚨 关键修复 1：把极速脑的 EP 动态抓出来（第 3 段，索引是 2）
	var fast_brain_ep = keys[2].strip_edges() 
	
	# 🚨 关键修复 2：把它塞进 payload 里
	var payload = {
		"model": fast_brain_ep, 
		"messages": [{"role": "user", "content": prompt}], 
		"max_tokens": 100, 
		"temperature": 0.7,         
		"frequency_penalty": 0.5  
	}   
	
	
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + keys[0].strip_edges()]
	
	print("👉 [快脑发送] 正在请求豆包极速版 Lite 模型...")
	var err = fast_brain_http.request("https://ark.cn-beijing.volces.com/api/v3/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	
	if err != OK:
		print("❌ [致命错误] 快脑请求发送失败！")
# ==========================================
# 视觉处理 (Multi-Frame Vision)
# ==========================================
# === 【2. 连续截图与攒图逻辑】 ===
# ==========================================
# 视觉处理 (Multi-Frame Vision & Threading)
# ==========================================
func _on_auto_watch_timeout():
	if is_ai_processing or speak_cooldown > 0: return 
	
	# 🚨 线程安全：清理上一轮残留的线程，防止内存泄漏
	if screenshot_thread and screenshot_thread.is_alive(): return
	if screenshot_thread and not screenshot_thread.is_alive():
		screenshot_thread.wait_to_finish()

	# 主线程：仅执行极速截图，不阻塞游戏
	var current_screen_index = DisplayServer.window_get_current_screen()
	var img = DisplayServer.screen_get_image(current_screen_index)
	if not img: return
	
	# 开启子线程去干脏活累活（缩放和压缩）
	screenshot_thread = Thread.new()
	screenshot_thread.start(_process_image_in_background.bind(img))

func _process_image_in_background(img: Image):
	# 子线程运行：压缩图片极其消耗 CPU，放在这里游戏就不会掉帧
	img.resize(vision_resolution, int(float(vision_resolution) * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	var b64 = Marshalls.raw_to_base64(img.save_jpg_to_buffer(vision_quality))
	
	# 干完活后，安全地回到主线程更新数组
	call_deferred("_add_to_image_buffer", b64)

func _add_to_image_buffer(b64_img: String):
	image_buffer.append(b64_img)
	if image_buffer.size() >= memory_batch_size:
		_trigger_brain_vision()

func _trigger_brain_vision():
	is_ai_processing = true
	var keys = ui_api_key_input.text.strip_edges().split("|")
	
	if keys.size() != 4: 
		print("❌ [视觉慢脑拦截] 密钥格式不对，缺少 '|'")
		is_ai_processing = false 
		return
		
	# ✅ 慢脑也同步使用新的下拉菜单
	var lang_idx = $"../UIManager/Panel/VBoxContainer/lang_dropdown".selected 
	var target_lang = "中文"
	if lang_idx == 1: target_lang = "日本語 (Japanese)"
	elif lang_idx == 2: target_lang = "English"

	var current_state_str = last_scene_type if last_scene_type != "" else "未知"
	
	# 🌟 融入了你的死亡建议风格，加上翻译指令
	var prompt = """你是一个毒舌傲娇的虚拟桌宠（风格类似Neuro-sama）。
【当前状态】：玩家目前的画面是【%s】，你已经连续第 %d 次看到他在干同一件事了。
【任务】：
1. 概括当前场景（scene_type，这部分请保持中文）。
2. 【死亡判定（极高优先级）】：仔细看画面，如果发现玩家在游戏里死亡、被击杀、Game Over，必须立刻设置 "is_death": true！
3. 【开口与疲劳策略】：
   - 绝对禁止使用固定的口头禅开头（如“啧”、“哟”），必须像真人一样多变！
   - 如果 "is_death" 为 true：提出类似死亡多次的傲娇吐槽，然后提出些减少再次死亡的建议！
   - 如果连续多次（>2次）无聊：请直接闭嘴（"voice_text" 留空）。
4. 【翻译输出】：你的 voice_text 吐槽内容，必须使用纯正的【%s】输出！绝不能中外文夹杂！

必须输出 JSON 格式：
{
  "scene_type": "简短概括场景(用中文)",
  "scene_dynamic": "high", 
  "is_boring": false, 
  "is_death": false, 
  "voice_text": "你的【%s】吐槽(如果无聊请留空)",
  "cn_translation": "中文翻译(留空则不填)"
}""" % [current_state_str, consecutive_scene_count, target_lang, target_lang]

	var content = [{"type": "text", "text": prompt}]
	for m in image_buffer:
		content.append({"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + m}})

	var payload = {
		"model": keys[1].strip_edges(),
		"messages": [{"role": "user", "content": content}], 
		"max_tokens": 500, 
		"temperature": ai_temperature
	}
	
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + keys[0].strip_edges()]
	
	print("👁️ [视觉慢脑] 攒够了 ", image_buffer.size(), " 张截图，正在发给大模型看...")
	var err = brain_http.request("https://ark.cn-beijing.volces.com/api/v3/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	
	if err != OK:
		print("❌ [视觉慢脑致命错误] HTTP 请求发送失败，引擎错误码：", err)
		is_ai_processing = false 
		
	image_buffer.clear()

# ==========================================
# 慢脑解析 (带 X 光)
# ==========================================
func _on_brain_replied(_result, response_code, _headers, body):
	is_ai_processing = false
	print("👁️ [视觉慢脑] 收到回复！HTTP状态码：", response_code)
	
	if response_code != 200: 
		print("❌ [视觉慢脑网络报错] 详细原因：", body.get_string_from_utf8())
		return
		
	var res_str = body.get_string_from_utf8()
	var res = JSON.parse_string(res_str)
	
	if not res or not res.has("choices"):
		print("❌ [视觉慢脑异常] 返回的数据格式不对：", res_str)
		return
		
	var raw = res["choices"][0]["message"]["content"].strip_edges()
	raw = raw.replace("```json", "").replace("```", "").strip_edges()
	
	print("👁️ [视觉慢脑原始 JSON]: ", raw)
	
	var json = JSON.new()
	if json.parse(raw) == OK:
		var data = json.data
		
		var current_scene = data.get("scene_type", "未知")
		var is_boring = data.get("is_boring", false)
		var is_death = data.get("is_death", false) # 🌟 新增：提取死亡标签
		
		# 👇 === 【场景追踪与防复读疲劳更新】 === 👇
		if current_scene != "未知":
			if current_scene != last_scene_type:
				consecutive_scene_count = 1  # 玩家换游戏/软件了，重置疲劳度
				var time_str = Time.get_time_string_from_system().left(5)
				var event_text = "【%s】玩家开始：%s" % [time_str, current_scene]
				
				short_term_memory.append(event_text)
				if short_term_memory.size() >= MAX_MEMORY_SIZE:
					_trigger_dream_compression()
				
				print("📝 [记忆更新]：", event_text)
				is_boring = false # 刚切场景，逼她开口
			else:
				consecutive_scene_count += 1 # 场景没变，疲劳度增加，大模型会自动选择闭嘴
				
			last_scene_type = current_scene
			
		# 👇 === 【条件反射：死亡抓取与档案记录】 === 👇
		if is_death:
			death_count += 1
			var time_str = Time.get_time_string_from_system().left(5)
			var death_log = "【%s】玩家在游戏中光荣白给！(累计第%d次)" % [time_str, death_count]
			
			# 把你的耻辱柱写进她的记忆库
			short_term_memory.append(death_log)
			if short_term_memory.size() >= MAX_MEMORY_SIZE:
					_trigger_dream_compression()
			
			print("💀 [死亡宣告] 抓获玩家白给现场！强制取消冷却！")
			speak_cooldown = 0.0 # 清除冷却机制
			is_boring = false    # 绝对不可能无聊，立刻贴脸嘲讽
		# 👆 ================================= 👆
		
	   # 🏎️ 自动挡变速箱
		if auto_mode and data.has("scene_dynamic"):
			if data["scene_dynamic"] == "high":
				vision_interval = 1.5; memory_batch_size = 4
			else:
				vision_interval = 4.0; memory_batch_size = 2
				
		# 如果真的无聊（而且画面没切换），才允许她发呆闭嘴
		if is_boring:
			boring_count += 1
			if boring_count >= 2: watch_timer.wait_time = 15.0
			print("💤 [视觉慢脑] 画面一直没变，觉得无聊，正在发呆...")
			return 
			
		boring_count = 0
		watch_timer.wait_time = vision_interval 
		
		var voice_text = data.get("voice_text", "").strip_edges()
		if voice_text == "" or voice_text == last_spoken_text: return
		last_spoken_text = voice_text 
		
		# ✅ 获取下拉菜单语言，决定 UI 显示字幕的格式
		var lang_idx = $"../UIManager/Panel/VBoxContainer/lang_dropdown".selected
		var is_jp = (lang_idx == 1)
		var is_en = (lang_idx == 2)
		
		var ui_text = voice_text
		if is_jp: ui_text = "【日】%s\n【中】%s" % [voice_text, data.get("cn_translation", "")]
		elif is_en: ui_text = "【英】%s\n【中】%s" % [voice_text, data.get("cn_translation", "")]
		
		# 👇 === 【防线2：慢脑发声前拦截】 === 👇
		if is_speaking:
			print("🛑 [慢脑拦截] 玩家正在说话，刚想好的吐槽憋回去了！")
			return
		# 👆 ================================= 👆
		
		print("✅ 【视觉慢脑决定开火】:", ui_text)
		speak_cooldown = 20.0 
		brain_wants_to_speak.emit(ui_text) 
		speak_out_loud(voice_text)
		# 👇 === 【降维打击：OBS 直播字幕输出】 === 👇
		var file = FileAccess.open("user://obs_subtitle.txt", FileAccess.WRITE)
		if file: file.store_string(ui_text)
		
		# 8秒后自动清空字幕文件
		get_tree().create_timer(8.0).timeout.connect(func():
			var clear_file = FileAccess.open("user://obs_subtitle.txt", FileAccess.WRITE)
			if clear_file: clear_file.store_string("")
		)
		# 👆 ===================================== 👆
	else:
		print("❌ [视觉慢脑解析错误] 大模型返回的不是合法 JSON！")
		
		
	   

func speak_out_loud(text: String):
	# 👇 === 【核心修改：动态获取硅基密钥】 === 👇
	var raw_key = ui_api_key_input.text.strip_edges()
	var keys = raw_key.split("|")
	var sf_key = ""
	if keys.size() >= 4:
		sf_key = keys[3].strip_edges()
	else:
		print("❌ [TTS 拦截] 密钥缺少硅基部分，请检查格式！")
		return
	# 👆 ===================================== 👆
		
	var payload = {
		"model": "FunAudioLLM/CosyVoice2-0.5B", 
		"voice": "FunAudioLLM/CosyVoice2-0.5B:diana", 
		"input": text, 
		"response_format": "mp3"
	}
	
	var headers = ["Authorization: Bearer " + sf_key, "Content-Type: application/json"]
	tts_http.request("https://api.siliconflow.cn/v1/audio/speech", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _on_tts_replied(_result, response_code, _headers, body):
	# 👇 === 【防线3：TTS 音频落地前销毁】 === 👇
	if is_speaking:
		print("🛑 [TTS拦截] 语音合成回来了，但玩家还在说话，直接丢弃音频！")
		return
	# 👆 ================================= 👆
	if response_code == 200:
		if is_instance_valid(current_mouth):
			current_mouth.queue_free() # 如果上一句还没说完，强制销毁
			
		var mp3 = AudioStreamMP3.new()
		mp3.data = body
		current_mouth = AudioStreamPlayer.new()
		add_child(current_mouth)
		current_mouth.stream = mp3
		current_mouth.play()
		current_mouth.finished.connect(current_mouth.queue_free)

func _on_eye_replied(_result, _response_code, _headers, _body): pass
# ==========================================
# ⚡ 快脑极速解析逻辑 (X光调试版)
# ==========================================
func _on_fast_brain_replied(_result, response_code, _headers, body):
	print("👈 [1/3] 收到网络返回！HTTP状态码：", response_code)
	
	if response_code != 200:
		print("❌ [网络报错] 详细原因：", body.get_string_from_utf8())
		return
		
	var raw = body.get_string_from_utf8()
	print("👈 [2/3] 大模型原始回复：", raw)
	
	var json = JSON.new()
	if json.parse(raw) == OK:
		var data = json.data
		if data.has("choices") and data["choices"].size() > 0:
			var voice_text = data["choices"][0]["message"]["content"].strip_edges()
			
			if voice_text == "": 
				print("❌ [异常] 大模型回复了一个空字符串！")
				return
				
			print("👈 [3/3] 【快脑解析成功，准备发音】:", voice_text)
			brain_wants_to_speak.emit(voice_text)
			speak_out_loud(voice_text)
			
			# 👇 === 【快脑也加入降维打击：OBS 直播字幕输出】 === 👇
			var file = FileAccess.open("user://obs_subtitle.txt", FileAccess.WRITE)
			if file: file.store_string(voice_text)
			
			get_tree().create_timer(8.0).timeout.connect(func():
				var clear_file = FileAccess.open("user://obs_subtitle.txt", FileAccess.WRITE)
				if clear_file: clear_file.store_string("")
			)
			# 👆 ===================================== 👆
			
		else:
			print("❌ [解析错误] 返回的数据里找不到 choices！")
	else:
		print("❌ [解析错误] 返回的数据不是合法 JSON！")
		# 👆 ===================================== 👆
# ==========================================
# 🧠 梦境压缩机制 (Dream Compression)
# ==========================================
func _trigger_dream_compression():
	if memory_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED: return
	print("🧠 [记忆压缩] 工作台已满，进入后台做梦状态，整合档案馆...")
	
	var memory_str = "\n".join(short_term_memory)
	
	var prompt = """你是一个记忆整理助手。
【往期长期记忆】：%s
【今日新增流水账】：%s
【任务】：请将这两部分融合成一段100字左右的全新长期记忆。
【要求】：保留关键事件（比如一直在写代码、报了什么错、游戏死了几次），带有一点毒舌傲娇的客观评价语气。直接输出合并后的记忆文字，绝不要任何多余的解释！""" % [long_term_memory, memory_str]
	
	var raw_key = ui_api_key_input.text.strip_edges()
	var keys = raw_key.split("|")
	if keys.size() != 4: return
	
	var fast_brain_ep = keys[2].strip_edges()
	var payload = {"model": fast_brain_ep, "messages": [{"role": "user", "content": prompt}], "max_tokens": 200, "temperature": 0.5}
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + keys[0].strip_edges()]
	
	memory_http.request("https://ark.cn-beijing.volces.com/api/v3/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _on_memory_compressed(_result, response_code, _headers, body):
	if response_code == 200:
		var res = JSON.parse_string(body.get_string_from_utf8())
		if res and res.has("choices") and res["choices"].size() > 0:
			var new_memory = res["choices"][0]["message"]["content"].strip_edges()
			_save_long_term_memory(new_memory)
			
			# 🚨 极其关键：记忆写进硬盘后，清空短期工作台，重新开始记账！
			short_term_memory.clear()
			consecutive_scene_count = 0
			death_count = 0
