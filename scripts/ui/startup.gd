extends Node
## Startup — the front door of PENROSE BREAK (scenes/startup.tscn, main scene).
## Splash choreography from the Prescription Games shared toolkit: black
## screen, the studio caduceus (~300 px, gentle 1.03→1.0 scale-in) over
## "PRESCRIPTION GAMES" / "presents"; fade in, hold, fade out; any key or
## click skips; skipped outright when Game.skip_splash_once is set by the
## in-game MAIN MENU buttons.
##
## The menu underneath: a fresh Penrose vista dusted with falling
## block-color rhombi, the title, the player-name field, START / OPTIONS /
## QUIT, the best-time line. Everything is built in code; all art is vector.

const VERSION := "v1.15"

const COL_TEXT := Color("d9fffa")
const COL_DIM := Color("55908f")
const COL_ACCENT := Color("19e3d2")

const SPLASH_FADE_IN := 0.6
const SPLASH_HOLD := 1.2
const SPLASH_FADE_OUT := 0.5
const SPLASH_LOGO_PX := 300.0

var _splash_layer: CanvasLayer
var _splash_black: ColorRect
var _splash_box: VBoxContainer
var _splash_tween: Tween
var _splash_done := false

var _menu_layer: CanvasLayer
var _menu_root: Control
var _menu_column: VBoxContainer
var _title_box: VBoxContainer
var _name_edit: LineEdit
var _best_label: Label
var _options_panel: PanelContainer
var _scores_panel: PanelContainer
var _main_buttons: Array = []
var _reset_btn: Button
var _reset_armed := false
var _mode_btn: Button
var _menu_mode_btn: Button
var _time_btn: Button
var _break_btn: Button
var _score_labels := {}   # "classic" / "penrose:regime" / "frame:regime" → Label
var _color_refresh: Array = []   # callables syncing color widgets ← Game


func _ready() -> void:
	_build_backdrop()
	_build_menu()
	_build_splash()
	Game.changed.connect(_refresh_best)
	if Game.skip_splash_once:
		Game.skip_splash_once = false
		_end_splash(true)
	else:
		_play_splash()
	# §cli: `-- --touchtest` verifies the touch path end-to-end (CLI.md).
	if OS.get_cmdline_user_args().has("--touchtest"):
		_run_touch_test()
	# §cli: `-- --padtest` drives the menu with a gamepad end-to-end.
	if OS.get_cmdline_user_args().has("--padtest"):
		_run_pad_test()
	# §cli: `-- --uitour` opens every panel once (robustness checks run it
	# against corrupted save files) and quits.
	if OS.get_cmdline_user_args().has("--uitour"):
		_run_ui_tour()


func _unhandled_input(event: InputEvent) -> void:
	if _splash_done:
		if event.is_action_pressed("ui_cancel"):
			if _options_panel != null and _options_panel.visible:
				_close_options()
				get_viewport().set_input_as_handled()
			elif _scores_panel != null and _scores_panel.visible:
				_close_scores()
				get_viewport().set_input_as_handled()
		return
	# Raw touches never reach the splash rect's gui_input (mouse emulation
	# is off), so a finger skips the splash here too.
	var pressed: bool = (event is InputEventKey or event is InputEventJoypadButton
		or event is InputEventScreenTouch) and event.is_pressed()
	if pressed:
		_end_splash(false)
		get_viewport().set_input_as_handled()


## Mouse presses and raw touches stop at the splash ColorRect, so
## click/tap-to-skip lives here.
func _on_splash_gui_input(event: InputEvent) -> void:
	if _splash_done:
		return
	if (event is InputEventMouseButton or event is InputEventScreenTouch) \
			and event.is_pressed():
		_end_splash(false)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------- backdrop -----

## The menu sits on its own random Penrose tiling — same generator as the
## arena — under a soft vertical wash (dark vignette up top for text
## legibility, turquoise glow pooling at the bottom where the wall of blocks
## will be), dusted with TileSnow: sparse lone rhombi in the block colors
## drifting down. Draw order is sibling order in layer 0: tiling, wash,
## snow; the menu UI lives on CanvasLayer 10 above all three.
func _build_backdrop() -> void:
	var bg := PenroseBg.new()
	add_child(bg)

	var wash := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(0.01, 0.045, 0.055, 0.9),
		Color(0.01, 0.05, 0.06, 0.55),
		Color(0.02, 0.35, 0.32, 0.28),
	])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.width = 64
	grad_tex.height = 256
	grad_tex.fill_from = Vector2(0.0, 0.0)
	grad_tex.fill_to = Vector2(0.0, 1.0)
	wash.texture = grad_tex
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	# Snow flakes are the vista's own prototiles: same edge length.
	var snow := TileSnow.new()
	snow.side = bg.tile_side()
	add_child(snow)


# --------------------------------------------------------------- splash -----

func _build_splash() -> void:
	_splash_layer = CanvasLayer.new()
	_splash_layer.layer = 50
	add_child(_splash_layer)

	_splash_black = ColorRect.new()
	_splash_black.color = Color.BLACK
	_splash_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_splash_black.mouse_filter = Control.MOUSE_FILTER_STOP
	_splash_black.gui_input.connect(_on_splash_gui_input)
	_splash_layer.add_child(_splash_black)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash_layer.add_child(center)

	_splash_box = VBoxContainer.new()
	_splash_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_splash_box.add_theme_constant_override("separation", 10)
	_splash_box.modulate.a = 0.0
	center.add_child(_splash_box)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/svg/ui/caduceus.svg") as Texture2D
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(SPLASH_LOGO_PX, SPLASH_LOGO_PX)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo_wrap := CenterContainer.new()
	logo_wrap.add_child(logo)
	_splash_box.add_child(logo_wrap)

	_splash_box.add_child(_spacer(14))
	_splash_box.add_child(_make_label("PRESCRIPTION GAMES", 30, Color("e8e0cc"), true, 8))
	_splash_box.add_child(_make_label("presents", 16, Color("8b8fa3"), false, 3))


