extends Node2D
## Audio manager node. Inteded to be globally loaded as a 2D Scene. Handles [method create_2d_audio_at_location()] and [method create_audio()] to handle the playback and culling of simultaneous sound effects.
##
## To properly use, define [enum SoundEffect.SOUND_EFFECT_TYPE] for each unique sound effect, create a Node2D scene for this AudioManager script add those SoundEffect resources to this globally loaded script's [member sound_effects], and setup your individual SoundEffect resources. Then, use [method create_2d_audio_at_location()] and [method create_audio()] to play those sound effects either at a specific location or globally.
## 
## See https://github.com/Aarimous/AudioManager for more information.
##
## @tutorial: https://www.youtube.com/watch?v=Egf2jgET3nQ

var sound_effect_dict: Dictionary = {} ## Loads all registered SoundEffects on ready as a reference.

@export var sound_effects: Array[SoundEffect] ## Stores all possible SoundEffects that can be played.


func _ready() -> void:
	for sound_effect: SoundEffect in sound_effects:
		sound_effect_dict[sound_effect.type] = sound_effect


## Creates a sound effect at a specific location if the limit has not been reached. Pass [param location] for the global position of the audio effect, and [param type] for the SoundEffect to be queued.
func create_2d_audio_at_location(location: Vector2, type: SoundEffect.SoundEeffectType) -> void:
	if sound_effect_dict.has(type):
		var sound_effect: SoundEffect = sound_effect_dict[type]
		if sound_effect.has_open_limit():
			sound_effect.change_audio_count(1)
			var _new_2d_audio: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			add_child(_new_2d_audio)
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
func create_audio(type: SoundEffect.SoundEeffectType) -> void:
	if sound_effect_dict.has(type):
		var sound_effect: SoundEffect = sound_effect_dict[type]
		if sound_effect.has_open_limit():
			sound_effect.change_audio_count(1)
			var _new_audio: AudioStreamPlayer = AudioStreamPlayer.new()
			add_child(_new_audio)
			_new_audio.stream = sound_effect.sound_effect
			_new_audio.volume_db = sound_effect.volume
			_new_audio.pitch_scale = sound_effect.pitch_scale
			_new_audio.pitch_scale += randf_range(-sound_effect.pitch_randomness, sound_effect.pitch_randomness )
			_new_audio.finished.connect(sound_effect.on_audio_finished)
			_new_audio.finished.connect(_new_audio.queue_free)
			_new_audio.play()
	else:
		push_error("Audio Manager failed to find setting for type ", type)
