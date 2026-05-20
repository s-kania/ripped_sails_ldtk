package data;

enum abstract ShipDirection(String) to String {
	var N = "N";
	var NE = "NE";
	var E = "E";
	var SE = "SE";
	var S = "S";
	var SW = "SW";
	var W = "W";
	var NW = "NW";

	public static function all():Array<ShipDirection> {
		return [N, NE, E, SE, S, SW, W, NW];
	}

	public function toAngle():Float {
		return switch (cast this : String) {
			case "N": 90;
			case "NE": 45;
			case "E": 0;
			case "SE": 315;
			case "S": 270;
			case "SW": 225;
			case "W": 180;
			case "NW": 135;
			default: 0;
		};
	}

	public function toFileSuffix():String {
		return (cast this : String).toLowerCase();
	}
}

typedef CannonSlot = {
	tx:Int,
	ty:Int
}

typedef VisualOffset = {
	x:Int,
	y:Int
}

typedef DeckGrid = {
	width:Int,
	height:Int,
	tile_size:Int,
	deck_tiles:Array<Array<Int>>
}

typedef DirectionCannonSlots = {
	left:Array<CannonSlot>,
	right:Array<CannonSlot>
}

typedef TileSlot = {
	tx:Int,
	ty:Int
}

typedef BoardPoint = {
	x:Int,
	y:Int
}

typedef LadderDeckSlots = {
	slots:Array<TileSlot>
}

typedef DirectionBoardPoints = {
	slots:Array<BoardPoint>
}

typedef MastSlotConfiguration = {
	slots:Array<TileSlot>
}

typedef BaseStats = {
	hullHp:Int,
	speed:Float,
	maxCrewCapacity:Int,
	cargoCapacity:Int
}

class ShipData {
	public var filePath:Null<dn.FilePath>;
	public var assetsPath:Null<dn.FilePath>;

	// Editable fields
	public var shipType:String = "small";
	public var maxCannonsPerSide:Int = 3;
	public var maxMastCount:Int = 1;
	public var maxSailsPerMast:Int = 1;
	public var baseStats:BaseStats;
	public var assetPrefix:Null<String> = null;
	public var assetScale:Float = 1.0;
	public var deckGrid:DeckGrid;
	public var cannonSlots:DirectionCannonSlots;
	public var visualOffsets:Map<String, VisualOffset> = new Map();

	// Props
	public var ladderDeckSlots:LadderDeckSlots;
	public var ladderBoardPoints:Map<String, DirectionBoardPoints> = new Map();
	public var mastSlotsByCount:Map<Int, MastSlotConfiguration> = new Map();
	public var steeringWheelTile:TileSlot;
	public var helmsmanTile:TileSlot;
	public var steeringWheelAsset:Null<String> = null;
	public var steeringWheelScale:Float = 1.0;

	// Pass-through: store raw JSON to preserve unknown keys
	var rawJson:Null<haxe.DynamicAccess<Dynamic>>;

