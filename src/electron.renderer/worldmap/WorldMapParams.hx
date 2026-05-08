package worldmap;

import haxe.DynamicAccess;

class WorldMapParams {
	public static inline var GOLDEN_RATIO = 1.6180339887;
	public static inline var SAVED_SETTINGS_KEY = "archipelago-generator-settings";

	public var seed:String = "GoldenAge";
	public var resolution:Int = 256;
	public var clusters:Int = 4;
	public var largeIslands:Int = 2;
	public var medIslands:Int = 8;
	public var smallIslands:Int = 40;
	public var seaLevel:Float = 0.55;
	public var coastIrregularity:Float = 0.6;
	public var forestDensity:Float = 0.5;
	public var mountainIntensity:Float = 0.4;
	public var mountainSteepness:Float = 0.5;
	public var beachWidth:Float = 0.04;
	public var reefFreq:Float = 0.5;
	public var enableStreams:Bool = true;
	public var showStreams:Bool = true;
	public var streamCount:Int = 6;
	public var streamMeander:Float = 0.45;
	public var streamTributaries:Int = 1;
	public var streamSourceBias:Float = 0.55;
	public var enableSettlements:Bool = true;
	public var enablePointsOfInterest:Bool = true;
	public var showSettlements:Bool = true;
	public var showPointsOfInterest:Bool = true;
	public var kmPerTile:Float = 0.5;
	public var coastalLocationMinDistanceKm:Float = 2.5;
	public var cityDensity:Float = 0.7;
	public var poiDensity:Float = 0.8;
	public var enableRoutes:Bool = true;
	public var showRoutes:Bool = true;
	public var routeMaxDistanceKm:Float = 35;
	public var routeDensity:Float = 0.65;
	public var routeHubBias:Float = 0.6;
	public var routeMinConnections:Int = 1;
	public var routeMaxConnections:Int = 4;
	public var caribbeanness:Float = 0.8;
	public var contNorth:Float = 0.0;
	public var contSouth:Float = 0.7;
	public var contEast:Float = 0.0;
	public var contWest:Float = 0.7;
	public var contNorthMountain:Float = 0.4;
	public var contSouthMountain:Float = 0.4;
	public var contEastMountain:Float = 0.4;
	public var contWestMountain:Float = 0.4;
	public var contNorthSteepness:Float = 0.5;
	public var contSouthSteepness:Float = 0.5;
	public var contEastSteepness:Float = 0.5;
	public var contWestSteepness:Float = 0.5;
	public var contNorthAttach:Bool = false;
	public var contSouthAttach:Bool = true;
	public var contEastAttach:Bool = false;
	public var contWestAttach:Bool = true;
	public var smoothTerrain:Bool = true;
	public var smoothTerrainStrength:Int = 2;
	public var blurElevation:Bool = true;
	public var blurElevationStrength:Int = 1;
	public var enableShadows:Bool = true;
	public var ditherShadows:Bool = true;
	public var shadowIntensity:Float = 1.1;
	public var shadowAlpha:Float = 0.4;
	public var lightAngleDeg:Float = 315;
	public var saturation:Float = 1.0;
	public var sepia:Float = 0.0;
	public var vignette:Float = 0.0;
	public var scanlines:Float = 0.0;
	public var showClouds:Bool = true;
	public var showHeightMap:Bool = false;
	public var showCartographicLines:Bool = true;
	public var cloudDensity:Float = 1.0;
	public var windSpeed:Float = 1.0;

	public function new() {}

	public function clone():WorldMapParams {
		var p = new WorldMapParams();
		p.applyDynamic(toJson());
		return p;
	}

	public static function defaultParams():WorldMapParams {
		return new WorldMapParams();
	}

	public static function loadSaved():WorldMapParams {
		var p = defaultParams();
		try {
			var raw = js.Browser.window.localStorage.getItem(SAVED_SETTINGS_KEY);
			if( raw!=null && raw.length>0 )
				p.applyDynamic(haxe.Json.parse(raw));
		}
		catch(_) {}
		return p;
	}

