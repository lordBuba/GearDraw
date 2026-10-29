extends Control

#signal generate_inpaint(image_path, mask_path, selection_rect)

@onready var http_request = $HTTPRequest
@onready var http_request_poll = $HTTPRequestPoll
@onready var http_request_cancel = $HTTPRequestCancel

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
@onready var button_to_image_result = $Panel/ColorRect/BtuttonPanel/VBoxContainer/img2img
@onready var button_close_result = $Panel/ColorRect/BtuttonPanel/VBoxContainer/Clear
@onready var button_explore = $Panel/ColorRect/BtuttonPanel/VBoxContainer/explorer
@onready var timer = $Timer
@onready var button_restart_server = $Panel/Container/ServerButton
@onready var lora_button = $Panel/Prompt/LoraButton
@onready var lora_popup = $Panel/Prompt/LoraButton/LoraPopup
@onready var lora_list = $Panel/Prompt/LoraButton/LoraPopup/ScrollContainer/LoraList
@onready var arguments_window = $ArgumentsWindow
@onready var arguments_button = $Panel/HSplitContainer/arguments
@onready var upscale_window = $UpscaleWindow
@onready var button_open_upscale = $Panel/image_to_image/UpscaleButton

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
var init_image_inp = ""
var inpaint_mask := ""
var inpaint_window
var inpaint_rect := Rect2()
var inpaint_selection_active := false
var active_prompt_preset := -1
var start_time := 0.0

var server_process = {}
var current_job_id := ""

var progress_regex = RegEx.new()

var is_load_lora = false

var extra_arguments := ""
var server_arguments := ""

var upscale_active := false
var upscale_tiles: Array = []
var upscale_tile_index := 0
var upscale_settings: Dictionary = {}
var upscale_result: Image

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
	button_to_image_result.pressed.connect(_on_result_to_image)
	button_close_result.pressed.connect(_on_close_result)
	button_explore.pressed.connect(_on_button_explore_result)
	
	lora_button.pressed.connect(_toggle_lora_popup)
	
	button_restart_server.pressed.connect(
		func():
		restart_sd_server(model_path.text))
	http_request.request_completed.connect(_on_request_completed)
	http_request_poll.request_completed.connect(_on_poll_completed)
	http_request_cancel.request_completed.connect(_on_cancel_completed)
	
	progress_regex.compile("(\\d+)/(\\d+)")
	
	arguments_button.pressed.connect(func():
		arguments_window.popup_centered())
	arguments_window.arguments_applied.connect(func(value: String):
		extra_arguments = value
		GenerationCache.data["extra_arguments"] = value
		GenerationCache.save_cache())
	
	arguments_window.arguments_applied.connect(func(value: String):
		extra_arguments = value
		server_arguments = arguments_window.server_arguments_edit.text)
	
	button_open_upscale.pressed.connect(_on_open_upscale_pressed)
	upscale_window.upscale_requested.connect(_on_upscale_requested)
	
	load_last_generation()
	load_prompt_buttons()
	load_extra_arguments()
	load_server_arguments()
	await get_tree().process_frame
	if model == "":
		print("Model is not saved")
		return
	if not FileAccess.file_exists(model):
		print("Model not found: ", model)
		return
	start_sd_server(model)
	

func blend_upscale_tile(tile: Image, tile_data: Dictionary):
	var start_x = int(tile_data["x"])
	var start_y = int(tile_data["y"])
	var overlap_size = int(upscale_settings["overlap"])

	var result_width = upscale_result.get_width()
	var result_height = upscale_result.get_height()
	var tile_width = tile.get_width()
	var tile_height = tile.get_height()

	for y in range(tile_height):
		for x in range(tile_width):
			var px = start_x + x
			var py = start_y + y

			if px >= result_width or py >= result_height:
				continue

			var weight = 1.0

			# Левая граница
			if start_x > 0:
				var t = clamp(float(x) / overlap_size, 0.0, 1.0)
				weight = min(weight, t * t * (3.0 - 2.0 * t))

			# Правая граница
			if start_x + tile_width < result_width:
				var t = clamp(
					float(tile_width - 1 - x) / overlap_size,
					0.0, 1.0
				)
				weight = min(weight, t * t * (3.0 - 2.0 * t))

			# Верхняя граница
			if start_y > 0:
				var t = clamp(float(y) / overlap_size, 0.0, 1.0)
				weight = min(weight, t * t * (3.0 - 2.0 * t))

			# Нижняя граница
			if start_y + tile_height < result_height:
				var t = clamp(
					float(tile_height - 1 - y) / overlap_size, 0.0, 1.0
				)
				weight = min(weight, t * t * (3.0 - 2.0 * t))

			var old_color = upscale_result.get_pixel(px, py)
			var new_color = tile.get_pixel(x, y)

			upscale_result.set_pixel(
				px, py, old_color.lerp(new_color, weight)
			)

