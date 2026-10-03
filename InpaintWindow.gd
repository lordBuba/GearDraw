extends Window

signal mask_saved(path)
signal generate_inpaint(image_path, mask_path, selection_rect)

var image_path := ""
var mask_path := ""

@onready var image_view = $VBoxContainer/Canvas/Image
@onready var mask_view = $VBoxContainer/Canvas/Mask
@onready var brush_slider = $VBoxContainer/Bottom/BrushSize
@onready var brush_value = $VBoxContainer/Bottom/BrushValue
@onready var clear_button = $VBoxContainer/Bottom/ClearButton
@onready var apply_button = $VBoxContainer/Bottom/ApplyButton
@onready var select_region_button = $VBoxContainer/Bottom/SelectRegion
@onready var canvas = $VBoxContainer/Canvas
@onready var brush_cursor = $VBoxContainer/Canvas/BrushCursor
@onready var selection_visual = $VBoxContainer/Canvas/SelectionRect
@onready var blur_slider = $VBoxContainer/Bottom/BlurSize
@onready var blur_value = $VBoxContainer/Bottom/BlurValue
@onready var output_size = $VBoxContainer/Bottom/OutputSize
@onready var output_value = $VBoxContainer/Bottom/OutputSize/OutputValue


var mask_image: Image
var mask_texture: ImageTexture

var brush_size := 40
var drawing := false
var erasing := false
var last_pos := Vector2.ZERO
var brush_cursor_pos := Vector2(-100, -100)

var selection_mode := false
var selection_rect := Rect2()
var selection_start := Vector2.ZERO
var selection_end := Vector2.ZERO
var original_image: Image
var generation_selection_rect := Rect2()

var main: Control

func _ready():
	var app_dir = OS.get_executable_path().get_base_dir()
	if OS.has_feature("editor"):
		app_dir = ProjectSettings.globalize_path("res://")
	mask_path = app_dir + "/inpaint_mask.png"
	brush_slider.value_changed.connect(_on_brush_size_changed)
	clear_button.pressed.connect(_on_clear_pressed)
	apply_button.pressed.connect(_on_apply_pressed)

	close_requested.connect(_on_close_requested)

	mask_view.gui_input.connect(_on_mask_input)
	select_region_button.pressed.connect(_toggle_selection_mode)
	
	brush_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brush_cursor.visible = false
	selection_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_visual.visible = false
	mask_view.gui_input.connect(_on_selection_input)
	blur_slider.value_changed.connect(_on_blur_size_changed)
	output_size.value_changed.connect(_on_output_size_changed)
	_on_blur_size_changed(blur_slider.value)
	

func _on_output_size_changed(value):
	output_value.text = str(int(value))
	main._on_width_changed(value)
	main._on_height_changed(value)

func _on_blur_size_changed(value):
	blur_value.text = str(int(value))

func blur_mask(image: Image, radius: int) -> Image:
	if radius <= 0:
		return image

	var width = image.get_width()
	var height = image.get_height()

	var source = image.duplicate()
	var temp = Image.create_empty(
		width,
		height,
		false,
		Image.FORMAT_RGBA8
	)

	var result = Image.create_empty(
		width,
		height,
		false,
		Image.FORMAT_RGBA8
	)

	var sigma = max(float(radius) / 2.0, 0.5)
	var kernel_radius = radius
	var kernel = []

	var kernel_sum = 0.0

	# Создаём Gaussian kernel
	for i in range(-kernel_radius, kernel_radius + 1):
		var value = exp(
			-(float(i * i)) /
			(2.0 * sigma * sigma)
		)

		kernel.append(value)
		kernel_sum += value

	# Нормализуем kernel
	for i in range(kernel.size()):
		kernel[i] /= kernel_sum

	# Горизонтальный проход
	for y in range(height):
		for x in range(width):
			var value = 0.0

			for k in range(-kernel_radius, kernel_radius + 1):
				var px = clamp(x + k, 0, width - 1)

				value += (
					source.get_pixel(px, y).r *
					kernel[k + kernel_radius]
				)

			result.set_pixel(
				x,
				y,
				Color(value, value, value, 1.0)
			)

	# Вертикальный проход
	for y in range(height):
		for x in range(width):
			var value = 0.0

			for k in range(-kernel_radius, kernel_radius + 1):
				var py = clamp(y + k, 0, height - 1)

				value += (
					result.get_pixel(x, py).r *
					kernel[k + kernel_radius]
				)

			temp.set_pixel(
				x,
				y,
				Color(value, value, value, 1.0)
			)

	return temp

