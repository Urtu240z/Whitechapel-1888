extends CharacterBody2D

# ==========================
# ✨ CONFIGURABLE PARAMETERS
# ==========================
@export var move_speed: float = 220.0
@export var jump_force: float = 420.0
@export var gravity: float = 980.0
@export var coyote_time: float = 0.12
@export var fall_multiplier: float = 1.5
@export var max_fall_speed: float = 3000.0
@export var acceleration_smoothness: float = 6.0

@export_group("Slope Slide")
@export var slope_slide_speed: float = 300.0
@export var slope_slide_threshold: float = 25.0
@export var slope_acceleration: float = 200.0
@export var slope_max_speed: float = 3000.0

@export_group("Soft Landing")
@export var soft_landing_distance: float = 120.0
@export var soft_landing_strength: float = 0.85
@export var raycast_length: float = 200.0
@export var min_jump_height: float = 100.0

# ==========================
# INTERNAL STATE
# ==========================
var input_dir: float = 0.0
var coyote_timer: float = 0.0
var can_soft_land: bool = false
var highest_jump_point: float = 0.0
var slide_timer: float = 0.0
var current_slide_speed: float = 0.0
var maintained_speed: float = 0.0
var just_jumped: bool = false # <--- nuevo flag

@onready var visual: Node2D = $Visual
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_state = anim_tree.get("parameters/playback")
@onready var ground_detector: RayCast2D = $GroundDetector
@onready var jump_detector: RayCast2D = $JumpDetector
@onready var slide_ground_detector: RayCast2D = $SlideGroundDetector # <--- nuevo

# ==========================
# READY
# ==========================
func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	floor_stop_on_slope = false
	floor_max_angle = deg_to_rad(60)
	floor_snap_length = 16.0
	anim_tree.active = true
	
	if ground_detector:
		ground_detector.enabled = true
		ground_detector.target_position = Vector2(0, raycast_length)
		ground_detector.collision_mask = 0xFFFFFFFF
		ground_detector.hit_from_inside = false
		ground_detector.collide_with_areas = false
		ground_detector.collide_with_bodies = true
	
	if jump_detector:
		jump_detector.enabled = true
		jump_detector.target_position = Vector2(0, min_jump_height)
		jump_detector.collision_mask = 0xFFFFFFFF
		jump_detector.hit_from_inside = false
		jump_detector.collide_with_areas = false
		jump_detector.collide_with_bodies = true
	
	if slide_ground_detector:
		slide_ground_detector.enabled = true
		slide_ground_detector.collision_mask = 0xFFFFFFFF
		slide_ground_detector.hit_from_inside = false
		slide_ground_detector.collide_with_areas = false
		slide_ground_detector.collide_with_bodies = true

# ==========================
# MAIN LOOP
# ==========================
func _physics_process(delta: float) -> void:
	update_slide_raycast()
	handle_input()
	apply_gravity(delta)
	apply_soft_landing(delta)
	handle_movement(delta)
	handle_animation()
	just_jumped = false # <--- reset flag

# ==========================
# RAYCAST AJUSTADO AL SUELO
# ==========================
func update_slide_raycast() -> void:
	if not slide_ground_detector:
		return
	
	if is_on_floor():
		var n := get_floor_normal().normalized()
		var cast_dir = -n
		slide_ground_detector.target_position = cast_dir * 60.0
	else:
		slide_ground_detector.target_position = Vector2(0, 60)

# ==========================
# INPUT
# ==========================
func handle_input() -> void:
	input_dir = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")

	var floor_normal = get_floor_normal()
	var floor_angle = rad_to_deg(acos(floor_normal.dot(Vector2.UP)))
	var slide_touching_ground = slide_ground_detector and slide_ground_detector.is_colliding()

	var can_jump = (
		is_on_floor()
		or coyote_timer > 0.0
		or (slide_touching_ground or abs(velocity.y) < 60.0)
	)

	if Input.is_action_just_pressed("jump"):
		print("---- INTENTO DE SALTO ----")
		print("is_on_floor(): ", is_on_floor())
		print("coyote_timer: ", coyote_timer)
		print("floor_angle: ", floor_angle)
		print("slide_touching_ground: ", slide_touching_ground)
		print("velocity.y: ", velocity.y)
		print("----------------------------")

	if Input.is_action_just_pressed("jump") and can_jump:
		print("✅ SALTANDO")
		if velocity.y > 0:
			velocity.y = 0
		velocity.y = -jump_force
		just_jumped = true
		coyote_timer = 0.0
		can_soft_land = false
		highest_jump_point = global_position.y
		maintained_speed = abs(velocity.x)