func finish_upscale():
	current_output = init_image.get_base_dir().path_join(
		init_image.get_file().get_basename() + "_upscaled.png"
	)
	
	var error = upscale_result.save_png(current_output)

	if error == OK:
		console.append_text("Upscale completed: " + current_output + "\n")

		new_image.texture = ImageTexture.create_from_image(upscale_result)
	else:
		console.append_text("error saving Upscale: " + str(error) + "\n")

	upscale_active = false
	upscale_tiles.clear()
	upscale_tile_index = 0
	current_job_id = ""
	button_strat_gen.disabled = false

func split_into_tiles(image: Image, tile_size: int, overlap_size: int) -> Array:
	var tiles: Array = []
	var step = tile_size - overlap_size

	if step <= 0:
		push_error("Overlap должен быть меньше Tile Size")
		return tiles

	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var width = min(tile_size, image.get_width() - x)
			var height = min(tile_size, image.get_height() - y)

			# Создаём тайл фиксированного размера
			var tile = Image.create(
				tile_size, tile_size, false, image.get_format()
			)

			# Заполняем его краевыми пикселями
			for py in range(tile_size):
				for px in range(tile_size):
					var src_x = min(px, width - 1)
					var src_y = min(py, height - 1)
					tile.set_pixel(
						px, py,
						image.get_pixel(x + src_x, y + src_y)
					)

			tiles.append({
				"image": tile,
				"x": x,
				"y": y,
				"width": width,
				"height": height
			})

	return tiles
func send_upscale_tile():
	if upscale_tile_index >= upscale_tiles.size():
		finish_upscale()
		return
	console.append_text(
		"Upscale: send %d / %d\n" % [
			upscale_tile_index + 1,
			upscale_tiles.size()
		]
	)
	var tile_data: Dictionary = upscale_tiles[upscale_tile_index]
	var tile: Image = tile_data["image"]
	console.append_text(
	"TILE %d: pos=(%d,%d), size=%dx%d\n" % [
		upscale_tile_index + 1,
		int(tile_data["x"]),
		int(tile_data["y"]),
		tile.get_width(),
		tile.get_height()
	])
	var tile_bytes = tile.save_png_to_buffer()
	var tile_b64 = Marshalls.raw_to_base64(tile_bytes)

	var request_data = {
		"prompt": prompt.text,
		"negative_prompt": negative_prompt.text,
		"clip_skip": -1,
		"width": tile.get_width(),
		"height": tile.get_height(),
		"strength": float(upscale_settings["strength"]),
		"seed": int(line_seed.text),
		"batch_count": 1,
		"init_image": tile_b64,
		"mask_image": null,
		"lora": build_lora_array(),
		"sample_params": {
			"sample_steps": int(slider_steps.value),
			"guidance": {"txt_cfg": float(slider_cfg.value)},
			"shifted_timestep": 0,
			"custom_sigmas": []
		},
		"output_format": "png"
	}

	var body = JSON.stringify(request_data)
	var error = http_request.request(
		"http://127.0.0.1:1234/sdcpp/v1/img_gen",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		console.append_text("Ошибка отправки тайла: " + str(error) + "\n")
		finish_upscale()
func _on_upscale_requested(settings: Dictionary):
	#to_console("upscale pressed 1\n")
	if upscale_active:
		return
	#to_console("upscale pressed 2\n")
	upscale_settings = settings
	upscale_active = true
	upscale_tile_index = 0

	var source = upscale_window.source_image
	var scale_factor = float(settings["scale"])

	var target_width = roundi(source.get_width() * scale_factor)
	var target_height = roundi(source.get_height() * scale_factor)
	upscale_result = source.duplicate()
	upscale_result.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)

	upscale_tiles = split_into_tiles(
		upscale_result,
		int(settings["tile_size"]),
		int(settings["overlap"])
	)

	console.append_text(
		"Upscale: total tiles: "
		+ str(upscale_tiles.size()) + "\n"
	)
	if upscale_tiles.is_empty():
		upscale_active = false
		return
	button_strat_gen.disabled = true
	button_stop.disabled = false
	start_time = Time.get_ticks_msec()/1000.0
	send_upscale_tile()

