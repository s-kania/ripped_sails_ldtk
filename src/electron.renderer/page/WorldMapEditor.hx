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

typedef WorldMapLocationInfo = {
	nodeId:String,
	name:String,
	type:String,
	x:Int,
	y:Int,
	kind:String,
}

class WorldMapEditor extends Page {
	static inline var WORLD_MAP_EXPORT_FORMAT = "ripped-sails-world-map";
	static inline var WORLD_MAP_EXPORT_VERSION = 1;
	static inline var WORLD_MAP_DRAFT_KEY = "ripped-sails-world-map-draft";
	static inline var WORLD_MAP_IMAGE_ASSET_PATH = "/assets/world/world_map.png";
	static inline var LOCATION_ASSET_PREFIX = "/assets/locations/";

	public static var ME:WorldMapEditor;

	var params:WorldMapParams;
	var mapData:Null<WorldMapData>;
	var renderer:Null<WorldMapRenderer>;
	var generateTimeout:Null<Int> = null;
	var selectedIslandId:Null<Int> = null;
	var selectedLocation:Null<ActiveLocation> = null;
	var startNodeId:Null<String> = null;
	var worldId = "golden_age";
	var worldName = "Golden Age";
	var locationAssetPaths:Map<String, String> = new Map();
	var locationLocalPaths:Map<String, String> = new Map();
	var lastExportSignature:Null<String> = null;
	var lastDraftSignature:Null<String> = null;
	var syncExportSignatureAfterNextGenerate = false;
	var showLegend = false;
	var worldLoaded = false;

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
		initOpeningScreen();
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
			var old = getControlValue(key);
			var value:Dynamic;
			if( jInput.attr("type")=="checkbox" ) {
				var input:InputElement = cast jInput.get(0);
				value = input.checked;
			}
			else
				value = jInput.val();
			setControlValue(key, value);
			updateControlValue(key);

