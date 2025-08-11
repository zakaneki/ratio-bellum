extends Node

const MENU_STREAM_PATH := "res://music/ancient-legend-187639.mp3" 
const GAME_STREAM_PATH := "res://music/the-britons-127687.mp3"   

var menu_player: AudioStreamPlayer
var game_player: AudioStreamPlayer
var _tween: Tween = null

func _ready():
	menu_player = AudioStreamPlayer.new()
	game_player = AudioStreamPlayer.new()
	add_child(menu_player)
	add_child(game_player)
	menu_player.stream = load(MENU_STREAM_PATH)
	game_player.stream = load(GAME_STREAM_PATH)
	menu_player.bus = "Master"
	game_player.bus = "Master"
	menu_player.autoplay = true
	game_player.autoplay = true
	menu_player.volume_db = 0.0
	game_player.volume_db = -60.0
	menu_player.play()
	game_player.play()
	

func fade_to_gameplay(dur := 1.5):
	_crossfade(menu_player, game_player, dur)

func fade_to_menu(dur := 1.5):
	_crossfade(game_player, menu_player, dur)

func _crossfade(from: AudioStreamPlayer, to: AudioStreamPlayer, dur: float):
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	to.volume_db = -60.0
	if not to.playing:
		to.play()
	_tween.tween_property(from, "volume_db", -60.0, dur)
	_tween.tween_property(to, "volume_db", -10.0, dur)
