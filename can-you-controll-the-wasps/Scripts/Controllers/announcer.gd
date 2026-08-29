class_name Announcer
extends Node2D

# 播报 / the announcer. 跟三个 director 并排挂在 Queen_controller 下。
# 唯一知道 Herald 存在的地方——director 只管发信号，翻译成句子是这里的事。
# The only node that knows the herald exists; the directors just emit.
#
# 一代（3.5 分钟）平均响 5~7 次。想加话就往 LINES 里加，别往 director 里塞 UI。
#
# 分层规则（改文案前先读 CLAUDE.md 的设计红线）：
#   事实 —— 玩家救得回来的不播，只播不可逆的
#   传闻 —— 延迟随机秒数，不带个体 / 位置 / 数量，而且**可能是假的**
# Facts are for losses you cannot undo; rumours are vague, delayed, and sometimes lies.

const HERALD_GROUP: StringName = &"herald"
const HIVE_GROUP: StringName = &"hive"

# 文案全在这一张表里，改词不用碰玩法代码 / every line lives here, and only here
const LINES: Dictionary = {
	&"raid_warning": {
		"text": "Something is coming to the rim.",
		"priority": 90, "tone": Herald.Tone.THREAT,
	},
	&"raid_lost": {
		"text": "They got away with it.",
		"priority": 80, "tone": Herald.Tone.THREAT,
	},
	&"starved": {
		"text": "A larva starved.", "repeat": "{n} larvae starved.",
		"priority": 75, "tone": Herald.Tone.LOSS,
	},
	# 教学句：新皇是**拖进去**的，不是自动来的。第一次玩看不懂这条就整局都在等
	# The rite is a verb, not a notification: nobody waits out a winter they can act on.
	&"throne": {
		"text": "Winter. Drag a worker into the glowing centre cell - she becomes your queen.",
		"priority": 100, "tone": Herald.Tone.RITE,
	},
	&"throne_late": {
		"text": "Still no heir. Carry one in now, or the comb picks its own.",
		"priority": 100, "tone": Herald.Tone.RITE,
	},
	# 你摔对人了。**这是全局唯一一条确认性的播报**——她不变色、不倒下，
	# 没有这句话玩家永远不知道自己刚才做对了没有
	# The one confirming line in the game: she neither changes colour nor falls, so
	# without it the player never learns whether the throw landed on the right wasp.
	&"unmasked": {
		"text": "She hits the wall and something goes out of her. That one will lay no more.",
		"priority": 95, "tone": Herald.Tone.RITE,
	},
	&"crowned": {
		"text": "She is crowned.",
		"priority": 100, "tone": Herald.Tone.RITE,
	},
	# 你第一次把一只蜂拿在手上时说一次。挂在**玩家的动作**上，不是挂在她身上——
	# 挂在伪王后醒来上的话，这句话本身就成了"她在场"的确认
	# Keyed to the player's own hand: keyed to her, it would confirm she exists.
	&"first_grab": {
		"text": "She cannot fly while you hold her. Fling her at a wall and she will feel it.",
		"priority": 70, "tone": Herald.Tone.RITE,
	},
	# ---- 以下是传闻 / rumours from here down ----
	&"awaken": {
		"pool": [
			"The comb smells wrong tonight.",
			"Something moves in the comb that answers to no one.",
		],
		"priority": 45, "tone": Herald.Tone.RUMOUR,
	},
	&"rebel_egg": {
		"pool": [
			"A cell was opened that no one remembers opening.",
			"There is an egg here that the comb did not ask for.",
		],
		"priority": 45, "tone": Herald.Tone.RUMOUR,
	},
	&"unrest": {
		"text": "The workers are slow to answer.",
		"priority": 40, "tone": Herald.Tone.RUMOUR,
	},
	&"innocent": {
		"text": "That one had done nothing.",
		"priority": 55, "tone": Herald.Tone.RUMOUR,
	},
}

@export_group("Raids")
## 提前这么久预警。**不报数量**——报了入侵就变成配兵的算术题
## No count in the warning: with a number the raid becomes arithmetic.
@export_range(0.0, 30.0, 0.5) var warn_lead: float = 8.0

