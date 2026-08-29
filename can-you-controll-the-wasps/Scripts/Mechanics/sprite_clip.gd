class_name SpriteClip
extends Resource

# 图集里的一段动画 / one clip in a sprite sheet: 一整行（或半行）连续帧。
# 加一段动画 = 在 SpriteAnimation 的 clips 里多一条，不用碰代码。
# Adding a clip means adding an entry, never touching code.

## 代码里点名用的 / the name play() takes
@export var name: StringName = &"fly"
## 第几行，从 0 数 / sheet row, 0-based
@export_range(0, 31, 1) var row: int = 0
## 这一行从第几列开始 / first column, for rows that hold two short clips
@export_range(0, 31, 1) var start_column: int = 0
## 用几帧 / how many frames to run
@export_range(1, 32, 1) var frames: int = 8
## 每秒几帧 / playback rate
@export_range(1.0, 60.0, 1.0) var fps: float = 12.0
## 关掉就是一次性的，播完自动回默认段 / one-shot clips fall back to the default one
@export var loop: bool = true
## 一次性段播完停在最后一帧，不回默认段。死亡动画要开这个——
## 不开的话尸体会在淡出前跳回走路姿势 / a corpse must not snap back to its walk pose
@export var hold_last: bool = false