# ==========================
# GRAVITY
# ==========================
func apply_gravity(delta: float) -> void:
	if is_on_floor():
		coyote_timer = coyote_time
		can_soft_land = false
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)
		
		if global_position.y < highest_jump_point:
			highest_jump_point = global_position.y
		
		if jump_detector and not jump_detector.is_colliding():
			can_soft_land = true
		
		velocity.y += gravity * delta
		
		if velocity.y > 0.0:
			velocity.y += gravity * (fall_multiplier - 1.0) * delta
	
	if not Input.is_action_pressed("jump") and velocity.y < 0.0:
		velocity.y += gravity * 2.0 * delta
	
	velocity.y = clamp(velocity.y, -9999.0, max_fall_speed)

# ==========================
# SOFT LANDING
# ==========================
func apply_soft_landing(_delta: float) -> void:
	if not can_soft_land or not ground_detector or velocity.y <= 0.0 or is_on_floor():
		return
	
	if not ground_detector.is_colliding():
		return
	
	if jump_detector and jump_detector.is_colliding():
		var jump_floor_normal = jump_detector.get_collision_normal()
		var jump_floor_angle = rad_to_deg(acos(jump_floor_normal.dot(Vector2.UP)))
		
		if jump_floor_angle >= slope_slide_threshold:
			return
	
	var collision_point = ground_detector.get_collision_point()
	var distance_to_ground = collision_point.y - global_position.y
	var fall_distance = collision_point.y - highest_jump_point
	
	if fall_distance < min_jump_height:
		return
	
	if distance_to_ground > 0 and distance_to_ground <= soft_landing_distance:
		var proximity = 1.0 - (distance_to_ground / soft_landing_distance)
		var brake_force = proximity * soft_landing_strength
		velocity.y = lerp(velocity.y, 0.0, brake_force)

# ==========================
# MOVEMENT
# ==========================
func handle_movement(delta: float) -> void:
	var target_x = input_dir * move_speed
	
	if is_on_floor():
		var floor_normal = get_floor_normal()
		var floor_angle = rad_to_deg(acos(floor_normal.dot(Vector2.UP)))
		var slide_direction = sign(floor_normal.x)
		
		if floor_angle > slope_slide_threshold:
			if sign(input_dir) == slide_direction and abs(input_dir) > 0.1:
				slide_timer += delta
				current_slide_speed = slope_slide_speed + (slope_acceleration * slide_timer)
				current_slide_speed = min(current_slide_speed, slope_max_speed)
				maintained_speed = abs(velocity.x)
				
				if slide_timer < 0.3:
					velocity.x = lerp(velocity.x, slide_direction * current_slide_speed, 8.0 * delta)
				else:
					velocity.x = slide_direction * current_slide_speed
				
				if not just_jumped: # 🔥 evita cancelar el salto
					velocity.y = 200.0
			elif abs(input_dir) < 0.1:
				slide_timer += delta
				current_slide_speed = slope_slide_speed + (slope_acceleration * slide_timer)
				current_slide_speed = min(current_slide_speed, slope_max_speed)
				
				if slide_timer < 0.3:
					velocity.x = lerp(velocity.x, slide_direction * current_slide_speed, 8.0 * delta)
				else:
					velocity.x = slide_direction * current_slide_speed
				
				if not just_jumped:
					velocity.y = 200.0
			else:
				maintained_speed = 0.0
				velocity.x = lerp(velocity.x, target_x, acceleration_smoothness * delta)
		else:
			slide_timer = 0.0
			current_slide_speed = 0.0
			
			if maintained_speed > move_speed and abs(input_dir) > 0.1 and sign(input_dir) == sign(velocity.x):
				velocity.x = lerp(velocity.x, sign(input_dir) * maintained_speed, 3.0 * delta)
				maintained_speed = max(maintained_speed - (50.0 * delta), move_speed)
			else:
				maintained_speed = 0.0
				velocity.x = lerp(velocity.x, target_x, acceleration_smoothness * delta)
	else:
		slide_timer = 0.0
		current_slide_speed = 0.0
		
		if maintained_speed > move_speed and abs(input_dir) > 0.1:
			velocity.x = lerp(velocity.x, sign(input_dir) * maintained_speed, 2.0 * delta)
		else:
			maintained_speed = 0.0
			velocity.x = lerp(velocity.x, target_x, acceleration_smoothness * delta)
	
	move_and_slide()

# ==========================
# ANIMATION
# ==========================
func handle_animation() -> void:
	if not anim_state:
		return

	if not is_on_floor():
		if velocity.y < -100.0:
			anim_state.travel("Fairy_Jump_Move" if abs(velocity.x) > 80.0 else "Fairy_Jump")
		elif velocity.y > 100.0:
			anim_state.travel("Fairy_Fall_Move" if abs(velocity.x) > 80.0 else "Fairy_Fall")
	else:
		anim_state.travel("Fairy_Move" if abs(velocity.x) > 10.0 else "Fairy_Idle")

	if visual and abs(velocity.x) > 10.0:
		var current_anim = str(anim_state.get_current_node())
		if "Jump_Move" in current_anim or "Fall_Move" in current_anim:
			visual.scale.x = -1.0 if velocity.x < 0.0 else 1.0
