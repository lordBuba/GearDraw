extends Control

#signal generate_inpaint(image_path, mask_path, selection_rect)

@onready var prompt = $Panel/Prompt
@onready var negative_prompt = $Panel/NegativePrompt
@onready var console = $Panel/panel_out/outText
@onready var new_image = $Panel/ColorRect/TextureRect
@onready var button_strat_gen = $Panel/Container/Generate
@onready var model_path = $Panel/HSplitContainer/ModelPath
@onready var model_dialog = $Panel/ModelFileDialog
@onready var image_dialog = $Panel/ImageFileDialog
@onready var model_choise = $Panel/HSplitContainer/ModelPathButton
@onready var slider_width = $Panel/HContainer/VContainer2/SliderWidth
@onready var slider_height = $Panel/HContainer/VContainer2/SliderHeight
@onready var slider_steps = $Panel/HContainer/VContainer2/SliderSteps
@onready var slider_cfg = $Panel/HContainer/VContainer2/SliderCFG
@onready var slider_strength = $Panel/image_to_image/SliderStrength
@onready var value_width = $Panel/HContainer/VContainer3/valueWidth
@onready var value_height = $Panel/HContainer/VContainer3/valueHeight
@onready var value_steps = $Panel/HContainer/VContainer3/valueSteps
@onready var value_cfg = $Panel/HContainer/VContainer3/valueCFG
@onready var value_strength = $Panel/image_to_image/valueStrength
@onready var button_stop = $Panel/Container/Stop
@onready var button_add_image = $Panel/Prompt/addImage
@onready var img2img_texture = $Panel/image_to_image
@onready var line_seed = $Panel/HContainer/VContainer2/SeedEdit
@onready var button_random_seed = $Panel/HContainer/VContainer3/ButtonSeed
@onready var button_clear_image = $Panel/image_to_image/ButtonClearImage
@onready var lora_path = $Panel/HSplitContainer2/LoraPath
@onready var lora_dialog = $Panel/LoraFileDialog
@onready var select_lora = $Panel/HSplitContainer2/SelectLora
@onready var prompt_presets = $Panel/PromptPresets
@onready var rename_dialog = $Panel/RenameDialog
@onready var rename_line_edit = $Panel/RenameDialog/LineEdit
@onready var mask_rect = $Panel/image_to_image/Mask

var prompt_popup = PopupMenu.new()
var prompt_popup_index = -1
var lora = ""
var sd_cli = "sd-cli.exe"
var model = ""
var process = {}
var current_output = ""
var current_generation_id = -1
var stdout_buffer = ""
var stderr_buffer = ""
var init_image = ""
var inpaint_mask := ""
var inpaint_window
var inpaint_rect := Rect2()
var inpaint_selection_active := false
var active_prompt_preset := -1

func _ready():
	button_strat_gen.pressed.connect(generate)
	button_stop.pressed.connect(stop_generation)
	button_random_seed.pressed.connect(set_random_seed)
	model_choise.pressed.connect(_on_select_model_pressed)
	button_add_image.pressed.connect(_on_select_image_pressed)
	image_dialog.file_selected.connect(_on_image_file_dialog_selected)
	model_dialog.file_selected.connect(_on_model_file_dialog_file_selected)
	slider_width.value_changed.connect(_on_width_changed)
	slider_height.value_changed.connect(_on_height_changed)
	slider_steps.value_changed.connect(_on_steps_changed)
	slider_cfg.value_changed.connect(_on_cfg_changed)
	slider_strength.value_changed.connect(_on_strength_changed)
	button_clear_image.pressed.connect(_on_clear_image_pressed)
	select_lora.pressed.connect(_on_select_lora_pressed)
	lora_dialog.dir_selected.connect(_on_lora_dir_selected)
	add_child(prompt_popup)
	prompt_popup.add_item("Rename", 0)
	prompt_popup.add_item("Del", 1)
	prompt_popup.id_pressed.connect(_on_prompt_popup_pressed)
	rename_dialog.confirmed.connect(_on_rename_confirmed)
	$Panel/image_to_image/InpaintButton.pressed.connect(_open_inpaint)
	prompt.text_changed.connect(_on_prompt_changed)
	
	load_last_generation()
	load_prompt_buttons()
	

func _on_prompt_changed():
	if active_prompt_preset == -1:
		return

	if active_prompt_preset >= GenerationCache.data["prompts"].size():
		active_prompt_preset = -1
		return

	GenerationCache.data["prompts"][active_prompt_preset]["prompt"] = prompt.text
	GenerationCache.save_cache()
