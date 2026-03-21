extends Resource
class_name PickupData

@export var name: String = "comida"        # Unique internal ID
@export var display_name: String = "Comida" # Visible name in UI
@export var cost: float = 0.5               # Cost in shillings
@export var effects := {                    # Attribute modifiers
	"hambre": -40.0,
	"felicidad": +5.0
}
@export var sound: AudioStream              # Optional pickup sound
@export var icon: Texture2D                 # Optional UI icon