func _play_splash() -> void:
	Sfx.play("ui")
	var box := _splash_box
	await get_tree().process_frame
	if _splash_done:
		return
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2(1.03, 1.03)

	_splash_tween = create_tween()
	_splash_tween.set_parallel(true)
	_splash_tween.tween_property(box, "modulate:a", 1.0, SPLASH_FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_splash_tween.tween_property(box, "scale", Vector2.ONE,
		SPLASH_FADE_IN + SPLASH_HOLD) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_splash_tween.set_parallel(false)
	_splash_tween.tween_interval(SPLASH_HOLD)
	_splash_tween.tween_property(box, "modulate:a", 0.0, SPLASH_FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_splash_tween.tween_callback(_end_splash.bind(false))


func _end_splash(instant: bool) -> void:
	if _splash_done:
		return
	_splash_done = true
	# Raw-touch taps for every menu widget (mouse emulation is off; see
	# touch_controls.gd) — wired only now: during the splash the menu sits
	# invisible underneath, and a tap there used to hit QUIT / START.
	TouchControls.wire_taps(_menu_root)
	if _splash_tween != null and _splash_tween.is_valid():
		_splash_tween.kill()
	if instant:
		_splash_layer.queue_free()
	else:
		var tw := create_tween()
		tw.tween_property(_splash_black, "modulate:a", 0.0, 0.35)
		tw.parallel().tween_property(_splash_box, "modulate:a", 0.0, 0.2)
		tw.tween_callback(_splash_layer.queue_free)
	_reveal_menu()


# ----------------------------------------------------------------- menu -----

func _build_menu() -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 10
	add_child(_menu_layer)

	_menu_root = Control.new()
	_menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_root.modulate.a = 0.0
	_menu_layer.add_child(_menu_root)

	# Title block on the LEFT half. The menu column lives bottom-right, so
	# the two never fight for space.
	_title_box = VBoxContainer.new()
	_title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_box.add_theme_constant_override("separation", 6)
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(_title_box)
	_title_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_title_box.offset_left = 80.0
	_title_box.offset_right = 580.0
	_title_box.offset_top = -240.0
	_title_box.offset_bottom = 240.0

	_title_box.add_child(_make_label("PenroseBreak", 64, COL_TEXT, true, 4))
	var underline := ColorRect.new()
	underline.color = COL_ACCENT
	underline.custom_minimum_size = Vector2(360, 3)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var under_wrap := CenterContainer.new()
	under_wrap.add_child(underline)
	_title_box.add_child(under_wrap)
	_title_box.add_child(_spacer(4))
	_title_box.add_child(_make_label("Aperiodic tiling countdown.", 17, COL_DIM, false, 3))

	# Menu column: bottom-right corner, controls hugging the right edge.
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 8)
	_menu_root.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	column.offset_left = -356.0
	column.offset_right = -46.0
	column.offset_top = -470.0
	column.offset_bottom = -52.0
	_menu_column = column

	# Player name, captioned so nobody wonders what the box is for (v1.10).
	var name_cap := _make_label("PLAYER NAME", 13, COL_DIM, false, 3)
	name_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_cap.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(name_cap)
	_name_edit = LineEdit.new()
	_name_edit.text = Game.player_name
	_name_edit.placeholder_text = "YOUR NAME"
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.max_length = Game.NAME_MAX
	_name_edit.custom_minimum_size = Vector2(280, 44)
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.add_theme_color_override("font_color", COL_ACCENT)
	_name_edit.add_theme_color_override("font_placeholder_color",
		Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.5))
	var ne_style := StyleBoxFlat.new()
	ne_style.bg_color = Color(0.02, 0.09, 0.1, 0.8)
	ne_style.border_color = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.4)
	ne_style.set_border_width_all(1)
	ne_style.set_corner_radius_all(6)
	var ne_focus := ne_style.duplicate() as StyleBoxFlat
	ne_focus.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.9)
	ne_focus.set_border_width_all(2)
	_name_edit.add_theme_stylebox_override("normal", ne_style)
	_name_edit.add_theme_stylebox_override("focus", ne_focus)
	_name_edit.text_changed.connect(func(t: String) -> void:
		Game.player_name = t)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _start_game())
	_name_edit.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(_name_edit)
	column.add_child(_spacer(8))

	# START / mode cycler / OPTIONS / TOP SCORES / QUIT.
	var start_btn := _make_menu_button("START")
	start_btn.name = "StartButton"
	start_btn.pressed.connect(_start_game)
	# Quick-switch the game mode right from the menu (v1.10) — same
	# cycle as the OPTIONS button, one click closer to the action.
	_menu_mode_btn = _make_menu_button("")
	_menu_mode_btn.pressed.connect(_cycle_mode)
	var options_btn := _make_menu_button("OPTIONS")
	options_btn.pressed.connect(_open_options)
	var scores_btn := _make_menu_button("TOP SCORES")
	scores_btn.pressed.connect(_open_scores)
	var quit_btn := _make_menu_button("QUIT")
	quit_btn.pressed.connect(func() -> void:
		Sfx.play("ui")
		get_tree().quit())
	_main_buttons = [start_btn, _menu_mode_btn, options_btn, scores_btn, quit_btn]
	for b: Button in _main_buttons:
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		column.add_child(b)
	# A browser tab can't close itself: quit() would only freeze the page.
	if OS.has_feature("web"):
		quit_btn.visible = false
	# Wrap-around column focus THROUGH the name field, so a controller can
	# reach it (START's up used to jump straight to QUIT — pad players
	# could only ever be ANON).
	var last: Button = scores_btn if OS.has_feature("web") else quit_btn
	_name_edit.focus_neighbor_top = _name_edit.get_path_to(last)
	last.focus_neighbor_bottom = last.get_path_to(_name_edit)

	# Best line (v1.10): full-width and screen-centered — inside the
	# right-hugging column, long records (mode · regime · time · name)
	# ran past the edge and clipped.
	_best_label = _make_label("", 18, COL_DIM, false, 2)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(_best_label)
	_best_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_best_label.offset_top = -46.0
	_best_label.offset_bottom = -16.0
	_refresh_best()

	# Footer: just the version, bottom-left. (The studio caduceus already has
	# its moment on the splash.)
	var version := _make_label(VERSION, 13, COL_DIM, false, 1)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 22.0
	version.offset_right = 200.0
	version.offset_top = -38.0
	version.offset_bottom = -14.0

	_build_options_panel()
	_build_scores_panel()


