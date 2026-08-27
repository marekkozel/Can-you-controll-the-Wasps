# 当前是不是采集岗 / is this wasp posted to a resource source.
class_name IsGathering
extends BTCondition


func _tick(_delta: float) -> Status:
	return SUCCESS if agent.job == Wasp.Job.GATHER else FAILURE
