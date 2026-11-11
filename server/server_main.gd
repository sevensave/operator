extends Node
## Заглушка сервера (реализуется на этапе сети).
func _ready() -> void:
	print("server stub")
	get_tree().quit()
