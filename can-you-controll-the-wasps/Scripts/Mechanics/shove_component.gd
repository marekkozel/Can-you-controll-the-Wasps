class_name ShoveComponent
extends Area2D

# 拨开 / shove: 把身边的散件推开。挂到 RigidBody2D 下，只推 carriable。
# A wasp elbowing loose pieces out of its way.
#
# **它不是用来解卡的。** 蜂和散件已经不在同一套碰撞层上（蜂 layer 2、散件 layer 8，
# 互相都不在对方的 mask 里），"蜂永远不会被货堆压住"是那条分层保证的，跟这里无关。
# 这里只负责让它看起来像在拨——不推的话蜂就是**穿过**一堆果子，那更假
# The layers guarantee a wasp can never be pinned; this only sells the motion. Without
# it a wasp simply passes through the pile, which reads worse than being stuck.
#
# 因为不碰撞，这里可以放心大胆地推：推歪了也不会把蜂自己弹开，
# 也不会出现"两个刚体互相挤到爆炸"那种解算器打架
# Nothing pushes back, so this can be generous without the usual solver fights.

## 每秒推多大的劲。散件 mass 0.5~0.6，除以质量才是加速度
## Divided by the piece's mass, so light fruit moves further than a scrap.
@export_range(0.0, 2000.0, 10.0) var force: float = 240.0
## 贴得越近推得越狠。一圈内力度一样的话，边上的果子会毫无理由地自己弹开
## A flat push makes fruit at the rim jump for no visible reason.
@export var falloff: bool = true
## 推出去的速度上限。没有它的话，一只蜂在堆里钻一下能把果子射到屏幕外
## Without a cap one pass through a pile launches fruit off-screen.
@export_range(0.0, 600.0, 10.0) var max_speed: float = 150.0

const CARRIABLE_GROUP: StringName = &"carriable"

var _radius: float = 26.0


func _ready() -> void:
	monitoring = true
	# 自己不需要被别人扫到 / nothing needs to detect this area
	monitorable = false
	var shape: CollisionShape2D = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape != null:
		var circle: CircleShape2D = shape.shape as CircleShape2D
		if circle != null:
			_radius = circle.radius


func _physics_process(delta: float) -> void:
	for body in get_overlapping_bodies():
		var piece: RigidBody2D = body as RigidBody2D
		if piece == null or not piece.is_in_group(CARRIABLE_GROUP):
			continue

		var away: Vector2 = piece.global_position - global_position
		var distance: float = away.length()
		if distance < 0.01:
			# 完全重合时没有方向可用，随便挑一个，否则这一份货会永远卡在蜂心上
			# Dead centre has no direction to push along; anything beats staying there.
			away = Vector2.from_angle(randf_range(0.0, TAU))
			distance = 0.01
		else:
			away /= distance

		var strength: float = force
		if falloff:
			strength *= clampf(1.0 - distance / maxf(_radius, 1.0), 0.0, 1.0)
		piece.apply_central_impulse(away * strength * delta)

		var speed: float = piece.linear_velocity.length()
		if speed > max_speed:
			piece.linear_velocity = piece.linear_velocity * (max_speed / speed)
