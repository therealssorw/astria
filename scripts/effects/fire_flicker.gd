extends Node3D
## Flickers the fire's light using layered sines (deterministic, no RNG jitter).

@export var base_energy := 2.2
@export var flicker_amount := 0.6
@export var flicker_speed := 9.0

@onready var light: OmniLight3D = $Light

var _t := 0.0

func _process(delta: float) -> void:
	_t += delta * flicker_speed
	var f := sin(_t) * 0.5 + sin(_t * 2.7 + 1.3) * 0.3 + sin(_t * 5.1 + 0.7) * 0.2
	light.light_energy = base_energy + f * flicker_amount