func update_prompt_buttons():
	for i in range(prompt_presets.get_child_count()):
		var button = prompt_presets.get_child(i)

		if not button is Button:
			continue

		var normal = StyleBoxFlat.new()
		normal.bg_color = Color(0.15, 0.15, 0.15)
		normal.corner_radius_top_left = 5
		normal.corner_radius_top_right = 5
		normal.corner_radius_bottom_left = 5
		normal.corner_radius_bottom_right = 5

		var active = StyleBoxFlat.new()
		active.bg_color = Color(0.4, 0.4, 0.4)
		active.corner_radius_top_left = 5
		active.corner_radius_top_right = 5
		active.corner_radius_bottom_left = 0
		active.corner_radius_bottom_right = 0

		if i == active_prompt_preset:
			button.add_theme_stylebox_override("normal", active)
		else:
			button.add_theme_stylebox_override("normal", normal)
func _open_inpaint():
	if init_image == "":
		console.append_text("Select image first\n")
		return
	
	if inpaint_window == null:
		var scene = preload("res://InpaintWindow.tscn")
		inpaint_window = scene.instantiate()
		inpaint_window.main = self
		
		
		
		print("CREATED NEW INPAINT WINDOW")
		get_tree().root.add_child(inpaint_window)
		print("WINDOW MODE: ", inpaint_window.mode)
		
		inpaint_window.mask_saved.connect(_on_mask_saved)
		inpaint_window.generate_inpaint.connect(_on_inpaint_generate)
		

	inpaint_window.setup(init_image)
	inpaint_window.popup_centered()

func _on_inpaint_generate(
	image_path: String,
	mask_path: String,
	rect: Rect2):
	
	init_image = image_path
	inpaint_mask = mask_path
	inpaint_rect = rect

	inpaint_selection_active = true
	print("START FROM INPAINT")
	generate()

func _on_mask_saved(path):
	inpaint_mask = path
	var image = Image.load_from_file(path)
	if not image.is_empty():
		var texture = ImageTexture.create_from_image(image)
		mask_rect.texture = texture
	
	console.append_text("Inpaint mask: " + path + "\n")

func load_prompt_buttons():
	for child in prompt_presets.get_children():
		child.queue_free()

	var prompts = GenerationCache.data.get("prompts", [])

	for i in range(prompts.size()):
		var preset = prompts[i]

		var button = Button.new()
		button.text = preset.get("name", "Prompt " + str(i + 1))

		button.gui_input.connect(
			func(event):
				if event is InputEventMouseButton:
					if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
						prompt_popup_index = i
						prompt_popup.position = Vector2i(event.global_position)
						prompt_popup.popup()
		)

		button.pressed.connect(
			func():
				active_prompt_preset = i
				prompt.text = preset.get("prompt", "")
				update_prompt_buttons()
		)

		prompt_presets.add_child(button)

	var add_button = Button.new()
	add_button.text = "+"
	add_button.pressed.connect(add_prompt_preset)

	prompt_presets.add_child(add_button)

	update_prompt_buttons()
func _on_prompt_popup_pressed(id):
	if id == 0:
		rename_prompt(prompt_popup_index)

	elif id == 1:
		var deleted_index = prompt_popup_index

		GenerationCache.remove_prompt(deleted_index)

		if active_prompt_preset == deleted_index:
			active_prompt_preset = -1
		elif active_prompt_preset > deleted_index:
			active_prompt_preset -= 1

		load_prompt_buttons()

	# НЕ сбрасываем здесь prompt_popup_index
func add_prompt_preset():
	if prompt.text.strip_edges() == "":
		return

	var _name = "Prompt " + str(
		GenerationCache.data["prompts"].size() + 1
	)

	GenerationCache.add_prompt(_name, prompt.text)

	active_prompt_preset = GenerationCache.data["prompts"].size() - 1

	load_prompt_buttons()
func rename_prompt(index):
	if index < 0:
		return

	if index >= GenerationCache.data["prompts"].size():
		return

	prompt_popup_index = index

	var preset = GenerationCache.data["prompts"][index]

	rename_line_edit.text = preset.get("name", "")
	rename_line_edit.select_all()

	rename_dialog.popup_centered()
	rename_line_edit.grab_focus()
func _on_rename_confirmed():
	if prompt_popup_index == -1:
		return

	if prompt_popup_index >= GenerationCache.data["prompts"].size():
		prompt_popup_index = -1
		return

	var new_name = rename_line_edit.text.strip_edges()

	if new_name == "":
		return

	GenerationCache.data["prompts"][prompt_popup_index]["name"] = new_name

	GenerationCache.save_cache()

	load_prompt_buttons()

	prompt_popup_index = -1

