extends CanvasLayer

# ==========================================
# ⚙️ 基础节点绑定
# ==========================================
@onready var panel = $Panel
@onready var vbox = $Panel/VBoxContainer
@onready var model_select = $Panel/VBoxContainer/ModelSelect
@onready var api_key_input = $Panel/VBoxContainer/APIKeyInput
@onready var get_key_button = $Panel/VBoxContainer/GetKeyButton
@onready var temp_slider = $Panel/VBoxContainer/TempSlider

@onready var ai_manager = $"../AIManager"
@onready var pet_body = $".." 

# ==========================================
# 🎛️ AI 视觉与自动挡控制节点绑定 (编辑器里建好的)
# ==========================================
@onready var auto_toggle = $Panel/VBoxContainer/AutoToggle
@onready var interval_slider = $Panel/VBoxContainer/IntervalContainer/IntervalSlider
@onready var interval_val_label = $Panel/VBoxContainer/IntervalContainer/IntervalValLabel
@onready var batch_slider = $Panel/VBoxContainer/BatchContainer/BatchSlider
@onready var batch_val_label = $Panel/VBoxContainer/BatchContainer/BatchValLabel

# ==========================================
# 🔧 内部状态变量
# ==========================================
var tray_icon: StatusIndicator
var tray_menu: PopupMenu
var dragging_panel: bool = false
var drag_offset: Vector2



func _ready():
	panel.hide()
	
	# 初始化模型选择器
	model_select.clear()
	model_select.add_item("云端 硅基流动 (旧版未启用)") 
	model_select.add_item("预留位置") 
	model_select.add_item("云端 豆包 Vision (主力稳定版)") # Index 2
	
	api_key_input.text = "" 
	model_select.selected = 2
	_on_model_changed(2)
	
	# 基础信号连接
	get_key_button.pressed.connect(_on_get_key_button_pressed)
	model_select.item_selected.connect(_on_model_changed)
	temp_slider.value_changed.connect(_on_temp_changed)
	panel.gui_input.connect(_on_panel_gui_input)
	
	# 🚨 连接编辑器里建好的 AI 控制 UI 信号
	if auto_toggle: auto_toggle.toggled.connect(_on_auto_mode_toggled)
	if interval_slider: interval_slider.value_changed.connect(_on_interval_changed)
	if batch_slider: batch_slider.value_changed.connect(_on_batch_changed)
	
	# 初始化外部系统
	setup_tray_icon()
	
	
	# 初始化滑块锁定状态
	if auto_toggle:
		_update_slider_state(auto_toggle.button_pressed)
# ==========================================
# ⌨️ 键盘快捷键监听
# ==========================================
func _input(event):
	# 按 Esc 键可以快速隐藏/显示控制台
	if event.is_action_pressed("ui_cancel"):
		panel.visible = !panel.visible


# ==========================================
# 🖱️ 拖拽和托盘代码
# ==========================================
func _on_panel_gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging_panel = true
			drag_offset = event.position 
		else: dragging_panel = false
	elif event is InputEventMouseMotion and dragging_panel:
		panel.global_position = panel.get_global_mouse_position() - drag_offset

func setup_tray_icon():
	tray_menu = PopupMenu.new()
	add_child(tray_menu)
	tray_menu.add_item("⚙️ 显示控制台", 0)
	tray_menu.add_item("👻 召唤桌宠", 1)
	tray_menu.add_separator()
	tray_menu.add_item("❌ 退出", 2)
	tray_menu.id_pressed.connect(func(id): match id:
		0: panel.visible = !panel.visible
		1: pet_body.visible = !pet_body.visible
		2: get_tree().quit()
	)
	tray_icon = StatusIndicator.new()
	tray_icon.icon = preload("res://assets/face_idle.png") 
	add_child(tray_icon)
	tray_icon.menu = tray_menu.get_path()

func _on_get_key_button_pressed(): OS.shell_open("https://console.volcengine.com/")

func _on_model_changed(index: int):
	if index == 2:
		api_key_input.editable = true
		api_key_input.placeholder_text = "格式: 豆包Key|视觉EP|极速文本EP|硅基Key"
	else:
		api_key_input.editable = false
		api_key_input.placeholder_text = "此版本代码仅支持豆包接口"

func _on_temp_changed(value: float): 
	if ai_manager: ai_manager.ai_temperature = value

# ==========================================
# 🏎️ 联动 AIManager 的响应函数 (自动挡 & 滑块)
# ==========================================
func _on_auto_mode_toggled(button_pressed: bool):
	if ai_manager: ai_manager.auto_mode = button_pressed
	_update_slider_state(button_pressed)
	print("自动变速挡状态: ", button_pressed)

func _on_interval_changed(value: float):
	if interval_val_label:
		interval_val_label.text = "%.1f 秒" % value 
	if not ai_manager: return
	ai_manager.vision_interval = value
	if ai_manager.watch_timer:
		ai_manager.watch_timer.wait_time = value

func _on_batch_changed(value: float):
	if batch_val_label:
		batch_val_label.text = "%d 张" % int(value) 
	if ai_manager: 
		ai_manager.memory_batch_size = int(value)

func _update_slider_state(is_auto: bool):
	# 安全校验，防止节点丢失
	if not interval_slider or not batch_slider: return 
	
	interval_slider.editable = !is_auto
	batch_slider.editable = !is_auto
	
	var alpha = 0.5 if is_auto else 1.0
	interval_slider.modulate.a = alpha
	batch_slider.modulate.a = alpha

func _process(delta):
	# 每帧同步：如果开启自动挡，滑块会跟着 AI 的大脑设定自己移动
	if ai_manager and auto_toggle and interval_slider and batch_slider:
		if auto_toggle.button_pressed:
			if interval_slider.value != ai_manager.vision_interval:
				interval_slider.set_value_no_signal(ai_manager.vision_interval)
				if interval_val_label: 
					interval_val_label.text = "%.1f 秒" % ai_manager.vision_interval
				
			if batch_slider.value != ai_manager.memory_batch_size:
				batch_slider.set_value_no_signal(ai_manager.memory_batch_size)
				if batch_val_label: 
					batch_val_label.text = "%d 张" % ai_manager.memory_batch_size