## Options: audio/shake/fullscreen toggles bound straight to Game
## properties, the game-mode and competition-time cyclers, the controls
## reference, and a two-click reset of all records. The panel is a
## screen-centered overlay; the menu column hides while it is open.
func _build_options_panel() -> void:
	_options_panel = PanelContainer.new()
	_options_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.07, 0.085, 0.94)
	sb.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 40.0
	sb.content_margin_right = 40.0
	sb.content_margin_top = 24.0
	sb.content_margin_bottom = 24.0
	_options_panel.add_theme_stylebox_override("panel", sb)
	var options_center := CenterContainer.new()
	options_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	options_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(options_center)
	options_center.add_child(_options_panel)

	# The panel outgrew the screen: a fixed-size scroll area holds the
	# content (wheel/keys on desktop; TapCatcher drag-scrolls it on touch).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(660, 560)
	scroll.follow_focus = true
	_options_panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	vb.add_child(_make_label("OPTIONS", 24, COL_ACCENT, true, 5))
	vb.add_child(_spacer(2))

	# Toggle rows: text, Game property name, initial value.
	var toggles: Array = [
		["Sound FX", "sfx_on", Game.sfx_on],
		["Screen shake", "screen_shake", Game.screen_shake],
		["Fullscreen", "fullscreen", Game.fullscreen],
		["Tilt control (mobile)", "tilt_control", Game.tilt_control],
		["Controller rumble", "rumble_on", Game.rumble_on],
	]
	var first_toggle: CheckBox = null
	for t: Array in toggles:
		var cb := CheckBox.new()
		cb.text = t[0]
		cb.button_pressed = t[2]
		cb.add_theme_font_size_override("font_size", 17)
		cb.add_theme_color_override("font_color", COL_TEXT)
		var prop: String = t[1]
		cb.toggled.connect(func(on: bool) -> void:
			Game.set(prop, on)
			Sfx.play("ui"))
		vb.add_child(cb)
		if first_toggle == null:
			first_toggle = cb

	# Game mode + competition round length, cycled with a click each.
	vb.add_child(_spacer(6))
	vb.add_child(_make_label("GAME MODE", 18, COL_ACCENT, true, 4))
	_mode_btn = Button.new()
	_mode_btn.add_theme_font_size_override("font_size", 16)
	_mode_btn.pressed.connect(_cycle_mode)
	vb.add_child(_mode_btn)
	_time_btn = Button.new()
	_time_btn.add_theme_font_size_override("font_size", 15)
	_time_btn.pressed.connect(_cycle_comp_time)
	vb.add_child(_time_btn)
	# Constant = the same field deal every run (fair competitions,
	# reproducible speedruns); off = fresh aperiodic patch per run.
	var field_cb := CheckBox.new()
	field_cb.text = "Constant field (same deal every run — needed for records)"
	field_cb.button_pressed = Game.field_constant
	field_cb.add_theme_font_size_override("font_size", 16)
	field_cb.add_theme_color_override("font_color", COL_TEXT)
	field_cb.toggled.connect(func(on: bool) -> void:
		Game.field_constant = on
		Sfx.play("ui"))
	vb.add_child(field_cb)

	# Penrose tile feel: one-shot vs hardened, and a color per prototile.
	vb.add_child(_spacer(6))
	vb.add_child(_make_label("PENROSE TILES", 18, COL_ACCENT, true, 4))
	_break_btn = Button.new()
	_break_btn.add_theme_font_size_override("font_size", 16)
	_break_btn.pressed.connect(_cycle_breaking)
	vb.add_child(_break_btn)
	vb.add_child(_color_row("Thin rhombi color", "tile_color_thin"))
	vb.add_child(_color_row("Thick rhombi color", "tile_color_thick"))
	# One tap home: the house turquoise, light thin tiles over dark thick.
	var def_btn := Button.new()
	def_btn.text = "Default turquoise (light thin, dark thick)"
	def_btn.add_theme_font_size_override("font_size", 14)
	def_btn.pressed.connect(func() -> void:
		Sfx.play("ui")
		Game.tile_color_thin = Game.DEF_THIN
		Game.tile_color_thick = Game.DEF_THICK
		for cb: Callable in _color_refresh:
			cb.call())
	vb.add_child(def_btn)
	_refresh_option_captions()

	vb.add_child(_spacer(8))
	vb.add_child(_make_label("HOW TO PLAY", 18, COL_ACCENT, true, 4))
	vb.add_child(_make_label(
		"Classic: clear the rectangle wall fast.  Penrose: shatter the",
		14, COL_DIM, false, 0))
	vb.add_child(_make_label(
		"aperiodic tile field.  Competition: break tiles against the clock.",
		14, COL_DIM, false, 0))
	vb.add_child(_spacer(2))

	# Controls reference: keyboard/mouse and gamepad side by side, touch
	# summarized below (its buttons explain themselves on screen).
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 7)
	vb.add_child(grid)
	var rows := [
		["", "KEYS / MOUSE", "CONTROLLER"],
		["Move", "mouse · A / D · ← / →", "left stick · d-pad"],
		["Launch", "Space · left click", "A · RB · RT"],
		["Boost", "Space mid-flight", "A mid-flight"],
		["Pause", "Esc · P", "Start (B resumes)"],
		["Restart", "R", "Back / View"],
	]
	for r: Array in rows:
		var head: bool = r[0] == ""
		for i in 3:
			var col: Color = COL_ACCENT if i == 0 else COL_TEXT
			if head:
				col = COL_DIM
			var cell := _make_label(r[i], 13 if head else 15, col, false,
				2 if head else (1 if i == 0 else 0))
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			grid.add_child(cell)
	var touch_note := _make_label(
		"Touch: drag anywhere to steer · tap to launch · bolt button boosts",
		14, COL_DIM, false, 0)
	vb.add_child(touch_note)

	vb.add_child(_spacer(8))

	# Reset best — two-click confirm so a stray click can't wipe the record.
	_reset_btn = Button.new()
	_reset_btn.text = _reset_caption()
	_reset_btn.add_theme_font_size_override("font_size", 15)
	_reset_btn.pressed.connect(_on_reset_pressed)
	_reset_btn.focus_exited.connect(_disarm_reset)
	vb.add_child(_reset_btn)

	var back := _make_menu_button("BACK")
	back.custom_minimum_size = Vector2(200, 42)
	back.pressed.connect(_close_options)
	var back_wrap := CenterContainer.new()
	back_wrap.add_child(back)
	vb.add_child(back_wrap)

	# Wrap-around focus loop inside the panel.
	if first_toggle != null:
		first_toggle.focus_neighbor_top = first_toggle.get_path_to(back)
		first_toggle.focus_previous = first_toggle.get_path_to(back)
		back.focus_neighbor_bottom = back.get_path_to(first_toggle)
		back.focus_next = back.get_path_to(first_toggle)


