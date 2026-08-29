class_name RevealBurst
extends CPUParticles2D

# 揭穿 / the unmask puff. 摔墙摔掉伪王后的面具时生成一团，播完自己走。
# One-shot puff spawned when a thrown false queen loses her mask.
#
# 它跟受击的 burst 是**反着**的：那个向四面炸开、立刻刹住；这个慢、朝上飘、悠着散。
# 场上其他所有反馈都是向外炸，只有这一下是「东西离开了她」——玩家不用认图案，
# 光看运动方向就知道这次不一样。
# Deliberately the inverse of the hit burst: everything else explodes outward, this one
# drifts up and away. The motion is the message.
#
# 辉光是**烘在贴图里**的（`DM/files/gen_fx.py` 的 halo/bloom 两圈），配场景上那个
# 加法混合的 CanvasItemMaterial 才会真的亮：加法在深底上是把颜色加上去，几颗叠在
# 一起会更亮；换回普通混合的话那圈光晕就只是一层灰纱。
# 项目里没有 WorldEnvironment，真 bloom 要开 HDR 2D + 全局辉光，那是整个游戏的观感
# The glow is baked into the texture and only reads with the additive material; there is
# no WorldEnvironment here, and real bloom would be a project-wide look change.


# 生成它的一方负责摆位置。tint 走她偷偷下的那种卵的血统色——玩家过一会儿在异色卵上
# 还会再看见同一个颜色 / tinted with her brood's colour, which the player meets again on the egg
func play(tint: Color) -> void:
	color = tint
	emitting = true


func _ready() -> void:
	# one_shot 播完不会自己释放，不接这条就是每揭穿一次多留一个空节点
	# one_shot does not free itself; without this each unmask leaks a node.
	finished.connect(queue_free)
