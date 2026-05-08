package page;

import haxe.crypto.Base64;
import js.Browser;
import js.html.CanvasElement;
import js.html.Element;
import js.html.InputElement;
import js.html.MouseEvent;
import worldmap.*;

typedef WorldMapControl = {
	key:String,
	label:String,
	type:String,
	section:String,
	?min:Float,
	?max:Float,
	?step:Float,
	?tip:String,
	?border:String,
}

class WorldMapEditor extends Page {
	public static var ME:WorldMapEditor;

	var params:WorldMapParams;
	var mapData:Null<WorldMapData>;
	var renderer:Null<WorldMapRenderer>;
	var generateTimeout:Null<Int> = null;
	var selectedIslandId:Null<Int> = null;
	var showLegend = false;

	public function new() {
		super();
		ME = this;
		log("init");
		loadPageTemplate("worldMapEditor");
		App.ME.setWindowTitle("World Map Editor");

		params = WorldMapParams.loadSaved();
		log("params loaded", params.toJson());
		initControls();
		initButtons();
		initCanvas();
		generateMap();
	}

	function initControls() {
		var jForm = jPage.find(".controlsForm");
		jForm.empty();
		log("init controls");
		var currentSection = "";
		for( c in getControls() ) {
			if( c.section!=currentSection ) {
				currentSection = c.section;
				jForm.append('<div class="controlSection" data-section="${StringTools.htmlEscape(currentSection)}"><h2>${StringTools.htmlEscape(currentSection)}</h2></div>');
			}
			jForm.children().last().append(makeControlHtml(c));
		}

		jPage.find("[data-param]").on("input change", (ev:js.jquery.Event)->{
			var jInput = ev.getThis();
			var key = jInput.attr("data-param");
			var old = params.getValue(key);
			var value:Dynamic;
			if( jInput.attr("type")=="checkbox" ) {
				var input:InputElement = cast jInput.get(0);
				value = input.checked;
			}
			else
				value = jInput.val();
			params.setValue(key, value);
			updateControlValue(key);

			if( Std.string(old)!=Std.string(params.getValue(key)) ) {
				if( WorldMapParams.isGeneratorParam(key) )
					debounceGenerate();
				else if( renderer!=null ) {
					renderer.updateParams(params);
					resizeMapFrame();
				}
			}
		});

		jPage.find(".borderPreview")
			.on("mouseenter", (ev:js.jquery.Event)->{
				if( renderer!=null )
					renderer.activeBorderHighlight = ev.getThis().attr("data-border");
			})
			.on("mouseleave", (_)->{
				if( renderer!=null )
					renderer.activeBorderHighlight = null;
			});

		for( c in getControls() )
			updateControlValue(c.key);
		log("controls ready", { count:getControls().length });
	}

	function makeControlHtml(c:WorldMapControl):String {
		var value = params.getValue(c.key);
		var label = StringTools.htmlEscape(c.label);
		var border = c.border!=null ? '<button type="button" class="borderPreview" data-border="${c.border}">view</button>' : "";
		var valueHtml = c.type=="check" ? "" : '<span class="value value-${c.key}"></span>';
		var input = switch c.type {
			case "text":
				'<input type="text" data-param="${c.key}" value="${StringTools.htmlEscape(Std.string(value))}"/>';
			case "check":
				'<input type="checkbox" data-param="${c.key}" ${Std.string(value)=="true" ? "checked" : ""}/>';
			case _:
				'<input type="range" data-param="${c.key}" min="${c.min}" max="${c.max}" step="${c.step}" value="${value}"/>';
		}
		var tip = c.tip==null ? "" : '<div class="tip">${StringTools.htmlEscape(c.tip)}</div>';
		return '<div class="control control-${c.key}"><label><span>$label$border</span>$valueHtml</label>$input$tip</div>';
	}

	function updateControlValue(key:String) {
		var value = params.getValue(key);
		var text = Std.isOfType(value, Float)
			? Std.string(Math.round((value:Float)*100)/100)
			: Std.string(value);
		if( key=="resolution" )
			text = '${params.resolution} x ${Math.round(params.resolution / WorldMapParams.GOLDEN_RATIO)}';
		jPage.find('.value-$key').text(text);
		var jInput = jPage.find('[data-param="$key"]');
		if( jInput.attr("type")=="checkbox" ) {
			var input:InputElement = cast jInput.get(0);
			input.checked = Std.string(value)=="true";
		}
		else
			jInput.val(Std.string(value));
	}