func _toggle_selection_mode():
	selection_mode = !selection_mode
	if !apply_button.disabled:
		if selection_mode:
			select_region_button.text = "Brush"
			apply_button.text = "Generate"
			mask_view.modulate = Color(1, 1, 1, 0)
			_on_clear_pressed()
		else:
			select_region_button.text = "Select Region"
			apply_button.text = "Apply"
			selection_visual.visible = false
			mask_view.modulate = Color(1, 1, 1, 0.5)
		

func _on_selection_input(event):
	if not selection_mode:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				selection_start = event.position
				selection_end = event.position
			else:
				selection_end = event.position

			_update_selection_visual()

	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			selection_end = event.position
			_update_selection_visual()
	if event is InputEventMouseButton and not event.pressed:
		print("Selection in image: ", selection_rect)

func _update_selection_visual():
	var start = screen_to_image(selection_start)
	var end = screen_to_image(selection_end)

	var x = min(start.x, end.x)
	var y = min(start.y, end.y)

	var width = abs(end.x - start.x)
	var height = abs(end.y - start.y)

	# Квадрат
	var _size = max(width, height)

	# Размер кратен 64 пикселям оригинального изображения
	_size = max(64.0, round(_size / 64.0) * 64.0)

	var image_width = original_image.get_width()
	var image_height = original_image.get_height()

	# Не выходим за границы изображения
	x = clamp(x, 0.0, image_width - _size)
	y = clamp(y, 0.0, image_height - _size)

	selection_rect = Rect2(x, y, _size, _size)

	# Переводим обратно из пикселей изображения
	# в координаты Image для отображения рамки
	var texture_size = Vector2(
		original_image.get_width(),
		original_image.get_height()
	)

	var scale = min(
		image_view.size.x / texture_size.x,
		image_view.size.y / texture_size.y
	)

	var displayed_size = texture_size * scale
	var offset = (image_view.size - displayed_size) * 0.5

	selection_visual.position = offset + selection_rect.position * scale
	selection_visual.size = selection_rect.size * scale
	selection_visual.visible = true
	

func get_mask_rect() -> Rect2:
	var margin = selection_rect.size.x * 0.15
	var image_size = original_image.get_size()

	var left_margin = margin
	var top_margin = margin
	var right_margin = margin
	var bottom_margin = margin

	# Левая грань касается края изображения
	if selection_rect.position.x <= 0:
		left_margin = 0

	# Верхняя грань
	if selection_rect.position.y <= 0:
		top_margin = 0

	# Правая грань
	if selection_rect.position.x + selection_rect.size.x >= image_size.x:
		right_margin = 0

	# Нижняя грань
	if selection_rect.position.y + selection_rect.size.y >= image_size.y:
		bottom_margin = 0

	return Rect2(
		selection_rect.position + Vector2(left_margin, top_margin),
		selection_rect.size - Vector2(
			left_margin + right_margin,
			top_margin + bottom_margin
		)
	)

func show_mask_area():
	if original_image == null:
		return

	var mask_rect = get_mask_rect()

	var preview = Image.create_empty(
		original_image.get_width(),
		original_image.get_height(),
		true,
		Image.FORMAT_RGBA8
	)

	preview.fill(Color(0, 0, 0, 1))

	for y in range(
		int(mask_rect.position.y),
		int(mask_rect.end.y)
	):
		for x in range(
			int(mask_rect.position.x),
			int(mask_rect.end.x)
		):
			if x >= 0 and x < preview.get_width() and y >= 0 and y < preview.get_height():
				preview.set_pixel(x, y, Color(1, 1, 1, 1))

	var texture = ImageTexture.create_from_image(preview)
	mask_view.texture = texture

