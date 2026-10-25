extends RefCounted

# Each hand-authored section fits the 960 x 540 viewport. Three sections form
# one continuous stage; the middle section is mirrored for route variety.
const SECTION_WIDTH := 960.0
const SECTION_COUNT := 3
const LEVEL_WIDTH := SECTION_WIDTH * SECTION_COUNT
const LEVEL_HEIGHT := 540.0

const BASE_DATA: Array[Dictionary] = [
	{
		"name": "Ruinas del huerto", "theme": "ruins", "background": "Brown",
		"fruit": "Apple", "spawn": Vector2(74, 350), "goal": Vector2(895, 192),
		"palette": [Color("a74f46"), Color("b75a4e"), Color("477e32"), Color("77be45"), Color("913e3d"), Color("c86a57")],
		"platforms": [Rect2(20, 460, 240, 55), Rect2(300, 460, 210, 55), Rect2(550, 460, 390, 55), Rect2(20, 390, 130, 70), Rect2(780, 220, 160, 240), Rect2(172, 370, 125, 30), Rect2(375, 335, 150, 30), Rect2(577, 366, 120, 30), Rect2(740, 310, 120, 30), Rect2(381, 234, 115, 28), Rect2(570, 180, 100, 28), Rect2(233, 175, 105, 28)],
		"trampolines": [Vector2(284, 355), Vector2(433, 319), Vector2(662, 351)],
		"saws": [Vector2(335, 436), Vector2(543, 421), Vector2(747, 436), Vector2(866, 280), Vector2(457, 207)],
		"fruits": [Vector2(250, 120), Vector2(155, 205), Vector2(210, 212), Vector2(276, 145), Vector2(332, 130), Vector2(405, 285), Vector2(460, 270), Vector2(617, 130), Vector2(675, 150), Vector2(721, 248), Vector2(760, 260), Vector2(824, 178), Vector2(883, 165)],
		"coins": [Vector2(103, 340), Vector2(345, 295), Vector2(540, 275), Vector2(705, 300), Vector2(870, 168)],
	},
	{
		"name": "Bosque esmeralda", "theme": "forest", "background": "Green",
		"fruit": "Cherries", "spawn": Vector2(70, 416), "goal": Vector2(874, 162),
		"palette": [Color("624934"), Color("79533c"), Color("24704c"), Color("82db70"), Color("463c31"), Color("926849")],
		"platforms": [Rect2(20, 450, 180, 65), Rect2(245, 470, 180, 45), Rect2(470, 455, 180, 60), Rect2(710, 450, 230, 65), Rect2(160, 360, 135, 28), Rect2(335, 290, 125, 28), Rect2(510, 350, 130, 28), Rect2(650, 270, 120, 28), Rect2(810, 190, 130, 28), Rect2(470, 180, 120, 28), Rect2(210, 180, 120, 28)],
		"trampolines": [Vector2(270, 344), Vector2(565, 334)],
		"saws": [Vector2(370, 447), Vector2(590, 432), Vector2(738, 426), Vector2(713, 245)],
		"fruits": [Vector2(115, 411), Vector2(190, 325), Vector2(250, 304), Vector2(365, 250), Vector2(427, 247), Vector2(242, 143), Vector2(308, 141), Vector2(506, 140), Vector2(564, 137), Vector2(536, 301), Vector2(621, 291), Vector2(673, 219), Vector2(794, 151), Vector2(853, 136)],
		"coins": [Vector2(115, 405), Vector2(277, 425), Vector2(386, 250), Vector2(598, 303), Vector2(858, 151)],
	},
	{
		"name": "Dunas del sol", "theme": "desert", "background": "Yellow",
		"fruit": "Orange", "spawn": Vector2(68, 422), "goal": Vector2(879, 147),
		"palette": [Color("a75a38"), Color("c97c42"), Color("dca34d"), Color("ffe08a"), Color("995136"), Color("edac62")],
		"platforms": [Rect2(20, 455, 170, 60), Rect2(245, 455, 130, 60), Rect2(430, 455, 135, 60), Rect2(635, 455, 120, 60), Rect2(820, 455, 120, 60), Rect2(170, 365, 120, 28), Rect2(345, 295, 110, 28), Rect2(495, 225, 110, 28), Rect2(660, 285, 125, 28), Rect2(815, 175, 125, 28), Rect2(145, 195, 120, 28), Rect2(475, 365, 90, 28)],
		"trampolines": [Vector2(220, 349), Vector2(707, 269)],
		"saws": [Vector2(304, 430), Vector2(514, 429), Vector2(683, 429), Vector2(393, 270), Vector2(595, 320)],
		"fruits": [Vector2(120, 416), Vector2(189, 326), Vector2(262, 320), Vector2(176, 155), Vector2(237, 152), Vector2(354, 248), Vector2(442, 245), Vector2(518, 182), Vector2(580, 182), Vector2(496, 325), Vector2(679, 239), Vector2(751, 238), Vector2(836, 131), Vector2(900, 117)],
		"coins": [Vector2(119, 414), Vector2(278, 411), Vector2(389, 250), Vector2(710, 239), Vector2(868, 132)],
	},
	{
		"name": "Cumbres de cristal", "theme": "snow", "background": "Blue",
		"fruit": "Strawberry", "spawn": Vector2(885, 422), "goal": Vector2(80, 147),
		"palette": [Color("476d9b"), Color("608aba"), Color("a8dcec"), Color("effbff"), Color("385b8b"), Color("82b9d5")],
		"platforms": [Rect2(770, 455, 170, 60), Rect2(555, 465, 155, 50), Rect2(340, 455, 150, 60), Rect2(20, 455, 250, 60), Rect2(685, 360, 115, 28), Rect2(515, 280, 115, 28), Rect2(345, 345, 115, 28), Rect2(200, 260, 100, 28), Rect2(20, 175, 130, 28), Rect2(715, 185, 130, 28), Rect2(395, 170, 115, 28)],
		"trampolines": [Vector2(752, 344), Vector2(399, 329)],
		"saws": [Vector2(605, 440), Vector2(402, 430), Vector2(223, 430), Vector2(566, 255), Vector2(270, 233)],
		"fruits": [Vector2(840, 416), Vector2(775, 317), Vector2(705, 311), Vector2(815, 145), Vector2(748, 142), Vector2(606, 237), Vector2(524, 235), Vector2(475, 130), Vector2(416, 127), Vector2(437, 302), Vector2(365, 302), Vector2(231, 211), Vector2(131, 131), Vector2(62, 126)],
		"coins": [Vector2(846, 413), Vector2(678, 419), Vector2(569, 239), Vector2(408, 302), Vector2(103, 132)],
	},
]