	function initButtons() {
		log("init buttons");
		jPage.find(".backHome").click(_->App.ME.loadPage(()->new Home()));
		jPage.find(".generateMap").click(_->generateMap());
		jPage.find(".randomSeed").click(_->randomizeSeed());
		jPage.find(".saveSettings").click(_->{
			params.saveToLocalStorage();
			setStatus("Settings saved");
		});
		jPage.find(".resetDefaults").click(_->{
			WorldMapParams.clearSaved();
			params = WorldMapParams.defaultParams();
			for( c in getControls() )
				updateControlValue(c.key);
			setStatus("Default settings restored");
			generateMap();
		});
		jPage.find(".exportPng").click(_->exportPng());
		jPage.find(".exportJson").click(_->exportJson());
		jPage.find(".exportLocations").click(_->exportLocationsJson());
		jPage.find(".legendToggle").click(_->{
			showLegend = !showLegend;
			if( showLegend )
				jPage.find(".legend").addClass("visible");
			else
				jPage.find(".legend").removeClass("visible");
		});
		jPage.find(".fullMap").click(_->toggleFullscreen());
	}

	function initCanvas() {
		var canvas:CanvasElement = cast jPage.find("#worldMapCanvas").get(0);
		log("init canvas", { found:canvas!=null });
		renderer = new WorldMapRenderer(canvas);

		canvas.addEventListener("mousemove", (ev:MouseEvent)->{
			if( mapData==null || renderer==null )
				return;
			var p = getMapPoint(ev);
			if( p==null )
				return;
			var loc = getLocationAt(p.x, p.y);
			renderer.activeLocation = loc;
			renderer.activeIslandId = loc!=null ? null : getIslandIdAt(p.x, p.y);
		});
		canvas.addEventListener("mouseleave", (_)->{
			if( renderer!=null ) {
				renderer.activeLocation = null;
				renderer.activeIslandId = null;
			}
		});
		canvas.addEventListener("click", (ev:MouseEvent)->{
			var p = getMapPoint(ev);
			if( p==null || renderer==null )
				return;
			selectedIslandId = getIslandIdAt(p.x, p.y);
			renderer.selectedIslandId = selectedIslandId;
			updateIslandInfo();
		});
		Browser.window.addEventListener("resize", (_)->resizeMapFrame());
	}

	function debounceGenerate() {
		if( generateTimeout!=null )
			Browser.window.clearTimeout(generateTimeout);
		setStatus("Generating...");
		generateTimeout = Browser.window.setTimeout(()->generateMap(), 150);
	}

	function generateMap() {
		if( generateTimeout!=null ) {
			Browser.window.clearTimeout(generateTimeout);
			generateTimeout = null;
		}
		setStatus("Generating...");
		log("generate queued", getParamsSummary());
		Browser.window.setTimeout(()->{
			try {
				var t0 = Browser.window.performance.now();
				log("generate start", getParamsSummary());
				var generator = new WorldMapGenerator(params);
				mapData = generator.generate((msg)->{
					setStatus(msg);
					log("generate progress: "+msg);
				});
				selectedIslandId = null;
				log("generate data ready", {
					width: mapData.width,
					height: mapData.height,
					islands: mapData.islands.length,
					cities: mapData.cities.length,
					pointsOfInterest: mapData.pointsOfInterest.length,
					routes: mapData.routes.length,
					streams: mapData.streams.length,
				});
				var r = renderer;
				if( r==null ) {
					log("render skipped: missing renderer");
					return;
				}
				r.selectedIslandId = null;
				r.activeIslandId = null;
				r.activeLocation = null;
				log("render start");
				r.render(mapData, params);
				log("render done", getCanvasSummary());
				resizeMapFrame();
				log("resize done", getCanvasSummary());
				updateIslandInfo();
				var t1 = Browser.window.performance.now();
				setStatus('Generated in ${Math.round(t1-t0)}ms');
				log("generate complete", { ms:Math.round(t1-t0) });
			}
			catch( err:Dynamic ) {
				var msg = Std.string(err);
				setStatus("World map error: "+msg);
				logError("generate failed", err);
			}
		}, 10);
	}

