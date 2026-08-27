# 这只是不是伪王后 / is this the impostor.
class_name IsFalseQueen
extends BTCondition


func _tick(_delta: float) -> Status:
	return SUCCESS if agent.allegiance().is_false_queen() else FAILURE