func _on_select_lora_pressed():
	lora_dialog.visible = true
	lora_dialog.popup_centered_ratio()

func _on_lora_dir_selected(path):
	lora_dialog.visible = false
	lora = path
	lora_path.text = path

func set_random_seed():
	line_seed.text = "-1"

func _on_width_changed(value):
	value_width.text = str(int(value))
	if slider_width.value != value:
		slider_width.value = value
func _on_height_changed(value):
	value_height.text = str(int(value))
	if slider_height.value != value:
		slider_height.value = value
func _on_steps_changed(value):
	value_steps.text = str(int(value))
func _on_cfg_changed(value):
	value_cfg.text = str(float(value))
func _on_strength_changed(value):
	value_strength.text = str(float(value))

func generate():
	if model == "":
		console.text += "error: model is not selected\n"
		button_strat_gen.disabled = false
		process_finished()
		return
	model = model_path.text
	console.append_text("-----------------------------------------------\n")
	console.append_text("start generation, model [" + model + "]\n")
	
	button_strat_gen.disabled = true
	button_stop.disabled = false
	stdout_buffer = ""
	stderr_buffer = ""
	$Panel/Container/ProgressBar.value = 10
	$Panel/Container/ProgressBar.max_value = slider_steps.value
	
	
	if not FileAccess.file_exists(model):
		console.append_text("error: model file not found\n")
		console.append_text("MODEL PATH: [" + model + "]\n")
		console.append_text("ABS PATH: [" + ProjectSettings.globalize_path(model) + "]\n")
		button_strat_gen.disabled = false
		process_finished()
		return
	
	current_output = get_next_image_path()
	
	var arguments = [
		"-m", model,
		"-p", prompt.text,
		"-n", negative_prompt.text,
		"-o", current_output,
		"--seed", line_seed.text,
		"-W", str(int(slider_width.value)),
		"-H", str(int(slider_height.value)),
		"--steps", str(int(slider_steps.value)),
		"--cfg-scale", str(slider_cfg.value),
		"--vae-tiling"
		]
	if init_image != "":
		arguments.append("--init-img")
		arguments.append(init_image)
		arguments.append("--strength")
		arguments.append(str(slider_strength.value))
	
	console.text = "start generation, be saved as " + current_output + "\n" + model +"\n"
	if lora != "":
		arguments.append("--lora-model-dir")
		arguments.append(lora)
	
	if inpaint_mask != "":
		arguments.append("--mask")
		arguments.append(inpaint_mask)
	
	current_generation_id = GenerationCache.add_generation(
	model,
	prompt.text,
	negative_prompt.text,
	init_image,
	lora,
	int(slider_width.value),
	int(slider_height.value),
	int(slider_steps.value),
	slider_cfg.value,
	int(line_seed.text),
	slider_strength.value,
	current_output
	)
	
	process = OS.execute_with_pipe(sd_cli, arguments, false)
	
	if process.is_empty():
		console.append_text("error sd-cli.exe\n")
		GenerationCache.set_status(
			current_generation_id,
			"failed"
		)
		button_strat_gen.disabled = false
		button_stop.disabled = true
		process_finished()
		return
	
	console.append_text("PID: " + str(process["pid"]) + "\n")

func stop_generation():
	if process.is_empty():
		return
	var pid = process["pid"]
	if OS.is_process_running(pid):
		OS.kill(pid)
	console.append_text("\nGeneration stopped\n")
	process = {}
	button_strat_gen.disabled = false
	button_stop.disabled = true

func _process(_delta: float):
	if process.is_empty():
		return
	# $Panel/outText.text += ".......\n"
	var stdout = process["stdio"]
	var stderr = process["stderr"]
	var out_text = read_pipe(stdout)
	var err_text = read_pipe(stderr)
	if out_text!="": 
		console.append_text(out_text + "\n") 
		update_generation_progress(out_text) 
	if err_text!="": 
		console.append_text(err_text + "\n")
	var pid = process["pid"]
	if not OS.is_process_running(pid):
		process_finished()

func read_pipe(pipe):
	if pipe == null:
		return ""
	var text = ""
	while true:
		var line = pipe.get_line()
		if pipe.get_error() != OK:
			break
		if line == "":
			break
		text += line + "\n"
	return text