	function resizeMapFrame() {
		if( mapData==null )
			return;
		var area:Element = cast jPage.find(".mapArea").get(0);
		var frame = jPage.find("#worldMapFrame");
		var availW = area.clientWidth - 48;
		var availH = area.clientHeight - 48;
		log("resize start", {
			areaWidth:area.clientWidth,
			areaHeight:area.clientHeight,
			availableWidth:availW,
			availableHeight:availH,
		});
		var mapRatio = mapData.width / mapData.height;
		var availRatio = availW / availH;
		if( mapRatio>availRatio ) {
			frame.width(availW);
			frame.height(availW / mapRatio);
		}
		else {
			frame.height(availH);
			frame.width(availH * mapRatio);
		}
	}

	function getMapPoint(ev:MouseEvent):Null<MapPoint> {
		if( mapData==null )
			return null;
		var canvas:CanvasElement = cast jPage.find("#worldMapCanvas").get(0);
		var rect = canvas.getBoundingClientRect();
		var x = Math.floor(((ev.clientX - rect.left) / rect.width) * mapData.width);
		var y = Math.floor(((ev.clientY - rect.top) / rect.height) * mapData.height);
		return { x:Std.int(Math.max(0, Math.min(mapData.width-1, x))), y:Std.int(Math.max(0, Math.min(mapData.height-1, y))) };
	}

	function getIslandIdAt(x:Int, y:Int):Null<Int> {
		var tile = mapData.getTile(x, y);
		return tile==null ? null : tile.islandId;
	}

	function getLocationAt(x:Int, y:Int):Null<ActiveLocation> {
		var best:Null<ActiveLocation> = null;
		var bestD = 25.;
		if( params.showSettlements )
			for( city in mapData.cities ) {
				var d = distSq(city.x+0.5, city.y+0.5, x, y);
				if( d<=bestD ) {
					bestD = d;
					best = { type:"city", id:city.id };
				}
			}
		if( params.showPointsOfInterest )
			for( point in mapData.pointsOfInterest ) {
				var d = distSq(point.x+0.5, point.y+0.5, x, y);
				if( d<=bestD ) {
					bestD = d;
					best = { type:"poi", id:point.id };
				}
			}
		return best;
	}

	function updateIslandInfo() {
		var jInfo = jPage.find(".islandInfo");
		if( selectedIslandId==null || mapData==null ) {
			jInfo.hide().empty();
			return;
		}
		for( island in mapData.islands )
			if( island.id==selectedIslandId ) {
				var cities = mapData.cities.filter(c -> c.islandId==island.id).length;
				var points = mapData.pointsOfInterest.filter(p -> p.islandId==island.id).length;
				var area = island.tiles.length * params.kmPerTile * params.kmPerTile;
				jInfo.html('<strong>${StringTools.htmlEscape(island.name)}</strong><br/>Area: ${round2(area)} km2 &nbsp; Cities: $cities &nbsp; POI: $points').show();
				return;
			}
		jInfo.hide().empty();
	}

	function randomizeSeed() {
		var words = ["PIRATE", "SAIL", "RUM", "ISLAND", "GOLD", "CANNON", "WIND", "SKULL", "BONE", "TIDE", "STORM", "CURSE"];
		var r1 = words[Math.floor(Math.random()*words.length)];
		var r2 = words[Math.floor(Math.random()*words.length)];
		var num = Math.floor(Math.random()*9999);
		params.seed = '${r1}_${r2}_${num}';
		updateControlValue("seed");
		debounceGenerate();
	}

	function exportPng() {
		if( mapData==null )
			return;
		var dir = App.ME.settings.getUiDir("WorldMapEditor", App.ME.getDefaultDialogDir());
		dn.js.ElectronDialogs.saveFileAs([".png"], dir + "/ripped_sails_" + sanitizeFileName(params.seed) + ".png", (filePath)->{
			if( filePath==null )
				return;
			var fp = dn.FilePath.fromFile(filePath);
			fp.extension = "png";
			App.ME.settings.storeUiDir("WorldMapEditor", fp.directory);
			var canvas:CanvasElement = cast jPage.find("#worldMapCanvas").get(0);
			var dataUrl = canvas.toDataURL("image/png");
			var comma = dataUrl.indexOf(",");
			if( comma<0 ) {
				N.error("PNG export failed");
				return;
			}
			NT.writeFileBytes(fp.full, Base64.decode(dataUrl.substr(comma+1)));
			N.success("World map PNG exported", fp.fileWithExt);
		});
	}

	function exportJson() {
		if( mapData==null )
			return;
		saveJson("map_" + sanitizeFileName(params.seed) + ".json", haxe.Json.stringify(makeFullExport(), null, "  "), "World map JSON exported");
	}