static var DATA: Array[Dictionary] = _make_full_levels()

static func _make_full_levels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source in BASE_DATA:
		var level: Dictionary = source.duplicate(true)
		for key in ["platforms", "trampolines", "saws", "fruits", "coins"]:
			level[key] = []
		for section in SECTION_COUNT:
			var mirrored := section == 1
			var offset := float(section) * SECTION_WIDTH
			for rect_variant in source.platforms:
				var rect: Rect2 = rect_variant
				var section_x := SECTION_WIDTH - rect.end.x if mirrored else rect.position.x
				level.platforms.append(Rect2(section_x + offset, rect.position.y, rect.size.x, rect.size.y))
			for key in ["trampolines", "saws", "fruits", "coins"]:
				for position_variant in source[key]:
					var position: Vector2 = position_variant
					var section_x := SECTION_WIDTH - position.x if mirrored else position.x
					level[key].append(Vector2(section_x + offset, position.y))
		# The fourth level intentionally travels right to left.
		if source.spawn.x > source.goal.x:
			level.spawn = source.spawn + Vector2(SECTION_WIDTH * (SECTION_COUNT - 1), 0)
		else:
			level.goal = source.goal + Vector2(SECTION_WIDTH * (SECTION_COUNT - 1), 0)
		result.append(level)
	return result
