extends Node

@onready var normal_ui: Control = $NormalUI
@onready var data_error_screen: DataErrorScreen = $DataErrorScreen
@onready var fsm: GameStateMachine = $GameStateMachine
@onready var debug_overlay: DebugOverlay = $DebugOverlay
@onready var dev_banner: DevBanner = $DevBanner
@onready var screen_stack: ScreenStack = $ScreenStack

## Player preferences file. Tests set it before adding Main to the tree.
var settings_path: String = GameSettings.DEFAULT_PATH
## Save library folder. Tests set it before adding Main to the tree.
var saves_root: String = SaveLibrary.DEFAULT_ROOT

func _ready() -> void:
	add_to_group(SettingsApply.GROUP)
	SettingsApply.apply_all(debug_overlay, settings_path)
	screen_stack.screen_opened.connect(_on_screen_opened)
	if fsm != null:
		fsm.screen_stack = screen_stack
		fsm.settings_path = settings_path
		fsm.saves_root = saves_root
	check_config_errors()
	if GameData.load_errors.is_empty() and fsm != null:
		fsm.start()
	if debug_overlay != null and fsm != null:
		debug_overlay.setup(fsm)
	if fsm != null:
		fsm.how_to_play_requested.connect(screen_stack.push.bind("how_to_play"))
		fsm.library_requested.connect(open_library)
	_show_how_to_play_on_first_launch()
	GameData.config_reload_failed.connect(_on_config_reload_failed)
	GameData.config_reloaded.connect(_on_config_reloaded)
	if fsm != null:
		fsm.config_applied.connect(_on_config_applied)
		fsm.phase_changed.connect(_on_phase_changed)

## SettingsApply.GROUP hook: the Settings screen saved a change.
func on_settings_changed() -> void:
	if data_error_screen == null or not data_error_screen.visible:
		SettingsApply.apply_debug_overlay(debug_overlay, settings_path)

func _on_screen_opened(_id: String) -> void:
	var top: Control = screen_stack.top_screen()
	var settings: SettingsScreen = top as SettingsScreen
	if settings != null and settings.settings_path != settings_path:
		settings.setup(settings_path)
	if settings != null:
		settings.fsm = fsm
		settings.refresh_raid_debug()
	var how_to_play: HowToPlayScreen = top as HowToPlayScreen
	if how_to_play != null:
		how_to_play.setup(settings_path, fsm)
	var saved: SavedScreen = top as SavedScreen
	if saved != null:
		SaveLibrary.open(saves_root, GameData.config, true)
		saved.setup(saves_root, fsm)
	var opponents: OpponentScreen = top as OpponentScreen
	if opponents != null and fsm != null:
		opponents.setup(fsm.session, fsm)
	var upgrades: UpgradesScreen = top as UpgradesScreen
	if upgrades != null and fsm != null:
		upgrades.setup(fsm.session, fsm)
	var defense_log: DefenseLogScreen = top as DefenseLogScreen
	if defense_log != null and fsm != null:
		defense_log.setup(fsm.session, fsm)

## Opens the Saved bases and armies screen on one tab ("base" or "army").
func open_library(kind: String) -> void:
	screen_stack.push("saved")
	var saved: SavedScreen = screen_stack.top_screen() as SavedScreen
	if saved != null:
		saved.open_tab(kind)

func _on_phase_changed(_from: GameStateMachine.Phase, _to: GameStateMachine.Phase) -> void:
	screen_stack.clear()

func _show_how_to_play_on_first_launch() -> void:
	if fsm == null or fsm.phase != GameStateMachine.Phase.TITLE:
		return
	if HowToPlayScreen.should_show_on_launch(settings_path):
		screen_stack.push("how_to_play")

func _on_config_reload_failed(errors: PackedStringArray) -> void:
	# The Data error screen lists the new errors itself; the banner is for hot reloads while playing.
	if data_error_screen != null and data_error_screen.visible:
		return
	dev_banner.show_errors(errors)

func _on_config_applied(summary: Dictionary) -> void:
	dev_banner.show_info(str(summary.get("message", "")))

# Clears error banners, and recovers from a config that was invalid at startup (no session yet).
func _on_config_reloaded(_config: GameConfig) -> void:
	# A successful reload ends an error state even when applying it is queued (INFECTION).
	if dev_banner.kind == DevBanner.Kind.ERROR:
		dev_banner.dismiss()
	if fsm == null or fsm.phase != GameStateMachine.Phase.NONE:
		return
	check_config_errors()
	fsm.start()
	dev_banner.show_info("Config reloaded")

func check_config_errors() -> void:
	if not GameData.load_errors.is_empty():
		_show_config_error_ui()
	else:
		_show_normal_ui()

func _show_config_error_ui() -> void:
	if normal_ui != null:
		normal_ui.visible = false
	if data_error_screen != null:
		data_error_screen.show_errors(GameData.load_errors)
	if fsm != null and fsm.phase_root != null:
		fsm.phase_root.visible = false
	if screen_stack != null:
		screen_stack.visible = false
	if debug_overlay != null and is_instance_valid(debug_overlay):
		debug_overlay.visible = false

func _show_normal_ui() -> void:
	if normal_ui != null:
		normal_ui.visible = true
	if data_error_screen != null:
		data_error_screen.visible = false
	if fsm != null and fsm.phase_root != null:
		fsm.phase_root.visible = true
	if screen_stack != null:
		screen_stack.visible = true
	SettingsApply.apply_debug_overlay(debug_overlay, settings_path)
