import haxe.Json;
import worldmap.WorldMapExport;

class WorldMapExportTest {
	static function main() {
		var params:Dynamic = {
			seed: "GoldenAge",
			resolution: 448,
		};
		var mapData:Dynamic = {
			width: 448,
			height: 277,
			cities: [
				{ id: 1, name: "Port Royal", x: 57, y: 176 },
			],
			pointsOfInterest: [
				{ id: 30, name: "Rumrunner Shore", x: 123, y: 188 },
			],
		};
		var assetPaths:Map<String, String> = new Map();
		assetPaths.set("city_1", "/assets/locations/port_royal.ldtk");
		var localPaths:Map<String, String> = new Map();
		localPaths.set("city_1", "/tmp/port_royal.ldtk");

		var out:Dynamic = WorldMapExport.makeWorldJson(
			"golden_age",
			"Golden Age",
			"/assets/world/world_map.png",
			"city_1",
			mapData,
			params,
			assetPaths,
			localPaths
		);

		assertEq(1, out.schema_version, "schema version");
		assertEq("golden_age", out.id, "world id");
		assertEq("Golden Age", out.name, "world name");
		assertEq("/assets/world/world_map.png", out.image, "image path");
		assertEq(448, out.size.width, "width");
		assertEq(277, out.size.height, "height");
		assertEq("city_1", out.start_node_id, "start node");
		assertEq("city_1", out.nodes[0].id, "city node id");
		assertEq("city", out.nodes[0].type, "city node type");
		assertEq(57, out.nodes[0].position.x, "city x");
		assertEq("/assets/locations/port_royal.ldtk", out.nodes[0].map, "city map path");
		assertEq("poi_30", out.nodes[1].id, "poi node id");
		assertEq(false, Reflect.hasField(out.nodes[1], "map"), "unassigned poi map field");
		assertEq("GoldenAge", out.editor_meta.generator_params.seed, "meta params");
		assertEq("/tmp/port_royal.ldtk", out.editor_meta.local_ldtk_paths.city_1, "meta local path");

		var raw = Json.stringify(out);
		if( raw.indexOf("\"schema_version\":1")<0 )
			throw "JSON output did not include schema_version";

		var signature = WorldMapExport.makeStateSignature(
			"golden_age",
			"Golden Age",
			"/assets/world/world_map.png",
			"city_1",
			mapData,
			params,
			assetPaths,
			localPaths
		);
		var sameSignature = WorldMapExport.makeStateSignature(
			"golden_age",
			"Golden Age",
			"/assets/world/world_map.png",
			"city_1",
			mapData,
			params,
			assetPaths,
			localPaths
		);
		assertEq(signature, sameSignature, "same world state signature");

		var changedAssets:Map<String, String> = new Map();
		changedAssets.set("city_1", "/assets/locations/changed.ldtk");
		var changedSignature = WorldMapExport.makeStateSignature(
			"golden_age",
			"Golden Age",
			"/assets/world/world_map.png",
			"city_1",
			mapData,
			params,
			changedAssets,
			localPaths
		);
		if( signature==changedSignature )
			throw "state signature did not change after map assignment changed";
	}

	static function assertEq(expected:Dynamic, actual:Dynamic, label:String) {
		if( expected!=actual )
			throw '$label expected $expected but got $actual';
	}
}
