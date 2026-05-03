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
	x:Int,
	y:Int
}

typedef VisualOffset = {
	x:Int,
	y:Int
}

typedef DeckGrid = {
	width:Int,
	height:Int,
	tile_size:Int,
	deck_tiles:Array<Array<Int>>,
	boarding_point:{x:Int, y:Int}
}

typedef DirectionCannonSlots = {
	left:Array<CannonSlot>,
	right:Array<CannonSlot>
}

typedef PropSlot = {
	x:Int,
	y:Int
}

typedef TileSlot = {
	tx:Int,
	ty:Int
}

typedef DirectionPropSlots = {
	slots:Array<PropSlot>
}

class ShipData {
	public var filePath:Null<dn.FilePath>;
	public var assetsPath:Null<dn.FilePath>;

	// Editable fields
	public var shipType:String = "small";
	public var maxCannonsPerSide:Int = 3;
	public var assetPrefix:Null<String> = null;
	public var assetScale:Float = 1.0;
	public var deckGrid:DeckGrid;
	public var cannonSlots:Map<String, DirectionCannonSlots> = new Map();
	public var visualOffsets:Map<String, VisualOffset> = new Map();

	// Props
	public var boardingPoints:Map<String, DirectionPropSlots> = new Map();
	public var steeringWheelTile:TileSlot;
	public var helmsmanTile:TileSlot;
	public var steeringWheelAsset:Null<String> = null;
	public var steeringWheelScale:Float = 1.0;

	// Pass-through: store raw JSON to preserve unknown keys
	var rawJson:Null<haxe.DynamicAccess<Dynamic>>;

