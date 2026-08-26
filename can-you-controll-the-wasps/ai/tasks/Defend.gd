class_name Defend
extends BTAction

## Wasps attacking range
@export var attack_distance: float = 50.0
## Wasps fly faster when angry
@export var chase_speed: float = 150.0

func _enter() -> void:
	# Priority 1: Drop all resources immediately
	if agent.has_method("drop_carried_resource"):
		agent.drop_carried_resource()
	
	# Grab all active enemies from the global group
	var enemies: Array = agent.get_tree().get_nodes_in_group("Enemy")
	
	if enemies.size() > 0:
		agent.target_enemy = _find_closest_enemy(enemies)
		
	else:
		agent.target_enemy = null

func _tick(delta: float) -> Status:
	# If the enemy was killed by the Queen, despawned, or doesn't exist, fail the task.
	if not is_instance_valid(agent.target_enemy):
		return FAILURE
	
	# This is there only because, new enemy can be spawned, or you can throw the wasps, so it has to recalculate the closest enemy every tick, unfortunately.
	var enemies: Array = agent.get_tree().get_nodes_in_group("Enemy")

	if enemies.size() > 0:
		agent.target_enemy = _find_closest_enemy(enemies)
	else:
		agent.target_enemy = null
		
	var dist_to_enemy: float = agent.global_position.distance_to(agent.target_enemy.global_position)
	
	# Steer toward the enemy
	if agent.has_method("steer_towards"):
		agent.steer_towards(agent.target_enemy.global_position, delta, chase_speed)
	
	# Check if we reached the enemy to attack it
	if dist_to_enemy <= attack_distance:
		agent.attack_enemy()
		return SUCCESS
		
	return RUNNING

func _exit() -> void:
	# Clean up the target when we are done defending
	agent.target_enemy = null

func _find_closest_enemy(enemies: Array) -> Node2D:
	var closest_enemy: Node2D = null
	var min_dist: float = INF
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
			
		var dist: float = agent.global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			closest_enemy = enemy
	  
	return closest_enemy
