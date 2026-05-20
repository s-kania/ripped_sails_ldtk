package page;

import data.ShipData;
import data.ShipData.BoardPoint;
import data.ShipData.CannonSlot;
import data.ShipData.ShipDirection;
import data.ShipData.TileSlot;
import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;
import js.html.Image;

class ShipEditor extends Page {
	public static var ME:ShipEditor;

	var ship:Null<ShipData>;
	var currentDirection:ShipDirection = N;
	var currentTab:String = "opening";

	// Sprite images per direction
	var spriteImages:Map<String, Image> = new Map();
	var spriteWidth:Int = 0;
	var spriteHeight:Int = 0;
	var assetScale:Float = 1.0;

	// Canvas zoom & pan
	var canvasZoom:Float = 1.0;
	var canvasPanX:Float = 0;
	var canvasPanY:Float = 0;
	var isPanning:Bool = false;
	var panStartX:Float = 0;
	var panStartY:Float = 0;
	var panOffsetStartX:Float = 0;
	var panOffsetStartY:Float = 0;

	// Drag state
	var isDragging:Bool = false;
	var dragStartX:Float = 0;
	var dragStartY:Float = 0;
	var dragOffsetStartX:Float = 0;
	var dragOffsetStartY:Float = 0;
	var selectedCannonSide:Null<String> = null;
	var selectedCannonIdx:Int = -1;

	// Undo system
	var undoStack:Array<{tab:String, snapshot:String}> = [];
	var savedGridState:Null<String> = null;
	var savedOffsetsState:Null<String> = null;
	var savedCannonsState:Null<String> = null;

	// Cannon overlay toggles
	var showCannonGrid:Bool = false;
	var showCannonHelperLines:Bool = false;

	// Props state
	var currentPropType:String = "ladder_slots";
	var showPropsGrid:Bool = false;
	var showPropsHelperLines:Bool = false;
	var savedPropsState:Null<String> = null;
	var wheelImages:Map<String, Image> = new Map();
	var dragPropIdx:Int = -1;
	var dragPropType:Null<String> = null;
	var selectedLadderIdx:Int = -1;
	var selectedMastCount:Int = 1;
	var selectedMastIdx:Int = -1;
	var ladderPlacementMode:String = "deck"; // "deck" or "board"
	var wheelPlacementMode:String = "wheel"; // "wheel" or "helmsman"
	var hoveredTileX:Int = -1;
	var hoveredTileY:Int = -1;

	public function new() {
		super();
		ME = this;
		loadPageTemplate("shipEditor");
		App.ME.setWindowTitle("Ship Editor");

		initNavigation();
		initCanvasControls();
		initUndoControls();
		initOpeningScreen();
		initParamsScreen();
		initGridScreen();
		initOffsetsScreen();
		initCannonsScreen();
		initPropsScreen();

		// Check for recent ship file
		var recentFile = App.ME.settings.getUiDir("ShipEditorFile", null);
		if (recentFile != null && NT.fileExists(recentFile)) {
			jPage.find(".openRecent").show();
			var fp = dn.FilePath.fromFile(recentFile);
			jPage.find(".recentShipInfo").show().html('<em>Recent: ${fp.fileWithExt}</em>');
			jPage.find(".openRecent").click((_) -> {
				loadShip(recentFile);
			});
		}
	}

	// =========================================================================
	// Navigation
	// =========================================================================

	function initNavigation() {
		jPage.find(".backHome").click((_) -> {
			App.ME.loadPage(() -> new page.Home());
		});

		jPage.find(".saveShip").click((_) -> {
			if (ship != null)
				saveShip();
		});

		jPage.find(".navTabs .tab").click((ev:js.jquery.Event) -> {
			var jTab = new J(ev.currentTarget);
			var tabId = jTab.attr("data-tab");
			switchTab(tabId);
		});
	}

	function switchTab(tabId:String) {
		currentTab = tabId;
		jPage.find(".navTabs .tab").removeClass("active");
		jPage.find('.navTabs .tab[data-tab="$tabId"]').addClass("active");
		jPage.find(".screen").removeClass("active");
		jPage.find('.screen.$tabId').addClass("active");

		// Redraw canvases when switching tabs
		if (ship != null) {
			switch (tabId) {
				case "params":
					renderParamsPreview();
				case "grid":
					renderDeckGrid();
				case "offsets":
					renderOffsetsCanvas();
				case "cannons":
					renderCannonsCanvas();
				case "props":
					updatePropInfo();
					renderPropsCanvas();
				default:
			}
		}
	}

	function enableEditorTabs() {
		jPage.find(".navTabs .tab").css("opacity", "1").css("pointer-events", "auto");
	}

	// =========================================================================
	// Canvas Zoom & Pan Controls
	// =========================================================================

	function initCanvasControls() {
		// Zoom slider
		jPage.find(".zoomSlider").on("input", (_) -> {
			var val = Std.parseFloat(jPage.find(".zoomSlider").val());
			if (val != null && !Math.isNaN(val))
				canvasZoom = val / 100.0;
			else
				canvasZoom = 1.0;
			jPage.find(".zoomValue").text(Std.string(Math.round(canvasZoom * 100)) + "%");
			redrawCurrentTab();
		});

		// Reset view
		jPage.find(".resetView").click((_) -> {
			canvasZoom = 1.0;
			canvasPanX = 0;
			canvasPanY = 0;
			jPage.find(".zoomSlider").val("100");
			jPage.find(".zoomValue").text("100%");
			redrawCurrentTab();
		});

		// Mouse wheel zoom on all canvases
		for (cls in [
			".previewCanvas",
			".deckGridCanvas",
			".visualOffsetsCanvas",
			".cannonSlotsCanvas",
			".propsCanvasEl"
		]) {
			var el = jPage.find(cls).get(0);
			if (el != null) {
				el.addEventListener("wheel", (ev:js.html.WheelEvent) -> {
					ev.preventDefault();
					var delta = ev.deltaY < 0 ? 0.1 : -0.1;
					canvasZoom = Math.max(0.25, Math.min(4.0, canvasZoom + delta));
					jPage.find(".zoomSlider").val(Std.string(Math.round(canvasZoom * 100)));
					jPage.find(".zoomValue").text(Std.string(Math.round(canvasZoom * 100)) + "%");
					redrawCurrentTab();
				});
			}
		}

		// Middle-mouse pan on all canvases
		for (cls in [
			".previewCanvas",
			".deckGridCanvas",
			".visualOffsetsCanvas",
			".cannonSlotsCanvas",
			".propsCanvasEl"
		]) {
			var el = jPage.find(cls).get(0);
			if (el != null) {
				el.addEventListener("mousedown", (ev:js.html.MouseEvent) -> {
					if (ev.button == 1) { // middle mouse
						ev.preventDefault();
						isPanning = true;
						panStartX = ev.clientX;
						panStartY = ev.clientY;
						panOffsetStartX = canvasPanX;
						panOffsetStartY = canvasPanY;
					}
				});
				el.addEventListener("mousemove", (ev:js.html.MouseEvent) -> {
					if (isPanning) {
						canvasPanX = panOffsetStartX + (ev.clientX - panStartX);
						canvasPanY = panOffsetStartY + (ev.clientY - panStartY);
						redrawCurrentTab();
					}
				});
				el.addEventListener("mouseup", (ev:js.html.MouseEvent) -> {
					if (ev.button == 1)
						isPanning = false;
				});
				el.addEventListener("mouseleave", (_) -> {
					isPanning = false;
				});
			}
		}
	}

	function redrawCurrentTab() {
		if (ship == null)
			return;
		switch (currentTab) {
			case "params":
				renderParamsPreview();
			case "grid":
				renderDeckGrid();
			case "offsets":
				renderOffsetsCanvas();
			case "cannons":
				renderCannonsCanvas();
			case "props":
				renderPropsCanvas();
			default:
		}
	}

	/** Convert screen (pixel) coords to world (content) coords, accounting for zoom + pan. */
	inline function screenToWorldX(screenX:Float, canvasW:Float):Float {
		return (screenX - canvasPanX - canvasW / 2) / canvasZoom + canvasW / 2;
	}

	inline function screenToWorldY(screenY:Float, canvasH:Float):Float {
		return (screenY - canvasPanY - canvasH / 2) / canvasZoom + canvasH / 2;
	}

	// =========================================================================
	// Direction Switcher (shared widget)
	// =========================================================================

