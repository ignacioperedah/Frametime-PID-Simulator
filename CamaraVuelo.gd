extends Camera3D

@export var velocidad_crucero: float = 35.0 
var sensibilidad_mouse: float = 0.002
var mirando: bool = false

func _ready():
	global_position.y = max(global_position.y, 40.0) 

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		mirando = event.pressed
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if mirando else Input.MOUSE_MODE_VISIBLE)
			
	if event is InputEventMouseMotion and mirando:
		rotate_y(-event.relative.x * sensibilidad_mouse)
		rotation.x = clamp(rotation.x - (event.relative.y * sensibilidad_mouse), deg_to_rad(-75), deg_to_rad(75))

func _process(delta: float):
	global_position += Vector3.FORWARD * velocidad_crucero * delta
