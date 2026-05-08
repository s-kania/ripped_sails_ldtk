package worldmap;

class WorldMapExport {
	public static inline var SCHEMA_VERSION = 1;

	public static function makeWorldJson(
		worldId:String,
		worldName:String,
		imagePath:String,
		startNodeId:Null<String>,
		mapData:Dynamic,
		generatorParams:Dynamic,
		assetPaths:Null<Map<String, String>>,
		localPaths:Null<Map<String, String>>
	):Dynamic {
		var nodes:Array<Dynamic> = [];
		var validNodeIds:Map<String, Bool> = new Map();

		var cities:Array<Dynamic> = cast Reflect.field(mapData, "cities");
		if( cities!=null )
			for( city in cities ) {
				var nodeId = getNodeId("city", readInt(Reflect.field(city, "id")));
				validNodeIds.set(nodeId, true);
				nodes.push(makeNode(
					nodeId,
					readString(Reflect.field(city, "name"), nodeId),
					"city",
					readInt(Reflect.field(city, "x")),
					readInt(Reflect.field(city, "y")),
					assetPaths
				));
			}

		var points:Array<Dynamic> = cast Reflect.field(mapData, "pointsOfInterest");
		if( points!=null )
			for( point in points ) {
				var nodeId = getNodeId("poi", readInt(Reflect.field(point, "id")));
				validNodeIds.set(nodeId, true);
				nodes.push(makeNode(
					nodeId,
					readString(Reflect.field(point, "name"), nodeId),
					"poi",
					readInt(Reflect.field(point, "x")),
					readInt(Reflect.field(point, "y")),
					assetPaths
				));
			}

		var resolvedStartNodeId = startNodeId!=null && validNodeIds.exists(startNodeId)
			? startNodeId
			: (nodes.length>0 ? Reflect.field(nodes[0], "id") : null);

		return {
			schema_version: SCHEMA_VERSION,
			id: worldId,
			name: worldName,
			image: imagePath,
			size: {
				width: readInt(Reflect.field(mapData, "width")),
				height: readInt(Reflect.field(mapData, "height")),
			},
			start_node_id: resolvedStartNodeId,
			nodes: nodes,
			editor_meta: {
				schema_version: SCHEMA_VERSION,
				generator_params: generatorParams,
				local_ldtk_paths: mapToDynamic(localPaths, validNodeIds),
			},
			};
	}

	public static function makeStateSignature(
		worldId:String,
		worldName:String,
		imagePath:String,
		startNodeId:Null<String>,
		mapData:Dynamic,
		generatorParams:Dynamic,
		assetPaths:Null<Map<String, String>>,
		localPaths:Null<Map<String, String>>
	):String {
		return haxe.Json.stringify(makeWorldJson(
			worldId,
			worldName,
			imagePath,
			startNodeId,
			mapData,
			generatorParams,
			assetPaths,
			localPaths
		));
	}

	public static inline function getNodeId(type:String, id:Int):String {
		return type + "_" + id;
	}

	public static function mapToDynamic(map:Null<Map<String, String>>, ?onlyKeys:Map<String, Bool>):Dynamic {
		var out:Dynamic = {};
		if( map!=null )
			for( key in map.keys() )
				if( onlyKeys==null || onlyKeys.exists(key) )
					Reflect.setField(out, key, map.get(key));
		return out;
	}

	static function makeNode(nodeId:String, name:String, type:String, x:Int, y:Int, assetPaths:Null<Map<String, String>>):Dynamic {
		var node:Dynamic = {
			id: nodeId,
			name: name,
			type: type,
			position: {
				x: x,
				y: y,
			},
			region_id: null,
		};
		if( assetPaths!=null && assetPaths.exists(nodeId) ) {
			var mapPath = assetPaths.get(nodeId);
			if( mapPath!=null && mapPath.length>0 )
				Reflect.setField(node, "map", mapPath);
		}
		return node;
	}

	static inline function readInt(v:Dynamic, def=0):Int {
		return v==null ? def : Std.int(v);
	}

	static inline function readString(v:Dynamic, def:String):String {
		return v==null ? def : Std.string(v);
	}
}