func _on_open_upscale_pressed():
	if init_image == "":
		console.append_text("error image path.\n")
		return

	var image = Image.load_from_file(init_image)
	if image.is_empty():
		console.append_text("error image.\n")
		return

	upscale_window.set_image(image)
	upscale_window.popup_centered()

func get_lora_settings() -> Array:
	var result: Array = []
	var list = lora_list

	for row in list.get_children():
		var checkbox = row.get_child(0) as CheckBox
		var weight = row.get_child(1) as SpinBox

		result.append({
			"name": checkbox.text,
			"enabled": checkbox.button_pressed,
			"weight": weight.value
		})

	return result

func apply_lora_settings(settings: Array) -> void:
	var list = lora_list

	for row in list.get_children():
		var checkbox = row.get_child(0) as CheckBox
		var weight = row.get_child(1) as SpinBox

		for item in settings:
			if item.get("name", "") == checkbox.text:
				checkbox.button_pressed = item.get("enabled", false)
				weight.value = item.get("weight", 1.0)
				break

func save_lora_settings():
	GenerationCache.data["lora_settings"] = get_lora_settings()
	GenerationCache.save_cache()

func build_lora_array() -> Array:
	var result: Array = []
	#var list = $Panel/LoraButton/LoraPopup/ScrollContainer/LoraList

	for row in lora_list.get_children():
		var checkbox = row.get_child(0) as CheckBox

		if not checkbox.button_pressed:
			continue

		var weight = checkbox.get_meta("weight_control") as SpinBox
		if weight == null:
			continue

		result.append({
			"path": checkbox.text + ".safetensors",
			"multiplier": float(weight.value),
			"is_high_noise": false
		})

	return result

func _toggle_lora_popup():
	if !is_load_lora:
		load_lora_list()
		is_load_lora = true
	if lora_popup.visible:
		lora_popup.hide()
	else:
		var pos = lora_button.get_screen_position()
		lora_popup.position = Vector2i(int(pos.x+lora_button.size.x), int(pos.y-100))
		lora_popup.popup()

func load_lora_list():
	for child in lora_list.get_children():
		child.queue_free()

	if lora.is_empty() or not DirAccess.dir_exists_absolute(lora):
		return

	var dir = DirAccess.open(lora)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "safetensors":
			add_lora_row(file_name.get_basename())

		file_name = dir.get_next()

	dir.list_dir_end()
	var settings = GenerationCache.data.get("lora_settings", [])
	apply_lora_settings(settings)

func add_lora_row(lora_name: String):
	var row = HBoxContainer.new()
	var list = $Panel/Prompt/LoraButton/LoraPopup/ScrollContainer/LoraList

	var checkbox = CheckBox.new()
	checkbox.text = lora_name
	checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	checkbox.add_theme_icon_override("unchecked", preload("res://checkbox_unchecked.png"))

	var weight = SpinBox.new()
	weight.min_value = -5.0
	weight.max_value = 5.0
	weight.step = 0.1
	weight.value = 1.0
	weight.custom_minimum_size.x = 50
	checkbox.set_meta("weight_control", weight)

	row.add_child(checkbox)
	#row.add_child(minus)
	row.add_child(weight)
	#row.add_child(plus)

	list.add_child(row)

func _on_cancel_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray):
	console.append_text("========== CANCEL RESPONSE ==========\n")
	console.append_text("RESULT: " + str(result) + "\n")
	console.append_text("CODE: " + str(response_code) + "\n")
	#console.append_text("BODY: " + body.get_string_from_utf8() + "\n")

	if response_code == 200:
		console.append_text("GENERATION CANCELLED\n")
		current_job_id = ""
		process_finished()

	elif response_code == 409:
		console.append_text("JOB ALREADY GENERATING, CANNOT CANCEL\n")

func _on_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray):
	console.append_text("========== HTTP RESPONSE ==========\n")
	console.append_text("RESULT: " + str(result) + "\n")
	console.append_text("CODE: " + str(response_code) + "\n")

	var response = JSON.parse_string(body.get_string_from_utf8())
	#console.append_text("RESPONSE PARSED: " + str(response) + "\n")
	if response != null and response.has("poll_url"):
		console.append_text(
			"POLL URL: " + response["poll_url"] + "\n"
		)

	if response != null and response.has("id"):
		var job_id = response["id"]
		current_job_id = job_id
		console.append_text(
			"JOB ID: " + job_id + "\n"
		)

		poll_generation(job_id)

