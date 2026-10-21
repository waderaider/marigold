## probe_090.gd - v0.9.0 asset probe: AABBs + load checks (headless).
extends SceneTree


func _report(label: String, n: Node3D) -> void:
	if n == null:
		print("PROBE MISSING: ", label)
		return
	var b := MarigoldModels.bounds_of(n)
	print("PROBE ", label, " size=", b.size, " min=", b.position)
	for ap_node in n.find_children("", "AnimationPlayer", true, false):
		var ap := ap_node as AnimationPlayer
		print("PROBE   anims: ", ap.get_animation_list())


func _init() -> void:
	for m in ["candle_tall", "candle_mid", "candle_short", "candle_hero_ivory",
			"pan_de_muerto_hero", "sugar_skull_hero", "sugar_skull_mini",
			"garland_marigold_hero", "frame_tallado_hero", "bowl_mole_hero",
			"shrine_nicho_hero", "tamal_a", "salt_dish", "sahumador", "water_glass"]:
		_report("ofrenda/" + m, MarigoldModels.blender_model(MarigoldModels.OFRENDA, m))
	for m in ["skeleton_mariachi_guitar", "skeleton_mariachi_violin",
			"skeleton_mariachi_trumpet", "skeleton_mariachi_maracas",
			"chandelier_hero", "lantern_hojalata_hero", "marigold_cluster_hero",
			"alebrije_venado_hero", "alebrije_jaguar_alado_hero",
			"alebrije_serpiente_hero", "guitar_folk", "flower_petal_quaternius",
			"wax_drip_bead", "torus"]:
		_report("artist/" + m, MarigoldModels.artist_model(m))
	var pp := {
		"architecture": ["bell_quaternius", "bell_tower_quaternius", "stone_tower_quaternius", "temple_quaternius"],
		"banners": ["banner_quaternius", "banner2_quaternius"],
		"dishes": ["bowl_zsky"],
		"flowers": ["desert_marigold", "flower_group_quaternius", "flower_petal_quaternius", "flowers_quaternius"],
		"hats": ["sombrero_hatmyguy", "sombrero_polygoogle"],
		"instruments": ["drum_jeremy", "guitar_quaternius", "guitar_zsky", "maracas_polygoogle", "tamborine_polygoogle", "trumpet_polygoogle", "violin_jeremy"],
		"lights": ["candle_stick_polygoogle", "chandelier_creativetrio", "holiday_lights_polygoogle", "kerosene_lamp_bruno", "lampara_redessociales", "lantern_joedorman", "tree_light_quaternius"],
		"ofrenda": ["shrine_kaylousberg"],
		"pots": ["jar_creativetrio", "large_pot_isalousberg", "medium_pot_isalousberg", "pot_c_large_isalousberg", "pot_quaternius"],
		"skeletons": ["skeleton_quaternius"],
		"textiles": ["oriental_rug_jeremy", "wool_carpet_zsky"],
	}
	for cat in pp.keys():
		for m in pp[cat]:
			_report("polypizza/" + cat + "/" + m, MarigoldModels.polypizza_model(cat, m))
	for m in ["alebrije_dragon_chibi", "alebrije_dragon_rainbow_hero", "alebrije_fox_spirit",
			"alebrije_jaguar_winged", "alebrije_kaiju_teal", "alebrije_macaw_scarlet",
			"alebrije_parrot", "alebrije_salamander", "alebrije_toucan",
			"butterfly_a", "butterfly_b"]:
		_report("hunt2/" + m, MarigoldModels.hunt2_model(m))
	quit()
