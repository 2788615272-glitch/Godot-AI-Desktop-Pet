extends Window

@onready var bg_panel = $SubtitleBackground
@onready var text_label = $SubtitleBackground/Label
@onready var clear_timer = $ClearTimer

func _ready():
	# 1. 初始化：把自己撑满屏幕宽度，并贴在最底边
	var screen_size = DisplayServer.screen_get_size()
	size = Vector2i(screen_size.x, 200) 
	position = Vector2i(0, screen_size.y - size.y) 
	
	# 2. 开启鼠标穿透 (不用找面板复选框了，代码直接搞定)
	mouse_passthrough_polygon = PackedVector2Array([Vector2(-1, -1)])
	
	bg_panel.hide()
	
	# 3. 连接大脑 (注意路径退一步，因为你现在是独立窗口了)
	var ai_manager = get_node("../AIManager") 
	if ai_manager:
		ai_manager.brain_wants_to_speak.connect(_on_ai_speak)
	
	clear_timer.timeout.connect(func(): bg_panel.hide())

func _on_ai_speak(text: String):
	text_label.text = text
	bg_panel.show()
	var show_time = max(3.0, float(text.length()) * 0.2)
	clear_timer.start(show_time)
