extends SceneTree
## Writes the Godot Engine's licence and the notices of every third-party
## component bundled with it — from the running engine itself, so the
## text always matches the engine that exported the game. Also renders
## icon.svg to the 256 px PNG the Linux packages use for their menu entry.
## Used by dist/package_release.sh:
##   godot --headless --path . --script res://dist/godot_notices.gd -- NOTICES.txt ICON.png


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "THIRD_PARTY_NOTICES.txt"
	var out := PackedStringArray()
	out.append("PENROSE BREAK is built with the Godot Engine (https://godotengine.org).")
	out.append("Godot Engine %s — its licence:" % Engine.get_version_info().string)
	out.append("")
	out.append(Engine.get_license_text())
	out.append("")
	out.append("Third-party components bundled with the Godot Engine:")
	out.append("")
	for comp: Dictionary in Engine.get_copyright_info():
		out.append("== %s" % comp["name"])
		for part: Dictionary in comp["parts"]:
			for c: String in part["copyright"]:
				out.append("   Copyright %s" % c)
			out.append("   License: %s" % part["license"])
		out.append("")
	out.append("Licence texts:")
	out.append("")
	var licenses: Dictionary = Engine.get_license_info()
	for lic_name: String in licenses:
		out.append("== %s" % lic_name)
		out.append(str(licenses[lic_name]))
		out.append("")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		quit(1)
		return
	f.store_string("\n".join(out))
	f.close()
	if args.size() > 1:
		var img := Image.new()
		# icon.svg is 128 px square: scale 2 → 256 px.
		if img.load_svg_from_buffer(FileAccess.get_file_as_bytes("res://icon.svg"), 2.0) != OK \
				or img.save_png(args[1]) != OK:
			push_error("cannot render the icon to %s" % args[1])
			quit(1)
			return
	quit(0)
