extends Node


var cache_file = ""
var data = {
	"version": 1,
	"next_id": 0,
	"generations": [],
	"prompts": []
}
func add_prompt(_name, prompt):
	data["prompts"].append({
		"name": _name,
		"prompt": prompt
	})
	save_cache()


func remove_prompt(index):
	if index >= 0 and index < data["prompts"].size():
		data["prompts"].remove_at(index)
		save_cache()

func _ready():
	var app_dir = OS.get_executable_path().get_base_dir()
	cache_file = app_dir + "/cache.json"

	load_cache()


func load_cache():
	if not FileAccess.file_exists(cache_file):
		save_cache()
		return

	var file = FileAccess.open(cache_file, FileAccess.READ)

	if file == null:
		print("Не удалось открыть cache.json")
		return

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()

	if json.parse(text) != OK:
		print("Ошибка чтения cache.json")
		return

	if typeof(json.data) == TYPE_DICTIONARY:
		data = json.data
	if not data.has("prompts"):
		data["prompts"] = []
		save_cache()

func save_cache():
	var file = FileAccess.open(cache_file, FileAccess.WRITE)

	if file == null:
		print("Не удалось сохранить cache.json")
		return

	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func add_generation(
	model,
	prompt,
	negative_prompt,
	init_image,
	lora,
	width,
	height,
	steps,
	cfg,
	_seed,
	strength,
	output
):
	var generation = {
		"id": data["next_id"],
		"model": model,
		"prompt": prompt,
		"negative_prompt": negative_prompt,
		"init_image": init_image,
		"lora": lora,
		"width": width,
		"height": height,
		"steps": steps,
		"cfg": cfg,
		"seed": _seed,
		"strength": strength,
		"output": output,
		"status": "pending"
	}

	data["generations"].append(generation)
	data["next_id"] += 1

	# Оставляем только последние 30
	while data["generations"].size() > 30:
		data["generations"].pop_front()

	save_cache()

	return generation["id"]

func set_status(id, status):
	for generation in data["generations"]:
		if generation["id"] == id:
			generation["status"] = status
			save_cache()
			return
