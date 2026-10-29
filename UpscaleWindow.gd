extends Window

signal upscale_requested(settings: Dictionary)

@onready var image_preview: TextureRect = $MarginContainer/VBoxContainer/ImagePreview
@onready var scale_slider: HSlider = $MarginContainer/VBoxContainer/AdvancedPanel/ScaleRow/ScaleOption
@onready var scale_label: Label = $MarginContainer/VBoxContainer/AdvancedPanel/ScaleRow/ScaleValue
@onready var advanced_button: Button = $MarginContainer/VBoxContainer/AdvancedButton
@onready var advanced_panel: VBoxContainer = $MarginContainer/VBoxContainer/AdvancedPanel
@onready var tile_size: OptionButton = $MarginContainer/VBoxContainer/AdvancedPanel/TileSize/TileSize
@onready var overlap: OptionButton = $MarginContainer/VBoxContainer/AdvancedPanel/OverlapSize/Overlap
@onready var strength: SpinBox = $MarginContainer/VBoxContainer/AdvancedPanel/Strength/StrengthValue
@onready var upscale_button: Button = $MarginContainer/VBoxContainer/UpscaleButton

var source_image: Image

func _ready():
	advanced_button.text = "Settings"
	advanced_button.pressed.connect(func():
		advanced_panel.visible = not advanced_panel.visible
	)
	scale_slider.value_changed.connect(func(value):
		scale_label.text = "x%.1f" % value)
	upscale_button.pressed.connect(_on_upscale_pressed)
	close_requested.connect(hide)

func set_image(image: Image):
	source_image = image
	image_preview.texture = ImageTexture.create_from_image(image)
	#var max_size = Vector2(size.x, size.y)
	#var image_size = Vector2(image.get_width(), image.get_height())
	#var ratio = min(
		#max_size.x / image_size.x,
		#max_size.y / image_size.y,
		#1.0)
#
	#image_preview.custom_minimum_size = image_size * ratio
	#image_preview.size = image_size * ratio
	#size.y = int(image_preview.size.y + 100)

func _on_upscale_pressed():
	if source_image == null or source_image.is_empty():
		push_warning("error image")
		return
	#get_parent().to_console("upscale pressed")
	var scale_factor: float = scale_slider.value
	upscale_requested.emit({
	"scale": scale_factor,
	"tile_size": int(tile_size.get_item_text(tile_size.selected)),
	"overlap": int(overlap.get_item_text(overlap.selected)),
	"strength": strength.value})


func resize_source_image(scale_factor: int) -> Image:
	var result = source_image.duplicate()
	result.resize(
		source_image.get_width() * scale_factor,
		source_image.get_height() * scale_factor,
		Image.INTERPOLATE_LANCZOS
	)
	return result


func split_into_tiles(image: Image, tile_size: int, overlap_size: int) -> Array:
	var tiles: Array = []
	var step = tile_size - overlap_size

	if step <= 0:
		push_error("Размер перекрытия должен быть меньше тайла")
		return tiles

	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var width = min(tile_size, image.get_width() - x)
			var height = min(tile_size, image.get_height() - y)

			if width <= 0 or height <= 0:
				continue

			var tile = Image.create(width, height, false, image.get_format())
			tile.blit_rect(
				image,
				Rect2i(x, y, width, height),
				Vector2i.ZERO
			)

			tiles.append({
				"image": tile,
				"x": x,
				"y": y
			})

	return tiles
