extends RefCounted

const CELL := 0.85
const WALL_HEIGHT := 1.12
const HALF_WALL_HEIGHT := WALL_HEIGHT / 2.0
const WALL_DEPTH := 0.10
const BRICK_WALL_SIZE := Vector3(CELL, WALL_HEIGHT, 0.14)
const SLAB_THICKNESS := 0.054
const ROOF_THICKNESS := 0.06

# Local sides are +Z, +X, -Z, -X. Heights run along +X or +Z.
# Side -1 uses the piece's own grid edge. Wall heights use its model bounds.
const PLACEMENT_PROFILES := {
	"floor": {"anchor": "cell", "shape": "slab", "interfaces": [
		["slab", 0, Vector2.ZERO], ["slab", 1, Vector2.ZERO],
		["slab", 2, Vector2.ZERO], ["slab", 3, Vector2.ZERO],
	]},
	"edge": {"anchor": "edge", "shape": "mesh", "conflicts": ["gable"], "interfaces": [
		["wall_base", -1], ["wall_top", -1],
	]},
	"gable": {"anchor": "edge", "shape": "gable", "conflicts": ["edge"], "interfaces": [
		["gable_base", -1, Vector2.ZERO], ["gable_pitch", -1, Vector2(0, HALF_WALL_HEIGHT)],
	]},
	"roof": {"anchor": "cell", "shape": "slope", "interfaces": [
		["eave", 0, Vector2.ZERO], ["crest", 2, Vector2.ONE * HALF_WALL_HEIGHT],
		["roof_pitch", 1, Vector2(HALF_WALL_HEIGHT, 0)], ["roof_pitch", 3, Vector2(HALF_WALL_HEIGHT, 0)],
		["bearing", 1, Vector2.ZERO], ["bearing", 3, Vector2.ZERO],
	]},
	"ridge": {"anchor": "edge", "shape": "mesh", "interfaces": [
		["ridge", -1, Vector2.ONE * HALF_WALL_HEIGHT],
	]},
	"object": {"anchor": "cell", "shape": "mesh"},
}
const INTERFACE_PAIRS := {
	"slab": ["wall_base", "wall_top", "gable_base", "eave"],
	"wall_top": ["gable_base", "eave", "crest", "bearing"],
	"roof_pitch": ["gable_pitch", "roof_pitch"],
	"crest": ["ridge", "crest"],
}

const STRUCTURES := "res://local-assets/models/synty-structures/"
const PIRATE := STRUCTURES + "polygon-pirate/Assets/PolygonPirates/Prefabs/"
const DUNGEON := STRUCTURES + "polygon_dungeon_01/Assets/PolygonDungeon/Prefabs/Environments/"
const GANG := STRUCTURES + "polygon-gang-warfare-01/Assets/Synty/PolygonGangWarfare/Prefabs/Buildings/"

