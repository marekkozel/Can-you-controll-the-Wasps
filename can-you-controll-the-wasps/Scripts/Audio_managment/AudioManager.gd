extends Node2D

## 音效总线。**名字要和 default_bus_layout.tres 里的对上**，写错了 Godot 只是
## 把声音丢回 Master，不报错——表现是"滑条对音效没反应"
## A typo silently falls back to Master; the symptom is a slider that does nothing.
const SFX_BUS: StringName = &"SFX"

var sound_effect_dict: Dictionary = {}

@export var sound_effects: Array[SoundEffect]


func _ready() -> void:
	for sound_effect: SoundEffect in sound_effects:
		sound_effect_dict[sound_effect.type] = sound_effect


## Creates a sound effect at a specific location if the limit has not been reached. Pass [param location] for the global position of the audio effect, and [param type] for the SoundEffect to be queued.
func create_2d_audio_at_location(location: Vector2, type: SoundEffect.SoundEffectType) -> void:
	if sound_effect_dict.has(type):
		var sound_effect: SoundEffect = sound_effect_dict[type]
		if sound_effect.has_open_limit():
			sound_effect.change_audio_count(1)
			var _new_2d_audio: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			add_child(_new_2d_audio)
			# 走 SFX 总线，音乐走 Music —— 全挤在 Master 上的话设置面板那三条滑条
			# 分不开，调音效就等于调音乐
			# Split from Music, or the settings sliders can only ever move together.
			_new_2d_audio.bus = SFX_BUS
			_new_2d_audio.position = location
			_new_2d_audio.stream = sound_effect.sound_effect
			_new_2d_audio.volume_db = sound_effect.volume
			_new_2d_audio.pitch_scale = sound_effect.pitch_scale
			_new_2d_audio.pitch_scale += randf_range(-sound_effect.pitch_randomness, sound_effect.pitch_randomness)
			_new_2d_audio.finished.connect(sound_effect.on_audio_finished)
			_new_2d_audio.finished.connect(_new_2d_audio.queue_free)
			_new_2d_audio.play()
	else:
		push_error("Audio Manager failed to find setting for type ", type)


## Creates a sound effect if the limit has not been reached. Pass [param type] for the SoundEffect to be queued.
func create_audio(type: SoundEffect.SoundEffectType) -> void:
	if sound_effect_dict.has(type):
		var sound_effect: SoundEffect = sound_effect_dict[type]
		if sound_effect.has_open_limit():
			sound_effect.change_audio_count(1)
			var _new_audio: AudioStreamPlayer = AudioStreamPlayer.new()
			add_child(_new_audio)
			_new_audio.bus = SFX_BUS
			_new_audio.stream = sound_effect.sound_effect
			_new_audio.volume_db = sound_effect.volume
			_new_audio.pitch_scale = sound_effect.pitch_scale
			_new_audio.pitch_scale += randf_range(-sound_effect.pitch_randomness, sound_effect.pitch_randomness )
			_new_audio.finished.connect(sound_effect.on_audio_finished)
			_new_audio.finished.connect(_new_audio.queue_free)
			_new_audio.play()
	else:
		push_error("Audio Manager failed to find setting for type ", type)
