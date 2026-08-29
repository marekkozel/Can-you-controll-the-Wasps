class_name SoundEffect 
extends Resource
## Sound effect resource, used to configure unique sound effects for use with the AudioManager. Passed to [method AudioManager.create_2d_audio_at_location()] and [method AudioManager.create_audio()] to play sound effects.

## Stores the different types of sounds effects available to be played to distinguish them from another. Each new SoundEffect resource created should add to this enum, to allow them to be easily instantiated via [method AudioManager.create_2d_audio_at_location()] and [method AudioManager.create_audio()].
enum SoundEffectType {
	CELL_BUILDING,
	CELL_DEATH,
	CELL_CLEAN,
	EGG_LAYING,
	EGG_LAID,
	REBEL_EGG_LAID,
	LARVA_BIRTH,
	LARVA_EATING,
	LARVA_HUNGRY,
	LARVA_DEATH,
	FOOD_POP,
	CARDBOARD_POP,
	QUEEN_POP,
	WASP_DEATH,
	WASP_HIT,
	WASP_FLY,
	WASP_ATTACK,
	RAID_WARNING,
	UPGRADE,
	END_GAME_SCREEN,
	POP,
	HIT,
	ENEMY_DEATH,
	QUEEN_EAT
}

@export_range(0, 10) var limit: int = 5 ## Maximum number of this SoundEffect to play simultaneously before culled.
@export var type: SoundEffectType ## The unique sound effect in the [enum SoundEffectType] to associate with this effect. Each SoundEffect resource should have it's own unique [enum SoundEffectType] setting.
@export var sound_effect: AudioStreamMP3 ## The [AudioStreamMP3] audio resource to play.
@export_range(-40, 20) var volume: float = 0 ## The volume of the [member sound_effect].
@export_range(0.0, 4.0,.01) var pitch_scale: float = 1.0 ## The pitch scale of the [member sound_effect].
@export_range(0.0, 1.0,.01) var pitch_randomness: float = 0.0 ## The pitch randomness setting of the [member sound_effect].

var audio_count: int = 0 ## The instances of this [AudioStreamMP3] currently playing.


## Takes [param amount] to change the [member audio_count]. 
func change_audio_count(amount: int) -> void:
	audio_count = max(0, audio_count + amount)


## Checkes whether the audio limit is reached. Returns true if the [member audio_count] is less than the [member limit].
func has_open_limit() -> bool:
	return audio_count < limit


## Connected to the [member sound_effect]'s finished signal to decrement the [member audio_count].
func on_audio_finished() -> void:
	change_audio_count(-1)