@export_group("Rumours")
## 传闻延迟多久才出口。跟事件同帧的话时间戳本身就是答案——
## 玩家回头看谁刚羽化、谁刚回巢，一抓一个准
## Same-frame rumours are a timestamp, and a timestamp is an answer.
@export var rumour_delay: Vector2 = Vector2(8.0, 20.0)
## 横幅正忙时传闻既不打断也不排队，隔这么久重投 / rumours wait for silence
@export var rumour_retry: Vector2 = Vector2(5.0, 10.0)
## 群体不安跨过这条线说一次 / said once, on the way up
@export_range(0.0, 1.0, 0.05) var unrest_threshold: float = 0.5

@export_group("Lies")
## 场上根本没有伪王后时也偶尔放一条传闻。没有这个的话"看到传闻"就是免费探测器
## Without the lies, seeing a rumour would simply mean she is here.
@export_range(0.0, 1.0, 0.05) var lie_chance: float = 0.5
## 不安低于这个数不撒谎——安定的蜂群造不出谣言 / a calm colony has no rumours
@export_range(0.0, 1.0, 0.05) var lie_after_unrest: float = 0.4
@export var lie_interval: Vector2 = Vector2(60.0, 120.0)
## 杀对了也有这么大概率说"那只什么都没做"。**这条不能设成 0**：
## 只在杀错时说的话，消息没出现就等于告诉玩家杀对了，缺席本身成了确认
## Never set this to zero - silence after a kill would confirm the kill.
@export_range(0.0, 1.0, 0.05) var false_absolution: float = 0.25

var _herald: Herald = null
var _betrayal: BetrayalDirector = null
var _raid: RaidDirector = null
var _season: SeasonDirector = null
var _hive: Hive = null

var _unrest_said: bool = false
## 教你怎么下手那句只说一次 / the lesson on hurting them fires once per run
var _grab_taught: bool = false
## 已经预警过的那个点在整年的位置，掷新时间表时清掉 / cleared when the schedule is rolled
var _warned_at: float = -1.0
var _lie_timer: float = 0.0


func _ready() -> void:
	# 延后一帧：director 和 Herald 都不保证比这里先 _ready
	# Deferred - nothing guarantees the directors or the herald are ready before us.
	_bind.call_deferred()
	_roll_lie_timer()


func _bind() -> void:
	_herald = Herald.find(get_tree())
	if _herald == null:
		push_warning("Announcer found no Herald, nothing will be announced")
		set_process(false)
		return

	_betrayal = BetrayalDirector.find(get_tree())
	_raid = RaidDirector.find(get_tree())
	_season = SeasonDirector.find(get_tree())
	_hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive

	if _betrayal != null:
		_betrayal.false_queen_awakened.connect(func(_w): _rumour(&"awaken"))
		# 事实，不是传闻：不延迟、不掺假，玩家的手刚做完这件事
		# A fact, not a rumour - no delay and never a lie; the player just did it.
		_betrayal.false_queen_unmasked.connect(func(_w): _say(&"unmasked"))
		_betrayal.unrest_changed.connect(_on_unrest_changed)
		_betrayal.execution_reported.connect(_on_execution)
	if _raid != null:
		_raid.raid_ended.connect(_on_raid_ended)
		_raid.schedule_changed.connect(func(_m): _warned_at = -1.0)
	if _season != null:
		_season.rite_changed.connect(_on_rite_changed)
	if _hive != null:
		_hive.cell_larva_starved.connect(func(_c): _say(&"starved"))
		_hive.cell_rebel_egg_laid.connect(func(_c): _rumour(&"rebel_egg"))


func _process(delta: float) -> void:
	_check_raid_warning()
	_check_first_grab()

	_lie_timer -= delta
	if _lie_timer > 0.0:
		return
	_roll_lie_timer()
	if _betrayal == null or _betrayal.unrest < lie_after_unrest:
		return
	if randf() < lie_chance:
		_rumour(&"awaken" if randf() < 0.5 else &"rebel_egg")