func process_pipe_buffer(is_error):
	var buffer = stderr_buffer if is_error else stdout_buffer
	while true:
		var pos_r = buffer.find("\r")
		var pos_n = buffer.find("\n")
		if pos_r == -1 and pos_n == -1:
			break
		var pos = -1
		if pos_r == -1:
			pos = pos_n
		elif pos_n == -1:
			pos = pos_r
		else:
			pos = min(pos_r, pos_n)
		var line = buffer.substr(0, pos)
		buffer = buffer.substr(pos + 1)
		if line != "":
			update_generation_progress(line)
			if is_error:
				console.append_text(line + "\n")
			else:
				console.append_text(line + "\n")
	if is_error:
		stderr_buffer = buffer
	else:
		stdout_buffer = buffer

func get_next_image_path() -> String:
	var app_dir = OS.get_executable_path().get_base_dir()
	var outputs_dir = app_dir + "/outputs"
	DirAccess.make_dir_absolute(outputs_dir)
	var number = 0
	var file_path
	while true:
		file_path = outputs_dir + "/img_" + str(number) + ".png"
		if not FileAccess.file_exists(file_path):
			break
		number += 1
	return file_path

func process_finished():
	process = {}
	button_strat_gen.disabled = false
	button_stop.disabled = true
	if inpaint_window != null and is_instance_valid(inpaint_window):
		inpaint_window.apply_button.disabled = false
	if FileAccess.file_exists(current_output):
		var image = Image.load_from_file(current_output)
		if not image.is_empty():
			var texture = ImageTexture.create_from_image(image)
			new_image.texture = texture
			console.append_text(
				"Done: " + current_output + "\n"
			)
			GenerationCache.set_status(
				current_generation_id,
				"completed")
			
		else:
			console.append_text("error generation image\n")
			GenerationCache.set_status(
				current_generation_id,
				"failed"
			)
	else:
		console.append_text("error file image\n")
		GenerationCache.set_status(
			current_generation_id,
			"failed"
		)

	if inpaint_selection_active == true:
		inpaint_selection_active = false

		if inpaint_window != null:
			console.append_text("InpaintWindow exists\n")
			if is_instance_valid(inpaint_window):
				inpaint_window.paste_result(current_output)
			else:
				console.append_text("ERROR: InpaintWindow invalid\n")
		else:
			console.append_text("ERROR: InpaintWindow is null\n")

func _on_select_model_pressed():
	model_dialog.popup_centered_ratio()
	model_dialog.visible = true
func _on_select_image_pressed():
	image_dialog.popup_centered_ratio()
	image_dialog.visible = true

func _on_model_file_dialog_file_selected(path):
	model_path.text = path
	model_dialog.visible = false
func _on_image_file_dialog_selected(path):
	init_image = path
	image_dialog.visible = false
	var image = Image.load_from_file(path)
	if not image.is_empty():
		var texture = ImageTexture.create_from_image(image)
		img2img_texture.visible = true
		img2img_texture.texture = texture
func _on_clear_image_pressed():
	init_image = ""
	inpaint_mask = ""
	img2img_texture.texture = null
	img2img_texture.visible = false


func load_last_generation():
	if GenerationCache.data["generations"].is_empty():
		return

	var last = GenerationCache.data["generations"].back()

	prompt.text = last.get("prompt", "")
	negative_prompt.text = last.get("negative_prompt", "")

	model_path.text = last.get("model", "")
	model = last.get("model", "")

	init_image = last.get("init_image", "")
	lora = last.get("lora", "")

	if init_image != "":
		var image = Image.load_from_file(init_image)
		if not image.is_empty():
			var texture = ImageTexture.create_from_image(image)
			img2img_texture.visible = true
			img2img_texture.texture = texture
		

	if lora != "":
		lora_path.text = lora
	else:
		lora_path.text = ""

	slider_width.value = last.get("width", 512)
	slider_height.value = last.get("height", 512)
	slider_steps.value = last.get("steps", 20)
	slider_cfg.value = last.get("cfg", 7.0)
	slider_strength.value = last.get("strength", 0.75)

func update_generation_progress(text):
	var regex = RegEx.new()
	regex.compile(r">\s+\|\s*(\d+)/(\d+)")
	var result = regex.search(text)
	if result:
		var current_step = int(result.get_string(1))
		var total_steps = int(result.get_string(2))
		$Panel/Container/ProgressBar.max_value = total_steps
		$Panel/Container/ProgressBar.value = current_step

func paste_inpaint_result():
	if inpaint_window == null:
		return

	if not is_instance_valid(inpaint_window):
		return

	inpaint_window.paste_result(current_output)

func to_console(text: String):
	console.append_text(text)
	