	public function saveToLocalStorage() {
		js.Browser.window.localStorage.setItem(SAVED_SETTINGS_KEY, haxe.Json.stringify(toJson()));
	}

	public static function clearSaved() {
		js.Browser.window.localStorage.removeItem(SAVED_SETTINGS_KEY);
	}

	public function getValue(name:String):Dynamic {
		return Reflect.field(this, name);
	}

	public function setValue(name:String, value:Dynamic) {
		switch name {
			case "seed":
				seed = Std.string(value);

			case "resolution", "clusters", "largeIslands", "medIslands", "smallIslands", "streamCount", "streamTributaries", "routeMinConnections", "routeMaxConnections", "smoothTerrainStrength", "blurElevationStrength":
				Reflect.setField(this, name, Std.int(parseFloat(value, Reflect.field(this, name))));

			case "enableStreams", "showStreams", "enableSettlements", "enablePointsOfInterest", "showSettlements", "showPointsOfInterest", "enableRoutes", "showRoutes", "contNorthAttach", "contSouthAttach", "contEastAttach", "contWestAttach", "smoothTerrain", "blurElevation", "enableShadows", "ditherShadows", "showClouds", "showHeightMap", "showCartographicLines":
				Reflect.setField(this, name, value==true || Std.string(value)=="true");

			case _:
				Reflect.setField(this, name, parseFloat(value, Reflect.field(this, name)));
		}

		clamp();
	}

	public function applyDynamic(raw:Dynamic) {
		if( raw==null )
			return;
		for( name in Reflect.fields(toJson()) )
			if( Reflect.hasField(raw, name) )
				setValue(name, Reflect.field(raw, name));
	}

	public static function isGeneratorParam(name:String):Bool {
		return switch name {
			case "seed", "resolution", "clusters", "largeIslands", "medIslands", "smallIslands",
				"seaLevel", "coastIrregularity", "forestDensity", "mountainIntensity", "mountainSteepness",
				"beachWidth", "reefFreq", "enableStreams", "streamCount", "streamMeander", "streamTributaries", "streamSourceBias",
				"enableSettlements", "enablePointsOfInterest", "kmPerTile", "coastalLocationMinDistanceKm", "cityDensity", "poiDensity",
				"enableRoutes", "routeMaxDistanceKm", "routeDensity", "routeHubBias", "routeMinConnections", "routeMaxConnections",
				"caribbeanness", "contNorth", "contSouth", "contEast", "contWest",
				"contNorthMountain", "contSouthMountain", "contEastMountain", "contWestMountain",
				"contNorthSteepness", "contSouthSteepness", "contEastSteepness", "contWestSteepness",
				"contNorthAttach", "contSouthAttach", "contEastAttach", "contWestAttach",
				"smoothTerrain", "smoothTerrainStrength", "blurElevation", "blurElevationStrength":
				true;
			case _:
				false;
		}
	}

	public function toJson():DynamicAccess<Dynamic> {
		var o:DynamicAccess<Dynamic> = {};
		for( name in [
			"seed", "resolution", "clusters", "largeIslands", "medIslands", "smallIslands",
			"seaLevel", "coastIrregularity", "forestDensity", "mountainIntensity", "mountainSteepness", "beachWidth", "reefFreq",
			"enableStreams", "showStreams", "streamCount", "streamMeander", "streamTributaries", "streamSourceBias",
			"enableSettlements", "enablePointsOfInterest", "showSettlements", "showPointsOfInterest", "kmPerTile", "coastalLocationMinDistanceKm", "cityDensity", "poiDensity",
			"enableRoutes", "showRoutes", "routeMaxDistanceKm", "routeDensity", "routeHubBias", "routeMinConnections", "routeMaxConnections",
			"caribbeanness", "contNorth", "contSouth", "contEast", "contWest",
			"contNorthMountain", "contSouthMountain", "contEastMountain", "contWestMountain",
			"contNorthSteepness", "contSouthSteepness", "contEastSteepness", "contWestSteepness",
			"contNorthAttach", "contSouthAttach", "contEastAttach", "contWestAttach",
			"smoothTerrain", "smoothTerrainStrength", "blurElevation", "blurElevationStrength",
			"enableShadows", "ditherShadows", "shadowIntensity", "shadowAlpha", "lightAngleDeg",
			"saturation", "sepia", "vignette", "scanlines", "showClouds", "showHeightMap", "showCartographicLines", "cloudDensity", "windSpeed"
		])
			o.set(name, Reflect.field(this, name));
		return o;
	}