func _on_close_requested():
	hide()


func setup(path: String):
	image_path = path

	original_image = Image.load_from_file(image_path)

	if original_image.is_empty():
		push_error("Can't load image: " + image_path)
		return

	image_view.texture = ImageTexture.create_from_image(original_image)

	_create_mask(
		original_image.get_width(),
		original_image.get_height()
	)

func _create_mask(width: int, height: int):
	mask_image = Image.create_empty(
		width,
		height,
		true,
		Image.FORMAT_RGBA8
	)

	mask_image.fill(Color(0, 0, 0, 1))

	mask_texture = ImageTexture.create_from_image(mask_image)
	mask_view.texture = mask_texture


func _on_brush_size_changed(value):
	brush_size = int(value)
	brush_value.text = str(brush_size)


func _on_clear_pressed():
	if mask_image:
		mask_image.fill(Color(0, 0, 0, 1))
		mask_texture.update(mask_image)


func _on_mask_input(event):
	if selection_mode:
		return
	if mask_image == null:
		return

	if event is InputEventMouseButton:

		if event.button_index == MOUSE_BUTTON_LEFT:
			drawing = event.pressed
			erasing = false

			if drawing:
				var canvas_pos = image_view.get_local_mouse_position()
				last_pos = canvas_pos
				paint_circle(canvas_pos, true)
				mask_texture.update(mask_image)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			drawing = event.pressed
			erasing = true

			if drawing:
				var canvas_pos = image_view.get_local_mouse_position()
				last_pos = canvas_pos
				paint_circle(canvas_pos, false)
				mask_texture.update(mask_image)

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_slider.value = min(
				brush_slider.value + 5,
				brush_slider.max_value
			)

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_slider.value = max(
				brush_slider.value - 5,
				brush_slider.min_value
			)

	elif event is InputEventMouseMotion:
		var canvas_pos = image_view.get_local_mouse_position()
		brush_cursor.visible = true
		brush_cursor.size = Vector2(brush_slider.value, brush_slider.value)
		brush_cursor.position = canvas_pos - brush_cursor.size / 2
		if drawing:
			draw_line_mask(last_pos, canvas_pos, !erasing)
			last_pos = canvas_pos
			mask_texture.update(mask_image)

		canvas.queue_redraw()

func paint_circle(pos: Vector2, paint: bool):
	var image_pos = screen_to_image(pos)

	var radius = brush_size * 0.5

	var min_x = max(0, int(image_pos.x - radius))
	var max_x = min(mask_image.get_width() - 1, int(image_pos.x + radius))

	var min_y = max(0, int(image_pos.y - radius))
	var max_y = min(mask_image.get_height() - 1, int(image_pos.y + radius))

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx = (x - image_pos.x) / radius
			var dy = (y - image_pos.y) / radius

			if dx * dx + dy * dy <= 1.0:
				if paint:
					mask_image.set_pixel(x, y, Color(1, 1, 1, 1))
				else:
					mask_image.set_pixel(x, y, Color(0, 0, 0, 1))


func draw_line_mask(from: Vector2, to: Vector2, paint: bool):
	var distance = from.distance_to(to)

	var step = max(2.0, brush_size * 0.2)
	var count = max(1, int(distance / step))

	for i in range(count + 1):

		var t = float(i) / float(count)

		var pos = from.lerp(to, t)

		paint_circle(pos, paint)


func _on_apply_pressed():
	if selection_mode:
		_generate_inpaint()
		apply_button.disabled = true
		return

	if mask_image == null:
		return

	var blur_radius = int(blur_slider.value)

	var final_mask = blur_mask(
		mask_image,
		blur_radius
	)

	var error = final_mask.save_png(mask_path)

	if error != OK:
		push_error("Can't save mask: " + str(error))
		return

	mask_saved.emit(mask_path)
	hide()