	public function new() {
		deckGrid = {
			width: 4,
			height: 9,
			tile_size: 16,
			deck_tiles: [],
			boarding_point: {x: 0, y: 0}
		};
		steeringWheelTile = {tx: 0, ty: 0};
		helmsmanTile = {tx: 0, ty: 1};
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			cannonSlots.set(d, {left: [], right: []});
			visualOffsets.set(d, {x: 0, y: 0});
			boardingPoints.set(d, {slots: []});
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

	function parseJson(json:Dynamic) {
		if (json == null)
			return;

		if (Reflect.hasField(json, "ship_type"))
			shipType = Reflect.field(json, "ship_type");
		if (Reflect.hasField(json, "max_cannons_per_side"))
			maxCannonsPerSide = Reflect.field(json, "max_cannons_per_side");

		// ship_editor section (with fallback to old top-level asset_prefix)
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
		} else if (Reflect.hasField(json, "asset_prefix")) {
			assetPrefix = Reflect.field(json, "asset_prefix");
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
			if (Reflect.hasField(dg, "boarding_point")) {
				var bp:Dynamic = Reflect.field(dg, "boarding_point");
				if (bp != null) {
					deckGrid.boarding_point = {
						x: (Reflect.hasField(bp, "x") ? Std.int(Reflect.field(bp, "x")) : 1) - 1, // Lua 1-based -> 0-based
						y: (Reflect.hasField(bp, "y") ? Std.int(Reflect.field(bp, "y")) : 1) - 1 // Lua 1-based -> 0-based
					};
				}
			}
		}

		// cannon_slots
		var cs:Dynamic = Reflect.field(json, "cannon_slots");
		if (cs != null) {
			for (dir in ShipDirection.all()) {
				var d:String = dir;
				var dirData:Dynamic = Reflect.field(cs, d);
				if (dirData != null) {
					var left:Array<CannonSlot> = [];
					var right:Array<CannonSlot> = [];
					var leftArr:Array<Dynamic> = Reflect.field(dirData, "left");
					var rightArr:Array<Dynamic> = Reflect.field(dirData, "right");
					if (leftArr != null)
						for (s in leftArr)
							left.push({x: Std.int(Reflect.field(s, "x")), y: Std.int(Reflect.field(s, "y"))});
					if (rightArr != null)
						for (s in rightArr)
							right.push({x: Std.int(Reflect.field(s, "x")), y: Std.int(Reflect.field(s, "y"))});
					cannonSlots.set(d, {left: left, right: right});
				}
			}
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

		// boarding_points
		var bpJson:Dynamic = Reflect.field(json, "boarding_points");
		if (bpJson != null) {
			for (dir in ShipDirection.all()) {
				var d:String = dir;
				var dirData:Dynamic = Reflect.field(bpJson, d);
				if (dirData != null) {
					var slotsArr:Array<PropSlot> = [];
					var rawSlots:Array<Dynamic> = Reflect.field(dirData, "slots");
					if (rawSlots != null)
						for (s in rawSlots)
							slotsArr.push({x: Std.int(Reflect.field(s, "x")), y: Std.int(Reflect.field(s, "y"))});
					boardingPoints.set(d, {slots: slotsArr});
				}
			}
		}

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
					tx: Reflect.hasField(pos, "tx") ? Std.int(Reflect.field(pos, "tx")) : 0,
					ty: Reflect.hasField(pos, "ty") ? Std.int(Reflect.field(pos, "ty")) : 0
				};
			}
			var hmPos:Dynamic = Reflect.field(swJson, "helmsman_position");
			if (hmPos != null) {
				helmsmanTile = {
					tx: Reflect.hasField(hmPos, "tx") ? Std.int(Reflect.field(hmPos, "tx")) : 0,
					ty: Reflect.hasField(hmPos, "ty") ? Std.int(Reflect.field(hmPos, "ty")) : 0
				};
			}
		}
	}

	public function toJson():Dynamic {
		// Start from raw JSON to preserve unknown keys
		var json:haxe.DynamicAccess<Dynamic> = rawJson != null ? rawJson : {};

		json.set("ship_type", shipType);
		json.set("max_cannons_per_side", maxCannonsPerSide);

		// ship_editor section
		var seObj:haxe.DynamicAccess<Dynamic> = {};
		if (assetPrefix != null)
			seObj.set("asset_prefix", assetPrefix);
		seObj.set("asset_scale", assetScale);
		if (assetsPath != null)
			seObj.set("asset_path", assetsPath.full);
		json.set("ship_editor", seObj);

		// deck_grid - preserve unknown keys
		var dgRaw:haxe.DynamicAccess<Dynamic> = rawJson != null
			&& Reflect.hasField(rawJson, "deck_grid") ? Reflect.field(rawJson, "deck_grid") : {};
		dgRaw.set("width", deckGrid.width);
		dgRaw.set("height", deckGrid.height);
		dgRaw.set("tile_size", deckGrid.tile_size);
		dgRaw.set("deck_tiles", deckGrid.deck_tiles.map((t) -> [t[0] + 1, t[1] + 1])); // 0-based -> Lua 1-based
		dgRaw.set("boarding_point", {x: deckGrid.boarding_point.x + 1, y: deckGrid.boarding_point.y + 1}); // 0-based -> Lua 1-based
		json.set("deck_grid", dgRaw);

		// cannon_slots
		var csObj:haxe.DynamicAccess<Dynamic> = {};
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var slots = cannonSlots.get(d);
			if (slots != null) {
				csObj.set(d, {left: slots.left, right: slots.right});
			}
		}
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

		// boarding_points
		var bpObj:haxe.DynamicAccess<Dynamic> = {};
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var bp = boardingPoints.get(d);
			if (bp != null) {
				bpObj.set(d, {slots: bp.slots});
			}
		}
		json.set("boarding_points", bpObj);

		// steering_wheel
		var swObj:haxe.DynamicAccess<Dynamic> = {};
		if (steeringWheelAsset != null)
			swObj.set("asset_folder", steeringWheelAsset);
		swObj.set("asset_scale", steeringWheelScale);
		swObj.set("position", {tx: steeringWheelTile.tx, ty: steeringWheelTile.ty});
		swObj.set("helmsman_position", {tx: helmsmanTile.tx, ty: helmsmanTile.ty});
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
				var closeChar = ch == "{".code ? "}".code : "]".code;
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
		if (deckGrid.boarding_point.x >= deckGrid.width)
			deckGrid.boarding_point.x = deckGrid.width - 1;
		if (deckGrid.boarding_point.y >= deckGrid.height)
			deckGrid.boarding_point.y = deckGrid.height - 1;
		if (deckGrid.boarding_point.x < 0)
			deckGrid.boarding_point.x = 0;
		if (deckGrid.boarding_point.y < 0)
			deckGrid.boarding_point.y = 0;
	}

	public function getCannonSlots(dir:ShipDirection):{left:Array<CannonSlot>, right:Array<CannonSlot>} {
		var d:String = dir;
		var s = cannonSlots.get(d);
		if (s == null) {
			s = {left: [], right: []};
			cannonSlots.set(d, s);
		}
		return s;
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

	public function getBoardingPoints(dir:ShipDirection):DirectionPropSlots {
		var d:String = dir;
		var bp = boardingPoints.get(d);
		if (bp == null) {
			bp = {slots: []};
			boardingPoints.set(d, bp);
		}
		return bp;
	}

}
