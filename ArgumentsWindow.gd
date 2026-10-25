extends Window

signal arguments_applied(value: String)

@onready var arguments_edit: TextEdit = $MarginContainer/VBoxContainer/HBoxText/ArgumentsEdit
@onready var server_arguments_edit: TextEdit = $MarginContainer/VBoxContainer/HBoxText/ArgumentsMEdit

func _ready():
	$MarginContainer/VBoxContainer/HBoxContainer/ButtonCancel.pressed.connect(hide)
	$MarginContainer/VBoxContainer/HBoxContainer/ButtonApply.pressed.connect(_apply)

func _apply():
	arguments_applied.emit(arguments_edit.text)
	GenerationCache.data["extra_arguments"] = arguments_edit.text
	GenerationCache.data["server_arguments"] = server_arguments_edit.text
	GenerationCache.save_cache()
	hide()