func _on_poll_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray):
	
	var response = JSON.parse_string(body.get_string_from_utf8())

	if response == null:
		return

	var status = response.get("status", "")

	#console.append_text("STATUS: " + status + "\n")

	if status == "generating" or status == "queued":
		await get_tree().create_timer(5).timeout
		if current_job_id == "":
			return
		if response.has("id"):
			poll_generation(current_job_id)
	elif status == "cancelled":
		console.append_text("GENERATION CANCELLED\n")
		current_job_id = ""
		#process_finished()
	elif status == "completed":
		console.append_text("GENERATION COMPLETED\n")

		var result_data = response.get("result", {})
		#console.append_text("RESULT RECEIVED\n")

		var images = result_data.get("images", [])
		console.append_text("IMAGES RECEIVED\n")

		if images.size() > 0:
			console.append_text("IMAGE 0 RECEIVED\n")

			var image_data = images[0]
			console.append_text("IMAGE DATA TYPE: " + str(typeof(image_data)) + "\n")

			var b64 = image_data.get("b64_json", "")
			console.append_text("BASE64 GOT\n")
			console.append_text("BASE64 LENGTH: " + str(b64.length()) + "\n")
			var image_bytes = Marshalls.base64_to_raw(b64)
			console.append_text("BYTES: " + str(image_bytes.size()) + "\n")

			var image = Image.new()
			var error = image.load_png_from_buffer(image_bytes)

			console.append_text("IMAGE LOAD RESULT: " + str(error) + "\n")

			if error != OK:
				return
			
			if upscale_active:
				var tile_data: Dictionary = upscale_tiles[upscale_tile_index]
				var original_width = int(tile_data["width"])
				var original_height = int(tile_data["height"])

				var cropped_tile = image.get_region(
				Rect2i(0, 0, original_width, original_height))
				blend_upscale_tile(cropped_tile, tile_data)

				upscale_tile_index += 1
				current_job_id = ""

				console.append_text(
				"Upscale: tile %d of %d ready\n" % [
				upscale_tile_index,
				upscale_tiles.size()])

				send_upscale_tile()
				return

			var texture = ImageTexture.create_from_image(image)
			new_image.texture = texture

			var file = FileAccess.open(current_output, FileAccess.WRITE)

			if file:
				file.store_buffer(image_bytes)
				file.close()
				console.append_text("IMAGE SAVED: " + current_output + "\n")
			else:
				console.append_text("FAILED TO SAVE IMAGE\n")
			process_finished()
	

func poll_generation(job_id: String):
	if current_generation_id == -1 and not upscale_active:
		return
	#console.append_text("START POLLING: " + job_id + "\n")

	var error = http_request_poll.request(
		"http://127.0.0.1:1234/sdcpp/v1/jobs/" + job_id,
		[],
		HTTPClient.METHOD_GET
	)

	#console.append_text(
	#	"POLL REQUEST RESULT: " + str(error) + "\n"
	#)

func restart_sd_server(_model: String):
	stop_sd_server()

	await get_tree().process_frame

	start_sd_server(_model)

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_sd_server()
		get_tree().quit()

func stop_sd_server():
	if server_process.is_empty():
		button_restart_server.text = "▶"
		return

	var pid = server_process["pid"]

	if OS.is_process_running(pid):
		console.append_text("Stopping sd-server...\n")
		OS.kill(pid)
	server_process = {}
	button_restart_server.text = "▶"

func start_sd_server(_model: String):
	var server = "sd-server.exe"

	var arguments = [
		"-m",
		_model
	]

	if lora != "":
		arguments.append("--lora-model-dir")
		arguments.append(lora)

	# Дополнительные аргументы сервера
	var extra_args = server_arguments.strip_edges()

	if extra_args != "":
		var parsed_args = extra_args.split(" ", false)
		arguments.append_array(parsed_args)

	server_process = OS.execute_with_pipe(server, arguments, false)

	if server_process.is_empty():
		print("Failed to start sd-server")
		return

	console.append_text(
		"sd-server started, PID: "
		+ str(server_process["pid"])
		+ "\n"
	)

	button_restart_server.text = "↻"

