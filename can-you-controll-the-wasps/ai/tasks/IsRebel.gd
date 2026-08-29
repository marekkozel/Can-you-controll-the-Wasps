# 异色叛军 / a variant rebel.
# 母亲死不死不影响它——摔掉伪王后只是止住了新卵，孵出来的那些得玩家自己清
# Her death does not release them: unmasking her only stops new eggs.
class_name IsRebel
extends BTCondition


func _tick(_delta: float) -> Status:
	return SUCCESS if agent.allegiance().is_rebel() else FAILURE