	public function new() {
		baseStats = {
			hullHp: 1000,
			speed: 300,
			maxCrewCapacity: 8,
			cargoCapacity: 100
		};
		deckGrid = {
			width: 4,
			height: 9,
			tile_size: 16,
			deck_tiles: []
		};
		cannonSlots = {left: [], right: []};
		ladderDeckSlots = {slots: []};
		steeringWheelTile = {tx: 0, ty: 0};
		helmsmanTile = {tx: 0, ty: 1};
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			visualOffsets.set(d, {x: 0, y: 0});
			ladderBoardPoints.set(d, {slots: []});
		}
	}

	public static function createEmpty():ShipData {
		return new ShipData();
	}

	public static function fromFile(path:String):Null<ShipData> {
		var raw = NT.readFileString(path);
		if (raw == null)
			return null;
		try {
			var json:Dynamic = haxe.Json.parse(raw);
			var ship = new ShipData();
			ship.filePath = dn.FilePath.fromFile(path);
			ship.rawJson = json;
			ship.parseJson(json);
			return ship;
		} catch (_) {
			return null;
		}
	}

	function parseTileSlot(slot:Dynamic):Null<TileSlot> {
		if (slot == null)
			return null;
		if (Reflect.hasField(slot, "tx") && Reflect.hasField(slot, "ty"))
			return {
				tx: Std.int(Reflect.field(slot, "tx")) - 1,
				ty: Std.int(Reflect.field(slot, "ty")) - 1
			};
		return null;
	}

	function parseCannonSlotArray(raw:Array<Dynamic>):Array<CannonSlot> {
		var result:Array<CannonSlot> = [];
		if (raw == null)
			return result;
		for (slot in raw) {
			var parsed = parseTileSlot(slot);
			if (parsed != null)
				result.push({tx: parsed.tx, ty: parsed.ty});
		}
		return result;
	}

	static inline var ISO_Y_SCALE:Float = 0.7071;
	static inline var GRID_BASE_ANGLE:Float = 90;

	function getRotationForDirection(dir:ShipDirection):{cos:Float, sin:Float} {
		var angle = dir.toAngle();
		var adjusted = ((angle - GRID_BASE_ANGLE) % 360 + 360) % 360;
		var rad = adjusted * Math.PI / 180;
		return {
			cos: Math.cos(rad),
			sin: -Math.sin(rad)
		};
	}

	function tileToScreen(tx:Float, ty:Float, dir:ShipDirection):{x:Float, y:Float} {
		var centerX = deckGrid.width / 2.0;
		var centerY = deckGrid.height / 2.0;
		var virtualX = (tx - centerX) * deckGrid.tile_size;
		var virtualY = (ty - centerY) * deckGrid.tile_size;

		var rot = getRotationForDirection(dir);
		var rotX = virtualX * rot.cos - virtualY * rot.sin;
		var rotY = virtualX * rot.sin + virtualY * rot.cos;

		return {x: rotX, y: rotY * ISO_Y_SCALE};
	}

	public function getDefaultBoardPointForDeck(deck:TileSlot, dir:ShipDirection):BoardPoint {
		var off = getVisualOffset(dir);
		var screen = tileToScreen(deck.tx + 0.5, deck.ty + 0.5, dir);
		return {
			x: Std.int(Math.round(off.x + screen.x)),
			y: Std.int(Math.round(off.y - screen.y))
		};
	}

	function copyTile(slot:TileSlot):TileSlot {
		return {tx: slot.tx, ty: slot.ty};
	}

	function parseBoardPoint(point:Dynamic):Null<BoardPoint> {
		if (point == null || !Reflect.hasField(point, "x") || !Reflect.hasField(point, "y"))
			return null;
		return {
			x: Std.int(Reflect.field(point, "x")),
			y: Std.int(Reflect.field(point, "y"))
		};
	}

	function parseTileSlotArray(raw:Array<Dynamic>):Array<TileSlot> {
		var result:Array<TileSlot> = [];
		if (raw == null)
			return result;
		for (slotRaw in raw) {
			var parsed = parseTileSlot(slotRaw);
			if (parsed != null)
				result.push(parsed);
		}
		return result;
	}

	function defaultMastSlot(index:Int, count:Int):TileSlot {
		if (deckGrid.deck_tiles.length > 0) {
			var idx = count <= 1 ? Std.int(Math.floor(deckGrid.deck_tiles.length / 2)) : Math.round(index * (deckGrid.deck_tiles.length - 1) / (count - 1));
			if (idx < 0)
				idx = 0;
			if (idx >= deckGrid.deck_tiles.length)
				idx = deckGrid.deck_tiles.length - 1;
			var tile = deckGrid.deck_tiles[idx];
			return {tx: tile[0], ty: tile[1]};
		}
		return {
			tx: Std.int(Math.max(0, Math.floor(deckGrid.width / 2))),
			ty: Std.int(Math.max(0, Math.floor(deckGrid.height / 2)))
		};
	}

	function normalizeMastSlotsForCount(count:Int) {
		if (count < 1)
			count = 1;
		var config = mastSlotsByCount.get(count);
		if (config == null) {
			config = {slots: []};
			mastSlotsByCount.set(count, config);
		}
		var normalized:Array<TileSlot> = [];
		for (i in 0...count) {
			var slot = i < config.slots.length ? config.slots[i] : defaultMastSlot(i, count);
			if (!slotInGrid(slot) || !isDeckTileActive(slot.tx, slot.ty))
				slot = defaultMastSlot(i, count);
			normalized.push(copyTile(slot));
		}
		config.slots = normalized;
	}

	public function ensureMastSlotConfigurations() {
		if (maxMastCount < 1)
			maxMastCount = 1;
		if (maxSailsPerMast < 1)
			maxSailsPerMast = 1;
		for (count in 1...(maxMastCount + 1))
			normalizeMastSlotsForCount(count);
	}

	public function getMastSlotConfiguration(count:Int):MastSlotConfiguration {
		if (count < 1)
			count = 1;
		if (count > maxMastCount)
			count = maxMastCount;
		normalizeMastSlotsForCount(count);
		return mastSlotsByCount.get(count);
	}

	function fallbackLadderDeck(last:Null<TileSlot>):TileSlot {
		for (t in deckGrid.deck_tiles) {
			if (last == null || t[0] != last.tx || t[1] != last.ty)
				return {tx: t[0], ty: t[1]};
		}
		if (last != null)
			return {tx: last.tx, ty: last.ty};
		return {tx: 0, ty: 0};
	}

	function ensureEvenLadderSlots() {
		if (ladderDeckSlots.slots.length % 2 == 0)
			return;
		var last = ladderDeckSlots.slots.length > 0 ? ladderDeckSlots.slots[ladderDeckSlots.slots.length - 1] : null;
		addLadderSlot(fallbackLadderDeck(last));
	}

	function ensureLadderBoardPointCounts() {
		for (dir in ShipDirection.all()) {
			var points = getLadderBoardPoints(dir).slots;
			while (points.length < ladderDeckSlots.slots.length) {
				var deck = ladderDeckSlots.slots[points.length];
				points.push(getDefaultBoardPointForDeck(deck, dir));
			}
			while (points.length > ladderDeckSlots.slots.length)
				points.pop();
		}
	}

	public function addLadderSlot(deck:TileSlot) {
		ladderDeckSlots.slots.push(copyTile(deck));
		for (dir in ShipDirection.all())
			getLadderBoardPoints(dir).slots.push(getDefaultBoardPointForDeck(deck, dir));
	}

	function slotInGrid(slot:{tx:Int, ty:Int}):Bool {
		return slot.tx >= 0 && slot.tx < deckGrid.width && slot.ty >= 0 && slot.ty < deckGrid.height;
	}

	function clampTileSlot(slot:TileSlot) {
		if (slot.tx >= deckGrid.width)
			slot.tx = deckGrid.width - 1;
		if (slot.ty >= deckGrid.height)
			slot.ty = deckGrid.height - 1;
		if (slot.tx < 0)
			slot.tx = 0;
		if (slot.ty < 0)
			slot.ty = 0;
	}

	function parseJson(json:Dynamic) {
		if (json == null)
			return;

		if (Reflect.hasField(json, "ship_type"))
			shipType = Reflect.field(json, "ship_type");
		if (Reflect.hasField(json, "max_cannons_per_side"))
			maxCannonsPerSide = Reflect.field(json, "max_cannons_per_side");
		if (Reflect.hasField(json, "max_mast_count"))
			maxMastCount = Std.int(Reflect.field(json, "max_mast_count"));
		if (Reflect.hasField(json, "max_sails_per_mast"))
			maxSailsPerMast = Std.int(Reflect.field(json, "max_sails_per_mast"));
		var bs:Dynamic = Reflect.field(json, "base_stats");
		if (bs != null) {
			if (Reflect.hasField(bs, "hull_hp"))
				baseStats.hullHp = Std.int(Reflect.field(bs, "hull_hp"));
			if (Reflect.hasField(bs, "speed"))
				baseStats.speed = Reflect.field(bs, "speed");
			if (Reflect.hasField(bs, "max_crew_capacity"))
				baseStats.maxCrewCapacity = Std.int(Reflect.field(bs, "max_crew_capacity"));
			if (Reflect.hasField(bs, "cargo_capacity"))
				baseStats.cargoCapacity = Std.int(Reflect.field(bs, "cargo_capacity"));
		}

		// ship_editor section
		var se:Dynamic = Reflect.field(json, "ship_editor");
		if (se != null) {
			if (Reflect.hasField(se, "asset_prefix"))
				assetPrefix = Reflect.field(se, "asset_prefix");
			if (Reflect.hasField(se, "asset_scale")) {
				var s:Float = Reflect.field(se, "asset_scale");
				if (!Math.isNaN(s) && s > 0)
					assetScale = s;
			}
			if (Reflect.hasField(se, "asset_path")) {
				var p:String = Reflect.field(se, "asset_path");
				if (p != null && p.length > 0)
					assetsPath = dn.FilePath.fromDir(p);
			}
		}

		// deck_grid
		var dg:Dynamic = Reflect.field(json, "deck_grid");
		if (dg != null) {
			if (Reflect.hasField(dg, "width"))
				deckGrid.width = Reflect.field(dg, "width");
			if (Reflect.hasField(dg, "height"))
				deckGrid.height = Reflect.field(dg, "height");
			if (Reflect.hasField(dg, "tile_size"))
				deckGrid.tile_size = Reflect.field(dg, "tile_size");
			if (Reflect.hasField(dg, "deck_tiles")) {
				deckGrid.deck_tiles = [];
				var tiles:Array<Dynamic> = Reflect.field(dg, "deck_tiles");
				if (tiles != null) {
					for (t in tiles) {
						var arr:Array<Dynamic> = t;
						if (arr != null && arr.length >= 2)
							deckGrid.deck_tiles.push([Std.int(arr[0]) - 1, Std.int(arr[1]) - 1]); // Lua 1-based -> 0-based
					}
				}
			}
		}

		var mastSlotsJson:Dynamic = Reflect.field(json, "mast_slots");
		var mastConfigurations:Dynamic = mastSlotsJson != null ? Reflect.field(mastSlotsJson, "configurations") : null;
		if (mastConfigurations != null) {
			for (count in 1...(maxMastCount + 1)) {
				var rawConfig:Dynamic = Reflect.field(mastConfigurations, Std.string(count));
				var rawSlots:Array<Dynamic> = rawConfig != null ? Reflect.field(rawConfig, "slots") : null;
				if (rawSlots != null)
					mastSlotsByCount.set(count, {slots: parseTileSlotArray(rawSlots)});
			}
		}
		ensureMastSlotConfigurations();

		// cannon_slots
		var cs:Dynamic = Reflect.field(json, "cannon_slots");
		if (cs != null) {
			var leftArr:Array<Dynamic> = Reflect.field(cs, "left");
			var rightArr:Array<Dynamic> = Reflect.field(cs, "right");
			cannonSlots = {
				left: parseCannonSlotArray(leftArr),
				right: parseCannonSlotArray(rightArr)
			};
		}

		// visual_offsets
		var vo:Dynamic = Reflect.field(json, "visual_offsets");
		if (vo != null) {
			for (dir in ShipDirection.all()) {
				var d:String = dir;
				var offData:Dynamic = Reflect.field(vo, d);
				if (offData != null) {
					visualOffsets.set(d, {
						x: Reflect.hasField(offData, "x") ? Std.int(Reflect.field(offData, "x")) : 0,
						y: Reflect.hasField(offData, "y") ? Std.int(Reflect.field(offData, "y")) : 0
					});
				}
			}
		}

		// Ladder data: deck tile slots and manual board points are separate.
		var ladderDeckJson:Dynamic = Reflect.field(json, "ladder_deck_slots");
		var ladderBoardJson:Dynamic = Reflect.field(json, "ladder_board_points");
		var rawDeckSlots:Array<Dynamic> = ladderDeckJson != null ? Reflect.field(ladderDeckJson, "slots") : null;
		if (rawDeckSlots != null)
			ladderDeckSlots.slots = parseTileSlotArray(rawDeckSlots);
		if (ladderBoardJson != null) {
			for (dir in ShipDirection.all()) {
				var d:String = dir;
				var directionData:Dynamic = Reflect.field(ladderBoardJson, d);
				var rawPoints:Array<Dynamic> = directionData != null ? Reflect.field(directionData, "slots") : null;
				if (rawPoints != null) {
					var points = getLadderBoardPoints(dir);
					points.slots = [];
					for (rawPoint in rawPoints) {
						var point = parseBoardPoint(rawPoint);
						if (point != null)
							points.slots.push(point);
					}
				}
			}
		}
		ensureEvenLadderSlots();
		ensureLadderBoardPointCounts();

		// steering_wheel
		var swJson:Dynamic = Reflect.field(json, "steering_wheel");
		if (swJson != null) {
			if (Reflect.hasField(swJson, "asset_folder"))
				steeringWheelAsset = Reflect.field(swJson, "asset_folder");
			if (Reflect.hasField(swJson, "asset_scale"))
				steeringWheelScale = Reflect.field(swJson, "asset_scale");
			var pos:Dynamic = Reflect.field(swJson, "position");
			if (pos != null) {
				steeringWheelTile = {
					tx: Reflect.hasField(pos, "tx") ? Std.int(Reflect.field(pos, "tx")) - 1 : 0,
					ty: Reflect.hasField(pos, "ty") ? Std.int(Reflect.field(pos, "ty")) - 1 : 0
				};
			}
			var hmPos:Dynamic = Reflect.field(swJson, "helmsman_position");
			if (hmPos != null) {
				helmsmanTile = {
					tx: Reflect.hasField(hmPos, "tx") ? Std.int(Reflect.field(hmPos, "tx")) - 1 : 0,
					ty: Reflect.hasField(hmPos, "ty") ? Std.int(Reflect.field(hmPos, "ty")) - 1 : 0
				};
			}
		}
	}

	public function toJson():Dynamic {
		// Start from raw JSON to preserve unknown keys
		var json:haxe.DynamicAccess<Dynamic> = rawJson != null ? rawJson : {};

		json.set("ship_type", shipType);
		json.set("max_cannons_per_side", maxCannonsPerSide);
		json.set("max_mast_count", maxMastCount);
		json.set("max_sails_per_mast", maxSailsPerMast);
		var baseStatsObj:haxe.DynamicAccess<Dynamic> = Reflect.field(json, "base_stats");
		if (baseStatsObj == null)
			baseStatsObj = {};
		baseStatsObj.set("hull_hp", baseStats.hullHp);
		baseStatsObj.set("speed", baseStats.speed);
		baseStatsObj.set("max_crew_capacity", baseStats.maxCrewCapacity);
		baseStatsObj.set("cargo_capacity", baseStats.cargoCapacity);
		json.set("base_stats", baseStatsObj);

		// ship_editor section
		var seObj:haxe.DynamicAccess<Dynamic> = {};
		if (assetPrefix != null)
			seObj.set("asset_prefix", assetPrefix);
		seObj.set("asset_scale", assetScale);
		if (assetsPath != null)
			seObj.set("asset_path", assetsPath.full);
		json.set("ship_editor", seObj);

		// deck_grid
		var dgRaw:haxe.DynamicAccess<Dynamic> = {};
		dgRaw.set("width", deckGrid.width);
		dgRaw.set("height", deckGrid.height);
		dgRaw.set("tile_size", deckGrid.tile_size);
		dgRaw.set("deck_tiles", deckGrid.deck_tiles.map((t) -> [t[0] + 1, t[1] + 1])); // 0-based -> Lua 1-based
		json.set("deck_grid", dgRaw);

		// mast_slots
		ensureMastSlotConfigurations();
		var mastConfigs:haxe.DynamicAccess<Dynamic> = {};
		for (count in 1...(maxMastCount + 1)) {
			var config = getMastSlotConfiguration(count);
			mastConfigs.set(Std.string(count), {slots: config.slots.map((s) -> {tx: s.tx + 1, ty: s.ty + 1})});
		}
		var mastObj:haxe.DynamicAccess<Dynamic> = {};
		mastObj.set("configurations", mastConfigs);
		json.set("mast_slots", mastObj);

		// cannon_slots
		var csObj:haxe.DynamicAccess<Dynamic> = {};
		csObj.set("left", cannonSlots.left.map((s) -> {tx: s.tx + 1, ty: s.ty + 1}));
		csObj.set("right", cannonSlots.right.map((s) -> {tx: s.tx + 1, ty: s.ty + 1}));
		json.set("cannon_slots", csObj);

		// visual_offsets
		var voObj:haxe.DynamicAccess<Dynamic> = {};
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var off = visualOffsets.get(d);
			if (off != null) {
				voObj.set(d, {x: off.x, y: off.y});
			}
		}
		json.set("visual_offsets", voObj);

		// ladder_deck_slots and ladder_board_points
		ensureEvenLadderSlots();
		ensureLadderBoardPointCounts();
		var ladderDeckObj:haxe.DynamicAccess<Dynamic> = {};
		ladderDeckObj.set("slots", ladderDeckSlots.slots.map((s) -> {tx: s.tx + 1, ty: s.ty + 1}));
		json.set("ladder_deck_slots", ladderDeckObj);

		var ladderBoardObj:haxe.DynamicAccess<Dynamic> = {};
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var points = getLadderBoardPoints(dir).slots;
			ladderBoardObj.set(d, {slots: points.map((p) -> {x: p.x, y: p.y})});
		}
		json.set("ladder_board_points", ladderBoardObj);

		// steering_wheel
		var swObj:haxe.DynamicAccess<Dynamic> = {};
		if (steeringWheelAsset != null)
			swObj.set("asset_folder", steeringWheelAsset);
		swObj.set("asset_scale", steeringWheelScale);
		swObj.set("position", {tx: steeringWheelTile.tx + 1, ty: steeringWheelTile.ty + 1});
		swObj.set("helmsman_position", {tx: helmsmanTile.tx + 1, ty: helmsmanTile.ty + 1});
		json.set("steering_wheel", swObj);

		return json;
	}

	public function toJsonString():String {
		var raw = haxe.Json.stringify(toJson(), null, "  ");
		return compactSmallContainers(raw);
	}

	/**
	 * Post-process indented JSON to collapse small leaf containers onto one line.
	 * Handles both {...} objects and [...] arrays that contain no nested containers.
	 */
	static function compactSmallContainers(json:String):String {
		var buf = new StringBuf();
		var i = 0;
		var len = json.length;
		while (i < len) {
			var ch = json.charCodeAt(i);
			var isOpen = (ch == "{".code || ch == "[".code);
			if (isOpen) {
				// Find matching closing bracket
				var depth = 1;
				var j = i + 1;
				var hasNested = false;
				var inStr = false;
				while (j < len && depth > 0) {
					var c = json.charCodeAt(j);
					if (inStr) {
						if (c == "\\".code) {
							j++; // skip escaped char
						} else if (c == '"'.code) {
							inStr = false;
						}
					} else {
						if (c == '"'.code)
							inStr = true;
						else if (c == "{".code || c == "[".code) {
							hasNested = true;
							depth++;
						} else if (c == "}".code || c == "]".code)
							depth--;
					}
					j++;
				}
				// j is now one past the closing bracket
				if (!hasNested && depth == 0) {
					// Collapse whitespace to single spaces
					var block = json.substring(i, j);
					var compacted = new StringBuf();
					var prevWs = false;
					for (k in 0...block.length) {
						var bc = block.charCodeAt(k);
						if (bc == " ".code || bc == "\n".code || bc == "\r".code || bc == "\t".code) {
							if (!prevWs) {
								compacted.addChar(" ".code);
								prevWs = true;
							}
						} else {
							compacted.addChar(bc);
							prevWs = false;
						}
					}
					var result = compacted.toString();
					if (result.length <= 80) {
						buf.add(result);
						i = j;
						continue;
					}
				}
				buf.addChar(ch);
				i++;
			} else {
				buf.addChar(ch);
				i++;
			}
		}
		return buf.toString();
	}

	public function save():Bool {
		if (filePath == null)
			return false;
		try {
			NT.writeFileString(filePath.full, toJsonString());
			return true;
		} catch (_) {
			return false;
		}
	}

	public function isDeckTileActive(tx:Int, ty:Int):Bool {
		for (t in deckGrid.deck_tiles) {
			if (t[0] == tx && t[1] == ty)
				return true;
		}
		return false;
	}

	public function toggleDeckTile(tx:Int, ty:Int) {
		var idx = -1;
		for (i in 0...deckGrid.deck_tiles.length) {
			if (deckGrid.deck_tiles[i][0] == tx && deckGrid.deck_tiles[i][1] == ty) {
				idx = i;
				break;
			}
		}
		if (idx >= 0)
			deckGrid.deck_tiles.splice(idx, 1);
		else
			deckGrid.deck_tiles.push([tx, ty]);
	}

	public function trimDeckTilesToGrid() {
		deckGrid.deck_tiles = deckGrid.deck_tiles.filter((t) -> t[0] >= 0 && t[0] < deckGrid.width && t[1] >= 0 && t[1] < deckGrid.height);
		cannonSlots.left = cannonSlots.left.filter(slotInGrid);
		cannonSlots.right = cannonSlots.right.filter(slotInGrid);
		ladderDeckSlots.slots = ladderDeckSlots.slots.filter(slotInGrid);
		clampTileSlot(steeringWheelTile);
		clampTileSlot(helmsmanTile);
		ensureEvenLadderSlots();
		ensureLadderBoardPointCounts();
		ensureMastSlotConfigurations();
	}

	public function getCannonSlots(dir:ShipDirection):{left:Array<CannonSlot>, right:Array<CannonSlot>} {
		return cannonSlots;
	}

	public function getVisualOffset(dir:ShipDirection):VisualOffset {
		var d:String = dir;
		var o = visualOffsets.get(d);
		if (o == null) {
			o = {x: 0, y: 0};
			visualOffsets.set(d, o);
		}
		return o;
	}

	public function getLadderDeckSlots():LadderDeckSlots {
		return ladderDeckSlots;
	}

	public function getLadderBoardPoints(dir:ShipDirection):DirectionBoardPoints {
		var d:String = dir;
		var points = ladderBoardPoints.get(d);
		if (points == null) {
			points = {slots: []};
			ladderBoardPoints.set(d, points);
		}
		return points;
	}

	public function getLadderBoardPoint(index:Int, dir:ShipDirection):BoardPoint {
		var points = getLadderBoardPoints(dir).slots;
		while (points.length <= index) {
			var deck = index < ladderDeckSlots.slots.length ? ladderDeckSlots.slots[index] : fallbackLadderDeck(null);
			points.push(getDefaultBoardPointForDeck(deck, dir));
		}
		return points[index];
	}

}
