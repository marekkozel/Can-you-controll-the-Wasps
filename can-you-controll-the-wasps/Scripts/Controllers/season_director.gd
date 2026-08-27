class_name SeasonDirector
extends Node2D

# 季节调度 / season director. 跟 BetrayalDirector / RaidDirector 并排挂在 Queen_controller 下。
# 目前只做一件事：转动四季的轮子，把倒计时喂给 SeasonBar。
# 世代更替和继位还没接上——冬天现在只是一段更短的季节，不结算任何东西。
# Turns the wheel and feeds the bar. Succession is not wired yet: winter is just a short
# season for now, and settles nothing.

signal season_changed(season: int, generation: int)
## 每帧一次，给表现层用 / per-frame, for the bar and for anything atmospheric later
signal season_tick(season: int, time_left: float, ratio: float)
## 转回夏天 = 又过了一代 / one full wheel is one generation
signal generation_advanced(generation: int)

enum Season { SUMMER, AUTUMN, WINTER, SPRING }

const GROUP: StringName = &"season_director"
const BAR_GROUP: StringName = &"season_bar"
const SEASON_COUNT: int = 4

@export_group("Duration")
@export_range(10.0, 600.0, 5.0) var summer_duration: float = 150.0
@export_range(10.0, 600.0, 5.0) var autumn_duration: float = 120.0
## 冬天短得多：它是一次结算，不是又一段玩法 / winter is a settlement beat, not another phase
@export_range(10.0, 600.0, 5.0) var winter_duration: float = 45.0
@export_range(10.0, 600.0, 5.0) var spring_duration: float = 90.0

@export_group("Start")
@export var start_season: Season = Season.SUMMER
## 开局先安静一会儿再起表。玩家第一眼还在认界面，不该已经在赶时间
## The player is still reading the screen; they should not already be on the clock.
@export_range(0.0, 120.0, 1.0) var start_delay: float = 0.0

var season: int = Season.SUMMER
var generation: int = 1

var _time_left: float = 0.0
var _duration: float = 1.0
var _delay: float = 0.0
var _bar: SeasonBar = null


static func find(tree: SceneTree) -> SeasonDirector:
	return tree.get_first_node_in_group(GROUP) as SeasonDirector


func _ready() -> void:
	_bar = get_tree().get_first_node_in_group(BAR_GROUP) as SeasonBar
	if _bar == null:
		push_warning("SeasonDirector found no season bar, the countdown is invisible")
	_delay = start_delay
	_enter(start_season)


func season_name() -> String:
	return Season.keys()[season]


func duration_of(which: int) -> float:
	match which:
		Season.SUMMER:
			return summer_duration
		Season.AUTUMN:
			return autumn_duration
		Season.WINTER:
			return winter_duration
		Season.SPRING:
			return spring_duration
	return 60.0


func time_left() -> float:
	return _time_left


## 0 = 刚进这个季节，1 = 走完 / 0 entering the season, 1 at its end
func progress() -> float:
	if _duration <= 0.0:
		return 0.0
	return clampf(1.0 - _time_left / _duration, 0.0, 1.0)


# 到点和调试跳过共用，以后"冬天结算完才走"也从这里接
# Shared by the timer and by the debug skip; whatever gates winter later hooks in here.
func advance() -> void:
	var next: int = (season + 1) % SEASON_COUNT
	if next == Season.SUMMER:
		generation += 1
		generation_advanced.emit(generation)
	_enter(next)


func _enter(which: int) -> void:
	season = which
	_duration = maxf(duration_of(which), 0.1)
	_time_left = _duration
	if _bar != null:
		_bar.current_season = season
	_push()
	season_changed.emit(season, generation)


func _process(delta: float) -> void:
	if _delay > 0.0:
		_delay = maxf(_delay - delta, 0.0)
		return

	_time_left = maxf(_time_left - delta, 0.0)
	_push()
	if _time_left <= 0.0:
		advance()


func _push() -> void:
	var ratio: float = progress()
	if _bar != null:
		_bar.set_time_left(_time_left)
		_bar.set_progress(ratio)
	season_tick.emit(season, _time_left, ratio)
