extends CharacterBody2D

# --- 物理与外观配置 ---
@export var gravity: float = 1200.0
@export var bounce_coefficient: float = 0.6
@export var interact_radius: float = 50.0
@export var stretch_factor: float = 0.0005 
@export var max_stretch: float = 1.5        
@export var min_squash: float = 0.5        
@export var deform_lerp_speed: float = 15.0 

const TEXTURE_FACE_IDLE = preload("res://assets/face_idle.png")
const TEXTURE_FACE_SQUISH = preload("res://assets/face_squish.png")
const TEXTURE_FACE_STRUGGLE = preload("res://assets/face_struggle.png")

var is_dragging: bool = false
var last_mouse_pos: Vector2
var throw_velocity: Vector2

@onready var screen_size = DisplayServer.screen_get_size()
@onready var body_sprite: Sprite2D = $Body
@onready var face_sprite: Sprite2D = $Body/Face
@onready var bubble = $SpeechBubble
@onready var bubble_panel = $SpeechBubble/PanelContainer
@onready var bubble_label = $SpeechBubble/PanelContainer/Label

var bubble_tween: Tween 
@onready var base_scale: Vector2 = body_sprite.scale 
var deform_tween: Tween 

@onready var ai_manager = $AIManager 
@onready var ui_panel = $UIManager/Panel

# --- 初始化 (防鬼影关键配置) ---
func _ready():
	# 1. 窗口透明与置顶设置
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	
	# 2. 引擎底层透明支持
	get_tree().root.transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0)) # 确保底色全透
	
	# 3. 铺满全屏 (修复残影的核心：窗口必须覆盖活动区域)
	DisplayServer.window_set_size(screen_size)
	DisplayServer.window_set_position(Vector2i(0, 0))
	
	face_sprite.texture = TEXTURE_FACE_IDLE
	global_position = screen_size / 2.0 
	
	# 信号连接
	if ai_manager:
		ai_manager.brain_wants_to_speak.connect(_on_ai_speak)
	
	update_mouse_passthrough()
	bubble.hide()

# --- 交互逻辑 ---
func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var distance = global_position.distance_to(get_global_mouse_position())
			if distance < interact_radius:
				is_dragging = true
				last_mouse_pos = get_global_mouse_position()
				velocity = Vector2.ZERO
				face_sprite.texture = TEXTURE_FACE_STRUGGLE
		else:
			if is_dragging:
				is_dragging = false
				velocity = throw_velocity
				face_sprite.texture = TEXTURE_FACE_IDLE

# --- 物理与形变逻辑 ---
func _physics_process(delta):
	if not visible:
		return
		
	if is_dragging:
		var current_mouse_pos = get_global_mouse_position()
		global_position = current_mouse_pos
		throw_velocity = (current_mouse_pos - last_mouse_pos) / delta
		last_mouse_pos = current_mouse_pos
		
		# 拖拽时的动态拉伸
		var target_scale_y = 1.0 + clamp(abs(throw_velocity.y) * stretch_factor, 0, max_stretch - 1.0)
		var target_scale_x = 1.0 / target_scale_y
		body_sprite.scale = body_sprite.scale.lerp(base_scale * Vector2(target_scale_x, target_scale_y), deform_lerp_speed * delta)
	else:
		velocity.y += gravity * delta
		var pre_bounce_vel = velocity
		global_position += velocity * delta
		handle_screen_bounce(pre_bounce_vel)
		
		# 自由落体时的形变恢复
		if not (deform_tween and deform_tween.is_running()):
			if abs(velocity.y) > 100 and global_position.y < screen_size.y - interact_radius - 10:
				var stretch_amount = 1.0 + clamp(abs(velocity.y) * stretch_factor, 0, max_stretch - 1.0)
				body_sprite.scale = body_sprite.scale.lerp(base_scale * Vector2(1.0 / stretch_amount, stretch_amount), deform_lerp_speed * delta)
			else:
				body_sprite.scale = body_sprite.scale.lerp(base_scale, deform_lerp_speed * delta)
				if abs(velocity.y) < 50 and abs(velocity.x) < 50:
					face_sprite.texture = TEXTURE_FACE_IDLE
					
	# 每一帧更新点击区域，确保点击精准
	update_mouse_passthrough()

func handle_screen_bounce(pre_vel: Vector2):
	var pos = global_position
	if pos.x < interact_radius:
		pos.x = interact_radius
		velocity.x = abs(velocity.x) * bounce_coefficient
		trigger_squash(abs(pre_vel.x), true) 
	elif pos.x > screen_size.x - interact_radius:
		pos.x = screen_size.x - interact_radius
		velocity.x = -abs(velocity.x) * bounce_coefficient
		trigger_squash(abs(pre_vel.x), true) 
	
	if pos.y < interact_radius:
		pos.y = interact_radius
		velocity.y = abs(velocity.y) * bounce_coefficient
		trigger_squash(abs(pre_vel.y), false) 
	elif pos.y > screen_size.y - interact_radius:
		pos.y = screen_size.y - interact_radius
		if abs(velocity.y) < 50: 
			velocity.y = 0
		else:
			velocity.y = -abs(velocity.y) * bounce_coefficient
			trigger_squash(abs(pre_vel.y), false) 
	global_position = pos