func _generate_inpaint():
	if selection_rect.size == Vector2.ZERO:
		return

	var mask_rect = get_mask_rect()

	var crop = original_image.get_region(selection_rect)

	var crop_mask = Image.create_empty(
		int(selection_rect.size.x),
		int(selection_rect.size.y),
		false,
		Image.FORMAT_RGBA8
	)

	crop_mask.fill(Color(0, 0, 0, 1))

	var local_mask_rect = Rect2(
		mask_rect.position - selection_rect.position,
		mask_rect.size
	)

	for y in range(
		int(local_mask_rect.position.y),
		int(local_mask_rect.end.y)
	):
		for x in range(
			int(local_mask_rect.position.x),
			int(local_mask_rect.end.x)
		):
			if x >= 0 and x < crop_mask.get_width() and \
			   y >= 0 and y < crop_mask.get_height():
				crop_mask.set_pixel(
					x,
					y,
					Color(1, 1, 1, 1)
				)
	

	var app_dir = OS.get_executable_path().get_base_dir()

	if OS.has_feature("editor"):
		app_dir = ProjectSettings.globalize_path("res://")

	var input_path = app_dir + "/inpaint_input.png"
	var mask_path_local = app_dir + "/inpaint_mask.png"
	
	var blur_radius = int(blur_slider.value)
	crop_mask = blur_mask(
		crop_mask,
		blur_radius )
	
	var error = crop.save_png(input_path)

	if error != OK:
		push_error("Can't save inpaint input")
		return

	error = crop_mask.save_png(mask_path_local)

	if error != OK:
		push_error("Can't save inpaint mask")
		return
	_on_blur_size_changed(blur_slider.value)
	generation_selection_rect = selection_rect
	generate_inpaint.emit(
	input_path,
	mask_path_local,
	selection_rect)
	print("EMIT DONE")

func screen_to_image(pos: Vector2) -> Vector2:
	var texture = image_view.texture

	if texture == null:
		return Vector2.ZERO

	var texture_size = texture.get_size()
	var control_size = image_view.size

	var scale = min(
		control_size.x / texture_size.x,
		control_size.y / texture_size.y
	)

	var displayed_size = texture_size * scale
	var offset = (control_size - displayed_size) * 0.5

	var local_pos = pos - image_view.position - offset

	return local_pos / scale

func paste_result(result_path: String) -> bool:
	main.to_console("PATH: " + result_path + "\n")
	main.to_console(
		"RECT: " + str(generation_selection_rect) + "\n"
	)
	var result 
	if result_path == "":
		main.to_console("RESULT EMPTY\n")
		return false
	else:
		result = Image.load_from_file(result_path)
	if result == null:
		main.to_console("RESULT EMPTY\n")
		return false

	var target_size = Vector2i(
		int(generation_selection_rect.size.x),
		int(generation_selection_rect.size.y)
	)

	result.resize(
		target_size.x,
		target_size.y,
		Image.INTERPOLATE_LANCZOS
	)

	original_image.blit_rect(
		result,
		Rect2i(
			0,
			0,
			target_size.x,
			target_size.y
		),
		Vector2i(
			int(generation_selection_rect.position.x),
			int(generation_selection_rect.position.y)
		)
	)

	image_view.texture = ImageTexture.create_from_image(original_image)

	main.to_console("BLIT DONE\n")

	var output_path = get_next_edit_path()

	var error = original_image.save_png(output_path)
	if error != OK:
		main.to_console(
			"ERROR SAVE: " + str(error) + "\n"
		)
		return false

	main.to_console(
		"EDITED IMAGE SAVED: " + output_path + "\n"
	)

	return true
	
func get_next_edit_path() -> String:
	var app_dir = OS.get_executable_path().get_base_dir()

	if OS.has_feature("editor"):
		app_dir = ProjectSettings.globalize_path("res://")

	var output_dir = app_dir + "/outputs"

	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_absolute(output_dir)

	var num := 1

	while FileAccess.file_exists(
		output_dir + "/img_ed_" + str(num) + ".png"
	):
		num += 1

	return output_dir + "/img_ed_" + str(num) + ".png"
	
