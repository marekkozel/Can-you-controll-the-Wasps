class_name BehaviourProfile
extends Resource

# 行为画像 / behaviour profile: 一只蜂"是什么样的蜂"。
# 存成 Resources/Behaviours/*.tres，跟 WaspVariant / EnemyVariant 一个路子——
# 加一种新蜂只要多一个 .tres，不用碰代码，也不用碰行为树。
# Add a kind of wasp by adding a .tres: no code, no behaviour-tree edit.
#
# **这里存的全是区间，不是定值。** 每只蜂 _ready 时从每个区间里抽一次，抽完就定死。
# 这一条是整套设计的地基，理由有两个：
#   1. 同一个画像生出来的蜂彼此不同——蜂群里本来就该有个体差异，不然没有"正常"的分布，
#      也就没有"异常"可言
#   2. 伪王后用另一个画像，而她的区间必须**压在**工蜂的区间里面，只是重心偏一点
# 不重叠就不是推理，是探测器：玩家抓一只就知道答案，唯一策略变成挨个抓一遍。
# Ranges, never fixed values. Rolled once at birth. The impostor's profile must overlap
# the worker's - separate ranges make a detector, not a deduction.
#
# 所以校验一条线索"是不是还能玩"，就是把两个 .tres 并排打开看区间有没有压住。
# 红线从注释变成了看得见的数据 / the red line is now something you can see in the editor.

## 面板和日志里怎么称呼它 / how it is named in logs
@export var display_name: String = "Worker"

@export_group("Perception")
## 看得见多远。**蜂不该是全知的**——之前每只蜂都在扫全场，采食蜂会为了地上一块
## 战利品横穿整张地图。区间拉开一点，蜂群里就有"眼尖的"和"迟钝的"
## Wasps are not omniscient. A spread here gives the swarm sharp and dull individuals.
@export var sight_radius: Vector2 = Vector2(260.0, 420.0)

@export_group("Loiter")
## 没活干时绕巢徘徊的半径 / how wide it drifts around the hive when idle
@export var loiter_radius: Vector2 = Vector2(150.0, 240.0)
## 徘徊时的巡航速度 / cruise speed while loitering
@export var loiter_speed: Vector2 = Vector2(45.0, 65.0)

# 巢里闲着时做什么。五项权重做加权随机，权重本身每只蜂不同——
# "这只蜂老在空格子附近晃"因此成为一个可读的个体特征，而那正是伪王后要藏进去的地方
# The five idle acts are weighted per wasp, which is what makes "that one keeps hanging
# around empty cells" a readable trait - and the exact bush the impostor hides in.
@export_group("Idle vocabulary")
## 巡视巢室：飞到某格上方停一会儿。SecretLay 的掩护形状就是它
## Inspect - the shape SecretLay wears as a disguise.
@export var inspect_weight: Vector2 = Vector2(0.7, 1.5)
## 照看幼虫：在有幼虫的格子旁停留 / hover by a larva
@export var attend_weight: Vector2 = Vector2(0.6, 1.6)
## 触角接触：飞近另一只蜂，短暂停顿再分开 / antennation, how real wasps trade information
@export var antennate_weight: Vector2 = Vector2(0.7, 1.5)
## 巡边：沿巢室区外缘绕行 / patrol the rim
@export var patrol_weight: Vector2 = Vector2(0.4, 1.2)
## 梳理：原地停着不动。它的价值是留白——全员一刻不停，异常就无从凸显
## Groom. Its job is negative space: constant motion hides the outlier.
@export var groom_weight: Vector2 = Vector2(0.5, 1.3)
## 每次停留多久。**这是最直接的一条线索**：SecretLay 的悬停就在拿它当掩护
## Linger time - the tell SecretLay's hover has to blend into.
@export var linger_time: Vector2 = Vector2(1.4, 3.2)
## 多久起一次念头 / seconds between urges
@export var urge_interval: Vector2 = Vector2(2.0, 6.0)

# 分工不再是硬岗位，而是"刺激超过我的阈值就去做"。这是社会性昆虫分工的标准模型，
# 而它顺带把玩家的指令从**命令**降级成**倾向**——你把蜂扔到食物点，它大部分时间会采集，
# 但巢里出事时它会自己回去。「你以为你在控制黄蜂」在 AI 层面就是这一段
# Response thresholds. The player's drop point becomes a bias, not an order.
@export_group("Work thresholds")
## 越低越容易被"缺纸板"拉走 / lower means more easily recruited to building
@export var cardboard_threshold: Vector2 = Vector2(0.22, 0.55)
## 越低越容易被"幼虫饿了"拉走 / same, for feeding
@export var food_threshold: Vector2 = Vector2(0.20, 0.52)
## 落点给的偏向有多强。**这就是"多听话"的旋钮**：低的蜂容易自作主张跑去干别的。
##
## 量级要比 demand 小一档。给到 0.35~0.75 时它和 (demand - threshold) 同量级，
## 结果是巢里 8 成格子没建、蜂群还全待在你放它们的地方——那不是倾向，那是命令，
## 整套阈值模型等于没接
## Must stay an order below `demand`: at 0.35+ it simply overrides need, and the whole
## threshold model collapses back into a hard posting.
@export var posting_bias: Vector2 = Vector2(0.10, 0.28)
## 多久重新掂量一次要干什么 / seconds between job re-evaluations
@export var reconsider_interval: Vector2 = Vector2(3.0, 6.5)


# 抽一次。返回具体值，蜂拿走之后这个 Resource 就跟它没关系了
# Roll once; the wasp keeps the numbers and stops caring about this resource.
#
# 注意别把返回值当成"这只蜂的画像"存回资源——Resource 是全场共享的，
# 抽出来的值才是每只蜂私有的（跟 DragProfile 必须 duplicate 是同一类坑）
# The rolled values are per-wasp; the resource itself is shared by everyone.
func roll() -> Dictionary:
	return {
		&"sight_radius": _pick(sight_radius),
		&"loiter_radius": _pick(loiter_radius),
		&"loiter_speed": _pick(loiter_speed),
		# 顺序必须和 Wasp.IdleAct 一致 / index order must match Wasp.IdleAct
		&"idle_weights": [
			_pick(inspect_weight),
			_pick(attend_weight),
			_pick(antennate_weight),
			_pick(patrol_weight),
			_pick(groom_weight),
		],
		&"linger_time": _pick(linger_time),
		&"urge_interval": _pick(urge_interval),
		&"cardboard_threshold": _pick(cardboard_threshold),
		&"food_threshold": _pick(food_threshold),
		&"posting_bias": _pick(posting_bias),
		&"reconsider_interval": _pick(reconsider_interval),
	}


# 区间是闭区间，写反了也能用 / inclusive, and tolerant of a reversed pair
static func _pick(range_: Vector2) -> float:
	return randf_range(minf(range_.x, range_.y), maxf(range_.x, range_.y))