func trigger_squash(impact_force: float, is_horizontal: bool):
	if impact_force > 150:
		var squash = clamp(1.0 - impact_force * stretch_factor * 2.0, min_squash, 1.0)
		var target_scale = base_scale
		if is_horizontal: target_scale = base_scale * Vector2(squash, 1.0 / squash)
		else: target_scale = base_scale * Vector2(1.0 / squash, squash)
		
		face_sprite.texture = TEXTURE_FACE_SQUISH
		if deform_tween: deform_tween.kill() 
		deform_tween = create_tween()
		deform_tween.tween_property(body_sprite, "scale", target_scale, 0.05)
		deform_tween.tween_property(body_sprite, "scale", base_scale, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

# ==========================================
# 🛡️ 大道至简：超级包围盒防裁剪算法
# ==========================================
func update_mouse_passthrough():
	if not visible:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(-1, -1)]))
		return

	# 1. 先算出小球的基础矩形
	var final_rect = Rect2(global_position - Vector2(interact_radius, interact_radius) * 1.2, Vector2(interact_radius, interact_radius) * 2.4)
	
	# 2. 如果气泡显示了，直接把气泡的矩形“吞”进来，变成一个包裹两者的更大方块
	if bubble and bubble.visible:
		var b_rect = Rect2(bubble_panel.global_position, bubble_panel.size).grow(5.0)
		final_rect = final_rect.merge(b_rect) # 核心魔法：自动计算包围盒！
		
	# 3. 如果面板显示了，也吞进来
	if ui_panel and ui_panel.visible:
		var p_rect = Rect2(ui_panel.global_position, ui_panel.size).grow(2.0)
		final_rect = final_rect.merge(p_rect)

	# 4. 把这个唯一且绝对不会交叉的“超级大方块”交给 Windows 系统
	var clickable_polygons = PackedVector2Array([
		final_rect.position,
		Vector2(final_rect.end.x, final_rect.position.y),
		final_rect.end,
		Vector2(final_rect.position.x, final_rect.end.y)
	])

	DisplayServer.window_set_mouse_passthrough(clickable_polygons)


# === 👇 下面这 3 个辅助函数也要一起贴进去哦 👇 ===

func _weld_rects_into_single_polygon(rects: Array[Rect2]) -> PackedVector2Array:
	if rects.size() == 0: return PackedVector2Array([Vector2(-1, -1)])
	
	# 建立一根靠在屏幕最左侧边缘的“隐形脊椎” (仅 1 像素宽，肉眼不可见)
	var main_beam = Rect2(0, 0, 1, screen_size.y)
	var polys: Array[PackedVector2Array] = [ _rect_to_poly(main_beam) ]
	
	for r in rects:
		var target_poly = _rect_to_poly(r)
		# 从脊椎拉一根横向的“隐形数据线”，精准插到每一个 UI 实体上
		var wire_poly = _rect_to_poly(Rect2(0, r.position.y + r.size.y / 2.0 - 1.0, r.position.x + 5.0, 2.0))
		
		# 引擎级合并：把实体、电线、脊椎融为一体！
		polys = _merge_poly_into_array(polys, target_poly)
		polys = _merge_poly_into_array(polys, wire_poly)
		
	# 经过 C++ 级的电焊，所有区块绝对连成了一个没有任何漏洞的单一多边形
	if polys.size() > 0: return polys[0]
	return PackedVector2Array([Vector2(-1, -1)])

func _merge_poly_into_array(polys: Array[PackedVector2Array], new_poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var to_merge = new_poly
	for p in polys:
		var merged = Geometry2D.merge_polygons(p, to_merge)
		if merged.size() == 1:
			to_merge = merged[0] # 两块碰到了，成功融合！
		else:
			result.append(p)     # 没碰到，原样保留放回池子
	result.append(to_merge)
	return result

func _rect_to_poly(r: Rect2) -> PackedVector2Array:
	# 简易生成顺时针矩形顶点
	return PackedVector2Array([ r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y) ])
func _add_rect_to_polygon(poly: PackedVector2Array, rect: Rect2):
	poly.append(rect.position)
	poly.append(Vector2(rect.end.x, rect.position.y))
	poly.append(rect.end)
	poly.append(Vector2(rect.position.x, rect.end.y))
	poly.append(rect.position) # 闭合

# --- 说话逻辑与智能时间 ---
func _on_ai_speak(text: String):
	if not visible: return
	face_sprite.texture = TEXTURE_FACE_SQUISH 
	say(text) # 🚨 删掉了原来这里硬编码的 5.0 秒

func say(text: String):
	var display_text = text
	# 过滤双语，只显示中文部分
	if "【中】" in text:
		display_text = text.split("【中】")[1].strip_edges()
	
	bubble.show()
	bubble_label.text = display_text
	bubble_label.visible_characters = 0
	
	# 👇 === 智能气泡时间计算 === 👇
	# 基础停留 3 秒；每多 1 个字就增加 0.2 秒的显示时间
	var show_time = max(3.0, float(display_text.length()) * 0.2)
	print("💬 [气泡] 本次字数：", display_text.length(), "，预计悬浮 ", show_time, " 秒")
	# 👆 ============================= 👆
	
	if bubble_tween: bubble_tween.kill()
	bubble_tween = create_tween()
	
	# 打字机特效：0.5 秒内把字“敲”完
	bubble_tween.tween_property(bubble_label, "visible_characters", display_text.length(), 0.5)
	
	# 停留我们刚才算出来的智能时间
	bubble_tween.tween_interval(show_time)
	
	# 时间到了，自动隐藏气泡
	bubble_tween.tween_callback(bubble.hide)