func _open_options() -> void:
	Sfx.play("ui")
	_arm_panel(_options_panel, true)
	_options_panel.visible = true
	_menu_column.visible = false  # the panel replaces the menu while open
	_title_box.visible = false
	_best_label.visible = false
	_disarm_reset()
	# Trap keyboard focus inside the panel while the column is hidden.
	for b: Button in _main_buttons:
		b.focus_mode = Control.FOCUS_NONE
	for c: Node in _options_panel.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl != null and ctl.focus_mode == Control.FOCUS_ALL:
			ctl.grab_focus.call_deferred()
			break


func _close_options() -> void:
	Sfx.play("ui")
	_arm_panel(_options_panel, false)
	_options_panel.visible = false
	_menu_column.visible = true
	_title_box.visible = true
	_best_label.visible = true
	_disarm_reset()
	for b: Button in _main_buttons:
		b.focus_mode = Control.FOCUS_ALL
	var start_btn := _menu_root.find_child("StartButton", true, false) as Button
	if start_btn != null:
		start_btn.grab_focus.call_deferred()


## Hiding a control that holds mouse focus makes Godot synthesize a mouse
## RELEASE on it, so a toggle / Reset held down while Esc / B closes the
## panel would fire. Panels disarm their buttons before hiding and re-arm
## when shown. (Found by --chaos; main.gd's pause menu does the same.)
func _arm_panel(panel: Control, on: bool) -> void:
	for b: Node in panel.find_children("*", "BaseButton", true, false):
		(b as BaseButton).disabled = not on


# ---------------------------------------------------- mode / top scores -----

func _cycle_mode() -> void:
	Sfx.play("ui")
	var i: int = Game.MODES.find(Game.game_mode)
	Game.game_mode = Game.MODES[(i + 1) % Game.MODES.size()]
	_refresh_option_captions()


func _cycle_comp_time() -> void:
	Sfx.play("ui")
	var i: int = Game.COMP_TIMES.find(Game.comp_time_s)
	Game.comp_time_s = Game.COMP_TIMES[(i + 1) % Game.COMP_TIMES.size()]
	_refresh_option_captions()


func _mode_caption(mode: String) -> String:
	match mode:
		"classic":
			return "Block Classic"
		"comp":
			return "Penrose Competition"
		_:
			return "Penrose"


func _refresh_option_captions() -> void:
	if _mode_btn == null:
		return
	_mode_btn.text = "Mode:  %s  (click to change)" % _mode_caption(Game.game_mode)
	_time_btn.text = "Competition time:  %s" % Game.format_frame(Game.comp_time_s)
	if _break_btn != null:
		_break_btn.text = "Tile breaking:  %s" \
			% ("One shot" if Game.tile_one_shot else "Hardened (5 hits)")