# 轮询而不是给每只蜂连 grabbed —— 蜂一直在羽化和被处决，逐只连信号是一堆生命周期
# Polled: wasps come and go constantly, and is_dragging() is already static.
func _check_first_grab() -> void:
	if _grab_taught or not DraggableComponent.is_dragging():
		return
	var held: RigidBody2D = DraggableComponent.held_body()
	if held == null or not held.is_in_group(&"wasps"):
		return  # 拖纸板不算 / carrying a piece is not the lesson
	_grab_taught = true
	_say(&"first_grab")


func _roll_lie_timer() -> void:
	_lie_timer = randf_range(lie_interval.x, lie_interval.y)


# ---------------- 播报 / speaking ----------------

func _say(key: StringName) -> void:
	if _herald == null:
		return
	var line: Dictionary = LINES.get(key, {})
	if line.is_empty():
		push_warning("Announcer has no line for %s" % key)
		return

	var text: String = line.get("text", "")
	var pool: Array = line.get("pool", [])
	if not pool.is_empty():
		text = String(pool[randi() % pool.size()])

	_herald.push(key, text, int(line["priority"]), int(line["tone"]), line.get("repeat", ""))


# 传闻：先等一段随机时间，再等横幅安静下来。
# 挤在"幼虫饿死了"后面的传闻是日志，落在安静里的才是传闻
# A rumour on the heels of a loss reads as a log line; it needs the silence.
func _rumour(key: StringName) -> void:
	await get_tree().create_timer(randf_range(rumour_delay.x, rumour_delay.y)).timeout
	while _herald != null and _herald.is_busy():
		await get_tree().create_timer(randf_range(rumour_retry.x, rumour_retry.y)).timeout
	_say(key)


# ---------------- 信号 / signals ----------------

func _on_unrest_changed(unrest: float) -> void:
	# 只在上行跨线时说一次，回落后才重新武装 / said on the way up, rearmed on the way down
	if unrest >= unrest_threshold and not _unrest_said:
		_unrest_said = true
		_rumour(&"unrest")
	elif unrest < unrest_threshold * 0.8:
		_unrest_said = false


func _on_execution(was_false_queen: bool) -> void:
	if was_false_queen and randf() >= false_absolution:
		return
	_rumour(&"innocent")


func _on_raid_ended(cleared: bool) -> void:
	# 打退了不说话。安静本身就是"没事了"，再播一遍是噪音
	# Silence is the all-clear; announcing it would only be noise.
	if not cleared:
		_say(&"raid_lost")


func _on_rite_changed(rite: int) -> void:
	match rite:
		SeasonDirector.Rite.THRONE:
			_say(&"throne")
			_watch_throne()
		SeasonDirector.Rite.GATHER:
			_say(&"crowned")


# 王座开了一半时间还没人进去，提醒一句蜂群要自己动手了
# Half the window gone with no heir: the swarm is about to decide without you.
func _watch_throne() -> void:
	if _season == null:
		return
	await get_tree().create_timer(_season.throne_timeout * 0.5).timeout
	if _season != null and _season.rite == SeasonDirector.Rite.THRONE:
		_say(&"throne_late")


# ---------------- 入侵预警 / the eight-second warning ----------------

func _check_raid_warning() -> void:
	if _raid == null or _season == null or _raid.paused:
		return
	var at: float = _raid.next_mark_at()
	if at < 0.0 or is_equal_approx(at, _warned_at):
		return
	var seconds: float = _seconds_until(at)
	if seconds > warn_lead:
		return
	_warned_at = at
	_say(&"raid_warning")


# 整年进度差换算成真实秒数。四季在轴上各占 1/4，但时长不同，
# 不换算的话八秒预警在长季节里会提前二十秒响
# Each season owns a quarter of the axis but not a quarter of the clock.
func _seconds_until(at: float) -> float:
	var from: float = _season.year_progress()
	if at <= from:
		return 0.0
	var total: float = 0.0
	var which: int = _season.season
	while which < SeasonDirector.SEASON_COUNT:
		var edge: float = float(which + 1) * 0.25
		var stop: float = minf(at, edge)
		total += (stop - from) * 4.0 * _season.duration_of(which)
		if stop >= at:
			break
		from = edge
		which += 1
	return total
