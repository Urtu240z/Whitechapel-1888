extends Node2D
#
#@onready var world = $World
#@onready var player = $Player
#@onready var cam = $Player/Camera2D
#@onready var fairy = $World/Fairy
#@onready var overlay = $LightOverlay
#
#var hada_activa := false
#var cam_original_parent : Node
#var cam_original_pos : Vector2
#var cam_original_zoom : Vector2
#
## 🔹 nuevo: lista de nodos exteriores que deben pausarse
#var world_nodes := []
#var world_frozen := false
#
#func _ready():
	#fairy.hide()
	#overlay.modulate.a = 0
#
	## 🔹 registramos todos los edificios en el mundo
	#for building in world.get_children():
		#if building.has_signal("player_entered_building"):
			#building.connect("player_entered_building", _on_building_entered)
			#building.connect("player_exited_building", _on_building_exited)
		#else:
			#world_nodes.append(building)
#
#
#func _input(event):
	#if event.is_action_pressed("pause_fairy"):
		#hada_activa = !hada_activa
		#if hada_activa:
			#activar_hada()
		#else:
			#desactivar_hada()
#
## =====================================================
## 🌙 Control del hada
## =====================================================
#func activar_hada():
	#if world_frozen:
		#return  # no activar hada si estamos dentro de un edificio
#
	#player.set_process(false)
	#cam_original_parent = cam.get_parent()
	#cam_original_pos = cam.position
	#cam_original_zoom = cam.zoom
#
	#cam_original_parent.remove_child(cam)
	#fairy.add_child(cam)
	#cam.position = Vector2.ZERO
#
	#var tw = create_tween()
	#tw.tween_property(overlay, "modulate:a", 0.6, 0.5)
	#fairy.aparecer(player)
	#tw.parallel().tween_property(cam, "zoom", Vector2(0.6, 0.6), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	#create_tween().tween_property(Engine, "time_scale", 0.3, 0.6)
#
#func desactivar_hada():
	#player.set_process(true)
	#fairy.desaparecer()
#
	#var tw = create_tween()
	#tw.tween_property(overlay, "modulate:a", 0.0, 0.5)
	#tw.parallel().tween_property(cam, "zoom", cam_original_zoom, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	#create_tween().tween_property(Engine, "time_scale", 1.0, 0.6)
#
	#await tw.finished
	#fairy.remove_child(cam)
	#cam_original_parent.add_child(cam)
	#cam.position = cam_original_pos
#
#
## =====================================================
## 🏠 Entrada / salida de edificios
## =====================================================
## =====================================================
## 🏠 Entrada / salida de edificios (sincronizada)
## =====================================================
#func _on_building_entered(building: Node) -> void:
	#print("🏠 Entrando a:", building.name)
	#world_frozen = true
#
	## 1️⃣ Congelar mundo exterior
	#for node in world_nodes:
		#if node == player or node == building:
			#continue
		#_pause_node(node, true)
#
	## 2️⃣ Fade a negro primero
	#var tw := create_tween()
	#tw.tween_property(overlay, "modulate:a", 1.0, 0.4)
	#await tw.finished  # 👈 esperamos a que el negro cubra todo
#
	## 3️⃣ Ocultamos el resto del mundo
	#for node in world_nodes:
		#if node != building:
			#node.visible = false
#
	## 4️⃣ Pedimos al edificio que empiece su fade-in interno
	#if building.has_method("_show_interior_smooth"):
		#building._show_interior_smooth()  # 👈 nuevo helper en el edificio
#
#
#func _on_building_exited(building: Node) -> void:
	#print("🚪 Saliendo de:", building.name)
	#world_frozen = false
#
	## 1️⃣ Pedimos al edificio que oculte su interior (esperando)
	#if building.has_method("_hide_interior_smooth"):
		#await building._hide_interior_smooth()
#
	## 2️⃣ Reactivamos todo el mundo exterior
	#for node in world_nodes:
		#_pause_node(node, false)
		#node.visible = true
#
	## 3️⃣ Fade out del overlay (volver a luz normal)
	#var tw := create_tween()
	#tw.tween_property(overlay, "modulate:a", 0.0, 0.4)
#
#
## =====================================================
## ⚙️ Helper para pausar nodos
## =====================================================
#func _pause_node(node: Node, paused: bool):
	#if node.has_method("set_process"):
		#node.set_process(!paused)
	#if node.has_method("set_physics_process"):
		#node.set_physics_process(!paused)