func update_generation_progress(text: String):
	var lines = text.split("\r")
	for line in lines:
		var result = progress_regex.search(line)
		console.append_text(line + "\n")
		if result:
			var current_step = result.get_string(1).to_int()
			var total_steps = result.get_string(2).to_int()
			$Panel/Container/ProgressBar.max_value = total_steps
			$Panel/Container/ProgressBar.value = current_step

func read_pipe(pipe: FileAccess) -> String:
	if pipe == null:
		return ""
	
	var length = pipe.get_length()
	if length > 0:
		return pipe.get_buffer(length).get_string_from_utf8()
	
	return ""	

func _on_close_result():
	new_image.texture = null

func _on_result_to_image():
	if current_output!="" and FileAccess.file_exists(current_output):
		image_dialog.visible = true
		_on_image_file_dialog_selected(current_output)

func _on_button_explore_result():
	var app_dir = OS.get_executable_path().get_base_dir()
	var outputs_dir = app_dir + "/outputs"
	OS.shell_show_in_file_manager(outputs_dir)

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

func _on_inpaint_generate(image_path: String,
	mask_path: String,
	rect: Rect2):
	
	init_image_inp = image_path
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

	if GenerationCache.data["prompts"].is_empty():
		GenerationCache.data["prompts"].append({
			"name": "Prompt 1",
			"prompt": ""
		})
		GenerationCache.save_cache()

	var prompts = GenerationCache.data["prompts"]

	active_prompt_preset = clampi(
	int(GenerationCache.data.get("active_prompt_preset", 0)),
	0,
	prompts.size() - 1)

	for i in range(prompts.size()):
		var preset = prompts[i]
		var button = Button.new()
		button.text = preset.get("name", "Prompt " + str(i + 1))

		button.gui_input.connect(
			func(event):
				if event is InputEventMouseButton:
					if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
						prompt_popup_index = i
						prompt_popup.position = DisplayServer.mouse_get_position()
						prompt_popup.popup())
		
		button.pressed.connect(func():
			active_prompt_preset = i
			GenerationCache.data["active_prompt_preset"] = i
			prompt.text = GenerationCache.data["prompts"][i].get("prompt", "")
			GenerationCache.save_cache()
			update_prompt_buttons())

		prompt_presets.add_child(button)

	var add_button = Button.new()
	add_button.text = " + "
	add_button.pressed.connect(add_prompt_preset)
	prompt_presets.add_child(add_button)

	prompt.text = prompts[active_prompt_preset].get("prompt", "")
	update_prompt_buttons()
func _on_prompt_popup_pressed(id):
	if id == 0:
		rename_prompt(prompt_popup_index)

	elif id == 1:
		if GenerationCache.data["prompts"].size() <= 1:
			return
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
	update_prompt_buttons()
	prompt_popup_index = -1

func _on_select_lora_pressed():
	lora_dialog.visible = true
	lora_dialog.popup_centered_ratio()

