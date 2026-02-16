package page;

import data.ShipData;
import data.ShipData.CannonSlot;
import data.ShipData.ShipDirection;
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
	var spritesLoaded:Bool = false;
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
	var dragCannonDir:Null<String> = null;
	var dragCannonSide:Null<String> = null;
	var dragCannonIdx:Int = -1;

	// Undo system
	var undoStack:Array<{tab:String, snapshot:String}> = [];
	var savedGridState:Null<String> = null;
	var savedOffsetsState:Null<String> = null;
	var savedCannonsState:Null<String> = null;

	// Cannon overlay toggles
	var showCannonGrid:Bool = false;
	var showCannonHelperLines:Bool = false;

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

		// Check for recent ship file
		var recentDir = App.ME.settings.getUiDir("ShipEditor", null);
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
			".cannonSlotsCanvas"
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
			".cannonSlotsCanvas"
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

		spritesLoaded = false;
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
		updateDirtyIndicators();

		// Set default asset prefix from file name if not set
		if (ship.assetPrefix == null && ship.filePath != null) {
			ship.assetPrefix = ship.filePath.fileName;
		}

		// Restore asset scale from ship data
		if (ship.assetScale > 0)
			assetScale = ship.assetScale;

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
			trace("Path for $d: " + path);
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
		spritesLoaded = true;
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
		for (cls in ["shipType", "maxCannons"]) {
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
			deck_tiles: ship.deckGrid.deck_tiles.map((t) -> [t[0], t[1]]),
			boarding_point: {x: ship.deckGrid.boarding_point.x, y: ship.deckGrid.boarding_point.y}
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
		var obj:haxe.DynamicAccess<Dynamic> = {};
		for (dir in ShipDirection.all()) {
			var d:String = dir;
			var slots = ship.getCannonSlots(dir);
			var leftArr:Array<Dynamic> = [for (s in slots.left) {x: s.x, y: s.y}];
			var rightArr:Array<Dynamic> = [for (s in slots.right) {x: s.x, y: s.y}];
			obj.set(d, {left: leftArr, right: rightArr});
		}
		return haxe.Json.stringify({slots: obj, maxCannonsPerSide: ship.maxCannonsPerSide});
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
			ship.deckGrid.boarding_point = {x: Std.int(obj.boarding_point.x), y: Std.int(obj.boarding_point.y)};
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
			var slotsObj:haxe.DynamicAccess<Dynamic> = obj.slots;
			for (dir in ShipDirection.all()) {
				var d:String = dir;
				var data:Dynamic = slotsObj.get(d);
				if (data != null) {
					var slots = ship.getCannonSlots(dir);
					var leftArr:Array<Dynamic> = data.left;
					var rightArr:Array<Dynamic> = data.right;
					slots.left = [for (s in leftArr) {x: Std.int(s.x), y: Std.int(s.y)}];
					slots.right = [for (s in rightArr) {x: Std.int(s.x), y: Std.int(s.y)}];
				}
			}
			ship.maxCannonsPerSide = Std.int(obj.maxCannonsPerSide);
		} catch (_) {}
	}

	function pushUndo(tab:String) {
		var snapshot = switch (tab) {
			case "grid": captureGridState();
			case "offsets": captureOffsetsState();
			case "cannons": captureCannonsState();
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
			default:
		}
		updateDirtyIndicators();
	}

	function updateDirtyIndicators() {
		var gridDirty = savedGridState != null && captureGridState() != savedGridState;
		var offsetsDirty = savedOffsetsState != null && captureOffsetsState() != savedOffsetsState;
		var cannonsDirty = savedCannonsState != null && captureCannonsState() != savedCannonsState;

		jPage.find(".gridUndo").css("display", gridDirty ? "flex" : "none");
		jPage.find(".offsetsUndo").css("display", offsetsDirty ? "flex" : "none");
		jPage.find(".cannonsUndo").css("display", cannonsDirty ? "flex" : "none");
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
				ship.deckGrid.boarding_point = {x: tx, y: ty};
				renderDeckGrid();
				updateDirtyIndicators();
			}
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
				var isBP = ship.deckGrid.boarding_point.x == tx && ship.deckGrid.boarding_point.y == ty;

				if (active)
					ctx.fillStyle = isBP ? "#44aa44" : "#5577bb";
				else
					ctx.fillStyle = isBP ? "#336633" : "#222233";

				ctx.fillRect(x + 1, y + 1, tileSize - 2, tileSize - 2);
				ctx.strokeStyle = "#556677";
				ctx.lineWidth = 1;
				ctx.strokeRect(x + 0.5, y + 0.5, tileSize - 1, tileSize - 1);

				if (isBP) {
					ctx.fillStyle = "#ffffff";
					ctx.font = Std.string(Math.round(tileSize * 0.4)) + "px sans-serif";
					ctx.textAlign = "center";
					ctx.textBaseline = "middle";
					ctx.fillText("B", x + tileSize / 2, y + tileSize / 2);
				}
			}
		}

		ctx.restore();

		// Update info
		jPage.find(".gridInfo")
			.html('Grid: ${ship.deckGrid.width}x${ship.deckGrid.height}, Tile: ${ship.deckGrid.tile_size}px, '
				+ 'Active tiles: ${ship.deckGrid.deck_tiles.length}, '
				+ 'Boarding: (${ship.deckGrid.boarding_point.x}, ${ship.deckGrid.boarding_point.y})');
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

	function drawIsoGrid(ctx:CanvasRenderingContext2D, cx:Float, cy:Float, dir:ShipDirection, alphaMultiplier:Float = 1.0) {
		if (ship == null)
			return;

		var rot = getRotationForDirection(dir);
		var half = ship.deckGrid.tile_size / 2;

		var gridAlpha = 0.5 * alphaMultiplier;
		var fillAlpha = 0.15 * alphaMultiplier;
		ctx.strokeStyle = "rgba(0, 255, 100, " + gridAlpha + ")";
		ctx.lineWidth = 1;

		for (ty in 0...ship.deckGrid.height) {
			for (tx in 0...ship.deckGrid.width) {
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

				// Fill active tiles
				if (ship.isDeckTileActive(tx, ty)) {
					ctx.fillStyle = "rgba(0, 200, 100, " + fillAlpha + ")";
					ctx.fill();
				}
				ctx.stroke();
			}
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
			slots.left.push({x: -20, y: 0});
			slots.right.push({x: 20, y: 0});
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

			// Find closest cannon marker
			var slots = ship.getCannonSlots(currentDirection);
			var bestDist = 15.0 / canvasZoom;

			for (i in 0...slots.left.length) {
				var s = slots.left[i];
				var dx = (spriteCX + s.x) - mx;
				var dy = (spriteCY - s.y) - my;
				var dist = Math.sqrt(dx * dx + dy * dy);
				if (dist < bestDist) {
					bestDist = dist;
					isDragging = true;
					dragCannonSide = "left";
					dragCannonIdx = i;
					dragStartX = mx;
					dragStartY = my;
					dragOffsetStartX = s.x;
					dragOffsetStartY = s.y;
				}
			}

			for (i in 0...slots.right.length) {
				var s = slots.right[i];
				var dx = (spriteCX + s.x) - mx;
				var dy = (spriteCY - s.y) - my;
				var dist = Math.sqrt(dx * dx + dy * dy);
				if (dist < bestDist) {
					bestDist = dist;
					isDragging = true;
					dragCannonSide = "right";
					dragCannonIdx = i;
					dragStartX = mx;
					dragStartY = my;
					dragOffsetStartX = s.x;
					dragOffsetStartY = s.y;
				}
			}
		});

		canvas.addEventListener("mousemove", (ev:js.html.MouseEvent) -> {
			if (!isDragging || ship == null || dragCannonSide == null)
				return;
			var rect = canvas.getBoundingClientRect();
			var mx = screenToWorldX(ev.clientX - rect.left, canvas.width);
			var my = screenToWorldY(ev.clientY - rect.top, canvas.height);
			var dx = mx - dragStartX;
			var dy = my - dragStartY;

			var slots = ship.getCannonSlots(currentDirection);
			var arr = dragCannonSide == "left" ? slots.left : slots.right;
			if (dragCannonIdx >= 0 && dragCannonIdx < arr.length) {
				arr[dragCannonIdx].x = Std.int(dragOffsetStartX + dx);
				arr[dragCannonIdx].y = Std.int(dragOffsetStartY - dy);
				updateCannonInfo();
				renderCannonsCanvas();
			}
		});

		canvas.addEventListener("mouseup", (_) -> {
			isDragging = false;
			dragCannonSide = null;
			dragCannonIdx = -1;
			updateDirtyIndicators();
		});

		canvas.addEventListener("mouseleave", (_) -> {
			isDragging = false;
			dragCannonSide = null;
			dragCannonIdx = -1;
		});
	}

	function updateCannonInfo() {
		if (ship == null)
			return;
		var slots = ship.getCannonSlots(currentDirection);
		var d:String = currentDirection;
		jPage.find(".cannonCount").text(Std.string(ship.maxCannonsPerSide));
		jPage.find(".cannonInfo").html('Direction: $d | Left: ${slots.left.length} | Right: ${slots.right.length} | Max per side: ${ship.maxCannonsPerSide}');
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

		// Draw cannon markers
		var slots = ship.getCannonSlots(currentDirection);
		drawCannonMarkers(ctx, spriteCX, spriteCY, slots.left, "#4488ff", "L");
		drawCannonMarkers(ctx, spriteCX, spriteCY, slots.right, "#ff4444", "R");

		ctx.restore();
	}

	function drawCannonMarkers(ctx:CanvasRenderingContext2D, cx:Float, cy:Float, slots:Array<CannonSlot>, color:String, label:String) {
		var r = 6.0;
		for (i in 0...slots.length) {
			var s = slots[i];
			var sx = cx + s.x;
			var sy = cy - s.y;

			ctx.beginPath();
			ctx.arc(sx, sy, r, 0, Math.PI * 2);
			ctx.fillStyle = color;
			ctx.fill();
			ctx.strokeStyle = "#ffffff";
			ctx.lineWidth = 1.5;
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