	function clamp() {
		resolution = clampInt(resolution, 128, 1536);
		clusters = clampInt(clusters, 1, 10);
		largeIslands = clampInt(largeIslands, 0, 4);
		medIslands = clampInt(medIslands, 0, 15);
		smallIslands = clampInt(smallIslands, 10, 100);
		streamCount = clampInt(streamCount, 0, 16);
		streamTributaries = clampInt(streamTributaries, 0, 3);
		routeMinConnections = clampInt(routeMinConnections, 1, 3);
		routeMaxConnections = clampInt(routeMaxConnections, 2, 8);
		smoothTerrainStrength = clampInt(smoothTerrainStrength, 1, 10);
		blurElevationStrength = clampInt(blurElevationStrength, 1, 5);
		seaLevel = clampFloat(seaLevel, 0.1, 0.9);
		coastIrregularity = clamp01(coastIrregularity);
		forestDensity = clamp01(forestDensity);
		mountainIntensity = clamp01(mountainIntensity);
		mountainSteepness = clamp01(mountainSteepness);
		beachWidth = clampFloat(beachWidth, 0, 0.2);
		reefFreq = clamp01(reefFreq);
		streamMeander = clamp01(streamMeander);
		streamSourceBias = clamp01(streamSourceBias);
		kmPerTile = clampFloat(kmPerTile, 0.1, 2);
		coastalLocationMinDistanceKm = clampFloat(coastalLocationMinDistanceKm, 0.5, 20);
		cityDensity = clampFloat(cityDensity, 0, 2);
		poiDensity = clampFloat(poiDensity, 0, 2);
		routeMaxDistanceKm = clampFloat(routeMaxDistanceKm, 5, 120);
		routeDensity = clampFloat(routeDensity, 0, 2);
		routeHubBias = clamp01(routeHubBias);
		caribbeanness = clamp01(caribbeanness);
		contNorth = clamp01(contNorth);
		contSouth = clamp01(contSouth);
		contEast = clamp01(contEast);
		contWest = clamp01(contWest);
		contNorthMountain = clamp01(contNorthMountain);
		contSouthMountain = clamp01(contSouthMountain);
		contEastMountain = clamp01(contEastMountain);
		contWestMountain = clamp01(contWestMountain);
		contNorthSteepness = clamp01(contNorthSteepness);
		contSouthSteepness = clamp01(contSouthSteepness);
		contEastSteepness = clamp01(contEastSteepness);
		contWestSteepness = clamp01(contWestSteepness);
		shadowIntensity = clampFloat(shadowIntensity, 0, 2);
		shadowAlpha = clamp01(shadowAlpha);
		lightAngleDeg = clampFloat(lightAngleDeg, 0, 360);
		saturation = clampFloat(saturation, 0, 2);
		sepia = clamp01(sepia);
		vignette = clamp01(vignette);
		scanlines = clampFloat(scanlines, 0, 0.5);
		cloudDensity = clampFloat(cloudDensity, 0.1, 2);
		windSpeed = clampFloat(windSpeed, 0.1, 3);
	}

	static function parseFloat(value:Dynamic, fallback:Dynamic):Float {
		var f = Std.parseFloat(Std.string(value));
		return Math.isNaN(f) ? Std.parseFloat(Std.string(fallback)) : f;
	}

	static inline function clamp01(v:Float) return clampFloat(v, 0, 1);
	static inline function clampFloat(v:Float, min:Float, max:Float) return Math.max(min, Math.min(max, v));
	static inline function clampInt(v:Int, min:Int, max:Int) return Std.int(Math.max(min, Math.min(max, v)));
}