func _on_lora_dir_selected(path):
	lora_dialog.visible = false
	lora = path
	lora_path.text = path
	load_lora_list()

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
	console.append_text("\n========== GENERATE ==========\n")
	model = model_path.text
	console.append_text("start generation, model [" + model + "]\n")
	if model == "":
		console.text += "error: model is not selected\n"
		button_strat_gen.disabled = false
		process_finished()
		return
	start_time = Time.get_ticks_msec()/1000.0
	button_strat_gen.disabled = true
	button_stop.disabled = false
	stdout_buffer = ""
	stderr_buffer = ""
	
	if not FileAccess.file_exists(model):
		console.append_text("error: model file not found\n")
		console.append_text("MODEL PATH: [" + model + "]\n")
		console.append_text("ABS PATH: [" + ProjectSettings.globalize_path(model) + "]\n")
		button_strat_gen.disabled = false
		process_finished()
		return
	console.append_text("MODEL OK\n")
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
	#if init_image != "":
		#arguments.append("--init-img")
		#if inpaint_selection_active:
			#arguments.append(init_image_inp)
		#else:
			#arguments.append(init_image)
		#arguments.append("--strength")
		#arguments.append(str(slider_strength.value))
	var init_image_data = null
	if init_image != "" or init_image_inp != "":
		var image_bytes
		arguments.append("--init-img")
		if inpaint_selection_active:
			image_bytes = FileAccess.get_file_as_bytes(init_image_inp)
			arguments.append(init_image_inp)
		else:
			image_bytes = FileAccess.get_file_as_bytes(init_image)
			arguments.append(init_image)
		init_image_data = Marshalls.raw_to_base64(image_bytes)
	#console.text = "start generation, be saved as " + current_output + "\n" + model +"\n"
	if lora != "":
		arguments.append("--lora-model-dir")
		arguments.append(lora)
	var mask_data = null
	if inpaint_mask != "":
		var image_bytes = FileAccess.get_file_as_bytes(inpaint_mask)
		mask_data = Marshalls.raw_to_base64(image_bytes)
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
	save_lora_settings()
	#process = OS.execute_with_pipe(sd_cli, arguments, false)
	
	#if server_process.is_empty():
		#console.append_text("error: sd-server is not running\n")
		#GenerationCache.set_status(
			#current_generation_id,
			#"failed"
		#)
		#button_strat_gen.disabled = false
		#button_stop.disabled = true
		#process_finished()
		#return
	console.append_text(JSON.stringify(build_lora_array()))
	console.append_text("OUTPUT: " + current_output + "\n")
	#var body = JSON.stringify({
	#"prompt": prompt.text,
	#"negative_prompt": negative_prompt.text,
	#"clip_skip": -1,
	#"width": int(slider_width.value),
	#"height": int(slider_height.value),
	#"strength": slider_strength.value,
	#"seed": int(line_seed.text),
	#"batch_count": 1,
	#"init_image": init_image_data,
	#"mask_image": mask_data,
	#"lora": build_lora_array(),
	#"sample_params": {
		#"sample_steps": int(slider_steps.value),
		#"shifted_timestep": 0,
		#"custom_sigmas": []},
	#"output_format": "png",
	#"vae_tiling_params": {
		#"enabled": true,
		#"tile_size_x": 0,
		#"tile_size_y": 0,
		#"target_overlap": 0.5,
		#"rel_size_x": 0,
		#"rel_size_y": 0	}})
	
	var request_data = {
	"prompt": prompt.text,
	"negative_prompt": negative_prompt.text,
	"clip_skip": -1,
	"width": int(slider_width.value),
	"height": int(slider_height.value),
	"strength": slider_strength.value,
	"seed": int(line_seed.text),
	"batch_count": 1,
	"init_image": init_image_data,
	"mask_image": mask_data,
	"lora": build_lora_array(),
	"sample_params": {
		"sample_steps": int(slider_steps.value),
		"guidance": {
			"txt_cfg": float(slider_cfg.value)},
		"shifted_timestep": 0,
		"custom_sigmas": []
	},
	"output_format": "png",
	"vae_tiling_params": {
		"enabled": true,
		"tile_size_x": 128,
		"tile_size_y": 128,
		"target_overlap": 0.5,
		"rel_size_x": 0,
		"rel_size_y": 0
	}}
	var extra_params = parse_extra_arguments()

	for key in extra_params:
		request_data[key] = extra_params[key]

	var body = JSON.stringify(request_data)
	#var body = JSON.stringify({
	#"model_path": model_path,
	#"prompt": "girl",
	#"negative_prompt": "",
	#"clip_skip": -1,
	#"width": 512,
	#"height": 512,
	#"strength": 0.75,
	#"seed": 42,
	#"batch_count": 1,
	#"init_image": null,
	#"mask_image": null,
	#"lora": [],
	#"sample_params": {
		#"sample_steps": 20
	#},
	#"output_format": "png"})
	
	var json = JSON.stringify(body)
	#console.append_text("REQUEST BODY:\n" + json + "\n")
	console.append_text("SENDING REQUEST...\n")
	
	var error = http_request.request(
	"http://127.0.0.1:1234/sdcpp/v1/img_gen",
	["Content-Type: application/json"],
	HTTPClient.METHOD_POST,
	body)
	
	console.append_text("REQUEST RESULT: " + error_string(error) + "\n")
	#console.append_text("PID: " + str(process["pid"]) + "\n")

func stop_generation():
	if current_job_id == "":
		return

	var job_id = current_job_id
	#current_job_id = ""

	console.append_text("\nCancelling job: " + job_id + "\n")

	var error = http_request_cancel.request(
		"http://127.0.0.1:1234/sdcpp/v1/jobs/" + job_id + "/cancel",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		""
	)

	console.append_text("CANCEL REQUEST RESULT: " + str(error) + "\n")

	#button_strat_gen.disabled = false
	#button_strat_gen.text = "Generate"
	#button_stop.disabled = true

	$Panel/Container/ProgressBar.max_value = 0

	finish_inpaint_rigeon()