			if( Std.string(old)!=Std.string(getControlValue(key)) ) {
				if( WorldMapParams.isGeneratorParam(key) )
					debounceGenerate();
				else if( renderer!=null ) {
					renderer.updateParams(params);
					resizeMapFrame();
				}
				saveDraftState();
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
		var value = getControlValue(c.key);
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
		var value = getControlValue(key);
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

	function getControlValue(key:String):Dynamic {
		return switch key {
			case "worldId": worldId;
			case "worldName": worldName;
			case _: params.getValue(key);
		}
	}

	function setControlValue(key:String, value:Dynamic) {
		switch key {
			case "worldId":
				worldId = sanitizeWorldId(Std.string(value));
			case "worldName":
				worldName = Std.string(value);
			case _:
				params.setValue(key, value);
		}
	}

	function initButtons() {
		log("init buttons");
		jPage.find(".backHome").click(_->App.ME.loadPage(()->new Home()));
		jPage.find(".generateMap").click(_->generateMap());
		jPage.find(".randomSeed").click(_->randomizeSeed());
		jPage.find(".saveSettings").click(_->{
			params.saveToLocalStorage();
			saveDraftState();
			setStatus("Settings saved");
		});
		jPage.find(".resetDefaults").click(_->{
			WorldMapParams.clearSaved();
				params = WorldMapParams.defaultParams();
				worldId = "golden_age";
				worldName = "Golden Age";
				lastExportSignature = null;
				lastDraftSignature = null;
				syncExportSignatureAfterNextGenerate = false;
				for( c in getControls() )
					updateControlValue(c.key);
			saveDraftState();
			setStatus("Default settings restored");
			generateMap();
		});
		jPage.find(".exportWorld").click(_->exportWorld());
		jPage.find(".legendToggle").click(_->{
			showLegend = !showLegend;
			if( showLegend )
				jPage.find(".legend").addClass("visible");
			else
				jPage.find(".legend").removeClass("visible");
		});
		jPage.find(".fullMap").click(_->toggleFullscreen());
		initLocationPopup();
	}

	function initOpeningScreen() {
		jPage.find(".newWorld").click(_->startNewWorld());
		jPage.find(".openWorld").click(_->openWorldFile());
		if( hasDraftState() )
			jPage.find(".resumeDraftWorld").show().click(_->resumeDraftWorld());
		else
			jPage.find(".resumeDraftWorld").hide();

		var recentFile = App.ME.settings.getUiDir("WorldMapEditorFile", null);
		if( recentFile!=null && NT.fileExists(recentFile) ) {
			var fp = dn.FilePath.fromFile(recentFile);
			jPage.find(".openRecentWorld").show().click(_->loadWorldFromFile(recentFile));
			jPage.find(".recentWorldInfo").show().html('<em>Recent: ${StringTools.htmlEscape(fp.fileWithExt)}</em>');
		}
		else {
			jPage.find(".openRecentWorld").hide();
			jPage.find(".recentWorldInfo").hide().empty();
		}
	}

	function startNewWorld() {
		params = WorldMapParams.loadSaved();
		worldId = "golden_age";
		worldName = "Golden Age";
		startNodeId = null;
		selectedLocation = null;
		selectedIslandId = null;
		locationAssetPaths = new Map();
		locationLocalPaths = new Map();
		lastExportSignature = null;
		lastDraftSignature = null;
		syncExportSignatureAfterNextGenerate = false;
		clearDraftState();
		updateAllControlValues();
		revealEditor();
		generateMap();
	}

	function resumeDraftWorld() {
		if( !loadDraftState() ) {
			setStatus("No draft found");
			return;
		}
		updateAllControlValues();
		revealEditor();
		generateMap();
	}

	function openWorldFile() {
		var dir = App.ME.settings.getUiDir("WorldMapEditor", App.ME.getDefaultDialogDir());
		dn.js.ElectronDialogs.openFile([".json"], dir, (filePath)->{
			if( filePath==null )
				return;
			loadWorldFromFile(filePath);
		});
	}

	function loadWorldFromFile(path:String) {
		try {
			var raw = NT.readFileString(path);
			var json:Dynamic = haxe.Json.parse(raw);
			if( json==null )
				throw "Missing JSON data";

			var loadedParams = WorldMapParams.defaultParams();
				locationAssetPaths = new Map();
				locationLocalPaths = new Map();
				lastExportSignature = null;
				lastDraftSignature = null;
				syncExportSignatureAfterNextGenerate = false;
				selectedLocation = null;
				selectedIslandId = null;

			if( Reflect.field(json, "schema_version")==WorldMapExport.SCHEMA_VERSION ) {
				worldId = readStringField(json, "id", "golden_age");
				worldName = readStringField(json, "name", "Golden Age");
				startNodeId = readNullableStringField(json, "start_node_id");
				var nodes:Array<Dynamic> = cast Reflect.field(json, "nodes");
				if( nodes!=null )
					for( node in nodes ) {
						var nodeId = readNullableStringField(node, "id");
						var mapPath = readNullableStringField(node, "map");
						if( nodeId!=null && mapPath!=null )
							locationAssetPaths.set(nodeId, mapPath);
					}

				var editorMeta = Reflect.field(json, "editor_meta");
					if( editorMeta!=null ) {
						loadedParams.applyDynamic(Reflect.field(editorMeta, "generator_params"));
						locationLocalPaths = readStringMap(Reflect.field(editorMeta, "local_ldtk_paths"));
					}
					syncExportSignatureAfterNextGenerate = true;
				}
			else {
				if( Reflect.field(json, "format")!=WORLD_MAP_EXPORT_FORMAT )
					throw "Unsupported world map JSON format";
				if( Reflect.field(json, "version")!=WORLD_MAP_EXPORT_VERSION )
					throw "Unsupported world map JSON version";
				if( !Reflect.hasField(json, "params") || Reflect.field(json, "params")==null )
					throw "Missing top-level params object";
				loadedParams.applyDynamic(Reflect.field(json, "params"));
				worldId = "golden_age";
				worldName = "Golden Age";
				startNodeId = null;
			}

			params = loadedParams;
			updateAllControlValues();
			rememberWorldFile(path);
			revealEditor();
			saveDraftState();
			generateMap();
		}
		catch( err:Dynamic ) {
			logError("load failed", err);
			setStatus("World map load failed");
			N.error("World map JSON load failed: " + Std.string(err));
		}
	}

	function rememberWorldFile(path:String) {
		var fp = dn.FilePath.fromFile(path);
		App.ME.settings.storeUiDir("WorldMapEditor", fp.directory);
		App.ME.settings.storeUiDir("WorldMapEditorFile", fp.full);
	}

	function revealEditor() {
		worldLoaded = true;
		jPage.find(".worldMapOpening").hide();
		jPage.find(".worldMapEditorBody").addClass("active");
		jPage.find(".worldMapActions").addClass("active");
	}

	function updateAllControlValues() {
		for( c in getControls() )
			updateControlValue(c.key);
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
			renderer.activeLocation = loc!=null ? loc : selectedLocation;
			renderer.activeIslandId = loc!=null || selectedLocation!=null ? null : getIslandIdAt(p.x, p.y);
		});
		canvas.addEventListener("mouseleave", (_)->{
			if( renderer!=null ) {
				renderer.activeLocation = selectedLocation;
				renderer.activeIslandId = null;
			}
		});
		canvas.addEventListener("click", (ev:MouseEvent)->{
			var p = getMapPoint(ev);
			if( p==null || renderer==null )
				return;
			var loc = getLocationAt(p.x, p.y);
			if( loc!=null ) {
				selectedLocation = loc;
				selectedIslandId = null;
			}
			else {
				selectedLocation = null;
				selectedIslandId = getIslandIdAt(p.x, p.y);
			}
			renderer.activeLocation = selectedLocation;
			renderer.selectedIslandId = selectedIslandId;
			updateIslandInfo();
			updateLocationPopup();
		});
		Browser.window.addEventListener("resize", (_)->resizeMapFrame());
	}

	function debounceGenerate() {
		if( !worldLoaded )
			return;
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
				ensureLocationStateIsValid();
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
				r.activeLocation = selectedLocation;
				log("render start");
				r.render(mapData, params);
				log("render done", getCanvasSummary());
					resizeMapFrame();
					log("resize done", getCanvasSummary());
					updateIslandInfo();
					updateLocationPopup();
					saveDraftState();
					if( syncExportSignatureAfterNextGenerate ) {
						lastExportSignature = makeCurrentWorldSignature();
						syncExportSignatureAfterNextGenerate = false;
					}
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

	function initLocationPopup() {
		jPage.find(".locationPopup .popupClose").click(_->closeLocationPopup());
		jPage.find(".createLocationMap").click(_->createSelectedLocationMap());
		jPage.find(".assignLocationMap").click(_->assignSelectedLocationMap());
		jPage.find(".relinkLocationMap").click(_->assignSelectedLocationMap());
		jPage.find(".openLocationMap").click(_->openSelectedLocationMap());
		jPage.find(".setStartLocation").click(_->setSelectedLocationAsStart());
		updateLocationPopup();
	}

	function closeLocationPopup() {
		selectedLocation = null;
		if( renderer!=null )
			renderer.activeLocation = null;
		updateLocationPopup();
	}

	function updateLocationPopup() {
		var jPopup = jPage.find(".locationPopup");
		var info = getSelectedLocationInfo();
		if( info==null ) {
			jPopup.removeClass("visible");
			return;
		}

		var assetPath = locationAssetPaths.get(info.nodeId);
		var localPath = locationLocalPaths.get(info.nodeId);
		var localExists = localPath!=null && NT.fileExists(localPath);
		var hasMap = assetPath!=null && assetPath.length>0;
		var typeLabel = info.type=="city" ? "City" : "POI";

		jPopup.find(".locationName").text(info.name);
		jPopup.find(".locationMeta").text('$typeLabel / ${info.kind} / ${info.x}, ${info.y}');
		jPopup.find(".locationNodeId").text(info.nodeId);
		if( hasMap )
			jPopup.find(".locationMapStatus").text(localExists ? 'Map: $assetPath' : 'Map: $assetPath (local file missing)');
		else
			jPopup.find(".locationMapStatus").text("Map: not assigned");

		setVisible(jPopup.find(".createLocationMap"), !hasMap);
		setVisible(jPopup.find(".openLocationMap"), localExists);
		setVisible(jPopup.find(".relinkLocationMap"), hasMap && !localExists);
		var jStart = jPopup.find(".setStartLocation");
		jStart.prop("disabled", startNodeId==info.nodeId);
		jStart.text(startNodeId==info.nodeId ? "Start node" : "Set as start");
		jPopup.addClass("visible");
	}

	function getSelectedLocationInfo():Null<WorldMapLocationInfo> {
		return selectedLocation==null ? null : getLocationInfo(cast selectedLocation);
	}

	function getLocationInfo(loc:ActiveLocation):Null<WorldMapLocationInfo> {
		if( mapData==null || loc==null )
			return null;
		if( loc.type=="city" )
			for( city in mapData.cities )
				if( city.id==loc.id )
					return {
						nodeId: WorldMapExport.getNodeId("city", city.id),
						name: city.name,
						type: "city",
						x: city.x,
						y: city.y,
						kind: city.kind,
					};
		if( loc.type=="poi" )
			for( point in mapData.pointsOfInterest )
				if( point.id==loc.id )
					return {
						nodeId: WorldMapExport.getNodeId("poi", point.id),
						name: point.name,
						type: "poi",
						x: point.x,
						y: point.y,
						kind: point.kind,
					};
		return null;
	}

	function createSelectedLocationMap() {
		var info = getSelectedLocationInfo();
		if( info==null )
			return;
		var dir = App.ME.settings.getUiDir("WorldMapLocationMap", App.ME.getDefaultDialogDir());
		var defaultPath = dir + "/" + sanitizeFileName(info.nodeId) + "." + Const.FILE_EXTENSION;
		dn.js.ElectronDialogs.saveFileAs(["."+Const.FILE_EXTENSION], defaultPath, (filePath)->{
			if( filePath==null )
				return;
			var fp = dn.FilePath.fromFile(filePath);
			fp.extension = Const.FILE_EXTENSION;
			App.ME.settings.storeUiDir("WorldMapLocationMap", fp.directory);

			var project = data.Project.createEmpty(fp.full);
			new ui.ProjectSaver(this, project, (success)->{
				if( !success ) {
					N.error("Location map creation failed");
					return;
				}
				assignLocationMap(info.nodeId, fp.full);
				saveDraftState();
				updateLocationPopup();
				N.success("Location map created", fp.fileWithExt);
			});
		});
	}

	function assignSelectedLocationMap() {
		var info = getSelectedLocationInfo();
		if( info==null )
			return;
		var curLocalPath = locationLocalPaths.get(info.nodeId);
		var dir = curLocalPath!=null ? dn.FilePath.extractDirectoryWithoutSlash(curLocalPath, true) : App.ME.settings.getUiDir("WorldMapLocationMap", App.ME.getDefaultDialogDir());
		dn.js.ElectronDialogs.openFile(["."+Const.FILE_EXTENSION], dir, (filePath)->{
			if( filePath==null )
				return;
			assignLocationMap(info.nodeId, filePath);
			saveDraftState();
			updateLocationPopup();
		});
	}

	function openSelectedLocationMap() {
		var info = getSelectedLocationInfo();
		if( info==null )
			return;
		var localPath = locationLocalPaths.get(info.nodeId);
		if( localPath==null || !NT.fileExists(localPath) ) {
			updateLocationPopup();
			return;
		}
		confirmOpenLocationMap(localPath);
	}

	function confirmOpenLocationMap(localPath:String) {
		var changesSinceExport = hasWorldChangesSinceExport();
		var changesSinceDraft = hasWorldChangesSinceDraft();
		var dialog = new ui.modal.Dialog(jPage.find(".openLocationMap"), "worldMapOpenLocation");
		dialog.addTitle(L.t._("Open location map"), true);
		dialog.addParagraph(L.t._("Before opening the LDtk location map, choose how to handle the current world draft."));
		dialog.addDiv(L.t._("Changes since export: ::state::", { state: changesSinceExport ? "yes" : "no" }), changesSinceExport ? "warning" : null);
		dialog.addDiv(L.t._("Changes since draft: ::state::", { state: changesSinceDraft ? "yes" : "no" }), changesSinceDraft ? "warning" : null);
		dialog.addButton(L.t._("Save draft and open"), "save", ()->{
			dialog.close();
			saveDraftState();
			App.ME.loadProject(localPath);
		});
		dialog.addButton(L.t._("Open without saving draft"), "gray", ()->{
			dialog.close();
			App.ME.loadProject(localPath);
		});
		dialog.addCancel();
	}

	function setSelectedLocationAsStart() {
		var info = getSelectedLocationInfo();
		if( info==null )
			return;
		startNodeId = info.nodeId;
		saveDraftState();
		updateLocationPopup();
		setStatus('Start node: ${info.nodeId}');
	}

	function assignLocationMap(nodeId:String, localPath:String) {
		var fp = dn.FilePath.fromFile(localPath);
		fp.extension = Const.FILE_EXTENSION;
		locationLocalPaths.set(nodeId, fp.full);
		locationAssetPaths.set(nodeId, LOCATION_ASSET_PREFIX + fp.fileWithExt);
		App.ME.settings.storeUiDir("WorldMapLocationMap", fp.directory);
	}

	function randomizeSeed() {
		var words = ["PIRATE", "SAIL", "RUM", "ISLAND", "GOLD", "CANNON", "WIND", "SKULL", "BONE", "TIDE", "STORM", "CURSE"];
		var r1 = words[Math.floor(Math.random()*words.length)];
		var r2 = words[Math.floor(Math.random()*words.length)];
		var num = Math.floor(Math.random()*9999);
		params.seed = '${r1}_${r2}_${num}';
		updateControlValue("seed");
		saveDraftState();
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

	function exportWorld() {
		if( mapData==null )
			return;
		var dir = App.ME.settings.getUiDir("WorldMapExport", App.ME.getDefaultDialogDir());
		dn.js.ElectronDialogs.openDir(dir, (dirPath)->{
			if( dirPath==null )
				return;
			var fp = dn.FilePath.fromDir(dirPath);
			fp.useSlashes();
			App.ME.settings.storeUiDir("WorldMapExport", fp.full);

			var pngBytes = getCanvasPngBytes();
			if( pngBytes==null ) {
				N.error("PNG export failed");
				return;
			}

			var pngPath = fp.full + "/world_map.png";
			var jsonPath = fp.full + "/world_map.json";
			NT.writeFileBytes(pngPath, pngBytes);
			NT.writeFileString(jsonPath, haxe.Json.stringify(makeRuntimeWorldExport(), null, "  "));
			lastExportSignature = makeCurrentWorldSignature();
			saveDraftState();
			rememberWorldFile(jsonPath);
			N.success("World map exported", "world_map.json + world_map.png");
		});
	}

	function exportJson() {
		if( mapData==null )
			return;
		saveJson("map_" + sanitizeFileName(params.seed) + ".json", haxe.Json.stringify(makeWorldSaveExport(), null, "  "), "World map JSON exported", true);
	}

	function exportLocationsJson() {
		if( mapData==null )
			return;
		saveJson("locations_" + sanitizeFileName(params.seed) + ".json", haxe.Json.stringify(makeLocationsExport(), null, "  "), "World locations JSON exported");
	}

	function saveJson(fileName:String, raw:String, success:String, rememberAsWorldFile=false) {
		var dir = App.ME.settings.getUiDir("WorldMapEditor", App.ME.getDefaultDialogDir());
		dn.js.ElectronDialogs.saveFileAs([".json"], dir + "/" + fileName, (filePath)->{
			if( filePath==null )
				return;
			var fp = dn.FilePath.fromFile(filePath);
			fp.extension = "json";
			App.ME.settings.storeUiDir("WorldMapEditor", fp.directory);
			NT.writeFileString(fp.full, raw);
			if( rememberAsWorldFile )
				rememberWorldFile(fp.full);
			N.success(success, fp.fileWithExt);
		});
	}

	function getCanvasPngBytes():Null<haxe.io.Bytes> {
		var canvas:CanvasElement = cast jPage.find("#worldMapCanvas").get(0);
		var dataUrl = canvas.toDataURL("image/png");
		var comma = dataUrl.indexOf(",");
		if( comma<0 )
			return null;
		return Base64.decode(dataUrl.substr(comma+1));
	}

	function makeWorldSaveExport():Dynamic {
		return {
			format: WORLD_MAP_EXPORT_FORMAT,
			version: WORLD_MAP_EXPORT_VERSION,
			params: params.toJson(),
		};
	}

	function makeRuntimeWorldExport():Dynamic {
		var cleanWorldId = sanitizeWorldId(worldId);
		return WorldMapExport.makeWorldJson(
			cleanWorldId,
			worldName.length>0 ? worldName : cleanWorldId,
			WORLD_MAP_IMAGE_ASSET_PATH,
			startNodeId,
			mapData,
			params.toJson(),
			locationAssetPaths,
			locationLocalPaths
		);
	}

	function makeCurrentWorldSignature():Null<String> {
		if( mapData==null )
			return null;
		var cleanWorldId = sanitizeWorldId(worldId);
		return WorldMapExport.makeStateSignature(
			cleanWorldId,
			worldName.length>0 ? worldName : cleanWorldId,
			WORLD_MAP_IMAGE_ASSET_PATH,
			startNodeId,
			mapData,
			params.toJson(),
			locationAssetPaths,
			locationLocalPaths
		);
	}

	function hasWorldChangesSinceExport():Bool {
		var signature = makeCurrentWorldSignature();
		return signature==null || lastExportSignature==null || signature!=lastExportSignature;
	}

	function hasWorldChangesSinceDraft():Bool {
		var signature = makeCurrentWorldSignature();
		return signature==null || lastDraftSignature==null || signature!=lastDraftSignature;
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

	function hasDraftState():Bool {
		var raw = Browser.window.localStorage.getItem(WORLD_MAP_DRAFT_KEY);
		return raw!=null && raw.length>0;
	}

	function saveDraftState() {
		try {
			var draft:Dynamic = {
				schema_version: WORLD_MAP_EXPORT_VERSION,
				world_id: worldId,
				world_name: worldName,
				start_node_id: startNodeId,
				params: params.toJson(),
				location_maps: WorldMapExport.mapToDynamic(locationAssetPaths),
				local_ldtk_paths: WorldMapExport.mapToDynamic(locationLocalPaths),
			};
			Browser.window.localStorage.setItem(WORLD_MAP_DRAFT_KEY, haxe.Json.stringify(draft));
			lastDraftSignature = makeCurrentWorldSignature();
		}
		catch( err:Dynamic ) {
			logError("draft save failed", err);
		}
	}

	function loadDraftState():Bool {
		try {
			var raw = Browser.window.localStorage.getItem(WORLD_MAP_DRAFT_KEY);
			if( raw==null || raw.length==0 )
				return false;
			var draft:Dynamic = haxe.Json.parse(raw);
			if( draft==null || Reflect.field(draft, "schema_version")!=WORLD_MAP_EXPORT_VERSION )
				return false;

			var loadedParams = WorldMapParams.defaultParams();
			loadedParams.applyDynamic(Reflect.field(draft, "params"));
			params = loadedParams;
			worldId = readStringField(draft, "world_id", "golden_age");
			worldName = readStringField(draft, "world_name", "Golden Age");
				startNodeId = readNullableStringField(draft, "start_node_id");
				locationAssetPaths = readStringMap(Reflect.field(draft, "location_maps"));
				locationLocalPaths = readStringMap(Reflect.field(draft, "local_ldtk_paths"));
				lastExportSignature = null;
				lastDraftSignature = null;
				syncExportSignatureAfterNextGenerate = false;
				selectedLocation = null;
				selectedIslandId = null;
			return true;
		}
		catch( err:Dynamic ) {
			logError("draft load failed", err);
			return false;
		}
	}

	function clearDraftState() {
		Browser.window.localStorage.removeItem(WORLD_MAP_DRAFT_KEY);
		lastDraftSignature = null;
	}

	function ensureLocationStateIsValid() {
		if( selectedLocation!=null && !hasLocation(selectedLocation) )
			selectedLocation = null;
		if( startNodeId==null || !hasNodeId(startNodeId) )
			startNodeId = getFirstNodeId();
	}

	function hasLocation(loc:Null<ActiveLocation>):Bool {
		return loc!=null && getLocationInfo(cast loc)!=null;
	}

	function hasNodeId(nodeId:Null<String>):Bool {
		if( mapData==null || nodeId==null )
			return false;
		for( city in mapData.cities )
			if( WorldMapExport.getNodeId("city", city.id)==nodeId )
				return true;
		for( point in mapData.pointsOfInterest )
			if( WorldMapExport.getNodeId("poi", point.id)==nodeId )
				return true;
		return false;
	}

	function getFirstNodeId():Null<String> {
		if( mapData==null )
			return null;
		if( mapData.cities.length>0 )
			return WorldMapExport.getNodeId("city", mapData.cities[0].id);
		if( mapData.pointsOfInterest.length>0 )
			return WorldMapExport.getNodeId("poi", mapData.pointsOfInterest[0].id);
		return null;
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
	static function sanitizeWorldId(v:String):String {
		var out = sanitizeFileName(v.toLowerCase());
		out = ~/_{2,}/g.replace(out, "_");
		while( out.length>0 && out.charAt(0)=="_" )
			out = out.substr(1);
		while( out.length>0 && out.charAt(out.length-1)=="_" )
			out = out.substr(0, out.length-1);
		return out.length>0 ? out : "world";
	}

	static function readStringMap(raw:Dynamic):Map<String, String> {
		var out:Map<String, String> = new Map();
		if( raw!=null )
			for( key in Reflect.fields(raw) ) {
				var value = Reflect.field(raw, key);
				if( value!=null )
					out.set(key, Std.string(value));
			}
		return out;
	}

	static function readNullableStringField(raw:Dynamic, key:String):Null<String> {
		if( raw==null )
			return null;
		var value = Reflect.field(raw, key);
		return value==null ? null : Std.string(value);
	}

	static function readStringField(raw:Dynamic, key:String, def:String):String {
		var value = readNullableStringField(raw, key);
		return value==null || value.length==0 ? def : value;
	}

	static function setVisible(j:js.jquery.JQuery, visible:Bool) {
		if( visible )
			j.show();
		else
			j.hide();
	}

	static function getControls():Array<WorldMapControl> {
		return [
			{ section:"General", key:"worldId", label:"World ID", type:"text" },
			{ section:"General", key:"worldName", label:"World Name", type:"text" },
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