	function buildDirectionSwitcher(jContainer:js.jquery.JQuery) {
		jContainer.empty();
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var jBtn = new J('<button class="dirBtn"/>');
			jBtn.text(d);
			if (dir == currentDirection)
				jBtn.addClass("active");
			jBtn.click((_) -> {
				currentDirection = dir;
				// Update all direction switchers
				jPage.find(".dirBtn").removeClass("active");
				jPage.find(".dirBtn").each((idx, el) -> {
					if (new J(el).text() == d)
						new J(el).addClass("active");
				});
				onDirectionChanged();
			});
			jContainer.append(jBtn);
		}
	}

	function onDirectionChanged() {
		if (ship == null)
			return;
		switch (currentTab) {
			case "params":
				renderParamsPreview();
			case "offsets":
				updateOffsetInfo();
				renderOffsetsCanvas();
			case "cannons":
				updateCannonInfo();
				renderCannonsCanvas();
			case "props":
				updatePropInfo();
				renderPropsCanvas();
			default:
		}
	}

	// =========================================================================
	// Opening Screen
	// =========================================================================

	function initOpeningScreen() {
		jPage.find(".newShip").click((_) -> {
			onNewShip();
		});
		jPage.find(".openShip").click((_) -> {
			onOpenShip();
		});
	}

	function onNewShip() {
		var dir = App.ME.settings.getUiDir("ShipEditor", App.ME.getDefaultDialogDir());
		dn.js.ElectronDialogs.saveFileAs([".json"], dir, (filePath) -> {
			if (filePath == null)
				return;
			var fp = dn.FilePath.fromFile(filePath);
			fp.extension = "json";
			ship = ShipData.createEmpty();
			ship.filePath = fp;
			App.ME.settings.storeUiDir("ShipEditor", fp.directory);
			App.ME.settings.storeUiDir("ShipEditorFile", fp.full);
			ship.save();
			onShipLoaded();
		});
	}

	function onOpenShip() {
		var dir = App.ME.settings.getUiDir("ShipEditor", App.ME.getDefaultDialogDir());
		dn.js.ElectronDialogs.openFile([".json"], dir, (filePath) -> {
			if (filePath == null)
				return;
			loadShip(filePath);
		});
	}

	function loadShip(path:String) {
		ship = ShipData.fromFile(path);
		if (ship == null) {
			App.LOG.error("Failed to load ship JSON: " + path);
			js.Browser.window.alert("Failed to load ship JSON: " + path);
			return;
		}
		App.ME.settings.storeUiDir("ShipEditor", ship.filePath.directory);
		App.ME.settings.storeUiDir("ShipEditorFile", ship.filePath.full);
		onShipLoaded();
	}

	function onShipLoaded() {
		if (ship == null)
			return;

		spriteImages = new Map();

		// Update UI
		jPage.find(".shipName").text(ship.filePath != null ? ship.filePath.fileName : "New Ship");
		enableEditorTabs();
		jPage.find(".canvasControls").css("display", "flex");

		// Capture saved state for undo/reset
		undoStack = [];
		savedGridState = captureGridState();
		savedOffsetsState = captureOffsetsState();
		savedCannonsState = captureCannonsState();
		savedPropsState = capturePropsState();
		updateDirtyIndicators();

		// Set default asset prefix from file name if not set
		if (ship.assetPrefix == null && ship.filePath != null) {
			ship.assetPrefix = ship.filePath.fileName;
		}

		// Restore asset scale from ship data
		if (ship.assetScale > 0)
			assetScale = ship.assetScale;

		ship.ensureMastSlotConfigurations();
		selectedMastCount = ship.maxMastCount;
		selectedMastIdx = selectedMastCount > 0 ? 0 : -1;

		populateParamsForm();

		// Build direction switchers
		jPage.find(".directionSwitcher").each((idx, el) -> {
			buildDirectionSwitcher(new J(el));
		});

		// Try to auto-load assets from ship_editor.asset_path, then same dir as JSON
		if (ship.assetsPath == null && ship.filePath != null) {
			ship.assetsPath = dn.FilePath.fromDir(ship.filePath.directory);
		}
		if (ship.assetsPath != null) {
			updateAssetsPathDisplay();
			loadSpriteAssets();
		}

		// Load wheel assets if path is set
		if (ship.steeringWheelAsset != null) {
			var wParts = ship.steeringWheelAsset.split("|");
			if (wParts.length == 2)
				jPage.find(".wheelAssetPath").text(wParts[0] + " / " + wParts[1] + "_*.png");
			else
				jPage.find(".wheelAssetPath").text(ship.steeringWheelAsset);
			loadWheelAssets();
		}
		jPage.find(".wheelScaleInput").val(ship.steeringWheelScale);

		switchTab("params");
	}

	function saveShip() {
		if (ship == null)
			return;

		// Read back params from form before saving
		readParamsForm();

		if (ship.filePath == null) {
			var dir = App.ME.settings.getUiDir("ShipEditor", App.ME.getDefaultDialogDir());
			dn.js.ElectronDialogs.saveFileAs([".json"], dir, (filePath) -> {
				if (filePath == null)
					return;
				var fp = dn.FilePath.fromFile(filePath);
				fp.extension = "json";
				ship.filePath = fp;
				App.ME.settings.storeUiDir("ShipEditor", fp.directory);
				if (ship.save()) {
					ui.Notification.success("Ship saved", ship.filePath.fileWithExt);
				} else {
					ui.Notification.error("Failed to save ship!");
				}
			});
		} else {
			if (ship.save()) {
				ui.Notification.success("Ship saved", ship.filePath.fileWithExt);
			} else {
				ui.Notification.error("Failed to save ship!");
			}
		}
	}

	// =========================================================================
	// Asset Loading
	// =========================================================================

	function loadSpriteAssets() {
		if (ship == null || ship.assetsPath == null)
			return;

		var basePath = ship.assetsPath.full;
		var assetPrefix = ship.assetPrefix != null ? ship.assetPrefix : "ship";

		spriteImages = new Map();
		var loadedCount = 0;
		var totalCount = 8;

		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var suffix = dir.toFileSuffix();
			var path = basePath + "/" + assetPrefix + "_" + suffix + ".png";
			if (NT.fileExists(path)) {
				var img = new Image();
				var dirKey = d;
				img.onload = () -> {
					spriteImages.set(dirKey, img);
					loadedCount++;
					if (loadedCount >= totalCount)
						onSpritesLoaded();
				};
				img.onerror = () -> {
					loadedCount++;
					if (loadedCount >= totalCount)
						onSpritesLoaded();
				};
				img.src = "data:image/png;base64," + haxe.crypto.Base64.encode(NT.readFileBytes(path));
			} else {
				loadedCount++;
				if (loadedCount >= totalCount)
					onSpritesLoaded();
			}
		}

		updateAssetsPathDisplay();
	}

	function onSpritesLoaded() {
		// Capture sprite dimensions from first loaded image
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var img = spriteImages.get(d);
			if (img != null) {
				spriteWidth = img.width;
				spriteHeight = img.height;
				break;
			}
		}
		// Redraw current canvas
		onDirectionChanged();
	}

	function updateAssetsPathDisplay() {
		var jPath = jPage.find(".assetsPath");
		if (ship != null && ship.assetsPath != null)
			jPath.text(ship.assetsPath.directory);
		else
			jPath.text("No assets folder selected");
	}

	// =========================================================================
	// Params Screen
	// =========================================================================

	function initParamsScreen() {
		jPage.find(".selectAssets").click((_) -> {
			if (ship == null)
				return;
			var dir = ship.assetsPath != null ? ship.assetsPath.directory : (ship.filePath != null ? ship.filePath.directory : App.ME.getDefaultDialogDir());
			dn.js.ElectronDialogs.openDir(dir, (dirPath) -> {
				if (dirPath == null)
					return;
				ship.assetsPath = dn.FilePath.fromDir(dirPath);
				loadSpriteAssets();
				saveShip();
			});
		});

		// Form field change handlers
		for (cls in ["shipType", "maxCannons", "maxMastCount", "maxSailsPerMast", "baseHullHp", "baseSpeed", "baseMaxCrewCapacity", "baseCargoCapacity"]) {
			jPage.find('.field.$cls').on("change", (_) -> {
				readParamsForm();
			});
		}

		// Asset scale handler
		jPage.find(".field.assetScale").on("change", (_) -> {
			var val = Std.parseFloat(jPage.find(".field.assetScale").val());
			if (val != null && !Math.isNaN(val) && val > 0)
				assetScale = val;
			else
				assetScale = 1.0;
			if (ship != null) {
				ship.assetScale = assetScale;
				saveShip();
			}
			onDirectionChanged();
		});

		// Asset prefix: reload sprites on Enter
		jPage.find(".field.assetPrefix").on("keydown", (ev:js.jquery.Event) -> {
			if (ev.which == 13) { // Enter
				ev.preventDefault();
				if (ship != null) {
					var val:String = jPage.find(".field.assetPrefix").val();
					if (val != null && val.length > 0)
						ship.assetPrefix = val;
					loadSpriteAssets();
				}
			}
		});
	}

	function populateParamsForm() {
		if (ship == null)
			return;
		jPage.find(".field.shipType").val(ship.shipType);
		jPage.find(".field.maxCannons").val(Std.string(ship.maxCannonsPerSide));
		jPage.find(".field.maxMastCount").val(Std.string(ship.maxMastCount));
		jPage.find(".field.maxSailsPerMast").val(Std.string(ship.maxSailsPerMast));
		jPage.find(".field.baseHullHp").val(Std.string(ship.baseStats.hullHp));
		jPage.find(".field.baseSpeed").val(Std.string(ship.baseStats.speed));
		jPage.find(".field.baseMaxCrewCapacity").val(Std.string(ship.baseStats.maxCrewCapacity));
		jPage.find(".field.baseCargoCapacity").val(Std.string(ship.baseStats.cargoCapacity));
		jPage.find(".field.gridWidth").val(Std.string(ship.deckGrid.width));
		jPage.find(".field.gridHeight").val(Std.string(ship.deckGrid.height));
		jPage.find(".field.tileSize").val(Std.string(ship.deckGrid.tile_size));
		jPage.find(".field.assetPrefix").val(ship.assetPrefix != null ? ship.assetPrefix : "");
		jPage.find(".field.assetScale").val(Std.string(assetScale));
		updateAssetsPathDisplay();
	}

	function readParamsForm() {
		if (ship == null)
			return;
		ship.shipType = jPage.find(".field.shipType").val();
		var mc = Std.parseInt(jPage.find(".field.maxCannons").val());
		if (mc != null)
			ship.maxCannonsPerSide = mc;
		var mastCountChanged = false;
		var maxMastCount = Std.parseInt(jPage.find(".field.maxMastCount").val());
		if (maxMastCount != null && maxMastCount > 0 && maxMastCount != ship.maxMastCount) {
			ship.maxMastCount = maxMastCount;
			mastCountChanged = true;
		}
		var maxSailsPerMast = Std.parseInt(jPage.find(".field.maxSailsPerMast").val());
		var maxSailsChanged = false;
		if (maxSailsPerMast != null && maxSailsPerMast > 0 && maxSailsPerMast != ship.maxSailsPerMast) {
			ship.maxSailsPerMast = maxSailsPerMast;
			maxSailsChanged = true;
		}
		if (mastCountChanged) {
			ship.ensureMastSlotConfigurations();
			if (selectedMastCount > ship.maxMastCount)
				selectedMastCount = ship.maxMastCount;
			if (selectedMastCount < 1)
				selectedMastCount = 1;
			var config = ship.getMastSlotConfiguration(selectedMastCount);
			if (selectedMastIdx >= config.slots.length)
				selectedMastIdx = config.slots.length - 1;
			if (selectedMastIdx < 0 && config.slots.length > 0)
				selectedMastIdx = 0;
			updatePropInfo();
			if (currentTab == "props")
				renderPropsCanvas();
			updateDirtyIndicators();
		} else if (maxSailsChanged && currentPropType == "masts") {
			updatePropInfo();
		}
		var hullHp = Std.parseInt(jPage.find(".field.baseHullHp").val());
		if (hullHp != null && hullHp >= 0)
			ship.baseStats.hullHp = hullHp;
		var speed = Std.parseFloat(jPage.find(".field.baseSpeed").val());
		if (!Math.isNaN(speed) && speed >= 0)
			ship.baseStats.speed = speed;
		var maxCrewCapacity = Std.parseInt(jPage.find(".field.baseMaxCrewCapacity").val());
		if (maxCrewCapacity != null && maxCrewCapacity >= 0)
			ship.baseStats.maxCrewCapacity = maxCrewCapacity;
		var cargoCapacity = Std.parseInt(jPage.find(".field.baseCargoCapacity").val());
		if (cargoCapacity != null && cargoCapacity >= 0)
			ship.baseStats.cargoCapacity = cargoCapacity;
		var gw = Std.parseInt(jPage.find(".field.gridWidth").val());
		if (gw != null && gw > 0)
			ship.deckGrid.width = gw;
		var gh = Std.parseInt(jPage.find(".field.gridHeight").val());
		if (gh != null && gh > 0)
			ship.deckGrid.height = gh;
		var ts = Std.parseInt(jPage.find(".field.tileSize").val());
		if (ts != null && ts > 0)
			ship.deckGrid.tile_size = ts;
		var prefix:String = jPage.find(".field.assetPrefix").val();
		if (prefix != null && prefix.length > 0)
			ship.assetPrefix = prefix;
	}

	function getCanvasSize():{w:Int, h:Int} {
		var padding = 40;
		if (spriteWidth > 0 && spriteHeight > 0) {
			var w = Math.round((Math.max(spriteWidth * assetScale, 200) + padding) * canvasZoom);
			var h = Math.round((Math.max(spriteHeight * assetScale, 200) + padding) * canvasZoom);
			return {w: Std.int(w), h: Std.int(h)};
		}
		return {w: Std.int(400 * canvasZoom), h: Std.int(400 * canvasZoom)};
	}

	function renderParamsPreview() {
		var canvas:CanvasElement = cast jPage.find(".previewCanvas").get(0);
		if (canvas == null)
			return;

		var sz = getCanvasSize();
		canvas.width = sz.w;
		canvas.height = sz.h;
		var ctx = canvas.getContext2d();
		ctx.clearRect(0, 0, canvas.width, canvas.height);

		ctx.save();
		ctx.translate(canvas.width / 2 + canvasPanX, canvas.height / 2 + canvasPanY);
		ctx.scale(canvasZoom, canvasZoom);
		ctx.translate(-canvas.width / 2, -canvas.height / 2);

		// Draw sprite
		var d:String = currentDirection;
		var img = spriteImages.get(d);
		if (img != null) {
			var drawW = img.width * assetScale;
			var drawH = img.height * assetScale;
			var cx = canvas.width / 2 - drawW / 2;
			var cy = canvas.height / 2 - drawH / 2;
			ctx.drawImage(img, cx, cy, drawW, drawH);
			ctx.strokeStyle = "rgba(255,255,255,0.3)";
			ctx.lineWidth = 1;
			ctx.strokeRect(cx + 0.5, cy + 0.5, drawW - 1, drawH - 1);
		} else {
			ctx.fillStyle = "#333";
			ctx.fillRect(100, 100, 200, 200);
			ctx.fillStyle = "#888";
			ctx.font = "14px sans-serif";
			ctx.textAlign = "center";
			ctx.fillText("No sprite for " + d, 200, 200);
		}

		ctx.restore();
	}

	// =========================================================================
	// Undo / Reset System
	// =========================================================================

	function captureGridState():String {
		if (ship == null)
			return "{}";
		return haxe.Json.stringify({
			deck_tiles: ship.deckGrid.deck_tiles.map((t) -> [t[0], t[1]])
		});
	}

	function captureOffsetsState():String {
		if (ship == null)
			return "{}";
		var obj:haxe.DynamicAccess<Dynamic> = {};
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var off = ship.getVisualOffset(dir);
			obj.set(d, {x: off.x, y: off.y});
		}
		return haxe.Json.stringify(obj);
	}

	function captureCannonsState():String {
		if (ship == null)
			return "{}";
		var slots = ship.getCannonSlots(currentDirection);
		var leftArr:Array<Dynamic> = [for (s in slots.left) {tx: s.tx, ty: s.ty}];
		var rightArr:Array<Dynamic> = [for (s in slots.right) {tx: s.tx, ty: s.ty}];
		return haxe.Json.stringify({left: leftArr, right: rightArr, maxCannonsPerSide: ship.maxCannonsPerSide});
	}

	function restoreGridState(json:String) {
		if (ship == null)
			return;
		try {
			var obj:Dynamic = haxe.Json.parse(json);
			var tiles:Array<Dynamic> = obj.deck_tiles;
			ship.deckGrid.deck_tiles = [
				for (t in tiles) {
					var arr:Array<Dynamic> = t;
					[Std.int(arr[0]), Std.int(arr[1])];
				}
			];
		} catch (_) {}
	}

	function restoreOffsetsState(json:String) {
		if (ship == null)
			return;
		try {
			var obj:haxe.DynamicAccess<Dynamic> = haxe.Json.parse(json);
			for (dir in ShipDirection.all()) {
				var d:String = dir;
				var data:Dynamic = obj.get(d);
				if (data != null) {
					var off = ship.getVisualOffset(dir);
					off.x = Std.int(data.x);
					off.y = Std.int(data.y);
				}
			}
		} catch (_) {}
	}

	function restoreCannonsState(json:String) {
		if (ship == null)
			return;
		try {
			var obj:Dynamic = haxe.Json.parse(json);
			var slots = ship.getCannonSlots(currentDirection);
			var leftArr:Array<Dynamic> = obj.left;
			var rightArr:Array<Dynamic> = obj.right;
			slots.left = [for (s in leftArr) {tx: Std.int(s.tx), ty: Std.int(s.ty)}];
			slots.right = [for (s in rightArr) {tx: Std.int(s.tx), ty: Std.int(s.ty)}];
			ship.maxCannonsPerSide = Std.int(obj.maxCannonsPerSide);
		} catch (_) {}
	}

	function pushUndo(tab:String) {
		var snapshot = switch (tab) {
			case "grid": captureGridState();
			case "offsets": captureOffsetsState();
			case "cannons": captureCannonsState();
			case "props": capturePropsState();
			default: return;
		};
		undoStack.push({tab: tab, snapshot: snapshot});
		if (undoStack.length > 50)
			undoStack.shift();
	}

	function performUndo() {
		if (undoStack.length == 0)
			return;
		var entry = undoStack.pop();
		switch (entry.tab) {
			case "grid":
				restoreGridState(entry.snapshot);
				renderDeckGrid();
			case "offsets":
				restoreOffsetsState(entry.snapshot);
				updateOffsetInfo();
				renderOffsetsCanvas();
			case "cannons":
				restoreCannonsState(entry.snapshot);
				updateCannonInfo();
				renderCannonsCanvas();
			case "props":
				restorePropsState(entry.snapshot);
				updatePropInfo();
				renderPropsCanvas();
			default:
		}
		updateDirtyIndicators();
	}

	function resetTabData(tab:String) {
		switch (tab) {
			case "grid":
				if (savedGridState != null) {
					pushUndo("grid");
					restoreGridState(savedGridState);
					renderDeckGrid();
				}
			case "offsets":
				if (savedOffsetsState != null) {
					pushUndo("offsets");
					restoreOffsetsState(savedOffsetsState);
					updateOffsetInfo();
					renderOffsetsCanvas();
				}
			case "cannons":
				if (savedCannonsState != null) {
					pushUndo("cannons");
					restoreCannonsState(savedCannonsState);
					updateCannonInfo();
					renderCannonsCanvas();
				}
			case "props":
				if (savedPropsState != null) {
					pushUndo("props");
					restorePropsState(savedPropsState);
					updatePropInfo();
					renderPropsCanvas();
				}
			default:
		}
		updateDirtyIndicators();
	}

	function updateDirtyIndicators() {
		var gridDirty = savedGridState != null && captureGridState() != savedGridState;
		var offsetsDirty = savedOffsetsState != null && captureOffsetsState() != savedOffsetsState;
		var cannonsDirty = savedCannonsState != null && captureCannonsState() != savedCannonsState;
		var propsDirty = savedPropsState != null && capturePropsState() != savedPropsState;

		jPage.find(".gridUndo").css("display", gridDirty ? "flex" : "none");
		jPage.find(".offsetsUndo").css("display", offsetsDirty ? "flex" : "none");
		jPage.find(".cannonsUndo").css("display", cannonsDirty ? "flex" : "none");
		jPage.find(".propsUndo").css("display", propsDirty ? "flex" : "none");
	}

	function initUndoControls() {
		// Grid undo/reset
		jPage.find(".gridUndo .undoBtn").click((_) -> {
			performUndo();
		});
		jPage.find(".gridUndo .resetDataBtn").click((_) -> {
			resetTabData("grid");
		});
		// Offsets undo/reset
		jPage.find(".offsetsUndo .undoBtn").click((_) -> {
			performUndo();
		});
		jPage.find(".offsetsUndo .resetDataBtn").click((_) -> {
			resetTabData("offsets");
		});
		// Cannons undo/reset
		jPage.find(".cannonsUndo .undoBtn").click((_) -> {
			performUndo();
		});
		jPage.find(".cannonsUndo .resetDataBtn").click((_) -> {
			resetTabData("cannons");
		});
		// Props undo/reset
		jPage.find(".propsUndo .undoBtn").click((_) -> {
			performUndo();
		});
		jPage.find(".propsUndo .resetDataBtn").click((_) -> {
			resetTabData("props");
		});
	}

	// =========================================================================
	// Deck Grid Screen
	// =========================================================================

	function initGridScreen() {
		// Grid dimension change handlers
		for (cls in ["gridWidth", "gridHeight", "tileSize"]) {
			jPage.find('.field.$cls').on("change", (_) -> {
				readParamsForm();
				if (ship != null) {
					ship.trimDeckTilesToGrid();
					renderDeckGrid();
				}
			});
		}

		var canvas:CanvasElement = cast jPage.find(".deckGridCanvas").get(0);
		if (canvas == null)
			return;

		canvas.addEventListener("click", (ev:js.html.MouseEvent) -> {
			if (ship == null)
				return;
			var rect = canvas.getBoundingClientRect();
			var mx = screenToWorldX(ev.clientX - rect.left, canvas.width);
			var my = screenToWorldY(ev.clientY - rect.top, canvas.height);
			var tileSize = getTileDrawSize();
			var offsetX = getGridOffsetX(canvas, tileSize);
			var offsetY = getGridOffsetY(canvas, tileSize);
			var tx = Math.floor((mx - offsetX) / tileSize);
			var ty = Math.floor((my - offsetY) / tileSize);
			if (tx >= 0 && tx < ship.deckGrid.width && ty >= 0 && ty < ship.deckGrid.height) {
				pushUndo("grid");
				ship.toggleDeckTile(tx, ty);
				renderDeckGrid();
				updateDirtyIndicators();
			}
		});

		canvas.addEventListener("contextmenu", (ev:js.html.MouseEvent) -> {
			ev.preventDefault();
		});
	}

	function getTileDrawSize():Float {
		if (ship == null)
			return 32;
		return Math.min(32, Math.max(16, 400 / Math.max(ship.deckGrid.width, ship.deckGrid.height)));
	}

	function getGridOffsetX(canvas:CanvasElement, tileSize:Float):Float {
		if (ship == null)
			return 0;
		return (canvas.width - ship.deckGrid.width * tileSize) / 2;
	}

	function getGridOffsetY(canvas:CanvasElement, tileSize:Float):Float {
		if (ship == null)
			return 0;
		return (canvas.height - ship.deckGrid.height * tileSize) / 2;
	}

	function renderDeckGrid() {
		var canvas:CanvasElement = cast jPage.find(".deckGridCanvas").get(0);
		if (canvas == null || ship == null)
			return;

		var sz = getCanvasSize();
		canvas.width = Std.int(Math.max(sz.w, 500 * canvasZoom));
		canvas.height = Std.int(Math.max(sz.h, 500 * canvasZoom));
		var ctx = canvas.getContext2d();
		ctx.clearRect(0, 0, canvas.width, canvas.height);

		ctx.save();
		ctx.translate(canvas.width / 2 + canvasPanX, canvas.height / 2 + canvasPanY);
		ctx.scale(canvasZoom, canvasZoom);
		ctx.translate(-canvas.width / 2, -canvas.height / 2);

		var tileSize = getTileDrawSize();
		var offsetX = getGridOffsetX(canvas, tileSize);
		var offsetY = getGridOffsetY(canvas, tileSize);

		// Draw grid
		for (ty in 0...ship.deckGrid.height) {
			for (tx in 0...ship.deckGrid.width) {
				var x = offsetX + tx * tileSize;
				var y = offsetY + ty * tileSize;
				var active = ship.isDeckTileActive(tx, ty);

				if (active)
					ctx.fillStyle = "#5577bb";
				else
					ctx.fillStyle = "#222233";

				ctx.fillRect(x + 1, y + 1, tileSize - 2, tileSize - 2);
				ctx.strokeStyle = "#556677";
				ctx.lineWidth = 1;
				ctx.strokeRect(x + 0.5, y + 0.5, tileSize - 1, tileSize - 1);
			}
		}

		ctx.restore();

		// Update info
		jPage.find(".gridInfo")
			.html('Grid: ${ship.deckGrid.width}x${ship.deckGrid.height}, Tile: ${ship.deckGrid.tile_size}px, '
				+ 'Active tiles: ${ship.deckGrid.deck_tiles.length}');
	}

	// =========================================================================
	// Visual Offsets Screen
	// =========================================================================

	function initOffsetsScreen() {
		var canvas:CanvasElement = cast jPage.find(".visualOffsetsCanvas").get(0);
		if (canvas == null)
			return;

		canvas.addEventListener("mousedown", (ev:js.html.MouseEvent) -> {
			if (ship == null || ev.button != 0)
				return;
			pushUndo("offsets");
			isDragging = true;
			dragStartX = ev.clientX;
			dragStartY = ev.clientY;
			var off = ship.getVisualOffset(currentDirection);
			dragOffsetStartX = off.x;
			dragOffsetStartY = off.y;
		});

		canvas.addEventListener("mousemove", (ev:js.html.MouseEvent) -> {
			if (!isDragging || ship == null)
				return;
			var dx = (ev.clientX - dragStartX) / canvasZoom;
			var dy = (ev.clientY - dragStartY) / canvasZoom;
			var off = ship.getVisualOffset(currentDirection);
			off.x = Std.int(dragOffsetStartX + dx);
			off.y = Std.int(dragOffsetStartY + dy);
			updateOffsetInfo();
			renderOffsetsCanvas();
		});

		canvas.addEventListener("mouseup", (_) -> {
			isDragging = false;
			updateDirtyIndicators();
		});

		canvas.addEventListener("mouseleave", (_) -> {
			isDragging = false;
		});
	}

	function updateOffsetInfo() {
		if (ship == null)
			return;
		var off = ship.getVisualOffset(currentDirection);
		jPage.find(".offsetX").text("X: " + off.x);
		jPage.find(".offsetY").text("Y: " + off.y);
	}

	function renderOffsetsCanvas() {
		var canvas:CanvasElement = cast jPage.find(".visualOffsetsCanvas").get(0);
		if (canvas == null || ship == null)
			return;

		var sz = getCanvasSize();
		canvas.width = sz.w;
		canvas.height = sz.h;
		var ctx = canvas.getContext2d();
		ctx.clearRect(0, 0, canvas.width, canvas.height);

		ctx.save();
		ctx.translate(canvas.width / 2 + canvasPanX, canvas.height / 2 + canvasPanY);
		ctx.scale(canvasZoom, canvasZoom);
		ctx.translate(-canvas.width / 2, -canvas.height / 2);

		var spriteCX = canvas.width / 2;
		var spriteCY = canvas.height / 2;

		// Draw sprite
		var d:String = currentDirection;
		var img = spriteImages.get(d);
		if (img != null) {
			var drawW = img.width * assetScale;
			var drawH = img.height * assetScale;
			ctx.drawImage(img, spriteCX - drawW / 2, spriteCY - drawH / 2, drawW, drawH);
			ctx.strokeStyle = "rgba(255,255,255,0.3)";
			ctx.lineWidth = 1;
			ctx.strokeRect(Std.int(spriteCX - drawW / 2) + 0.5, Std.int(spriteCY - drawH / 2) + 0.5, drawW - 1, drawH - 1);
		} else {
			ctx.fillStyle = "#333";
			ctx.fillRect(spriteCX - 50, spriteCY - 75, 100, 150);
		}

		// Draw isometric grid overlay (Defold Y-up → canvas Y-down: negate off.y)
		var off = ship.getVisualOffset(currentDirection);
		drawIsoGrid(ctx, spriteCX + off.x, spriteCY - off.y, currentDirection);

		ctx.restore();
	}

	// =========================================================================
	// Isometric Projection (Section 5 of plan)
	// =========================================================================
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
		if (ship == null)
			return {x: 0, y: 0};

		var centerX = ship.deckGrid.width / 2.0;
		var centerY = ship.deckGrid.height / 2.0;
		var virtualX = (tx - centerX) * ship.deckGrid.tile_size;
		var virtualY = (ty - centerY) * ship.deckGrid.tile_size;

		var rot = getRotationForDirection(dir);
		var rotX = virtualX * rot.cos - virtualY * rot.sin;
		var rotY = virtualX * rot.sin + virtualY * rot.cos;

		return {x: rotX, y: rotY * ISO_Y_SCALE};
	}

	function screenToTile(sx:Float, sy:Float, dir:ShipDirection):{tx:Int, ty:Int} {
		if (ship == null)
			return {tx: 0, ty: 0};

		// Undo ISO scaling
		var unscaledY = sy / ISO_Y_SCALE;
		var rot = getRotationForDirection(dir);
		// Inverse rotation: transpose of rotation matrix
		var virtualX = sx * rot.cos + unscaledY * rot.sin;
		var virtualY = -sx * rot.sin + unscaledY * rot.cos;

		var centerX = ship.deckGrid.width / 2.0;
		var centerY = ship.deckGrid.height / 2.0;
		var tileX = virtualX / ship.deckGrid.tile_size + centerX;
		var tileY = virtualY / ship.deckGrid.tile_size + centerY;

		return {tx: Std.int(Math.floor(tileX)), ty: Std.int(Math.floor(tileY))};
	}

	function canvasPointToTile(canvas:CanvasElement, mx:Float, my:Float, dir:ShipDirection):TileSlot {
		if (ship == null)
			return {tx: -1, ty: -1};
		var spriteCX = canvas.width / 2;
		var spriteCY = canvas.height / 2;
		var off = ship.getVisualOffset(dir);
		var relX = mx - spriteCX - off.x;
		var relY = my - spriteCY + off.y;
		return screenToTile(relX, relY, dir);
	}

	function isActiveTile(tile:TileSlot):Bool {
		return ship != null
			&& tile.tx >= 0
			&& tile.tx < ship.deckGrid.width
			&& tile.ty >= 0
			&& tile.ty < ship.deckGrid.height
			&& ship.isDeckTileActive(tile.tx, tile.ty);
	}

	function firstActiveTile():TileSlot {
		if (ship == null || ship.deckGrid.deck_tiles.length == 0)
			return {tx: 0, ty: 0};
		var t = ship.deckGrid.deck_tiles[0];
		return {tx: t[0], ty: t[1]};
	}

	function defaultTileForSide(side:String):TileSlot {
		if (ship == null || ship.deckGrid.deck_tiles.length == 0)
			return {tx: 0, ty: 0};
		var minX = 999999;
		var maxX = -999999;
		for (t in ship.deckGrid.deck_tiles) {
			if (t[0] < minX)
				minX = t[0];
			if (t[0] > maxX)
				maxX = t[0];
		}
		var targetX = side == "right" ? maxX : minX;
		var best:Null<TileSlot> = null;
		for (t in ship.deckGrid.deck_tiles) {
			if (t[0] == targetX && (best == null || t[1] < best.ty))
				best = {tx: t[0], ty: t[1]};
		}
		return best != null ? best : firstActiveTile();
	}

	function updateHoveredTileForCanvas(canvas:CanvasElement, mx:Float, my:Float, dir:ShipDirection) {
		var tile = canvasPointToTile(canvas, mx, my, dir);
		if (!isActiveTile(tile))
			tile = {tx: -1, ty: -1};
		if (tile.tx != hoveredTileX || tile.ty != hoveredTileY) {
			hoveredTileX = tile.tx;
			hoveredTileY = tile.ty;
			renderCurrentCanvas();
		}
	}

	function renderCurrentCanvas() {
		switch currentTab {
			case "cannons":
				renderCannonsCanvas();
			case "props":
				renderPropsCanvas();
			default:
		}
	}

	function drawIsoGrid(ctx:CanvasRenderingContext2D, cx:Float, cy:Float, dir:ShipDirection, alphaMultiplier:Float = 1.0) {
		if (ship == null)
			return;

		var rot = getRotationForDirection(dir);
		var half = ship.deckGrid.tile_size / 2;

		var gridAlpha = 0.5 * alphaMultiplier;
		var fillAlpha = 0.15 * alphaMultiplier;
		ctx.strokeStyle = "rgba(0, 255, 100, " + gridAlpha + ")";
		ctx.lineWidth = 1;

		for (tile in ship.deckGrid.deck_tiles) {
			var tx = tile[0];
			var ty = tile[1];
			var tileCX = tx + 0.5;
			var tileCY = ty + 0.5;
			var center = tileToScreen(tileCX, tileCY, dir);

			// 4 corners of the tile in virtual space (relative to tile center)
			var corners = [
				{x: -half, y: -half},
				{x: half, y: -half},
				{x: half, y: half},
				{x: -half, y: half}
			];

			ctx.beginPath();
			for (i in 0...4) {
				var vx = corners[i].x;
				var vy = corners[i].y;
				var rx = vx * rot.cos - vy * rot.sin;
				var ry = (vx * rot.sin + vy * rot.cos) * ISO_Y_SCALE;
				var sx = cx + center.x + rx;
				var sy = cy + center.y + ry;
				if (i == 0)
					ctx.moveTo(sx, sy);
				else
					ctx.lineTo(sx, sy);
			}
			ctx.closePath();
			ctx.fillStyle = "rgba(0, 200, 100, " + fillAlpha + ")";
			ctx.fill();
			ctx.stroke();
		}
	}

	// =========================================================================
	// Cannon Slots Screen
	// =========================================================================

	function initCannonsScreen() {
		// Visual grid overlay toggle
		jPage.find(".showCannonGrid").on("change", (_) -> {
			showCannonGrid = jPage.find(".showCannonGrid").is(":checked");
			renderCannonsCanvas();
		});
		// Helper lines toggle
		jPage.find(".showCannonHelperLines").on("change", (_) -> {
			showCannonHelperLines = jPage.find(".showCannonHelperLines").is(":checked");
			renderCannonsCanvas();
		});

		jPage.find(".addPair").click((_) -> {
			if (ship == null)
				return;
			pushUndo("cannons");
			var slots = ship.getCannonSlots(currentDirection);
			var leftDefault = defaultTileForSide("left");
			var rightDefault = defaultTileForSide("right");
			slots.left.push({tx: leftDefault.tx, ty: leftDefault.ty});
			slots.right.push({tx: rightDefault.tx, ty: rightDefault.ty});
			selectedCannonSide = "left";
			selectedCannonIdx = slots.left.length - 1;
			ship.maxCannonsPerSide = Std.int(Math.max(slots.left.length, slots.right.length));
			updateCannonInfo();
			renderCannonsCanvas();
			updateDirtyIndicators();
		});

		jPage.find(".removePair").click((_) -> {
			if (ship == null)
				return;
			pushUndo("cannons");
			var slots = ship.getCannonSlots(currentDirection);
			if (slots.left.length > 0)
				slots.left.pop();
			if (slots.right.length > 0)
				slots.right.pop();
			if (selectedCannonSide == "left" && selectedCannonIdx >= slots.left.length)
				selectedCannonIdx = slots.left.length - 1;
			if (selectedCannonSide == "right" && selectedCannonIdx >= slots.right.length)
				selectedCannonIdx = slots.right.length - 1;
			if (selectedCannonIdx < 0)
				selectedCannonSide = null;
			ship.maxCannonsPerSide = Std.int(Math.max(slots.left.length, slots.right.length));
			if (ship.maxCannonsPerSide < 0)
				ship.maxCannonsPerSide = 0;
			updateCannonInfo();
			renderCannonsCanvas();
			updateDirtyIndicators();
		});

		var canvas:CanvasElement = cast jPage.find(".cannonSlotsCanvas").get(0);
		if (canvas == null)
			return;

		canvas.addEventListener("mousedown", (ev:js.html.MouseEvent) -> {
			if (ship == null || ev.button != 0)
				return;
			pushUndo("cannons");
			var rect = canvas.getBoundingClientRect();
			var mx = screenToWorldX(ev.clientX - rect.left, canvas.width);
			var my = screenToWorldY(ev.clientY - rect.top, canvas.height);
			var spriteCX = canvas.width / 2;
			var spriteCY = canvas.height / 2;

			var slots = ship.getCannonSlots(currentDirection);
			var leftIdx = findTileSlotMarkerAt(mx, my, spriteCX, spriteCY, cast slots.left, currentDirection);
			var rightIdx = findTileSlotMarkerAt(mx, my, spriteCX, spriteCY, cast slots.right, currentDirection);
			if (leftIdx >= 0 || rightIdx >= 0) {
				if (rightIdx < 0 || leftIdx >= 0) {
					selectedCannonSide = "left";
					selectedCannonIdx = leftIdx;
				} else {
					selectedCannonSide = "right";
					selectedCannonIdx = rightIdx;
				}
				updateCannonInfo();
				renderCannonsCanvas();
				return;
			}

			var tile = canvasPointToTile(canvas, mx, my, currentDirection);
			if (isActiveTile(tile) && selectedCannonSide != null && selectedCannonIdx >= 0) {
				var arr = selectedCannonSide == "left" ? slots.left : slots.right;
				if (selectedCannonIdx < arr.length) {
					pushUndo("cannons");
					arr[selectedCannonIdx].tx = tile.tx;
					arr[selectedCannonIdx].ty = tile.ty;
					updateCannonInfo();
					renderCannonsCanvas();
					updateDirtyIndicators();
				}
			}
		});

		canvas.addEventListener("mousemove", (ev:js.html.MouseEvent) -> {
			if (ship == null)
				return;
			var rect = canvas.getBoundingClientRect();
			var mx = screenToWorldX(ev.clientX - rect.left, canvas.width);
			var my = screenToWorldY(ev.clientY - rect.top, canvas.height);
			updateHoveredTileForCanvas(canvas, mx, my, currentDirection);
		});

		canvas.addEventListener("mouseup", (_) -> {
			isDragging = false;
			updateDirtyIndicators();
		});

		canvas.addEventListener("mouseleave", (_) -> {
			isDragging = false;
			if (hoveredTileX != -1 || hoveredTileY != -1) {
				hoveredTileX = -1;
				hoveredTileY = -1;
				renderCannonsCanvas();
			}
		});
	}

	function updateCannonInfo() {
		if (ship == null)
			return;
		var slots = ship.getCannonSlots(currentDirection);
		var d:String = currentDirection;
		jPage.find(".cannonCount").text(Std.string(ship.maxCannonsPerSide));
		var selected = selectedCannonSide != null && selectedCannonIdx >= 0 ? ' | Selected: ${selectedCannonSide} ${selectedCannonIdx + 1}' : "";
		jPage.find(".cannonInfo").html('Preview: $d | Left: ${slots.left.length} | Right: ${slots.right.length} | Max per side: ${ship.maxCannonsPerSide}$selected');
	}

	function renderCannonsCanvas() {
		var canvas:CanvasElement = cast jPage.find(".cannonSlotsCanvas").get(0);
		if (canvas == null || ship == null)
			return;

		var sz = getCanvasSize();
		canvas.width = sz.w;
		canvas.height = sz.h;
		var ctx = canvas.getContext2d();
		ctx.clearRect(0, 0, canvas.width, canvas.height);

		ctx.save();
		ctx.translate(canvas.width / 2 + canvasPanX, canvas.height / 2 + canvasPanY);
		ctx.scale(canvasZoom, canvasZoom);
		ctx.translate(-canvas.width / 2, -canvas.height / 2);

		var spriteCX = canvas.width / 2;
		var spriteCY = canvas.height / 2;

		// Draw sprite
		var d:String = currentDirection;
		var img = spriteImages.get(d);
		if (img != null) {
			var drawW = img.width * assetScale;
			var drawH = img.height * assetScale;
			ctx.drawImage(img, spriteCX - drawW / 2, spriteCY - drawH / 2, drawW, drawH);
			ctx.strokeStyle = "rgba(255,255,255,0.3)";
			ctx.lineWidth = 1;
			ctx.strokeRect(Std.int(spriteCX - drawW / 2) + 0.5, Std.int(spriteCY - drawH / 2) + 0.5, drawW - 1, drawH - 1);
		} else {
			ctx.fillStyle = "#333";
			ctx.fillRect(spriteCX - 50, spriteCY - 75, 100, 150);
		}

		// Draw crosshair at center
		ctx.strokeStyle = "rgba(255,255,255,0.2)";
		ctx.lineWidth = 1;
		ctx.beginPath();
		ctx.moveTo(spriteCX, 0);
		ctx.lineTo(spriteCX, canvas.height);
		ctx.moveTo(0, spriteCY);
		ctx.lineTo(canvas.width, spriteCY);
		ctx.stroke();

		// Draw optional visual grid overlay (half opacity compared to Visual Offsets)
		if (showCannonGrid) {
			var off = ship.getVisualOffset(currentDirection);
			drawIsoGrid(ctx, spriteCX + off.x, spriteCY - off.y, currentDirection, 0.5);
		}

		// Draw optional helper lines at 2× tile size
		if (showCannonHelperLines) {
			drawHelperLines(ctx, spriteCX, spriteCY, canvas.width, canvas.height);
		}

		var off = ship.getVisualOffset(currentDirection);
		var gridCX = spriteCX + off.x;
		var gridCY = spriteCY - off.y;
		if (hoveredTileX >= 0 && hoveredTileX < ship.deckGrid.width && hoveredTileY >= 0 && hoveredTileY < ship.deckGrid.height) {
			drawTileHighlight(ctx, gridCX, gridCY, hoveredTileX, hoveredTileY, currentDirection, "rgba(255,200,50,0.25)");
		}

		// Draw cannon markers
		var slots = ship.getCannonSlots(currentDirection);
		drawCannonMarkers(ctx, spriteCX, spriteCY, slots.left, "#4488ff", "L", "left");
		drawCannonMarkers(ctx, spriteCX, spriteCY, slots.right, "#ff4444", "R", "right");

		ctx.restore();
	}

	function drawCannonMarkers(ctx:CanvasRenderingContext2D, cx:Float, cy:Float, slots:Array<CannonSlot>, color:String, label:String, side:String) {
		var r = 6.0;
		for (i in 0...slots.length) {
			var s = slots[i];
			var pos = tileSlotToCanvasPosition(cx, cy, s, currentDirection);
			var sx = pos.x;
			var sy = pos.y;

			ctx.beginPath();
			ctx.arc(sx, sy, r, 0, Math.PI * 2);
			ctx.fillStyle = color;
			ctx.fill();
			ctx.strokeStyle = "#ffffff";
			ctx.lineWidth = selectedCannonSide == side && selectedCannonIdx == i ? 3 : 1.5;
			ctx.stroke();

			ctx.fillStyle = "#ffffff";
			ctx.font = "9px sans-serif";
			ctx.textAlign = "center";
			ctx.textBaseline = "middle";
			ctx.fillText(label + Std.string(i + 1), sx, sy);
		}
	}

	function drawHelperLines(ctx:CanvasRenderingContext2D, cx:Float, cy:Float, canvasW:Float, canvasH:Float) {
		if (ship == null)
			return;
		var step = ship.deckGrid.tile_size * 2.0;
		if (step <= 0)
			return;

		ctx.strokeStyle = "rgba(255, 255, 255, 0.4)";
		ctx.lineWidth = 0.5;

		// Vertical lines
		var x = cx;
		while (x < canvasW) {
			ctx.beginPath();
			ctx.moveTo(x, 0);
			ctx.lineTo(x, canvasH);
			ctx.stroke();
			x += step;
		}
		x = cx - step;
		while (x > 0) {
			ctx.beginPath();
			ctx.moveTo(x, 0);
			ctx.lineTo(x, canvasH);
			ctx.stroke();
			x -= step;
		}

		// Horizontal lines
		var y = cy;
		while (y < canvasH) {
			ctx.beginPath();
			ctx.moveTo(0, y);
			ctx.lineTo(canvasW, y);
			ctx.stroke();
			y += step;
		}
		y = cy - step;
		while (y > 0) {
			ctx.beginPath();
			ctx.moveTo(0, y);
			ctx.lineTo(canvasW, y);
			ctx.stroke();
			y -= step;
		}
	}

	function tileSlotToCanvasPosition(cx:Float, cy:Float, slot:{tx:Int, ty:Int}, dir:ShipDirection):{x:Float, y:Float} {
		if (ship == null)
			return {x: cx, y: cy};
		var off = ship.getVisualOffset(dir);
		var screen = tileToScreen(slot.tx + 0.5, slot.ty + 0.5, dir);
		return {
			x: cx + off.x + screen.x,
			y: cy - off.y + screen.y
		};
	}

	function findTileSlotMarkerAt(mx:Float, my:Float, cx:Float, cy:Float, slots:Array<{tx:Int, ty:Int}>, dir:ShipDirection):Int {
		var bestIdx = -1;
		var bestDist = 12.0 / canvasZoom;
		for (i in 0...slots.length) {
			var pos = tileSlotToCanvasPosition(cx, cy, slots[i], dir);
			var dx = pos.x - mx;
			var dy = pos.y - my;
			var dist = Math.sqrt(dx * dx + dy * dy);
			if (dist < bestDist) {
				bestDist = dist;
				bestIdx = i;
			}
		}
		return bestIdx;
	}

	function findLadderDeckMarkerAt(mx:Float, my:Float, cx:Float, cy:Float, slots:Array<TileSlot>, dir:ShipDirection):Int {
		var bestIdx = -1;
		var bestDist = 12.0 / canvasZoom;
		for (i in 0...slots.length) {
			var pos = tileSlotToCanvasPosition(cx, cy, slots[i], dir);
			var dx = pos.x - mx;
			var dy = pos.y - my;
			var dist = Math.sqrt(dx * dx + dy * dy);
			if (dist < bestDist) {
				bestDist = dist;
				bestIdx = i;
			}
		}
		return bestIdx;
	}

	function findLadderBoardMarkerAt(mx:Float, my:Float, cx:Float, cy:Float, points:Array<BoardPoint>):Int {
		var bestIdx = -1;
		var bestDist = 14.0 / canvasZoom;
		for (i in 0...points.length) {
			var point = points[i];
			var sx = cx + point.x;
			var sy = cy - point.y;
			var dx = sx - mx;
			var dy = sy - my;
			var dist = Math.sqrt(dx * dx + dy * dy);
			if (dist < bestDist) {
				bestDist = dist;
				bestIdx = i;
			}
		}
		return bestIdx;
	}

	// =========================================================================
	// Props Screen
	// =========================================================================

	function initPropsScreen() {
		// Prop type switcher
		jPage.find(".propTypeBtn").click((ev:js.jquery.Event) -> {
			var jBtn = new J(ev.currentTarget);
			var propType = jBtn.attr("data-prop");
			if (propType == null)
				return;
			currentPropType = propType;
			jPage.find(".propTypeBtn").removeClass("active");
			jBtn.addClass("active");
			jPage.find(".propConfig").hide();
			jPage.find('.propConfig-$propType').show();
			// Rebuild direction switchers inside props configs
			jPage.find(".screen.props .directionSwitcher").each((idx, el) -> {
				buildDirectionSwitcher(new J(el));
			});
			updatePropInfo();
			renderPropsCanvas();
		});

		jPage.find(".ladderModeBtn").click((ev:js.jquery.Event) -> {
			var jBtn = new J(ev.currentTarget);
			var mode = jBtn.attr("data-mode");
			if (mode != null) {
				ladderPlacementMode = mode;
				jPage.find(".ladderModeBtn").removeClass("active");
				jBtn.addClass("active");
				updatePropInfo();
				renderPropsCanvas();
			}
		});

		jPage.find(".ladderIndexSelect").on("change", (ev:js.jquery.Event) -> {
			var val = Std.parseInt(new J(ev.currentTarget).val());
			if (val != null) {
				selectedLadderIdx = val;
				updatePropInfo();
				renderPropsCanvas();
			}
		});

		jPage.find(".mastCountSelect").on("change", (ev:js.jquery.Event) -> {
			var val = Std.parseInt(new J(ev.currentTarget).val());
			if (ship != null && val != null) {
				selectedMastCount = val;
				var config = ship.getMastSlotConfiguration(selectedMastCount);
				selectedMastIdx = config.slots.length > 0 ? 0 : -1;
				updatePropInfo();
				renderPropsCanvas();
			}
		});

		jPage.find(".mastIndexSelect").on("change", (ev:js.jquery.Event) -> {
			var val = Std.parseInt(new J(ev.currentTarget).val());
			if (val != null) {
				selectedMastIdx = val;
				updatePropInfo();
				renderPropsCanvas();
			}
		});

		// Visual grid overlay toggle
		jPage.find(".showPropsGrid").on("change", (_) -> {
			showPropsGrid = jPage.find(".showPropsGrid").is(":checked");
			renderPropsCanvas();
		});
		// Helper lines toggle
		jPage.find(".showPropsHelperLines").on("change", (_) -> {
			showPropsHelperLines = jPage.find(".showPropsHelperLines").is(":checked");
			renderPropsCanvas();
		});

		// Ladder slots: Add two points to keep an even slot count.
		jPage.find(".addPropPoint").click((_) -> {
			if (ship == null)
				return;
			pushUndo("props");
			var slots = ship.getLadderDeckSlots();
			var leftDefault = defaultTileForSide("left");
			var rightDefault = defaultTileForSide("right");
			ship.addLadderSlot(leftDefault);
			ship.addLadderSlot(rightDefault);
			selectedLadderIdx = slots.slots.length - 2;
			updatePropInfo();
			renderPropsCanvas();
			updateDirtyIndicators();
		});

		// Ladder slots: Remove two points to keep an even slot count.
		jPage.find(".removePropPoint").click((_) -> {
			if (ship == null)
				return;
			pushUndo("props");
			var slots = ship.getLadderDeckSlots();
			for (dir in ShipDirection.all()) {
				var points = ship.getLadderBoardPoints(dir).slots;
				if (points.length > 0)
					points.pop();
				if (points.length > 0)
					points.pop();
			}
			if (slots.slots.length > 0)
				slots.slots.pop();
			if (slots.slots.length > 0)
				slots.slots.pop();
			if (selectedLadderIdx >= slots.slots.length)
				selectedLadderIdx = slots.slots.length - 1;
			updatePropInfo();
			renderPropsCanvas();
			updateDirtyIndicators();
		});

		// Wheel assets: Select Folder
		jPage.find(".selectWheelAssets").click((_) -> {
			if (ship == null)
				return;
			var dir = ship.assetsPath != null ? ship.assetsPath.full : (ship.filePath != null ? ship.filePath.directory : App.ME.getDefaultDialogDir());
			dn.js.ElectronDialogs.openDir(dir, (dirPath) -> {
				if (dirPath == null)
					return;
				// Auto-detect prefix using raw JS, returning detailed JSON result for debugging
				var scanResultJson:String = js.Syntax.code("(function(dir) {
					try {
						var fs = require('fs');
						if (!fs.existsSync(dir)) return JSON.stringify({error: 'Directory does not exist'});
						var files = fs.readdirSync(dir);
						var pngs = [];
						for (var i = 0; i < files.length; i++) {
							if (files[i].toLowerCase().endsWith('.png')) {
								pngs.push(files[i]);
								if (files[i].toLowerCase().endsWith('_n.png')) {
									return JSON.stringify({prefix: files[i].substring(0, files[i].length - 6), pngCount: pngs.length});
								}
							}
						}
						return JSON.stringify({error: 'No file ending with _n.png found', filesFound: pngs.slice(0, 5).join(', ')});
					} catch(e) { return JSON.stringify({error: e.toString()}); }
				})({0})", dirPath);

				var result:Dynamic = haxe.Json.parse(scanResultJson);

				if (Reflect.hasField(result, "error")) {
					var err = Reflect.field(result, "error");
					var filesFound = Reflect.hasField(result, "filesFound") ? Reflect.field(result, "filesFound") : "none";
					js.Browser.window.alert("Could not load wheel assets!\n\nReason: " + err + "\nPNGs found in folder: " + filesFound + "\n\nPlease ensure your north-facing wheel is named ending with '_n.png' (e.g. helm_wheel_n.png).");
					return;
				}

				var detectedPrefix:String = Reflect.field(result, "prefix");
				js.Browser.window.alert("Successfully loaded wheel assets!\nDetected prefix: " + detectedPrefix);

				ship.steeringWheelAsset = dirPath + "|" + detectedPrefix;
				jPage.find(".wheelAssetPath").text(dirPath + " / " + detectedPrefix + "_*.png");
				loadWheelAssets();
			});
		});

		// Wheel assets: Scale
		jPage.find(".wheelScaleInput").on("input change", (ev:js.jquery.Event) -> {
			if (ship == null)
				return;
			var jInput = new J(ev.currentTarget);
			var val = Std.parseFloat(jInput.val());
			if (!Math.isNaN(val) && val > 0) {
				ship.steeringWheelScale = val;
				renderPropsCanvas();
				updateDirtyIndicators();
			}
		});

		// Wheel placement mode buttons
		jPage.find(".wheelModeBtn").click((ev:js.jquery.Event) -> {
			var jBtn = new J(ev.currentTarget);
			var mode = jBtn.attr("data-mode");
			if (mode != null) {
				wheelPlacementMode = mode;
				jPage.find(".wheelModeBtn").removeClass("active");
				jBtn.addClass("active");
				renderPropsCanvas();
			}
		});

		// Canvas interaction
		var canvas:CanvasElement = cast jPage.find(".propsCanvasEl").get(0);
		if (canvas == null)
			return;

		canvas.addEventListener("mousedown", (ev:js.html.MouseEvent) -> {
			if (ship == null || ev.button != 0)
				return;
			var rect = canvas.getBoundingClientRect();
			var mx = screenToWorldX(ev.clientX - rect.left, canvas.width);
			var my = screenToWorldY(ev.clientY - rect.top, canvas.height);
			var spriteCX = canvas.width / 2;
			var spriteCY = canvas.height / 2;

			if (currentPropType == "ladder_slots") {
				var deckSlots = ship.getLadderDeckSlots();
				if (selectedLadderIdx < 0 && deckSlots.slots.length > 0)
					selectedLadderIdx = 0;
				if (ladderPlacementMode == "board") {
					var boardPoints = ship.getLadderBoardPoints(currentDirection);
					var boardIdx = findLadderBoardMarkerAt(mx, my, spriteCX, spriteCY, boardPoints.slots);
					if (boardIdx >= 0) {
						selectedLadderIdx = boardIdx;
					}
					if (selectedLadderIdx >= 0 && selectedLadderIdx < boardPoints.slots.length) {
						pushUndo("props");
						var point = ship.getLadderBoardPoint(selectedLadderIdx, currentDirection);
						point.x = Std.int(mx - spriteCX);
						point.y = Std.int(spriteCY - my);
						isDragging = true;
						dragPropType = "ladder_board";
						dragPropIdx = selectedLadderIdx;
						dragStartX = mx;
						dragStartY = my;
						dragOffsetStartX = point.x;
						dragOffsetStartY = point.y;
						updatePropInfo();
						renderPropsCanvas();
						updateDirtyIndicators();
					}
				} else if (ladderPlacementMode == "deck") {
					var markerIdx = findLadderDeckMarkerAt(mx, my, spriteCX, spriteCY, deckSlots.slots, currentDirection);
					if (markerIdx >= 0) {
						selectedLadderIdx = markerIdx;
						updatePropInfo();
						renderPropsCanvas();
						return;
					}
					var tile = canvasPointToTile(canvas, mx, my, currentDirection);
					if (isActiveTile(tile) && selectedLadderIdx >= 0 && selectedLadderIdx < deckSlots.slots.length) {
						pushUndo("props");
						deckSlots.slots[selectedLadderIdx].tx = tile.tx;
						deckSlots.slots[selectedLadderIdx].ty = tile.ty;
						updatePropInfo();
						renderPropsCanvas();
						updateDirtyIndicators();
					}
				}
			} else if (currentPropType == "steering_wheel") {
				// Click-to-place on tile for steering wheel / helmsman
				var tile = canvasPointToTile(canvas, mx, my, currentDirection);
				if (isActiveTile(tile)) {
					pushUndo("props");
					if (wheelPlacementMode == "helmsman") {
						ship.helmsmanTile.tx = tile.tx;
						ship.helmsmanTile.ty = tile.ty;
					} else {
						ship.steeringWheelTile.tx = tile.tx;
						ship.steeringWheelTile.ty = tile.ty;
					}
					updatePropInfo();
					renderPropsCanvas();
					updateDirtyIndicators();
				}
			} else if (currentPropType == "masts") {
				var config = ship.getMastSlotConfiguration(selectedMastCount);
				if (selectedMastIdx < 0 && config.slots.length > 0)
					selectedMastIdx = 0;
				var markerIdx = findTileSlotMarkerAt(mx, my, spriteCX, spriteCY, cast config.slots, currentDirection);
				if (markerIdx >= 0) {
					selectedMastIdx = markerIdx;
					updatePropInfo();
					renderPropsCanvas();
					return;
				}
				var tile = canvasPointToTile(canvas, mx, my, currentDirection);
				if (isActiveTile(tile) && selectedMastIdx >= 0 && selectedMastIdx < config.slots.length) {
					pushUndo("props");
					config.slots[selectedMastIdx].tx = tile.tx;
					config.slots[selectedMastIdx].ty = tile.ty;
					updatePropInfo();
					renderPropsCanvas();
					updateDirtyIndicators();
				}
			}
		});

		canvas.addEventListener("mousemove", (ev:js.html.MouseEvent) -> {
			if (ship == null)
				return;
			var rect = canvas.getBoundingClientRect();
			var mx = screenToWorldX(ev.clientX - rect.left, canvas.width);
			var my = screenToWorldY(ev.clientY - rect.top, canvas.height);

			if (isDragging && dragPropType == "ladder_board") {
				var points = ship.getLadderBoardPoints(currentDirection).slots;
				if (dragPropIdx >= 0 && dragPropIdx < points.length) {
					var dx = mx - dragStartX;
					var dy = my - dragStartY;
					var point = points[dragPropIdx];
					point.x = Std.int(dragOffsetStartX + dx);
					point.y = Std.int(dragOffsetStartY - dy);
					updatePropInfo();
					renderPropsCanvas();
				}
			} else if ((currentPropType == "ladder_slots" && ladderPlacementMode == "deck") || currentPropType == "steering_wheel" || currentPropType == "masts") {
				updateHoveredTileForCanvas(canvas, mx, my, currentDirection);
			}
		});

		canvas.addEventListener("mouseup", (_) -> {
			isDragging = false;
			dragPropType = null;
			dragPropIdx = -1;
			updateDirtyIndicators();
		});

		canvas.addEventListener("mouseleave", (_) -> {
			isDragging = false;
			dragPropType = null;
			dragPropIdx = -1;
			if (hoveredTileX != -1 || hoveredTileY != -1) {
				hoveredTileX = -1;
				hoveredTileY = -1;
				renderPropsCanvas();
			}
		});
	}

	function loadWheelAssets() {
		if (ship == null || ship.steeringWheelAsset == null)
			return;

		// Parse "folder|prefix" format
		var parts = ship.steeringWheelAsset.split("|");
		if (parts.length != 2)
			return;
		var folderPath = parts[0];
		var prefix = parts[1];

		wheelImages = new Map();
		var loadedCount = 0;
		var totalCount = 8;

		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var suffix = dir.toFileSuffix();
			var path = folderPath + "/" + prefix + "_" + suffix + ".png";
			if (NT.fileExists(path)) {
				var img = new Image();
				var dirKey = d;
				img.onload = () -> {
					wheelImages.set(dirKey, img);
					loadedCount++;
					if (loadedCount >= totalCount) {
						renderPropsCanvas();
					}
				};
				img.onerror = () -> {
					loadedCount++;
					if (loadedCount >= totalCount) {
						renderPropsCanvas();
					}
				};
				img.src = "data:image/png;base64," + haxe.crypto.Base64.encode(NT.readFileBytes(path));
			} else {
				loadedCount++;
				if (loadedCount >= totalCount) {
					renderPropsCanvas();
				}
			}
		}
	}

	function updatePropInfo() {
		if (ship == null)
			return;
		var d:String = currentDirection;
		if (currentPropType == "ladder_slots") {
			var deckSlots = ship.getLadderDeckSlots();
			if (selectedLadderIdx < 0 && deckSlots.slots.length > 0)
				selectedLadderIdx = 0;
			if (selectedLadderIdx >= deckSlots.slots.length)
				selectedLadderIdx = deckSlots.slots.length - 1;

			jPage.find(".propConfig-ladder_slots .propCount").text(Std.string(deckSlots.slots.length));
			var jSelect = jPage.find(".ladderIndexSelect");
			jSelect.empty();
			for (i in 0...deckSlots.slots.length) {
				var jOption = new J('<option/>');
				jOption.attr("value", Std.string(i));
				jOption.text("Ladder " + Std.string(i + 1));
				if (i == selectedLadderIdx)
					jOption.attr("selected", "selected");
				jSelect.append(jOption);
			}
			jSelect.prop("disabled", deckSlots.slots.length == 0);

			var selected = selectedLadderIdx >= 0 ? ' | Selected: ${selectedLadderIdx + 1}' : "";
			var mode = ladderPlacementMode == "board" ? "Board Point" : "Ladder Deck";
			var info = 'Preview: $d | Mode: $mode | Ladders: ${deckSlots.slots.length}$selected';
			if (selectedLadderIdx >= 0 && selectedLadderIdx < deckSlots.slots.length) {
				var deck = deckSlots.slots[selectedLadderIdx];
				var point = ship.getLadderBoardPoint(selectedLadderIdx, currentDirection);
				info += ' | Deck: (${deck.tx}, ${deck.ty}) | Board: (${point.x}, ${point.y})';
			}
			jPage.find(".propConfig-ladder_slots .propInfo").html(info);
		} else if (currentPropType == "steering_wheel") {
			var sw = ship.steeringWheelTile;
			var hm = ship.helmsmanTile;
			var info = 'Wheel Tile: (${sw.tx}, ${sw.ty}) | Helmsman Tile: (${hm.tx}, ${hm.ty})';
			jPage.find(".propConfig-steering_wheel .propInfo").html(info);
		} else if (currentPropType == "masts") {
			ship.ensureMastSlotConfigurations();
			if (selectedMastCount < 1)
				selectedMastCount = 1;
			if (selectedMastCount > ship.maxMastCount)
				selectedMastCount = ship.maxMastCount;
			var config = ship.getMastSlotConfiguration(selectedMastCount);
			if (selectedMastIdx < 0 && config.slots.length > 0)
				selectedMastIdx = 0;
			if (selectedMastIdx >= config.slots.length)
				selectedMastIdx = config.slots.length - 1;

			var countSelect = jPage.find(".mastCountSelect");
			countSelect.empty();
			for (count in 1...(ship.maxMastCount + 1)) {
				var countOption = new J('<option/>');
				countOption.attr("value", Std.string(count));
				countOption.text(Std.string(count) + (count == 1 ? " mast" : " masts"));
				if (count == selectedMastCount)
					countOption.attr("selected", "selected");
				countSelect.append(countOption);
			}

			var mastSelect = jPage.find(".mastIndexSelect");
			mastSelect.empty();
			for (i in 0...config.slots.length) {
				var mastOption = new J('<option/>');
				mastOption.attr("value", Std.string(i));
				mastOption.text("Mast " + Std.string(i + 1));
				if (i == selectedMastIdx)
					mastOption.attr("selected", "selected");
				mastSelect.append(mastOption);
			}
			mastSelect.prop("disabled", config.slots.length == 0);

			var mastInfo = 'Preview: $d | Configuration: $selectedMastCount | Max sails per mast: ${ship.maxSailsPerMast}';
			if (selectedMastIdx >= 0 && selectedMastIdx < config.slots.length) {
				var slot = config.slots[selectedMastIdx];
				mastInfo += ' | Selected: ${selectedMastIdx + 1} | Tile: (${slot.tx}, ${slot.ty})';
			}
			jPage.find(".propConfig-masts .propInfo").html(mastInfo);
		}
	}

	function capturePropsState():String {
		if (ship == null)
			return "{}";
		var deckSlots = ship.getLadderDeckSlots();
		var boardObj:haxe.DynamicAccess<Dynamic> = {};
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var points = ship.getLadderBoardPoints(dir);
			boardObj.set(d, {slots: [for (p in points.slots) {x: p.x, y: p.y}]});
		}
		ship.ensureMastSlotConfigurations();
		var mastConfigs:haxe.DynamicAccess<Dynamic> = {};
		for (count in 1...(ship.maxMastCount + 1)) {
			var config = ship.getMastSlotConfiguration(count);
			mastConfigs.set(Std.string(count), {slots: [for (s in config.slots) {tx: s.tx, ty: s.ty}]});
		}
		return haxe.Json.stringify({
			ladder_deck_slots: {slots: [for (s in deckSlots.slots) {tx: s.tx, ty: s.ty}]},
			ladder_board_points: boardObj,
			mast_slots: {configurations: mastConfigs},
			steering_wheel: {tx: ship.steeringWheelTile.tx, ty: ship.steeringWheelTile.ty},
			helmsman: {tx: ship.helmsmanTile.tx, ty: ship.helmsmanTile.ty},
			steering_wheel_asset: ship.steeringWheelAsset
		});
	}

	function restorePropsState(json:String) {
		if (ship == null)
			return;
		try {
			var obj:Dynamic = haxe.Json.parse(json);
			var deckData:Dynamic = obj.ladder_deck_slots;
			if (deckData != null) {
				var slotsArr:Array<Dynamic> = deckData.slots;
				var deckSlots = ship.getLadderDeckSlots();
				deckSlots.slots = [];
				if (slotsArr != null) {
					for (s in slotsArr) {
						deckSlots.slots.push({
							tx: Reflect.hasField(s, "tx") ? Std.int(Reflect.field(s, "tx")) : 0,
							ty: Reflect.hasField(s, "ty") ? Std.int(Reflect.field(s, "ty")) : 0
						});
					}
				}
				var boardData:Dynamic = Reflect.field(obj, "ladder_board_points");
				for (dir in ShipDirection.all()) {
					var d:String = dir;
					var directionData:Dynamic = boardData != null ? Reflect.field(boardData, d) : null;
					var points = ship.getLadderBoardPoints(dir);
					points.slots = [];
					var rawPoints:Array<Dynamic> = directionData != null ? Reflect.field(directionData, "slots") : null;
					if (rawPoints != null) {
						for (p in rawPoints)
							points.slots.push({
								x: Reflect.hasField(p, "x") ? Std.int(Reflect.field(p, "x")) : 0,
								y: Reflect.hasField(p, "y") ? Std.int(Reflect.field(p, "y")) : 0
							});
					}
					while (points.slots.length < deckSlots.slots.length)
						points.slots.push(ship.getDefaultBoardPointForDeck(deckSlots.slots[points.slots.length], dir));
					while (points.slots.length > deckSlots.slots.length)
						points.slots.pop();
				}
				if (selectedLadderIdx >= deckSlots.slots.length)
					selectedLadderIdx = deckSlots.slots.length - 1;
			}
			var mastData:Dynamic = Reflect.field(obj, "mast_slots");
			var mastConfigurations:Dynamic = mastData != null ? Reflect.field(mastData, "configurations") : null;
			if (mastConfigurations != null) {
				for (count in 1...(ship.maxMastCount + 1)) {
					var rawConfig:Dynamic = Reflect.field(mastConfigurations, Std.string(count));
					var rawSlots:Array<Dynamic> = rawConfig != null ? Reflect.field(rawConfig, "slots") : null;
					if (rawSlots != null) {
						var config = ship.getMastSlotConfiguration(count);
						config.slots = [];
						for (s in rawSlots)
							config.slots.push({
								tx: Reflect.hasField(s, "tx") ? Std.int(Reflect.field(s, "tx")) : 0,
								ty: Reflect.hasField(s, "ty") ? Std.int(Reflect.field(s, "ty")) : 0
							});
					}
				}
				ship.ensureMastSlotConfigurations();
				if (selectedMastCount > ship.maxMastCount)
					selectedMastCount = ship.maxMastCount;
				var mastConfig = ship.getMastSlotConfiguration(selectedMastCount);
				if (selectedMastIdx >= mastConfig.slots.length)
					selectedMastIdx = mastConfig.slots.length - 1;
			}
			var swDir:Dynamic = obj.steering_wheel;
			if (swDir != null) {
				ship.steeringWheelTile.tx = Reflect.hasField(swDir, "tx") ? Std.int(swDir.tx) : 0;
				ship.steeringWheelTile.ty = Reflect.hasField(swDir, "ty") ? Std.int(swDir.ty) : 0;
			}
			var hmDir:Dynamic = obj.helmsman;
			if (hmDir != null) {
				ship.helmsmanTile.tx = Reflect.hasField(hmDir, "tx") ? Std.int(hmDir.tx) : 0;
				ship.helmsmanTile.ty = Reflect.hasField(hmDir, "ty") ? Std.int(hmDir.ty) : 0;
			}
			if (Reflect.hasField(obj, "steering_wheel_asset"))
				ship.steeringWheelAsset = obj.steering_wheel_asset;
		} catch (_) {}
	}

	function renderPropsCanvas() {
		var canvas:CanvasElement = cast jPage.find(".propsCanvasEl").get(0);
		if (canvas == null || ship == null)
			return;

		var sz = getCanvasSize();
		canvas.width = sz.w;
		canvas.height = sz.h;
		var ctx = canvas.getContext2d();
		ctx.clearRect(0, 0, canvas.width, canvas.height);

		ctx.save();
		ctx.translate(canvas.width / 2 + canvasPanX, canvas.height / 2 + canvasPanY);
		ctx.scale(canvasZoom, canvasZoom);
		ctx.translate(-canvas.width / 2, -canvas.height / 2);

		var spriteCX = canvas.width / 2;
		var spriteCY = canvas.height / 2;

		// Draw sprite
		var d:String = currentDirection;
		var img = spriteImages.get(d);
		if (img != null) {
			var drawW = img.width * assetScale;
			var drawH = img.height * assetScale;
			ctx.drawImage(img, spriteCX - drawW / 2, spriteCY - drawH / 2, drawW, drawH);
			ctx.strokeStyle = "rgba(255,255,255,0.3)";
			ctx.lineWidth = 1;
			ctx.strokeRect(Std.int(spriteCX - drawW / 2) + 0.5, Std.int(spriteCY - drawH / 2) + 0.5, drawW - 1, drawH - 1);
		} else {
			ctx.fillStyle = "#333";
			ctx.fillRect(spriteCX - 50, spriteCY - 75, 100, 150);
		}

		// Draw crosshair at center
		ctx.strokeStyle = "rgba(255,255,255,0.2)";
		ctx.lineWidth = 1;
		ctx.beginPath();
		ctx.moveTo(spriteCX, 0);
		ctx.lineTo(spriteCX, canvas.height);
		ctx.moveTo(0, spriteCY);
		ctx.lineTo(canvas.width, spriteCY);
		ctx.stroke();

		// Draw optional visual grid overlay. Tile-placement modes keep active deck tiles visible.
		if (showPropsGrid || currentPropType == "steering_wheel" || currentPropType == "masts" || (currentPropType == "ladder_slots" && ladderPlacementMode == "deck")) {
			var off = ship.getVisualOffset(currentDirection);
			drawIsoGrid(ctx, spriteCX + off.x, spriteCY - off.y, currentDirection, 0.5);
		}

		// Draw optional helper lines
		if (showPropsHelperLines) {
			drawHelperLines(ctx, spriteCX, spriteCY, canvas.width, canvas.height);
		}

		// Draw prop markers based on current type
		if (currentPropType == "ladder_slots") {
			var off = ship.getVisualOffset(currentDirection);
			var gridCX = spriteCX + off.x;
			var gridCY = spriteCY - off.y;
			if (ladderPlacementMode == "deck" && hoveredTileX >= 0 && hoveredTileX < ship.deckGrid.width && hoveredTileY >= 0 && hoveredTileY < ship.deckGrid.height) {
				drawTileHighlight(ctx, gridCX, gridCY, hoveredTileX, hoveredTileY, currentDirection, "rgba(100,220,100,0.25)");
			}
			var deckSlots = ship.getLadderDeckSlots();
			var boardPoints = ship.getLadderBoardPoints(currentDirection);
			drawLadderMarkers(ctx, spriteCX, spriteCY, deckSlots.slots, boardPoints.slots);
		} else if (currentPropType == "masts") {
			var off = ship.getVisualOffset(currentDirection);
			var gridCX = spriteCX + off.x;
			var gridCY = spriteCY - off.y;
			if (hoveredTileX >= 0 && hoveredTileX < ship.deckGrid.width && hoveredTileY >= 0 && hoveredTileY < ship.deckGrid.height) {
				drawTileHighlight(ctx, gridCX, gridCY, hoveredTileX, hoveredTileY, currentDirection, "rgba(255,200,50,0.28)");
			}
			var mastConfig = ship.getMastSlotConfiguration(selectedMastCount);
			drawMastMarkers(ctx, spriteCX, spriteCY, mastConfig.slots);
		} else if (currentPropType == "steering_wheel") {
			var off = ship.getVisualOffset(currentDirection);
			var gridCX = spriteCX + off.x;
			var gridCY = spriteCY - off.y;

			// Draw hovered tile highlight
			if (hoveredTileX >= 0 && hoveredTileX < ship.deckGrid.width && hoveredTileY >= 0 && hoveredTileY < ship.deckGrid.height) {
				drawTileHighlight(ctx, gridCX, gridCY, hoveredTileX, hoveredTileY, currentDirection,
					wheelPlacementMode == "helmsman" ? "rgba(100,150,255,0.3)" : "rgba(255,200,50,0.3)");
			}

			// Draw steering wheel at tile position
			var sw = ship.steeringWheelTile;
			var swScreen = tileToScreen(sw.tx + 0.5, sw.ty + 0.5, currentDirection);
			var sx = gridCX + swScreen.x;
			var sy = gridCY + swScreen.y;

			// Draw wheel sprite if available
			var wheelImg = wheelImages.get(d);
			if (wheelImg != null) {
				var customScale = ship.steeringWheelScale != null ? ship.steeringWheelScale : 1.0;
				var wW = wheelImg.width * assetScale * customScale;
				var wH = wheelImg.height * assetScale * customScale;
				ctx.drawImage(wheelImg, sx - wW / 2, sy - wH / 2, wW, wH);
			}

			// Wheel marker (gold diamond)
			ctx.save();
			ctx.translate(sx, sy);
			ctx.rotate(Math.PI / 4);
			ctx.fillStyle = "#cca922";
			ctx.fillRect(-5, -5, 10, 10);
			ctx.strokeStyle = "#ffffff";
			ctx.lineWidth = 1.5;
			ctx.strokeRect(-5, -5, 10, 10);
			ctx.restore();
			ctx.fillStyle = "#ffffff";
			ctx.font = "9px sans-serif";
			ctx.textAlign = "center";
			ctx.textBaseline = "top";
			ctx.fillText("W", sx, sy + 8);

			// Draw helmsman marker at tile position
			var hm = ship.helmsmanTile;
			var hmScreen = tileToScreen(hm.tx + 0.5, hm.ty + 0.5, currentDirection);
			var hx = gridCX + hmScreen.x;
			var hy = gridCY + hmScreen.y;

			ctx.beginPath();
			ctx.arc(hx, hy, 6, 0, Math.PI * 2);
			ctx.fillStyle = "#4488ff";
			ctx.fill();
			ctx.strokeStyle = "#ffffff";
			ctx.lineWidth = 1.5;
			ctx.stroke();
			ctx.fillStyle = "#ffffff";
			ctx.font = "9px sans-serif";
			ctx.textAlign = "center";
			ctx.textBaseline = "middle";
			ctx.fillText("H", hx, hy);
		}

		ctx.restore();
	}

	function drawMastMarkers(ctx:CanvasRenderingContext2D, cx:Float, cy:Float, slots:Array<TileSlot>) {
		for (i in 0...slots.length) {
			var pos = tileSlotToCanvasPosition(cx, cy, slots[i], currentDirection);
			var selected = selectedMastIdx == i;

			ctx.beginPath();
			ctx.arc(pos.x, pos.y, 7, 0, Math.PI * 2);
			ctx.fillStyle = "#cc9a32";
			ctx.fill();
			ctx.strokeStyle = "#ffffff";
			ctx.lineWidth = selected ? 3 : 1.5;
			ctx.stroke();

			ctx.fillStyle = "#ffffff";
			ctx.font = "9px sans-serif";
			ctx.textAlign = "center";
			ctx.textBaseline = "middle";
			ctx.fillText("M" + Std.string(i + 1), pos.x, pos.y);
		}
	}

	function drawLadderMarkers(ctx:CanvasRenderingContext2D, cx:Float, cy:Float, deckSlots:Array<TileSlot>, boardPoints:Array<BoardPoint>) {
		if (ship == null)
			return;
		var r = 6.0;
		for (i in 0...deckSlots.length) {
			var deck = deckSlots[i];
			var deckPos = tileSlotToCanvasPosition(cx, cy, deck, currentDirection);
			var point = i < boardPoints.length ? boardPoints[i] : ship.getLadderBoardPoint(i, currentDirection);
			var bx = cx + point.x;
			var by = cy - point.y;
			var selected = selectedLadderIdx == i;

			ctx.beginPath();
			ctx.moveTo(deckPos.x, deckPos.y);
			ctx.lineTo(bx, by);
			ctx.strokeStyle = selected ? "rgba(255,255,255,0.8)" : "rgba(100,220,100,0.45)";
			ctx.lineWidth = selected ? 2 : 1;
			ctx.stroke();

			ctx.save();
			ctx.translate(deckPos.x, deckPos.y);
			ctx.rotate(Math.PI / 4);
			ctx.fillStyle = "#2f8f4b";
			ctx.fillRect(-5, -5, 10, 10);
			ctx.strokeStyle = "#ffffff";
			ctx.lineWidth = selected && ladderPlacementMode == "deck" ? 3 : 1.5;
			ctx.strokeRect(-5, -5, 10, 10);
			ctx.restore();

			ctx.fillStyle = "#ffffff";
			ctx.font = "8px sans-serif";
			ctx.textAlign = "center";
			ctx.textBaseline = "top";
			ctx.fillText("D" + Std.string(i + 1), deckPos.x, deckPos.y + 8);

			ctx.beginPath();
			ctx.arc(bx, by, r, 0, Math.PI * 2);
			ctx.fillStyle = "#44cc44";
			ctx.fill();
			ctx.strokeStyle = "#ffffff";
			ctx.lineWidth = selected && ladderPlacementMode == "board" ? 3 : 1.5;
			ctx.stroke();

			ctx.fillStyle = "#ffffff";
			ctx.font = "9px sans-serif";
			ctx.textAlign = "center";
			ctx.textBaseline = "middle";
			ctx.fillText("B" + Std.string(i + 1), bx, by);
		}
	}

	function drawTileHighlight(ctx:CanvasRenderingContext2D, cx:Float, cy:Float, tx:Int, ty:Int, dir:ShipDirection, color:String) {
		if (ship == null)
			return;

		var rot = getRotationForDirection(dir);
		var half = ship.deckGrid.tile_size / 2;
		var tileCX = tx + 0.5;
		var tileCY = ty + 0.5;
		var center = tileToScreen(tileCX, tileCY, dir);

		var corners = [
			{x: -half, y: -half},
			{x: half, y: -half},
			{x: half, y: half},
			{x: -half, y: half}
		];

		ctx.beginPath();
		for (i in 0...4) {
			var vx = corners[i].x;
			var vy = corners[i].y;
			var rx = vx * rot.cos - vy * rot.sin;
			var ry = (vx * rot.sin + vy * rot.cos) * ISO_Y_SCALE;
			var sx = cx + center.x + rx;
			var sy = cy + center.y + ry;
			if (i == 0)
				ctx.moveTo(sx, sy);
			else
				ctx.lineTo(sx, sy);
		}
		ctx.closePath();
		ctx.fillStyle = color;
		ctx.fill();
		ctx.strokeStyle = "#ffffff";
		ctx.lineWidth = 1.5;
		ctx.stroke();
	}

	// =========================================================================
	// Lifecycle
	// =========================================================================

	override function onKeyPress(keyCode:Int) {
		super.onKeyPress(keyCode);
		if (App.ME.isLocked())
			return;

		switch keyCode {
			case hxd.Key.S:
				if (App.ME.isCtrlCmdDown() && ship != null) {
					saveShip();
				}
			case hxd.Key.Z:
				if (App.ME.isCtrlCmdDown() && ship != null) {
					performUndo();
				}
			case hxd.Key.ESCAPE:
				if (ui.Modal.hasAnyOpen())
					ui.Modal.closeLatest();
			default:
		}
	}

	override function onDispose() {
		super.onDispose();
		ME = null;
	}
}