	function exportLocationsJson() {
		if( mapData==null )
			return;
		saveJson("locations_" + sanitizeFileName(params.seed) + ".json", haxe.Json.stringify(makeLocationsExport(), null, "  "), "World locations JSON exported");
	}

	function saveJson(fileName:String, raw:String, success:String) {
		var dir = App.ME.settings.getUiDir("WorldMapEditor", App.ME.getDefaultDialogDir());
		dn.js.ElectronDialogs.saveFileAs([".json"], dir + "/" + fileName, (filePath)->{
			if( filePath==null )
				return;
			var fp = dn.FilePath.fromFile(filePath);
			fp.extension = "json";
			App.ME.settings.storeUiDir("WorldMapEditor", fp.directory);
			NT.writeFileString(fp.full, raw);
			N.success(success, fp.fileWithExt);
		});
	}

	function makeFullExport():Dynamic {
		var islands = [
			for( island in mapData.islands ) {
				id: island.id,
				name: island.name,
				bounds: island.bounds,
				center: island.center,
				areaKm2: round2(island.tiles.length * params.kmPerTile * params.kmPerTile),
				cityCount: mapData.cities.filter(city -> city.islandId==island.id).length,
				poiCount: mapData.pointsOfInterest.filter(poi -> poi.islandId==island.id).length,
			}
		];
		var tiles = [
			for( t in mapData.tiles ) {
				e: round2(t.elevation),
				m: round2(t.moisture),
				t: (t.terrain:Int),
				n: t.isNavigable ? 1 : 0,
				w: t.walkable ? 1 : 0,
				i: t.islandId,
			}
		];
		return {
			width: mapData.width,
			height: mapData.height,
			params: params.toJson(),
			streams: mapData.streams,
			islands: islands,
			cities: mapData.cities,
			pointsOfInterest: mapData.pointsOfInterest,
			routes: mapData.routes,
			tiles: tiles,
		};
	}

	function makeLocationsExport():Dynamic {
		return {
			seed: params.seed,
			width: mapData.width,
			height: mapData.height,
			cities: [for( city in mapData.cities ) {
				id: city.id,
				name: city.name,
				x: city.x,
				y: city.y,
				kind: city.kind,
				populationTier: city.populationTier,
			}],
			pointsOfInterest: [for( point in mapData.pointsOfInterest ) {
				id: point.id,
				name: point.name,
				x: point.x,
				y: point.y,
				kind: point.kind,
			}],
		};
	}

	function toggleFullscreen() {
		var area:Element = cast jPage.find(".mapArea").get(0);
		if( untyped Browser.document.fullscreenElement==null )
			untyped area.requestFullscreen();
		else
			untyped Browser.document.exitFullscreen();
	}

	function setStatus(msg:String) {
		jPage.find(".status, .bottomStatus").text(msg);
	}

	function getParamsSummary():Dynamic {
		return {
			seed: params.seed,
			resolution: params.resolution,
			enableRoutes: params.enableRoutes,
			routeDensity: params.routeDensity,
			routeMaxDistanceKm: params.routeMaxDistanceKm,
			enableStreams: params.enableStreams,
			showClouds: params.showClouds,
		};
	}

	function getCanvasSummary():Dynamic {
		var canvas:CanvasElement = cast jPage.find("#worldMapCanvas").get(0);
		var frame = jPage.find("#worldMapFrame");
		var area:Element = cast jPage.find(".mapArea").get(0);
		return {
			canvasWidth: canvas==null ? -1 : canvas.width,
			canvasHeight: canvas==null ? -1 : canvas.height,
			frameWidth: frame.width(),
			frameHeight: frame.height(),
			areaWidth: area==null ? -1 : area.clientWidth,
			areaHeight: area==null ? -1 : area.clientHeight,
		};
	}

	static function log(msg:String, ?data:Dynamic) {
		if( data==null )
			Browser.console.log("[WorldMapEditor] "+msg);
		else
			Browser.console.log("[WorldMapEditor] "+msg, data);
	}

	static function logError(msg:String, err:Dynamic) {
		Browser.console.error("[WorldMapEditor] "+msg, err);
	}

	override function onAppResize() {
		super.onAppResize();
		resizeMapFrame();
	}

	override function onDispose() {
		if( generateTimeout!=null )
			Browser.window.clearTimeout(generateTimeout);
		if( renderer!=null )
			renderer.dispose();
		if( ME==this )
			ME = null;
		super.onDispose();
	}

