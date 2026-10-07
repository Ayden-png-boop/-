extends SceneTree
const C_HEX := Color("#7fe3ff")
const D_HEX := Color("#0e2438", 0.86)
static var SV := {"a": Color("#ff8a5c"), "b": 3}
func _initialize() -> void:
	print("HEX=", C_HEX)
	print("HEX_A=", D_HEX)
	print("SV=", SV)
	print("FONT=", FontFile.new() != null)
	quit()