func _process(_delta: float):
	if button_strat_gen.disabled:
		var elapsed_time: float = (Time.get_ticks_msec()/1000.0)-start_time
		@warning_ignore("integer_division")
		var minutes: int = int(elapsed_time)/60
		var seconds: int = int(elapsed_time)%60
		button_strat_gen.text = "%02d:%02d" % [minutes, seconds]
	####/* sd-cli
	##if process.is_empty():
		##return
	#var stdout = process["stdio"]
	#var stderr = process["stderr"]
	#var out_text = read_pipe(stdout)
	#var err_text = read_pipe(stderr)
	#if out_text!="":  
		#update_generation_progress(out_text) 
	#if err_text!="": 
		#console.append_text(err_text + "\n")
	#var pid = process["pid"]
	#if not OS.is_process_running(pid):
		#process_finished()
	####
	# sd-server
	if not server_process.is_empty():
		var stdout = server_process["stdio"]
		var stderr = server_process["stderr"]

		var out_text = read_pipe(stdout)
		var err_text = read_pipe(stderr)

		if out_text != "":
			update_generation_progress(out_text)

		if err_text != "":
			console.append_text(err_text)

		var server_pid = server_process["pid"]

		if not OS.is_process_running(server_pid):
			console.append_text("sd-server stopped\n")
			server_process = {}
			button_stop.disabled = true
			button_strat_gen.disabled = false


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
	#process = {}
	var last
	if current_output != "":
		last = button_strat_gen.text
	button_strat_gen.disabled = false
	if current_output != "":
		button_strat_gen.text = "Generate (" + last + ")"
	button_stop.disabled = true
	
	if FileAccess.file_exists(current_output):
		var image = Image.load_from_file(current_output)
		if not image.is_empty():
			var texture = ImageTexture.create_from_image(image)
			new_image.texture = texture
			#console.append_text(
			#	"Done: " + current_output + "\n"
			#)
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
	finish_inpaint_rigeon()

func finish_inpaint_rigeon():
	if inpaint_selection_active == true:
		inpaint_selection_active = false
		if inpaint_window != null:
			console.append_text("InpaintWindow exists\n")
			if is_instance_valid(inpaint_window):
				inpaint_window.apply_button.disabled = false
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
	model = path
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
	init_image_inp = ""
	img2img_texture.texture = null
	img2img_texture.visible = false
	inpaint_window.hide()

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
		load_lora_list()
		var settings = GenerationCache.data.get("lora_settings", [])
		apply_lora_settings(settings)
	else:
		lora_path.text = ""
	
	slider_width.value = last.get("width", 512)
	slider_height.value = last.get("height", 512)
	slider_steps.value = last.get("steps", 20)
	slider_cfg.value = last.get("cfg", 7.0)
	slider_strength.value = last.get("strength", 0.75)
	value_steps.text = slider_steps.value
	#start_sd_server(model_path)

func paste_inpaint_result():
	if inpaint_window == null:
		return

	if not is_instance_valid(inpaint_window):
		return

	inpaint_window.paste_result(current_output)

func to_console(text: String):
	console.append_text(text)
	
func load_extra_arguments():
	extra_arguments = GenerationCache.data.get("extra_arguments", "")
	arguments_window.arguments_edit.text = extra_arguments
func parse_extra_arguments() -> Dictionary:
	var result := {}

	for line in extra_arguments.split("\n", false):
		line = line.strip_edges()
		if line.is_empty():
			continue

		var parts = line.split("=", false, 1)
		if parts.size() != 2:
			push_warning("Неверный аргумент: " + line)
			continue

		var key = parts[0].strip_edges()
		var value = parts[1].strip_edges().to_lower()

		if value == "true":
			result[key] = true
		elif value == "false":
			result[key] = false
		elif value.is_valid_int():
			result[key] = int(value)
		elif value.is_valid_float():
			result[key] = float(value)
		else:
			result[key] = parts[1].strip_edges()

	return result
func load_server_arguments():
	server_arguments = GenerationCache.data.get(
		"server_arguments", "")
	arguments_window.server_arguments_edit.text = server_arguments