	static inline function distSq(x1:Float, y1:Float, x2:Float, y2:Float):Float {
		var dx = x1-x2;
		var dy = y1-y2;
		return dx*dx + dy*dy;
	}

	static inline function round2(v:Float):Float return Math.round(v*100)/100;
	static function sanitizeFileName(v:String):String return ~/[^a-z0-9_\-]+/ig.replace(v, "_");

	static function getControls():Array<WorldMapControl> {
		return [
			{ section:"General", key:"seed", label:"Seed", type:"text" },
			{ section:"General", key:"resolution", label:"Map Resolution", type:"range", min:128, max:1536, step:32, tip:"Width; height uses golden ratio." },
			{ section:"Island Layout", key:"clusters", label:"Clusters", type:"range", min:1, max:10, step:1 },
			{ section:"Island Layout", key:"largeIslands", label:"Large Landmasses", type:"range", min:0, max:4, step:1 },
			{ section:"Island Layout", key:"medIslands", label:"Medium Islands", type:"range", min:0, max:15, step:1 },
			{ section:"Island Layout", key:"smallIslands", label:"Small Islands", type:"range", min:10, max:100, step:1 },
			{ section:"Island Layout", key:"caribbeanness", label:"Caribbeanness", type:"range", min:0, max:1, step:0.05 },
			{ section:"Terrain", key:"seaLevel", label:"Sea Level", type:"range", min:0.1, max:0.9, step:0.05 },
			{ section:"Terrain", key:"coastIrregularity", label:"Coast Irregularity", type:"range", min:0, max:1, step:0.05 },
			{ section:"Terrain", key:"forestDensity", label:"Forest Density", type:"range", min:0, max:1, step:0.05 },
			{ section:"Terrain", key:"mountainIntensity", label:"Mountain Coverage", type:"range", min:0, max:1, step:0.05 },
			{ section:"Terrain", key:"mountainSteepness", label:"Mountain Steepness", type:"range", min:0, max:1, step:0.05 },
			{ section:"Terrain", key:"beachWidth", label:"Beach Width", type:"range", min:0, max:0.2, step:0.01 },
			{ section:"Terrain", key:"reefFreq", label:"Reef Frequency", type:"range", min:0, max:1, step:0.05 },
			{ section:"Streams", key:"enableStreams", label:"Generate Streams", type:"check" },
			{ section:"Streams", key:"showStreams", label:"Show Streams", type:"check" },
			{ section:"Streams", key:"streamCount", label:"Stream Count", type:"range", min:0, max:16, step:1 },
			{ section:"Streams", key:"streamMeander", label:"Stream Meander", type:"range", min:0, max:1, step:0.05 },
			{ section:"Streams", key:"streamTributaries", label:"Tributaries", type:"range", min:0, max:3, step:1 },
			{ section:"Streams", key:"streamSourceBias", label:"Edge Source Bias", type:"range", min:0, max:1, step:0.05 },
			{ section:"Cities and POI", key:"enableSettlements", label:"Generate Cities", type:"check" },
			{ section:"Cities and POI", key:"enablePointsOfInterest", label:"Generate POI", type:"check" },
			{ section:"Cities and POI", key:"showSettlements", label:"Show Cities", type:"check" },
			{ section:"Cities and POI", key:"showPointsOfInterest", label:"Show POI", type:"check" },
			{ section:"Cities and POI", key:"kmPerTile", label:"Km Per Tile", type:"range", min:0.1, max:2, step:0.1 },
			{ section:"Cities and POI", key:"coastalLocationMinDistanceKm", label:"Min Location Distance", type:"range", min:0.5, max:20, step:0.5 },
			{ section:"Cities and POI", key:"cityDensity", label:"City Density", type:"range", min:0, max:2, step:0.05 },
			{ section:"Cities and POI", key:"poiDensity", label:"POI Density", type:"range", min:0, max:2, step:0.05 },
			{ section:"Sea Routes", key:"enableRoutes", label:"Generate Routes", type:"check" },
			{ section:"Sea Routes", key:"showRoutes", label:"Show Routes", type:"check" },
			{ section:"Sea Routes", key:"routeMaxDistanceKm", label:"Max Route Distance", type:"range", min:5, max:120, step:5 },
			{ section:"Sea Routes", key:"routeDensity", label:"Route Density", type:"range", min:0, max:2, step:0.05 },
			{ section:"Sea Routes", key:"routeHubBias", label:"Prefer Hubs", type:"range", min:0, max:1, step:0.05 },
			{ section:"Sea Routes", key:"routeMinConnections", label:"Min Connections", type:"range", min:1, max:3, step:1 },
			{ section:"Sea Routes", key:"routeMaxConnections", label:"Max Connections", type:"range", min:2, max:8, step:1 },
			{ section:"Continental Borders", key:"contNorth", label:"North Border", type:"range", min:0, max:1, step:0.05, border:"north" },
			{ section:"Continental Borders", key:"contNorthAttach", label:"Attach North", type:"check" },
			{ section:"Continental Borders", key:"contNorthMountain", label:"North Mountains", type:"range", min:0, max:1, step:0.05 },
			{ section:"Continental Borders", key:"contNorthSteepness", label:"North Steepness", type:"range", min:0, max:1, step:0.05 },
			{ section:"Continental Borders", key:"contSouth", label:"South Border", type:"range", min:0, max:1, step:0.05, border:"south" },
			{ section:"Continental Borders", key:"contSouthAttach", label:"Attach South", type:"check" },
			{ section:"Continental Borders", key:"contSouthMountain", label:"South Mountains", type:"range", min:0, max:1, step:0.05 },
			{ section:"Continental Borders", key:"contSouthSteepness", label:"South Steepness", type:"range", min:0, max:1, step:0.05 },
			{ section:"Continental Borders", key:"contEast", label:"East Border", type:"range", min:0, max:1, step:0.05, border:"east" },
			{ section:"Continental Borders", key:"contEastAttach", label:"Attach East", type:"check" },
			{ section:"Continental Borders", key:"contEastMountain", label:"East Mountains", type:"range", min:0, max:1, step:0.05 },
			{ section:"Continental Borders", key:"contEastSteepness", label:"East Steepness", type:"range", min:0, max:1, step:0.05 },
			{ section:"Continental Borders", key:"contWest", label:"West Border", type:"range", min:0, max:1, step:0.05, border:"west" },
			{ section:"Continental Borders", key:"contWestAttach", label:"Attach West", type:"check" },
			{ section:"Continental Borders", key:"contWestMountain", label:"West Mountains", type:"range", min:0, max:1, step:0.05 },
			{ section:"Continental Borders", key:"contWestSteepness", label:"West Steepness", type:"range", min:0, max:1, step:0.05 },
			{ section:"Smoothing", key:"smoothTerrain", label:"Terrain Smoothing", type:"check" },
			{ section:"Smoothing", key:"smoothTerrainStrength", label:"Smoothing Strength", type:"range", min:1, max:10, step:1 },
			{ section:"Smoothing", key:"blurElevation", label:"Elevation Blur", type:"check" },
			{ section:"Smoothing", key:"blurElevationStrength", label:"Blur Strength", type:"range", min:1, max:5, step:1 },
			{ section:"Rendering", key:"enableShadows", label:"Enable Shadows", type:"check" },
			{ section:"Rendering", key:"ditherShadows", label:"Dither Shadows", type:"check" },
			{ section:"Rendering", key:"shadowIntensity", label:"Shadow Intensity", type:"range", min:0, max:2, step:0.1 },
			{ section:"Rendering", key:"shadowAlpha", label:"Shadow Alpha", type:"range", min:0, max:1, step:0.05 },
			{ section:"Rendering", key:"lightAngleDeg", label:"Light Angle", type:"range", min:0, max:360, step:5 },
			{ section:"Rendering", key:"saturation", label:"Saturation", type:"range", min:0, max:2, step:0.1 },
			{ section:"Rendering", key:"sepia", label:"Sepia", type:"range", min:0, max:1, step:0.05 },
			{ section:"Rendering", key:"vignette", label:"Vignette", type:"range", min:0, max:1, step:0.05 },
			{ section:"Rendering", key:"scanlines", label:"CRT Effect", type:"range", min:0, max:0.5, step:0.05 },
			{ section:"Rendering", key:"showClouds", label:"Show Clouds", type:"check" },
			{ section:"Rendering", key:"showHeightMap", label:"Show Height Map", type:"check" },
			{ section:"Rendering", key:"showCartographicLines", label:"Cartographic Lines", type:"check" },
			{ section:"Rendering", key:"cloudDensity", label:"Cloud Density", type:"range", min:0.1, max:2, step:0.1 },
			{ section:"Rendering", key:"windSpeed", label:"Wind Speed", type:"range", min:0.1, max:3, step:0.1 },
		];
	}
}