func _cycle_breaking() -> void:
	Sfx.play("ui")
	Game.tile_one_shot = not Game.tile_one_shot
	_refresh_option_captions()


## A labeled color row bound straight to a Game color property: a full
## picker on desktop; on touch hardware the swatch instead rolls a fresh
## random color on every tap — the picker popup's sliders need a mouse,
## and tapping until it pleases is honest mobile fun anyway.
func _color_row(text: String, prop: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var lbl := _make_label(text, 16, COL_TEXT, false, 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.custom_minimum_size = Vector2(230, 0)
	row.add_child(lbl)
	if TouchControls.wanted():
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(84, 30)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Game.get(prop)
		sb.set_corner_radius_all(5)
		sb.border_color = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.6)
		sb.set_border_width_all(1)
		# one shared stylebox: recoloring it repaints every state at once
		for state: String in ["normal", "hover", "pressed", "focus"]:
			swatch.add_theme_stylebox_override(state, sb)
		swatch.pressed.connect(func() -> void:
			var c := Color.from_hsv(Game.rng.randf(),
				Game.rng.randf_range(0.55, 0.95),
				Game.rng.randf_range(0.75, 1.0))
			Game.set(prop, c)
			sb.bg_color = c
			Sfx.play("ui"))
		_color_refresh.append(func() -> void: sb.bg_color = Game.get(prop))
		row.add_child(swatch)
		row.add_child(_make_label("tap = random", 13, COL_DIM, false, 1))
	else:
		var pick := ColorPickerButton.new()
		pick.color = Game.get(prop)
		pick.edit_alpha = false
		pick.custom_minimum_size = Vector2(84, 30)
		pick.color_changed.connect(func(c: Color) -> void:
			Game.set(prop, c))
		_color_refresh.append(func() -> void: pick.color = Game.get(prop))
		row.add_child(pick)
	return row


## Top Scores: every record slot on one overlay — the two clear modes by
## time, then the competition table, tiles per round length.
func _build_scores_panel() -> void:
	_scores_panel = PanelContainer.new()
	_scores_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.07, 0.085, 0.94)
	sb.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 48.0
	sb.content_margin_right = 48.0
	sb.content_margin_top = 26.0
	sb.content_margin_bottom = 26.0
	_scores_panel.add_theme_stylebox_override("panel", sb)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(center)
	center.add_child(_scores_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	_scores_panel.add_child(vb)

	vb.add_child(_make_label("TOP SCORES", 24, COL_ACCENT, true, 5))
	vb.add_child(_spacer(4))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 7)
	vb.add_child(grid)
	var clear_rows := [
		["BLOCK CLASSIC", "classic"],
		["PENROSE — ONE SHOT", "penrose:shot"],
		["PENROSE — HARDENED", "penrose:hard"],
	]
	for r: Array in clear_rows:
		var tag := _make_label(r[0], 16, COL_ACCENT, false, 2)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(tag)
		var val := _make_label("—", 16, COL_TEXT, false, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(val)
		_score_labels[r[1]] = val

	vb.add_child(_spacer(6))
	vb.add_child(_make_label("COMPETITION — TILES PER ROUND", 16,
		COL_ACCENT, true, 3))
	var cgrid := GridContainer.new()
	cgrid.columns = 3
	cgrid.add_theme_constant_override("h_separation", 30)
	cgrid.add_theme_constant_override("v_separation", 6)
	vb.add_child(cgrid)
	for h: String in ["", "ONE SHOT", "HARDENED"]:
		var head := _make_label(h, 13, COL_DIM, false, 2)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		cgrid.add_child(head)
	for frame: int in Game.COMP_TIMES:
		var tag := _make_label(Game.format_frame(frame), 15, COL_DIM, false, 1)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		cgrid.add_child(tag)
		for regime: String in ["shot", "hard"]:
			var val := _make_label("—", 15, COL_TEXT, false, 0)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			cgrid.add_child(val)
			_score_labels["%d:%s" % [frame, regime]] = val

	vb.add_child(_spacer(10))
	var back := _make_menu_button("BACK")
	back.name = "ScoresBackButton"
	back.custom_minimum_size = Vector2(200, 42)
	back.pressed.connect(_close_scores)
	var back_wrap := CenterContainer.new()
	back_wrap.add_child(back)
	vb.add_child(back_wrap)


func _refresh_scores() -> void:
	if _score_labels.is_empty():
		return
	for r: Array in [["classic", true], ["penrose:shot", true],
			["penrose:hard", false]]:
		var mode: String = (r[0] as String).get_slice(":", 0)
		var lbl: Label = _score_labels[r[0]]
		if Game.clear_best_time(mode, r[1]) > 0.0:
			lbl.text = "%s — %s" % [
				Game.format_time(Game.clear_best_time(mode, r[1])),
				Game.clear_best_name(mode, r[1])]
		else:
			lbl.text = "—"
	for frame: int in Game.COMP_TIMES:
		for regime: String in ["shot", "hard"]:
			var lbl: Label = _score_labels["%d:%s" % [frame, regime]]
			var cb: Array = Game.comp_best(frame, regime == "shot")
			if int(cb[0]) > 0:
				lbl.text = "%d tiles — %s" % [cb[0], cb[1]]
			else:
				lbl.text = "—"


func _open_scores() -> void:
	Sfx.play("ui")
	_refresh_scores()
	_arm_panel(_scores_panel, true)
	_scores_panel.visible = true
	_menu_column.visible = false
	_title_box.visible = false
	_best_label.visible = false
	for b: Button in _main_buttons:
		b.focus_mode = Control.FOCUS_NONE
	var back := _scores_panel.find_child("ScoresBackButton", true, false) as Button
	if back != null:
		back.grab_focus.call_deferred()


func _close_scores() -> void:
	Sfx.play("ui")
	_arm_panel(_scores_panel, false)
	_scores_panel.visible = false
	_menu_column.visible = true
	_title_box.visible = true
	_best_label.visible = true
	for b: Button in _main_buttons:
		b.focus_mode = Control.FOCUS_ALL
	var start_btn := _menu_root.find_child("StartButton", true, false) as Button
	if start_btn != null:
		start_btn.grab_focus.call_deferred()


## First press arms the reset; second press wipes the record.
func _on_reset_pressed() -> void:
	Sfx.play("ui")
	if not _reset_armed:
		_reset_armed = true
		_reset_btn.text = "REALLY? click again to confirm"
		_reset_btn.add_theme_color_override("font_color", Color("d84a4a"))
		return
	Game.reset_best()
	_reset_armed = false
	_reset_btn.remove_theme_color_override("font_color")
	_reset_btn.text = _reset_caption()


func _disarm_reset() -> void:
	if _reset_btn == null or not _reset_armed:
		return
	_reset_armed = false
	_reset_btn.remove_theme_color_override("font_color")
	_reset_btn.text = _reset_caption()


func _reset_caption() -> String:
	var any := Game.clear_best_time("classic") > 0.0
	for shot in [true, false]:
		any = any or Game.clear_best_time("penrose", shot) > 0.0
		for frame: int in Game.COMP_TIMES:
			any = any or int(Game.comp_best(frame, shot)[0]) > 0
	return "Reset all records" if any else "Reset records (none set)"


func _regime_word() -> String:
	return "one shot" if Game.tile_one_shot else "hardened"


## The menu's one-line best: the record for the currently selected mode
## AND breaking regime (they are separate slots — different sports).
func _refresh_best() -> void:
	# The menu mode cycler mirrors Game.game_mode wherever it changed
	# (menu click OR the OPTIONS cycler — both funnel through
	# Game.changed, which lands here).
	if _menu_mode_btn != null:
		_menu_mode_btn.text = "‹ %s ›" % _mode_caption(Game.game_mode).to_upper()
	var shot := Game.tile_one_shot
	if Game.game_mode == "comp":
		var cb: Array = Game.comp_best(Game.comp_time_s, shot)
		if int(cb[0]) > 0:
			_best_label.text = "BEST (%s, %s)  %d TILES — %s" % [
				Game.format_frame(Game.comp_time_s), _regime_word(),
				cb[0], cb[1]]
		else:
			_best_label.text = "no record yet (%s, %s) — set one" % [
				Game.format_frame(Game.comp_time_s), _regime_word()]
	elif Game.game_mode == "penrose":
		if Game.clear_best_time("penrose", shot) > 0.0:
			_best_label.text = "BEST (%s)  %s — %s" % [_regime_word(),
				Game.format_time(Game.clear_best_time("penrose", shot)),
				Game.clear_best_name("penrose", shot)]
		else:
			_best_label.text = "no record yet (%s) — set one" % _regime_word()
	elif Game.clear_best_time("classic") > 0.0:
		_best_label.text = "BEST  %s — %s" % [
			Game.format_time(Game.clear_best_time("classic")),
			Game.clear_best_name("classic")]
	else:
		_best_label.text = "no record yet — set one"
	if Game.game_mode != "classic" and not Game.field_constant:
		_best_label.text += "   ·   random deals are unranked"
	if _reset_btn != null and not _reset_armed:
		_reset_btn.text = _reset_caption()
	if _scores_panel != null and _scores_panel.visible:
		_refresh_scores()
	_refresh_option_captions()


func _reveal_menu() -> void:
	var tw := create_tween()
	tw.tween_property(_menu_root, "modulate:a", 1.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var start_btn := _menu_root.find_child("StartButton", true, false) as Button
	if start_btn != null:
		start_btn.grab_focus.call_deferred()


func _start_game() -> void:
	Sfx.play("ui")
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## §cli `--touchtest`: end-to-end touch check with mouse emulation OFF —
## inject a raw ScreenTouch tap on START; reaching main.tscn is the pass
## signal (printed there). If this scene is still alive 3 s later, the tap
## fell on deaf controls: fail. Runs headless.
func _run_touch_test() -> void:
	# 1. A tap during the splash — right where QUIT will be — must only
	#    skip the splash (v1.14: it used to hit the invisible menu).
	await get_tree().create_timer(0.3).timeout
	var quit_at := _menu_button("QUIT").get_global_rect().get_center()
	await _tap_at(quit_at)
	await get_tree().create_timer(0.6).timeout
	if not _touch_check(_splash_done, "a tap skips the splash (and hits nothing)"):
		return
	# 2. OPTIONS by tap; a drag that starts on a toggle scrolls the panel
	#    and leaves the toggle alone; a clean tap flips it exactly once.
	await _tap_at(_menu_button("OPTIONS").get_global_rect().get_center())
	if not _touch_check(_options_panel.visible, "tap opens OPTIONS"):
		return
	var scroll := _options_panel.find_children("*", "ScrollContainer", true, false)[0] \
		as ScrollContainer
	var sfx := _options_panel.find_children("*", "CheckBox", true, false)[0] as CheckBox
	var sfx_at := sfx.get_global_rect().get_center()
	var before := Game.sfx_on
	var scroll_before := scroll.scroll_vertical
	_tap(sfx_at, true)
	for k in 6:
		await get_tree().process_frame
		_touch_drag(sfx_at + Vector2(0.0, -16.0 * (k + 1)), Vector2(0.0, -16.0))
	await get_tree().process_frame
	_tap(sfx_at + Vector2(0.0, -96.0), false)
	await get_tree().create_timer(0.1).timeout
	if not _touch_check(Game.sfx_on == before and scroll.scroll_vertical > scroll_before,
			"dragging over a toggle scrolls without flipping it"):
		return
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	sfx_at = sfx.get_global_rect().get_center()
	await _tap_at(sfx_at)
	if not _touch_check(Game.sfx_on != before, "a clean tap flips the toggle once"):
		return
	await _tap_at(sfx_at)   # put it back
	# BACK sits below the visible window: a tap where it would be must NOT
	# land (scrolled-out widgets are clipped), then scroll it into view.
	var back := _menu_button("BACK")
	await _tap_at(back.get_global_rect().get_center())
	if not _touch_check(_options_panel.visible,
			"a tap on a scrolled-out button is ignored"):
		return
	scroll.ensure_control_visible(back)
	await get_tree().process_frame
	await _tap_at(back.get_global_rect().get_center())
	if not _touch_check(not _options_panel.visible, "tap on BACK closes OPTIONS"):
		return
	# 3. START by tap → the arena prints the pass.
	var btn := _menu_root.find_child("StartButton", true, false) as Button
	var at := btn.get_global_rect().get_center()
	print("touchtest: tapping START at ", at)
	await _tap_at(at)
	await get_tree().create_timer(3.0).timeout
	printerr("touchtest FAIL: raw touch did not activate START")
	get_tree().quit(1)


func _menu_button(caption: String) -> Button:
	for b: Node in _menu_root.find_children("*", "Button", true, false):
		if (b as Button).text == caption and (b as Button).is_visible_in_tree():
			return b as Button
	return null


func _touch_check(ok: bool, what: String) -> bool:
	if ok:
		print("touchtest: %s — OK" % what)
		return true
	printerr("touchtest FAIL: " + what)
	get_tree().quit(1)
	return false


## A clean tap (down, short pause, up at the same spot) + settle time.
func _tap_at(at: Vector2) -> void:
	_tap(at, true)
	await get_tree().create_timer(0.08).timeout
	_tap(at, false)
	await get_tree().create_timer(0.15).timeout


func _touch_drag(at: Vector2, relative: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	var xf := get_tree().root.get_final_transform()
	ev.position = xf * at
	ev.relative = xf.basis_xform(relative)
	Input.parse_input_event(ev)


## §cli `--padtest`: the menu driven by gamepad events alone — focus starts
## on START, D-pad down walks to OPTIONS, A opens it, B closes it (focus
## back on START), A on START enters the arena, which prints the pass.
## Every step is asserted; nothing persisted is touched. Runs headless.
func _run_pad_test() -> void:
	if not _splash_done:
		_end_splash(true)
	await get_tree().create_timer(1.0).timeout
	var vp := get_viewport()
	var start_btn := _menu_root.find_child("StartButton", true, false) as Button
	if not _pad_check(vp.gui_get_focus_owner() == start_btn,
			"START holds focus when the menu appears"):
		return
	await _pad_press(JOY_BUTTON_DPAD_DOWN)
	if not _pad_check(vp.gui_get_focus_owner() == _menu_mode_btn,
			"d-pad down → mode cycler"):
		return
	await _pad_press(JOY_BUTTON_DPAD_DOWN)
	var focused := vp.gui_get_focus_owner() as Button
	if not _pad_check(focused != null and focused.text == "OPTIONS",
			"d-pad down → OPTIONS"):
		return
	await _pad_press(JOY_BUTTON_A)
	if not _pad_check(_options_panel.visible, "A opens OPTIONS"):
		return
	# v1.13: a mouse button held on a toggle while B closes the panel must
	# not flip it (hiding a control under a held button fires a release).
	var sfx_before := Game.sfx_on
	var toggle: CheckBox = null
	for c: Node in _options_panel.find_children("*", "CheckBox", true, false):
		if (c as CheckBox).text == "Sound FX":
			toggle = c
	var at := get_tree().root.get_final_transform() \
		* toggle.get_global_rect().get_center()
	var hover := InputEventMouseMotion.new()
	hover.position = at
	Input.parse_input_event(hover)
	_mouse_button(at, true)
	await get_tree().create_timer(0.08).timeout
	await _pad_press(JOY_BUTTON_B)
	_mouse_button(at, false)
	await get_tree().create_timer(0.1).timeout
	if not _pad_check(not _options_panel.visible, "B closes OPTIONS"):
		return
	if not _pad_check(Game.sfx_on == sfx_before,
			"a toggle held under the mouse did not flip on close"):
		return
	if not _pad_check(vp.gui_get_focus_owner() == start_btn,
			"focus returns to START"):
		return
	await _pad_press(JOY_BUTTON_A)
	await get_tree().create_timer(3.0).timeout
	printerr("padtest FAIL: A on START did not enter the arena")
	get_tree().quit(1)


## §cli `--uitour`: open OPTIONS and TOP SCORES (every record reader and
## option caption runs), close them, quit 0. Script errors surface on
## stderr; tools/robustness.sh greps for them.
func _run_ui_tour() -> void:
	if not _splash_done:
		_end_splash(true)
	await get_tree().create_timer(0.3).timeout
	_open_options()
	await get_tree().create_timer(0.3).timeout
	_close_options()
	_open_scores()
	await get_tree().create_timer(0.3).timeout
	_close_scores()
	_refresh_best()
	# Touch a setting there and back: proves saving still works after
	# whatever load just happened (the flush lands on quit).
	Game.sfx_on = not Game.sfx_on
	Game.sfx_on = not Game.sfx_on
	print("uitour OK: best line = \"%s\"" % _best_label.text)
	get_tree().quit(0)


func _mouse_button(at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = at
	ev.pressed = down
	Input.parse_input_event(ev)


func _pad_check(ok: bool, what: String) -> bool:
	if ok:
		print("padtest: %s — OK" % what)
		return true
	printerr("padtest FAIL: " + what)
	get_tree().quit(1)
	return false


## Press and release one pad button, a few frames apart, then let the GUI
## settle (deferred focus grabs land a frame later).
func _pad_press(b: JoyButton) -> void:
	for down: bool in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = b
		ev.pressed = down
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.08).timeout
	await get_tree().create_timer(0.1).timeout


func _tap(at: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	# Injected positions are window coordinates: delivery applies the
	# window→content stretch, so pre-map `at` into window space.
	ev.position = get_tree().root.get_final_transform() * at
	ev.pressed = down
	Input.parse_input_event(ev)


# ------------------------------------------------------------- helpers ------

func _make_menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 46)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.add_theme_color_override("font_hover_color", COL_ACCENT)
	btn.add_theme_color_override("font_focus_color", COL_ACCENT)
	btn.add_theme_color_override("font_pressed_color", COL_ACCENT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.09, 0.1, 0.8)
	normal.border_color = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.4)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.03, 0.14, 0.15, 0.92)
	focus.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.9)
	focus.set_border_width_all(2)
	var pressed := focus.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.05, 0.2, 0.2, 0.95)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", focus)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.mouse_entered.connect(func() -> void:
		if btn.focus_mode != Control.FOCUS_NONE:
			btn.grab_focus())
	btn.focus_entered.connect(func() -> void: Sfx.play("ui"))
	return btn


