class_name SpriteAnimation
extends Resource

# 一张图集的动画表 / the animation table for one sprite sheet.
# 存成 Resources/Animations/*.tres，跟 DragProfile / BehaviourProfile 一个路子——
# 美术覆盖同名 PNG，改行号和帧数在这里改，场景和代码都不用动。
# Overwrite the PNG, edit the rows here: no scene edit, no code edit.

## 图集切几列几行 / the sheet's grid, pushed onto the Sprite2D at runtime
@export_range(1, 32, 1) var hframes: int = 8
@export_range(1, 32, 1) var vframes: int = 6

## 没在播别的就播它 / what plays when nothing else asked
@export var default_clip: StringName = &"fly"
@export var clips: Array[SpriteClip] = []


func find(clip_name: StringName) -> SpriteClip:
	for clip in clips:
		if clip != null and clip.name == clip_name:
			return clip
	return null
