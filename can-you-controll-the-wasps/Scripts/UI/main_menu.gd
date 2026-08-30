class_name MainMenu
extends Control

# 主菜单 / the main menu. 它是 run/main_scene，Play 才切进 world.tscn。
# The menu is the main scene; world.tscn only loads on Play.
#
# 做成**独立场景**而不是压在 world.tscn 上的一层：world 一 _ready 就开始生蜂、
# 起季节计时、排入侵表。当覆盖层的话要么让整局在菜单背后空跑，要么挨个摆六个
# director 的 process_mode——而独立场景一行都不用碰 world.tscn，重开一局也只是重载
# world starts spawning and ticking the moment it loads; an overlay would mean either a
# menu with a live game behind it or juggling six directors' process modes.

const WORLD_SCENE: String = "res://Scenes/world.tscn"

@export_group("Juice")
## 每个元素之间差多久入场 / the beat between elements
@export_range(0.0, 0.4, 0.01) var stagger: float = 0.07
## 从下方多远飘上来 / how far below each one starts
@export_range(0.0, 60.0, 1.0) var rise: float = 22.0
@export_range(0.05, 1.0, 0.01) var rise_time: float = 0.35
## 鼠标悬停时按钮胀多少 / how much a hovered button swells
@export_range(1.0, 1.2, 0.01) var hover_scale: float = 1.05

@onready var _title: Label = $Title
@onready var _tagline: Label = $Tagline
@onready var _buttons: VBoxContainer = $Buttons
@onready var _settings: SettingsPanel = $SettingsPanel
@onready var _howto: HowToPlay = $HowToPlay


func _ready() -> void:
	$Buttons/Play.pressed.connect(_on_play)
	$Buttons/HowTo.pressed.connect(_howto.open)
	$Buttons/Settings.pressed.connect(_settings.open)
	$Buttons/Quit.pressed.connect(_on_quit)

	# 菜单曲接回来。**`autoplay` 只在第一次进树时响一次**——从游戏里退回菜单时，
	# 它早就被 Play 那次淡出停掉了，只 stop 背景乐的话菜单是一片安静
	# Returning from a run lands on a silent menu otherwise: autoplay already fired once,
	# and Play's crossfade stopped this track on the way out.
	if StartMenuMusic.playing:
		BackgroundMusic.stop()
	else:
		_crossfade_music(BackgroundMusic, StartMenuMusic, 0.5)

	# 网页导出里退不出去，这个键点了什么都不会发生——干脆别让它出现
	# quit() is a no-op on web, and a button that does nothing is worse than no button.
	$Buttons/Quit.visible = not OS.has_feature("web")

	for button in _buttons.get_children():
		_wire_hover(button as Button)

	_intro()


# 逐个飘上来。一次性全出现的菜单读起来像一张图，不像一组可以按的东西
# Staggered on purpose: everything arriving at once reads as a picture, not a menu.
func _intro() -> void:
	# 位移只给这三个**自己摆位置**的节点。按钮在 VBoxContainer 里，容器每次重排都会
	# 把 position 写回去，动画会跟它打架——按钮那一层只能动 modulate，容器不碰它
	# Only these three own their position; a VBoxContainer child would have its tween
	# overwritten on every re-layout, so buttons stagger on alpha alone.
	var risers: Array[Control] = [_title, _tagline, _buttons]
	for i in risers.size():
		_rise_in(risers[i], stagger * float(i))

	var index: int = 0
	for child in _buttons.get_children():
		var button: Control = child as Control
		if button == null or not button.visible:
			continue
		button.modulate.a = 0.0
		var tween: Tween = create_tween()
		tween.tween_interval(stagger * float(2 + index))
		tween.tween_property(button, "modulate:a", 1.0, rise_time)
		index += 1


func _rise_in(element: Control, delay: float) -> void:
	var seat: float = element.position.y
	element.modulate.a = 0.0
	element.position.y = seat + rise
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_interval(delay)
	tween = tween.chain().set_parallel(true)
	tween.tween_property(element, "modulate:a", 1.0, rise_time)
	tween.tween_property(element, "position:y", seat, rise_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# 悬停胀一下。pivot 要摆到中心，默认在左上角，胀起来会往右下角长出去
# The pivot has to be centred or the swell grows out of the top-left corner.
func _wire_hover(button: Button) -> void:
	if button == null:
		return
	button.pivot_offset = button.size * 0.5
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	button.mouse_entered.connect(_scale_to.bind(button, hover_scale))
	button.mouse_exited.connect(_scale_to.bind(button, 1.0))
	button.focus_entered.connect(_scale_to.bind(button, hover_scale))
	button.focus_exited.connect(_scale_to.bind(button, 1.0))


func _scale_to(button: Button, amount: float) -> void:
	create_tween().tween_property(button, "scale", Vector2.ONE * amount, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_play() -> void:
	_crossfade_music(StartMenuMusic, BackgroundMusic, 0.5)
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_quit() -> void:
	get_tree().quit()

func _crossfade_music(track_out: AudioStreamPlayer2D, track_in: AudioStreamPlayer2D, duration: float) -> void:
	track_in.volume_db = linear_to_db(0.01)
	track_in.play()
		
	var tween: Tween = track_in.create_tween().set_parallel(true)
		
	tween.tween_method(
		func(vol: float): track_out.volume_db = linear_to_db(vol), 
		1.0, 0.01, duration
	)
		
	tween.tween_method(
		func(vol: float): track_in.volume_db = linear_to_db(vol), 
		0.01, 1.0, duration
	)
		 
	tween.chain().tween_callback(track_out.stop)


func _on_play_button_down() -> void:
	AudioManager.create_audio(SoundEffect.SoundEffectType.FOOD_POP)


func _on_how_to_button_down() -> void:
		AudioManager.create_audio(SoundEffect.SoundEffectType.FOOD_POP)



func _on_settings_button_down() -> void:
		AudioManager.create_audio(SoundEffect.SoundEffectType.FOOD_POP)



func _on_quit_button_down() -> void:
		AudioManager.create_audio(SoundEffect.SoundEffectType.FOOD_POP)
