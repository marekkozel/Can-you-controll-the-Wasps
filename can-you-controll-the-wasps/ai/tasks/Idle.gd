class_name Idle
extends BTAction

func _tick(delta: float) -> Status:
  if agent.has_method("wander"):
    agent.wander(delta)
    
  return SUCCESS