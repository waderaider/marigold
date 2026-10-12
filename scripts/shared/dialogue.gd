## dialogue.gd - MarigoldDialogue: narrative content (MARIGOLD v0.7.0).
## Narrative Designer's 45 dialogue lines (NARRATIVE_V0110.md §1.4).
## Each line: key, speaker, expression, text, trigger.
## Played via MarigoldVoice.play_line() which handles caption + audio.
## Voice clips: assets/audio/voice/<chapter>/<speaker>_<key>.wav
## (generated via TTS; missing files = caption-only fallback).
## Headless-safe: pure data + static helpers.
class_name MarigoldDialogue
extends RefCounted

## All 45 lines. Format: [key, chapter, speaker, expression, text]
const LINES := [
	# CH1 — Abuela Rosa
	["rosa_welcome_01", "ch1", "Rosa", "JOY", "Ay, mijo… you made it. Come, come — the candles are already lit for you."],
	["rosa_welcome_02", "ch1", "Rosa", "WONDER", "Look at this night. The marigolds remembered the way, even if you forgot."],
	["rosa_teach_01", "ch1", "Rosa", "CURIOUS", "Gently, gently — that's somebody's road home you're holding."],
	["rosa_teach_02", "ch1", "Rosa", "JOY", "Qué bonito. See? Your hands remember what your head forgot."],
	["rosa_candle_01", "ch1", "Rosa", "WONDER", "One flame for every name we say out loud. Say one with me… go on."],
	["rosa_viva_01", "ch1", "Rosa", "JOY", "Mira! The altar heard you. Everybody up — the family is here!"],
	["rosa_viva_02", "ch1", "Rosa", "JOY", "Dance, mijo! On this night, nobody watches from the chairs."],
	["rosa_photo_01", "ch1", "Rosa", "JOY", "There she is. …Keep her close. Memory is the only luggage that gets lighter."],
	["rosa_farewell_01", "ch1", "Rosa", "HAPPY", "You built that with love. The bridge is waiting — Tomás will walk you over."],
	# CH2 — Abuelo Tomás
	["tomas_walk_01", "ch2", "Tomás", "WONDER", "Walk slow. Every petal under your feet was laid by somebody's grandmother."],
	["tomas_walk_02", "ch2", "Tomás", "CURIOUS", "They say the gods made this flower from a love they couldn't bear to end."],
	["tomas_walk_03", "ch2", "Tomás", "WONDER", "Orange like dusk, sweet like memory. That is how the dead find us."],
	["tomas_walk_04", "ch2", "Tomás", "JOY", "On this night the path goes both ways, mijo. We walk to them; they walk to us."],
	["tomas_walk_05", "ch2", "Tomás", "HAPPY", "You crossed. Take this bread — nobody walks the long road hungry. Not even us."],
	# CH3 — Tía Luz
	["luz_plaza_01", "ch3", "Luz", "JOY", "¡Llegó! Everybody, the guest of honor is here! …That means you, mijo."],
	["luz_guide_01", "ch3", "Luz", "CURIOUS", "They've been watching you since the arch. Pick one — they don't bite. Much."],
	["luz_feed_01", "ch3", "Luz", "JOY", "¡Ándale! Did you see those eyes? You just made a friend for life. Literally."],
	["luz_feed_02", "ch3", "Luz", "WONDER", "Three down. The plaza hasn't glowed like this in years, mijo."],
	["luz_bless_01", "ch3", "Luz", "HAPPY", "Four guardians, one family. Walk safe tonight — the spirits know your name now."],
	["luz_guitar_01", "ch3", "Luz", "MISCHIEVOUS", "Careful — that guitar has ended more shyness than tequila. Strum something!"],
	# CH3 — Alebrije guides
	["xochi_hi", "ch3", "Xochi", "JOY", "Finally! I was getting bored being beautiful. Feed me, let's fly!"],
	["xochi_fed", "ch3", "Xochi", "JOY", "¡Sí! Okay, okay — best human. Don't tell the others I said that."],
	["tlanetl_hi", "ch3", "Tlanetl", "SHY", "Oh… hello. You can come closer. I don't mind. Really."],
	["tlanetl_fed", "ch3", "Tlanetl", "HAPPY", "Mmm… warm. Thank you. I'll remember your hands."],
	["mictli_hi", "ch3", "Mictli", "CURIOUS", "Another traveler. The plaza collects us, you know. Stay a while."],
	["mictli_fed", "ch3", "Mictli", "WONDER", "You feed the old serpent. The old serpent does not forget."],
	["papalotl_hi", "ch3", "Papalotl", "SURPRISED", "Eyes up here! …All of them. I see everything. It's a lot."],
	["papalotl_fed", "ch3", "Papalotl", "JOY", "Ha! Good aim. The many eyes approve. Mostly."],
	# CH3 — Banda musicians
	["banda_beto_01", "ch3", "Beto", "JOY", "¡Compadre! You walk like the drum line. Come closer, feel it."],
	["banda_chayo_01", "ch3", "Chayo", "JOY", "This one's for the arrivals! …That's you, by the way."],
	["banda_nena_01", "ch3", "Nena", "HAPPY", "Shh — listen. The strings are saying your name. Probably."],
	# CH4 — Don Rafa
	["rafa_gate_01", "ch4", "Rafa", "HAPPY", "Forty years I've cut this paper, and it still surprises me. Come see."],
	["rafa_gate_02", "ch4", "Rafa", "WONDER", "¡Eso! You woke it. Paper remembers every hand, mijo — now it remembers yours."],
	["rafa_gate_03", "ch4", "Rafa", "JOY", "One gate. My grandmother cut that pattern. She'd like you."],
	["rafa_gate_04", "ch4", "Rafa", "HAPPY", "Walk through, walk through! The arch is old — be gentle, it's held by love."],
	# CH5 — Maestro Nico
	["nico_hello_01", "ch5", "Nico", "JOY", "You! Yes, you! Tonight you don't watch the dance — you ARE the dance."],
	["nico_move_01", "ch5", "Nico", "JOY", "Follow me. Left hand up — like you're catching starlight."],
	["nico_mid_01", "ch5", "Nico", "WONDER", "Now here — hands to your heart. Feel that? That's everybody, all at once."],
	["nico_bow_01", "ch5", "Nico", "HAPPY", "And bow! The dead applaud the loudest, mijo — listen."],
	["nico_fin_01", "ch5", "Nico", "JOY", "¡Bravo! The plaza will talk about this night for a hundred years."],
	# Espejo — Tomás
	["tomas_mirror_01", "espejo", "Tomás", "WONDER", "Look at you. On this night, we paint our faces so the dead recognize us — and so we recognize ourselves."],
	["tomas_paint_01", "espejo", "Tomás", "JOY", "¡Qué calavera! Wear it proud, mijo. That's the face of somebody loved."],
	# Pinta — Luz + Moti
	["luz_pinta_01", "pinta", "Luz", "CURIOUS", "Easy… easy… you're giving somebody their colors. That's a sacred job, you know."],
	["moti_wake_01", "pinta", "Moti", "JOY", "Whoa — I can SEE! …Are you my person? I think you're my person!"],
	["luz_pinta_02", "pinta", "Luz", "HAPPY", "Moti, mijo. He'll wait in your menagerie. Painted things remember their painters."],
	# Guitarra — Luz
	["luz_guitar_done", "guitarra", "Luz", "JOY", "¡Olé! That pick's yours now — every ofrenda needs music. Yours just got some."],
	# Finale — Rosa
	["rosa_finale_enter", "ofrenda", "Rosa", "WONDER", "This is yours. Every candle here is a name somebody loved — including yours."],
	["rosa_reveal_01", "ofrenda", "Rosa", "JOY", "Mira… mira! The light knows you. Welcome home, Familia Flores."],
	["rosa_reveal_02", "ofrenda", "Rosa", "HAPPY", "An ofrenda isn't for the dead, mijo. It's for the living who refuse to forget."],
	["rosa_farewell_final", "ofrenda", "Rosa", "JOY", "Blow out nothing. Let them burn. We'll be here — every year, same night, same love. Vete con Dios, mijo."],
	["rosa_missing_foto", "ofrenda", "Rosa", "CURIOUS", "A photo is missing — somebody's face. The first altar, where it all began… she waits there."],
	["rosa_missing_pan", "ofrenda", "Rosa", "CURIOUS", "No bread for the road. The bridge keeper still has a loaf with your name on it."],
	["rosa_missing_marigold", "ofrenda", "Rosa", "CURIOUS", "The bloom isn't here. Four guardians in the plaza are holding one for you."],
	["rosa_missing_pick", "ofrenda", "Rosa", "CURIOUS", "No music yet. The guitar corner in the plaza — finish a song, take the pick."],
]


## Get a line by key. Returns [chapter, speaker, expression, text] or [].
static func get_line(key: String) -> Array:
	for line in LINES:
		if line[0] == key:
			return [line[1], line[2], line[3], line[4]]
	return []


## Play a line by key (voice + caption). One-shot guard via the caller.
static func say(key: String) -> void:
	var line := get_line(key)
	if line.is_empty():
		return
	var voice: Node = Engine.get_main_loop().get_root().get_node_or_null("MarigoldVoice")
	if voice == null:
		return
	voice.play_line(line[0], line[1], key, line[3])