const ITEMS := {
	"floor": {"label": "木地板", "category": "structure", "subcategory": "floors", "layer": "floor", "width": 1, "depth": 1, "scale": 1.0},
	"harborDock": {"label": "码头平台", "category": "structure", "subcategory": "docks", "layer": "floor", "width": 2, "depth": 2, "scale": 0.30, "deck_y": 7.24, "asset": "res://local-assets/models/pirate-harbor/dock.tscn"},
	"harborBridge": {"label": "栈桥", "category": "structure", "subcategory": "docks", "layer": "floor", "width": 1, "depth": 2, "scale": 0.30, "deck_y": 7.24, "asset": "res://local-assets/models/pirate-harbor/boardwalk.tscn"},
	"harborRope": {"label": "绳栏", "category": "structure", "subcategory": "fences", "layer": "edge", "width": 1, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/pirate-harbor/rope-fence.tscn"},
	"harborBarrel": {"label": "木桶", "category": "furniture", "subcategory": "storage", "layer": "object", "width": 1, "depth": 1, "scale": 0.40, "fine": true, "asset": "res://local-assets/models/pirate-harbor/barrel.tscn"},
	"wall": {"label": "墙壁", "category": "structure", "subcategory": "walls", "layer": "edge", "width": 1, "depth": 1, "scale": 1.0, "shape": "box"},
	"doorway": {"label": "门洞", "category": "structure", "subcategory": "openings", "layer": "edge", "width": 1, "depth": 1, "scale": 1.0},
	"woodDoor": {"label": "木门", "category": "structure", "subcategory": "openings", "layer": "edge", "width": 1, "depth": 1, "scale": 1.0},
	"windowWall": {"label": "窗墙", "category": "structure", "subcategory": "openings", "layer": "edge", "width": 1, "depth": 1, "scale": 1.0},
	"woodRoofSlope": {"label": "木直坡片", "category": "structure", "subcategory": "roofs", "layer": "roof", "width": 1, "depth": 1},
	"woodRoofRidge": {"label": "木屋脊条", "category": "structure", "subcategory": "roofs", "layer": "ridge", "width": 1, "depth": 1},
	"woodRoofGable": {"label": "木半山墙", "category": "structure", "subcategory": "roofs", "layer": "gable", "width": 1, "depth": 1},
	"flowers": {"label": "花坛", "category": "garden", "subcategory": "flowers", "layer": "object", "width": 1, "depth": 1, "scale": 0.78, "asset": "res://assets/models/flower-bed-708e73.glb", "fine": true},
	"crate": {"label": "木箱", "category": "furniture", "subcategory": "storage", "layer": "object", "width": 1, "depth": 1, "scale": 0.94, "asset": "res://assets/models/wooden-crate-e46521.glb", "fine": true},
	"lantern": {"label": "提灯", "category": "landscape", "subcategory": "lights", "layer": "object", "width": 1, "depth": 1, "scale": 1.35, "asset": "res://assets/models/farm-lantern-747dc8.glb", "fine": true},
	"bridge": {"label": "木桥", "category": "landscape", "subcategory": "bridges", "layer": "object", "width": 3, "depth": 2, "scale": 0.54, "asset": "res://assets/models/creek-footbridge-d35cf7.glb"},
	"bench": {"label": "长椅", "category": "furniture", "subcategory": "seats", "layer": "object", "width": 3, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/bench.glb"},
	"planter": {"label": "种植箱", "category": "garden", "subcategory": "planters", "layer": "object", "width": 3, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/planter.glb"},
	"cafeCounter": {"label": "咖啡台", "category": "furniture", "subcategory": "tables", "layer": "object", "width": 2, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/cafe-counter.glb"},
	"gazebo": {"label": "凉亭", "category": "structure", "subcategory": "frames", "layer": "object", "width": 2, "depth": 2, "scale": 0.0063, "asset": "res://local-assets/models/gazebo.glb"},
	"picketFence": {"label": "木围栏", "category": "structure", "subcategory": "fences", "layer": "edge", "width": 1, "depth": 1, "scale": 0.0033, "asset": "res://local-assets/models/picket-fence.glb"},
	"halfWall": {"label": "半高墙", "category": "structure", "subcategory": "walls", "layer": "edge", "width": 1, "depth": 1, "scale": 1.0, "shape": "box", "asset": "res://local-assets/models/half-wall.glb"},
	"glassWall": {"label": "玻璃墙", "category": "structure", "subcategory": "walls", "layer": "edge", "width": 1, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/glass-wall.glb"},
	"glassDoor": {"label": "玻璃门", "category": "structure", "subcategory": "openings", "layer": "edge", "width": 1, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/glass-door.glb"},
	"shopWindow": {"label": "展示窗", "category": "structure", "subcategory": "openings", "layer": "edge", "width": 1, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/shop-window.glb"},
	"rollerShutter": {"label": "卷帘门", "category": "structure", "subcategory": "openings", "layer": "edge", "width": 1, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/roller-shutter.glb"},
	"shopfront": {"label": "店面", "category": "structure", "subcategory": "openings", "layer": "edge", "width": 2, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/shopfront.glb"},
	"steelColumn": {"label": "金属立柱", "category": "structure", "subcategory": "frames", "layer": "object", "width": 1, "depth": 1, "scale": 1.0, "floor_support": true, "asset": "res://local-assets/models/steel-column.glb"},
	"stairs": {"label": "楼梯", "category": "structure", "subcategory": "stairs", "layer": "object", "width": 1, "depth": 1, "scale": 1.0},
	"flatRoof": {"label": "石纹地板", "category": "structure", "subcategory": "floors", "layer": "floor", "width": 1, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/flat-roof.glb"},
	"skylight": {"label": "玻璃地板", "category": "structure", "subcategory": "floors", "layer": "floor", "width": 1, "depth": 1, "scale": 1.0, "asset": "res://local-assets/models/skylight.glb"},
	"brickWall": {
		"label": "砖墙", "category": "structure", "subcategory": "walls", "layer": "edge",
		"width": 1, "depth": 1, "fit_size": BRICK_WALL_SIZE, "shape": "box",
		"asset": GANG + "SM_Bld_Wall_Brick_01_Solid.tscn",
	},
	"stoneLowWall": {
		"label": "石矮墙", "category": "structure", "subcategory": "walls", "layer": "edge",
		"width": 1, "depth": 1, "fit_size": Vector3(CELL, 0.54, 0.18),
		"asset": PIRATE + "Buildings/SM_Bld_Stone_Wall_01.tscn",
	},
	"brickWindow": {
		"label": "砖墙窗", "category": "structure", "subcategory": "openings", "layer": "edge",
		"width": 1, "depth": 1, "fit_size": BRICK_WALL_SIZE,
		"asset": GANG + "SM_Bld_Wall_Brick_Window_01_Solid.tscn",
	},
	"stoneArch": {
		"label": "石拱门", "category": "structure", "subcategory": "openings", "layer": "edge",
		"width": 1, "depth": 1, "fit_size": Vector3(CELL, 1.16, 0.20),
		"asset": DUNGEON + "Walls/SM_Env_Door_Frame_Round_01.tscn",
	},
	"stoneArcade": {
		"label": "四面拱亭", "category": "structure", "subcategory": "frames", "layer": "object",
		"width": 2, "depth": 2, "fit_size": Vector3(2 * CELL, 1.45, 2 * CELL),
		"asset": PIRATE + "Buildings/SM_Bld_Cuba_Arch_01.tscn",
	},
	"stoneColumn": {
		"label": "方石柱", "category": "structure", "subcategory": "frames", "layer": "object",
		"width": 1, "depth": 1, "fit_size": Vector3(0.34, WALL_HEIGHT, 0.34), "floor_support": true,
		"asset": DUNGEON + "Optimized/SM_Env_Pillar_Square_Simple_01.tscn",
	},
	"timberFence": {
		"label": "粗木栅栏", "category": "structure", "subcategory": "fences", "layer": "edge",
		"width": 1, "depth": 1, "fit_size": Vector3(CELL, 0.47, 0.08),
		"asset": PIRATE + "Props/SM_Prop_Fence_01.tscn",
	},
	"stoneRailing": {
		"label": "石栏杆", "category": "structure", "subcategory": "fences", "layer": "edge",
		"width": 1, "depth": 1, "fit_size": Vector3(CELL, 0.48, 0.13),
		"asset": DUNGEON + "Misc/SM_Env_Railing_01.tscn",
	},
	"ornateStoneFloor": {
		"label": "花纹石地板", "category": "structure", "subcategory": "floors", "layer": "floor",
		"width": 1, "depth": 1, "asset": DUNGEON + "Floors/SM_Env_Tiles_Ornate_01.tscn",
	},
	"concreteFloor": {
		"label": "水泥地板", "category": "structure", "subcategory": "floors", "layer": "floor",
		"width": 1, "depth": 1, "asset": GANG + "SM_Bld_Floor_01.tscn",
	},
	"cafeChair": {"label": "咖啡椅", "category": "furniture", "subcategory": "seats", "layer": "object", "width": 1, "depth": 1, "scale": 0.009, "asset": "res://local-assets/models/cafe-chair.glb", "fine": true},
	"cafeTable": {"label": "户外小桌", "category": "furniture", "subcategory": "tables", "layer": "object", "width": 1, "depth": 1, "scale": 0.009, "asset": "res://local-assets/models/cafe-table.glb", "fine": true},
	"flowerPot": {"label": "花盆", "category": "garden", "subcategory": "planters", "layer": "object", "width": 1, "depth": 1, "scale": 0.008, "asset": "res://local-assets/models/flower-pot.glb", "fine": true},
	"pathLight": {"label": "矮柱灯", "category": "landscape", "subcategory": "lights", "layer": "object", "width": 1, "depth": 1, "scale": 0.0075, "asset": "res://local-assets/models/path-light.glb", "fine": true},
	"trashBin": {"label": "垃圾桶", "category": "landscape", "subcategory": "props", "layer": "object", "width": 1, "depth": 1, "scale": 0.008, "asset": "res://local-assets/models/trash-bin.glb", "fine": true},
	"treeStump": {"label": "树桩", "category": "landscape", "subcategory": "props", "layer": "object", "width": 1, "depth": 1, "scale": 0.009, "asset": "res://local-assets/models/tree-stump.glb", "fine": true},
	"pebbles": {"asset": "res://assets/models/lake-pebbles-6c0359.glb"},
	"lilies": {"asset": "res://assets/models/lily-pads-b0c5d0.glb"},
	"pine": {"asset": "res://assets/models/campground-pine-stand-0bf4f2.glb"},
	"cabin": {"asset": "res://assets/models/porch-log-cabin-d2f3ef.glb"},
	"harborShed": {"scale": 0.62, "asset": "res://local-assets/models/pirate-harbor/shed.tscn"},
	"spyPlayer": {"asset": "res://local-assets/models/spy-player/spy-player.tscn"},
}
