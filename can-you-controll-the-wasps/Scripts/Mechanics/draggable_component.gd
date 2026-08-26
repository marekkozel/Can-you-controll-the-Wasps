extends Area2D

var is_grabbed: bool = false
var previous_mouse_pos: Vector2 = Vector2.ZERO
var mouse_velocity: Vector2 = Vector2.ZERO
var original_gravity: float = 1.0 

@export var drag_speed: float = 20.0 
@export var wobble_multiplier: float = 0.001 

func _on_input_event(_viewport, event, _shape_idx):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed and not is_grabbed:
            is_grabbed = true
            var parent = get_parent()
            previous_mouse_pos = get_global_mouse_position()
            
            if parent is RigidBody2D:
                original_gravity = parent.gravity_scale
                parent.gravity_scale = 0.0

func _input(event):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if not event.pressed and is_grabbed:
            is_grabbed = false
            var parent = get_parent()
            
            if parent is RigidBody2D:
                parent.gravity_scale = original_gravity

func _physics_process(delta):
    var current_mouse_pos = get_global_mouse_position()
    mouse_velocity = (current_mouse_pos - previous_mouse_pos) / delta
    previous_mouse_pos = current_mouse_pos
    
    if is_grabbed:
        var parent = get_parent()
        if parent is RigidBody2D:
            var distance_to_mouse = current_mouse_pos - parent.global_position
            parent.linear_velocity = distance_to_mouse * drag_speed
            
            var target_rotation = mouse_velocity.x * wobble_multiplier
            parent.rotation = clamp(lerp_angle(parent.rotation, target_rotation, 5.0 * delta), -PI, PI)