func _make_label(text: String, size_px: int, color: Color, bold: bool,
		letter_spacing: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", size_px)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0.1, 0.1, 0.6))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	if bold or letter_spacing > 0:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		if bold:
			f.variation_embolden = 0.85
		if letter_spacing > 0:
			f.set_spacing(TextServer.SPACING_GLYPH, letter_spacing)
		lbl.add_theme_font_override("font", f)
	return lbl


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Sparse "Penrose snow" behind the menu: lone rhombi — the two P3
## prototiles, thin (36°) and thick (72°) — in the block damage-ladder
## colors, drifting down here and there with a lazy sway and spin. A quiet
## nod to the wall waiting in the arena; deliberately NOT dense. Flakes
## share the backdrop's exact tile edge (set by the builder), with the
## count easing off when the deal is chunky.
class TileSnow extends Node2D:
	## Rhombus edge length, matched to PenroseBg.tile_side().
	var side := 40.0

	## Per flake: [x, y, fall px/s, sway phase, sway rad/s, side px,
	## thick?, angle, spin rad/s, color]
	var _flakes: Array = []

	func _ready() -> void:
		var count := clampi(int(560.0 / side), 7, 13)
		for i in count:
			_flakes.append(_new_flake(true))

	func _process(delta: float) -> void:
		var respawn_y := get_viewport_rect().size.y + 40.0
		for i in _flakes.size():
			var f: Array = _flakes[i]
			f[1] += f[2] * delta
			f[3] += f[4] * delta
			f[7] += f[8] * delta
			if f[1] > respawn_y:
				_flakes[i] = _new_flake(false)
		queue_redraw()

	## A fresh flake — scattered over the whole screen at build time
	## (anywhere), respawned just above the top edge afterwards.
	func _new_flake(anywhere: bool) -> Array:
		var rng := Game.rng
		var view := get_viewport_rect().size
		var col: Color = Block.STAGE_COLORS[
			rng.randi_range(0, Block.STAGE_COLORS.size() - 1)]
		col.a = rng.randf_range(0.3, 0.55)
		# Spawn fully above the top edge (big flakes need more headroom).
		var y := rng.randf_range(-side - 90.0, -side - 20.0)
		if anywhere:
			y = rng.randf_range(-60.0, view.y)
		return [
			rng.randf_range(0.0, view.x),
			y,
			rng.randf_range(18.0, 42.0),
			rng.randf_range(0.0, TAU),
			rng.randf_range(0.4, 1.1),
			side,
			rng.randf() < 0.5,
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.35, 0.35),
			col,
		]

	func _draw() -> void:
		for f: Array in _flakes:
			# Rhombus from its half-diagonals: side s, acute angle θ →
			# s·cos(θ/2) and s·sin(θ/2). Thick tile θ = 72°, thin θ = 36°.
			var half := deg_to_rad(36.0) if f[6] else deg_to_rad(18.0)
			var side: float = f[5]
			var ang: float = f[7]
			var p := Vector2(f[0] + sin(f[3]) * 14.0, f[1])
			var u := Vector2.from_angle(ang) * (side * cos(half))
			var v := Vector2.from_angle(ang + PI * 0.5) * (side * sin(half))
			var quad := PackedVector2Array([p + u, p + v, p - u, p - v])
			draw_colored_polygon(quad, f[9])
			var rim: Color = f[9]
			rim = rim.lightened(0.4)
			rim.a = (f[9] as Color).a * 0.7
			quad.append(quad[0])
			draw_polyline(quad, rim, 1.0, true)


