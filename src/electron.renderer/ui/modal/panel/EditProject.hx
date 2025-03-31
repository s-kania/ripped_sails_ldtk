package ui.modal.panel;

import utils.AStar;
import js.lib.Error;
import js.Node;

class EditProject extends ui.modal.Panel {

	var showAdvanced = false;
	var allAdvancedOptions = [
		ldtk.Json.ProjectFlag.MultiWorlds,
		ldtk.Json.ProjectFlag.PrependIndexToLevelFileNames,
		ldtk.Json.ProjectFlag.ExportPreCsvIntGridFormat,
		ldtk.Json.ProjectFlag.UseMultilinesType,
		ldtk.Json.ProjectFlag.ExportOldTableOfContentData,
	];

	var levelNamePatternEditor : NamePatternEditor;
	var pngPatternEditor : ui.NamePatternEditor;

	public function new() {
		super();

		loadTemplate("editProject", "editProject", {
			app: Const.APP_NAME,
			ext: Const.FILE_EXTENSION,
		});
		linkToButton("button.editProject");

		showAdvanced = project.hasAnyFlag(allAdvancedOptions);

		var jSave = jContent.find("button.save").click( function(ev) {
			App.ME.executeAppCommand(C_SaveProject);
			if( project.isBackup() )
				close();
		});
		if( project.isBackup() )
			jSave.text(L.t._("Restore this backup"));

		var jSaveAs = jContent.find("button.saveAs").click( _->App.ME.executeAppCommand(C_SaveProjectAs) );
		if( project.isBackup() )
			jSaveAs.hide();


		var jRename = jContent.find("button.rename").click( _->App.ME.executeAppCommand(C_RenameProject) );
		if( project.isBackup() )
			jRename.hide();

		jContent.find("button.locate").click( function(ev) {
			JsTools.locateFile( project.filePath.full, true );
		});

		pngPatternEditor = new ui.NamePatternEditor(
			"png",
			project.getImageExportFilePattern(),
			[
				{ k:"world", displayName:"WorldName" },
				{ k:"level_name", displayName:"LevelName" },
				{ k:"level_idx", displayName:"LevelIdx" },
				{ k:"layer_name", displayName:"LayerName" },
				{ k:"layer_idx", displayName:"LayerIdx" },
			],
			(pat)->{
				project.pngFilePattern = pat==project.getDefaultImageExportFilePattern() ? null : pat;
				editor.ge.emit(ProjectSettingsChanged);
			},
			()->{
				project.pngFilePattern = null;
				editor.ge.emit(ProjectSettingsChanged);
			}
		);
		jContent.find(".pngPatternEditor").empty().append( pngPatternEditor.jEditor );

		levelNamePatternEditor = new ui.NamePatternEditor(
			"levelId",
			project.levelNamePattern,
			[
				{ k:"world", displayName:"WorldId" },
				{ k:"idx1", displayName:"LevelIndex(1)", desc:"Level index (starting at 1)" },
				{ k:"idx", displayName:"LevelIndex(0)", desc:"Level index (starting at 0)" },
				{ k:"x", displayName:"LevelX", desc:"X coordinate of the level" },
				{ k:"y", displayName:"LevelY", desc:"Y coordinate of the level" },
				{ k:"gx", displayName:"GridX", desc:"X grid coordinate of the level" },
				{ k:"gy", displayName:"GridY", desc:"Y grid coordinate of the level" },
				{ k:"depth", displayName:"WorldDepth", desc:"Level depth in the world" },
			],
			(pat)->{
				project.levelNamePattern = pat;
				editor.ge.emit(ProjectSettingsChanged);
				editor.invalidateAllLevelsCache();
				project.tidy();
			},
			()->{
				if( project.levelNamePattern!=data.Project.DEFAULT_LEVEL_NAME_PATTERN ) {
					project.levelNamePattern = data.Project.DEFAULT_LEVEL_NAME_PATTERN;
					editor.ge.emit(ProjectSettingsChanged);
					editor.invalidateAllLevelsCache();
					project.tidy();
					N.success("Value reset.");
				}
			}
		);
		jContent.find(".levelNamePatternEditor").empty().append( levelNamePatternEditor.jEditor );

		updateProjectForm();
	}

	override function onGlobalEvent(ge:GlobalEvent) {
		super.onGlobalEvent(ge);
		switch( ge ) {
			case ProjectSettingsChanged:
				updateProjectForm();

			case ProjectSaved:
				updateProjectForm();

			case _:
		}
	}

	function recommendSaving() {
		if( !cd.hasSetS("saveReco",2) )
			N.warning(
				L.t._("Project file setting changed"),
				L.t._("You should save the project at least once for this setting to apply its effects.")
			);
	}

		// Helper function to extract grid coordinates from level ID
	function extractGridCoords(levelId:String): {x:Float, y:Float} {
		var parts = levelId.split("_");
		if(parts.length >= 3) {
			var x = Std.parseFloat(parts[parts.length-2]);
			var y = Std.parseFloat(parts[parts.length-1]);
			if(x != null && y != null) {
				return { x: x, y: y };
			}
		}
		return null;
	}

	function getChunkName(levelId:String):String {
		var coords = extractGridCoords(levelId);
		if(coords == null) {
			return null;
		}
		return coords.x + "_" + coords.y;
	}

	function getTransitionPoints(fromCollisionLayer:Array<Array<Int>>, toCollisionLayer:Array<Array<Int>>, direction:String, levelSize:Int):Array<Int> {
		// Tablica przechowująca pozycje punktów przejścia
		var transitionPoints:Array<Int> = [];
		
		// Jeśli oba poziomy są puste (oceany), ustaw domyślny punkt przejścia na środku
		if (fromCollisionLayer == null && toCollisionLayer == null) {
			// Używamy po prostu połowy rozmiaru poziomu jako punktu przejścia
			transitionPoints.push(Std.int(levelSize / 2));
			return transitionPoints;
		}
		
		switch (direction) {
			case "right":
				// Sprawdzamy prawą granicę pierwszego poziomu i lewą granicę drugiego poziomu
				// Iterujemy po całej wysokości
				var startY = -1; // Początek ciągłego segmentu przejścia
				
				// Zmieniona pętla na levelSize
				for (y in 0...levelSize) {
					// Sprawdź czy punkt na prawej krawędzi pierwszego poziomu jest przechodni (0)
					var fromRightEdge = 
						fromCollisionLayer == null 
						? true // Ocean jest zawsze przechodni
						: (y < fromCollisionLayer.length && 
							fromCollisionLayer[y] != null && 
							fromCollisionLayer[y].length > 0 && // Upewnij się, że wiersz nie jest pusty
							fromCollisionLayer[y][fromCollisionLayer[y].length - 1] == 0);
					
					// Sprawdź czy punkt na lewej krawędzi drugiego poziomu jest przechodni (0)
					var toLeftEdge = 
						toCollisionLayer == null 
						? true // Ocean jest zawsze przechodni
						: (y < toCollisionLayer.length && 
							toCollisionLayer[y] != null && 
							toCollisionLayer[y].length > 0 && // Upewnij się, że wiersz nie jest pusty
							toCollisionLayer[y][0] == 0);
					
					// Jeśli oba punkty są przechodnie, mamy przejście
					if (fromRightEdge && toLeftEdge) {
						// Jeśli to początek nowego segmentu
						if (startY == -1) {
							startY = y;
						}
						// Jeśli to ostatni punkt (zaktualizowano warunek do levelSize), zapisz środek segmentu
						if (y == levelSize - 1 && startY != -1) {
							// Zmiana na Math.round
							var middleY = Math.round((startY + y) / 2);
							transitionPoints.push(middleY);
						}
					} else if (startY != -1) {
						// Koniec ciągłego segmentu, zapisz środek
						// Zmiana na Math.round
						var middleY = Math.round((startY + (y - 1)) / 2);
						transitionPoints.push(middleY);
						startY = -1; // Reset dla nowego segmentu
					}
				}
				
			case "bottom":
				// Sprawdzamy dolną granicę pierwszego poziomu i górną granicę drugiego poziomu
				// Usunięto zewnętrzny warunek if sprawdzający czy oba collisionLayer istnieją
				var startX = -1; // Początek ciągłego segmentu przejścia
				
				// Zmieniona pętla na levelSize
				for (x in 0...levelSize) {
					// Sprawdź czy punkt na dolnej krawędzi pierwszego poziomu jest przechodni (0)
					var fromBottomEdge = 
						fromCollisionLayer == null 
						? true // Ocean jest zawsze przechodni
						: (fromCollisionLayer.length > 0 && // Upewnij się, że jest co najmniej jeden wiersz
							fromCollisionLayer[fromCollisionLayer.length - 1] != null && 
							x < fromCollisionLayer[fromCollisionLayer.length - 1].length && // Sprawdź graniczniki X
							fromCollisionLayer[fromCollisionLayer.length - 1][x] == 0);
					
					// Sprawdź czy punkt na górnej krawędzi drugiego poziomu jest przechodni (0)
					var toTopEdge = 
						toCollisionLayer == null 
						? true // Ocean jest zawsze przechodni
						: (toCollisionLayer.length > 0 && // Upewnij się, że jest co najmniej jeden wiersz
							toCollisionLayer[0] != null && 
							x < toCollisionLayer[0].length && // Sprawdź graniczniki X
							toCollisionLayer[0][x] == 0);
					
					// Jeśli oba punkty są przechodnie, mamy przejście
					if (fromBottomEdge && toTopEdge) {
						// Jeśli to początek nowego segmentu
						if (startX == -1) {
							startX = x;
						}
						// Jeśli to ostatni punkt (zaktualizowano warunek do levelSize), zapisz środek segmentu
						if (x == levelSize - 1 && startX != -1) {
							// Zmiana na Math.round
							var middleX = Math.round((startX + x) / 2);
							transitionPoints.push(middleX);
						}
					} else if (startX != -1) {
						// Koniec ciągłego segmentu, zapisz środek
						// Zmiana na Math.round
						var middleX = Math.round((startX + (x - 1)) / 2);
						transitionPoints.push(middleX);
						startX = -1; // Reset dla nowego segmentu
					}
				}
				
			case "left":
				// Wywołaj funkcję dla kierunku przeciwnego, zamieniając poziomy miejscami
				return getTransitionPoints(toCollisionLayer, fromCollisionLayer, "right", levelSize);
				
			case "top":
				// Wywołaj funkcję dla kierunku przeciwnego, zamieniając poziomy miejscami
				return getTransitionPoints(toCollisionLayer, fromCollisionLayer, "bottom", levelSize);
		}
		
		// Jeśli nie znaleziono przejścia, zwróć pustą listę
		return transitionPoints;
	}

	
	// ==========================================================================================
	// PATHFINDING HELPERS
	// ==========================================================================================

	/**
	 * Finds other transition nodes reachable from the given currentNodeId
	 * by checking for A* paths on the two levels connected by currentNodeId.
	 * Updates the 'connections' map for both the current node and the found neighbors
	 * directly within the main nodeMap.
	 */
	 	/**
	 * Finds other transition nodes reachable from the given currentNodeId
	 * by checking for A* paths on the two levels connected by currentNodeId.
	 * Updates the 'connections' map for both the current node and the found neighbors
	 * directly within the main nodeMap.
	 */
	 private function findAndAddConnectionsForNode(
		currentNodeId:String,
		nodeMap:Map<String, {id:String, connections:Map<String, Int>}>,
		levelsByGridPos:Map<String, data.Level>,
		levelWidth:Int
	):Void {
		// Parsowanie ID bez zmian
		var parts = currentNodeId.split("⎯");
		if (parts.length != 4) {
			trace('Error: Invalid currentNodeId format: $currentNodeId');
			return;
		}
		var levelA_ID = parts[0];
		var levelB_ID = parts[1];
		var direction = parts[2];
		var position = Std.parseInt(parts[3]);
	
		if (position == null) {
			trace('Error: Invalid position in currentNodeId: $currentNodeId');
			return;
		}
	
		var nodeInfo = nodeMap.get(currentNodeId);
		if (nodeInfo == null) {
			trace('Error: Node info not found for $currentNodeId in nodeMap');
			return;
		}
	
		// Pobieranie poziomów
		var levelA = levelsByGridPos.get(levelA_ID);
		var levelB = levelsByGridPos.get(levelB_ID);
	
		// Sprawdzanie poziomów
		if (levelA == null) {
			trace('Warning: Level A ($levelA_ID) not found for node $currentNodeId');
		}
		if (levelB == null) {
			trace('Warning: Level B ($levelB_ID) not found for node $currentNodeId');
		}
	
		// Ustalenie wysokości poziomów (prawdopodobnie z project.defaultGridSize lub z innego źródła)
		var levelHeight = levelWidth; // Zakładam, że poziomy są kwadratowe, dostosuj to jeśli potrzeba
	
		// Sprawdzanie połączeń na Level A
		if (levelA != null) {
			var coordsA = getCoordsFromNodeId(currentNodeId, levelA_ID, levelWidth, levelHeight);
			if (coordsA != null) {
				checkConnectionsOnLevel(levelA_ID, levelA, currentNodeId, coordsA, nodeInfo, nodeMap, levelsByGridPos, levelWidth, levelHeight);
			} else {
				trace('Error: Could not calculate coordinates for $currentNodeId on level $levelA_ID');
			}
		}
	
		// Sprawdzanie połączeń na Level B
		if (levelB != null) {
			var coordsB = getCoordsFromNodeId(currentNodeId, levelB_ID, levelWidth, levelHeight);
			if (coordsB != null) {
				checkConnectionsOnLevel(levelB_ID, levelB, currentNodeId, coordsB, nodeInfo, nodeMap, levelsByGridPos, levelWidth, levelHeight);
			} else {
				trace('Error: Could not calculate coordinates for $currentNodeId on level $levelB_ID');
			}
		}
	}


	/**
	 * Checks for connections between the current node and all other nodes
	 * that share the specified target level. Updates connections maps directly.
	 */
	 private function checkConnectionsOnLevel(
		targetLevelId:String, 
		targetLevel:data.Level,
		currentNodeId:String,
		currentNodeCoords:{x:Int, y:Int},
		nodeInfo:{id:String, connections:Map<String, Int>},
		nodeMap:Map<String, {id:String, connections:Map<String, Int>}>,
		levelsByGridPos:Map<String, data.Level>,
		levelWidth:Int,
		levelHeight:Int
	):Void {
		// 1. Pobierz warstwę kolizji i sprawdź czy to poziom "ocean"
		var collisionLayer = targetLevel.collisionLayer;
		var isOceanLevel = (collisionLayer == null || collisionLayer.length == 0);
	
		// 2. Iteracja przez wszystkie inne potencjalne cele połączenia
		for (otherNodeId => otherNodeInfo in nodeMap) {
			if (otherNodeId == currentNodeId) continue;
	
			// 3. Parsowanie ID drugiego węzła
			var otherParts = otherNodeId.split("⎯");
			if (otherParts.length != 4) continue;
	
			var otherLevelA = otherParts[0];
			var otherLevelB = otherParts[1];
	
			// 4. Sprawdź czy drugi węzeł jest związany z targetLevelId
			if (otherLevelA != targetLevelId && otherLevelB != targetLevelId) {
				continue;
			}
	
			// 5. Oblicz współrzędne drugiego węzła NA TYM poziomie
			var otherNodeCoords = getCoordsFromNodeId(otherNodeId, targetLevelId, levelWidth, levelHeight);
			if (otherNodeCoords == null) {
				continue;
			}
	
			// 6. Sprawdź czy istnieje ścieżka
			var hasPath = false;
			if (isOceanLevel) {
				// Poziomy "ocean" automatycznie łączą wszystkie punkty
				hasPath = true;
			} else {
				// Sprawdź czy pozycje są w granicach mapy i nie są zablokowane
				if (isValidPosition(currentNodeCoords.x, currentNodeCoords.y, collisionLayer) &&
					isValidPosition(otherNodeCoords.x, otherNodeCoords.y, collisionLayer)) {
					
					// Użyj klasy AStar do znalezienia ścieżki
					var path = utils.AStar.findPath(
						collisionLayer,
						{ x: currentNodeCoords.x, y: currentNodeCoords.y },
						{ x: otherNodeCoords.x, y: otherNodeCoords.y }
					);
					
					// Jeśli znaleziono ścieżkę, hasPath = true
					hasPath = (path != null && path.length > 0);
				}
			}
	
			// 7. Dodaj dwukierunkowe połączenie jeśli istnieje ścieżka
			if (hasPath) {
				nodeInfo.connections.set(otherNodeId, 1);
				otherNodeInfo.connections.set(currentNodeId, 1);
			}
		}
	}
	
	// Pomocnicza funkcja do sprawdzania, czy dana pozycja jest legalna na mapie kolizji
	private function isValidPosition(x:Int, y:Int, collisionLayer:Array<Array<Int>>):Bool {
		if (collisionLayer == null) return false;
		if (y < 0 || y >= collisionLayer.length) return false;
		if (x < 0 || x >= collisionLayer[y].length) return false;
		
		// Wartość 0 zazwyczaj oznacza brak kolizji, ale to może zależeć od implementacji mapy kolizji
		return collisionLayer[y][x] == 0;
	}

	/**
	 * Calculates grid coordinates (x,y) from a node ID based on level dimensions and transition direction.
	 *
	 * @param nodeId The transition node ID (format: "levelA⎯levelB⎯direction⎯position")
	 * @param onLevelId Which level's perspective to use (must match either levelA or levelB in nodeId)
	 * @param levelWidth Width of the level in grid cells
	 * @param levelHeight Height of the level in grid cells
	 * @return Coordinates or null if calculation fails
	 */
	 private function getCoordsFromNodeId(
		nodeId:String,
		onLevelId:String,
		levelWidth:Int,
		levelHeight:Int
	):Null<{x:Int, y:Int}> {
		var parts = nodeId.split("⎯");
		if (parts.length != 4) {
			trace('Error getCoords: Invalid node ID format: $nodeId');
			return null;
		}

		var levelA_ID = parts[0];
		var levelB_ID = parts[1];
		var direction = parts[2]; // Expecting "bottom" or "right"
		var position = Std.parseInt(parts[3]);

		if (position == null) {
			trace('Error getCoords: Invalid position in node ID: $nodeId');
			return null;
		}

		// Check if the target level ID is actually part of this transition
		if (onLevelId != levelA_ID && onLevelId != levelB_ID) {
			trace('Error getCoords: Target level $onLevelId is not part of transition $nodeId');
			return null;
		}

		// Determine if we are calculating coordinates from the perspective of the 'source' level (levelA)
		var isSourceLevelPerspective = (onLevelId == levelA_ID);

		// Calculate coordinates based on direction and perspective
		switch (direction.toLowerCase()) {
			case "bottom": // Transition is along the bottom edge of levelA / top edge of levelB
				if (isSourceLevelPerspective) {
					// On Level A (source), point is at the bottom edge
					return { x: position, y: levelHeight - 1 };
				} else {
					// On Level B (destination), point is at the top edge
					return { x: position, y: 0 };
				}

			case "right": // Transition is along the right edge of levelA / left edge of levelB
				if (isSourceLevelPerspective) {
					// On Level A (source), point is at the right edge
					return { x: levelWidth - 1, y: position };
				} else {
					// On Level B (destination), point is at the left edge
					return { x: 0, y: position };
				}

			default:
				trace('Error getCoords: Unknown direction "$direction" in node ID: $nodeId');
				return null; // Unknown or unsupported direction
		}
	}

	/**
	 * Parses a transition node ID (e.g., "0_0⎯0_1⎯bottom⎯16") and returns 
	 * its corresponding point coordinates on the level grid.
	 * Returns null if parsing fails.
	 */
	private function parseTransitionNodeToPoint(nodeId:String, levelGridSize:Int):Point {
		var parts = nodeId.split("⎯");
		if (parts.length < 4) {
			trace('Error: Invalid transition node ID format: $nodeId');
			return null;
		}

		var direction = parts[2];
		var positionStr = parts[3];
		var position = Std.parseInt(positionStr);

		if (position == null) {
			trace('Error: Failed to parse position from node ID: $nodeId');
			return null;
		}

		// Convert direction and position along edge to {x, y} grid coordinates
		switch (direction) {
			case "top":    return { x: position, y: 0 };
			case "bottom": return { x: position, y: levelGridSize - 1 };
			case "left":   return { x: 0, y: position };
			case "right":  return { x: levelGridSize - 1, y: position };
			default:       
				trace('Error: Unknown direction in node ID: $nodeId');
				return null; 
		}
	}

	/**
	 * Checks if a direct connection should be made between two transition nodes 
	 * based on A* pathfinding on the shared level's collision map.
	 * Returns true if they share a level and (a path exists OR the level has no collision map), 
	 * false otherwise.
	 */
	private function hasPathBetweenTransitions(nodeId1:String, nodeId2:String, levelsByGridPos:Map<String, data.Level>, levelGridSize:Int):Bool {
		var parts1 = nodeId1.split("⎯");
		var parts2 = nodeId2.split("⎯");

		// Basic validation
		if (parts1.length < 4 || parts2.length < 4) {
			return false; 
		}

		// Find the ID of the level they potentially share
		var sharedLevelId:String = null;
		if (parts1[0] == parts2[0] || parts1[0] == parts2[1]) { 
			sharedLevelId = parts1[0];
		} else if (parts1[1] == parts2[0] || parts1[1] == parts2[1]) {
			sharedLevelId = parts1[1];
		} else {
			 return false; // Don't share a potential connection level
		}

		// Get the level data
		var level = levelsByGridPos.get(sharedLevelId);
		if (level == null) {
			 trace('Warning: Shared level ID $sharedLevelId not found in levelsByGridPos map.');
			 return false; 
		}

		// Get collision data
		var collisionLayer = level.collisionLayer;

		// If no collision layer exists (e.g., ocean level), consider them connected
		if (collisionLayer == null) {
			return true; 
		}

		// Parse node IDs to start/end points on the grid
		var startPoint = parseTransitionNodeToPoint(nodeId1, levelGridSize);
		var endPoint = parseTransitionNodeToPoint(nodeId2, levelGridSize);

		if (startPoint == null || endPoint == null) {
			// Error already traced in parseTransitionNodeToPoint
			return false;
		}
		
		// Ensure points are within bounds (A* might also check this)
		if (startPoint.x < 0 || startPoint.x >= levelGridSize || startPoint.y < 0 || startPoint.y >= levelGridSize ||
			endPoint.x < 0 || endPoint.x >= levelGridSize || endPoint.y < 0 || endPoint.y >= levelGridSize) {
			trace('Warning: Start or end point out of bounds for A* check on level $sharedLevelId');
			return false;
		}

		// Perform A* pathfinding
		var path = AStar.findPath(collisionLayer, startPoint, endPoint);
		trace(path);
		// Return true if A* found a path
		return (path != null);
	}

	function updateProjectForm() {
		ui.Tip.clear();
		var jForms = jContent.find("dl.form");
		jForms.off().find("*").off();

		// Simplified format adjustments
		if( project.simplifiedExport )
			jForms.find(".notSimplified").hide();
		else
			jForms.find(".notSimplified").show();

		// File extension
		var ext = project.filePath.extension;
		var usesAppDefault = ext==Const.FILE_EXTENSION;
		var i = Input.linkToHtmlInput( usesAppDefault, jForms.find("[name=useAppExtension]") );
		i.onValueChange = (v)->{
			var old = project.filePath.full;
			var fp = project.filePath.clone();
			fp.extension = v ? Const.FILE_EXTENSION : "json";
			if( NT.fileExists(old) && NT.renameFile(old, fp.full) ) {
				App.ME.renameRecentProject(old, fp.full);
				project.filePath.parseFilePath(fp.full);
				N.success(L.t._("Changed file extension to ::ext::", { ext:fp.extWithDot }));
			}
			else {
				N.error(L.t._("Couldn't rename project file!"));
			}
		}

		// Backups
		var i = Input.linkToHtmlInput( project.backupOnSave, jForms.find("#backup") );
		i.linkEvent(ProjectSettingsChanged);
		var jLocate = i.jInput.siblings(".locate").empty();
		if( project.backupOnSave )
			jLocate.append( JsTools.makeLocateLink(project.getAbsBackupDir(), false) );
		var jCount = jForms.find("#backupCount");
		var jBackupPath = jForms.find(".curBackupPath");
		var jResetBackup = jForms.find(".resetBackupPath");
		jCount.val( Std.string(Const.DEFAULT_BACKUP_LIMIT) );
		if( project.backupOnSave ) {
			jBackupPath.show();

			jCount.show();
			jCount.siblings("span").show();
			var i = Input.linkToHtmlInput( project.backupLimit, jCount );
			i.setBounds(3, 50);
			i.linkEvent(ProjectSettingsChanged);

			jBackupPath.text( project.backupRelPath==null ? "[Default dir]" : "[Custom dir]" );
			if( project.backupRelPath==null )
				jBackupPath.removeAttr("title");
			else
				jBackupPath.attr("title", project.backupRelPath);

			jBackupPath.click(_->{
				var absPath = project.getAbsBackupDir();
				if( !NT.fileExists(absPath) )
					absPath = project.filePath.full;

				dn.js.ElectronDialogs.openDir(absPath, (dirPath)->{
					var fp = dn.FilePath.fromDir(dirPath);
					fp.useSlashes();
					fp.makeRelativeTo(project.filePath.directory);
					project.backupRelPath = fp.full;
					editor.ge.emit(ProjectSettingsChanged);
				});
			});
			jResetBackup.find(".reset");
			if( project.backupRelPath==null )
				jResetBackup.hide();
			else
				jResetBackup.show().click( (ev:js.jquery.Event)->{
					ev.preventDefault();
					project.backupRelPath = null;
					editor.ge.emit(ProjectSettingsChanged);
				});
		}
		else {
			jCount.hide();
			jCount.siblings("span").hide();
			jBackupPath.hide();
			jResetBackup.hide();
		}
		jForms.find(".backupRecommend").css("visibility", project.recommendsBackup() ? "visible" : "hidden");


		// Json minifiying
		var i = Input.linkToHtmlInput( project.minifyJson, jForms.find("[name=minify]") );
		i.linkEvent(ProjectSettingsChanged);
		i.onChange = ()->{
			editor.invalidateAllLevelsCache;
			recommendSaving();
		}

		// Simplified format
		var i = Input.linkToHtmlInput( project.simplifiedExport, jForms.find("[name=simplifiedExport]") );
		i.onChange = ()->{
			editor.invalidateAllLevelsCache();
			editor.ge.emit(ProjectSettingsChanged);
			if( project.simplifiedExport )
				recommendSaving();
		}
		var jLocate = jForms.find(".simplifiedExport .locate").empty();
		if( project.simplifiedExport )
			jLocate.append(
				NT.fileExists( project.getAbsExternalFilesDir() )
					? JsTools.makeLocateLink(project.getAbsExternalFilesDir()+"/simplified", false)
					: JsTools.makeLocateLink(project.filePath.full, true)
			);

		// External level files
		var i = Input.linkToHtmlInput( project.externalLevels, jForms.find("#externalLevels") );
		i.linkEvent(ProjectSettingsChanged);
		i.onValueChange = (v)->{
			editor.invalidateAllLevelsCache();
			recommendSaving();
		}
		var jLocate = jForms.find("#externalLevels").siblings(".locate").empty();
		if( project.externalLevels )
			jLocate.append( JsTools.makeLocateLink(project.getAbsExternalFilesDir(), false) );

		// Image export
		var jImgExport = jForms.find(".imageExportMode");
		var jSelect = jImgExport.find("select");
		var i = new form.input.EnumSelect(
			jSelect,
			ldtk.Json.ImageExportMode,
			()->project.imageExportMode,
			(v)->{
				project.pngFilePattern = null;
				project.imageExportMode = v;
				if( v!=None )
					recommendSaving();
			},
			(v)->switch v {
				case None: L.t._("Don't export any image");
				case OneImagePerLayer: L.t._("One PNG per layer");
				case OneImagePerLevel: L.t._("One PNG per level (layers are merged down)");
				case LayersAndLevels: L.t._("One PNG per layer and one per level.");
			}
		);
		i.linkEvent(ProjectSettingsChanged);
		var jLocate = jImgExport.find(".locate").empty();
		pngPatternEditor.jEditor.hide();
		jForms.find(".imageExportOnly").hide();
		if( project.imageExportMode!=None && !project.simplifiedExport ) {
			jForms.find(".imageExportOnly").show();
			jLocate.append( JsTools.makeLocateLink(project.getAbsExternalFilesDir()+"/png", false) );

			pngPatternEditor.jEditor.show();
			pngPatternEditor.ofString( project.getImageExportFilePattern() );
		}

		var i = Input.linkToHtmlInput(project.exportLevelBg, jForms.find("#exportLevelBg"));
		i.linkEvent(ProjectSettingsChanged);


		// Identifier style
		var i = new form.input.EnumSelect(
			jForms.find("#identifierStyle"),
			ldtk.Json.IdentifierStyle,
			false,
			()->return project.identifierStyle,
			(v)->{
				if( v==project.identifierStyle )
					return;

				var old = project.identifierStyle;
				new LastChance(L.t._("Identifier style changed"), project);
				project.identifierStyle = v;
				project.applyIdentifierStyleEverywhere(old);
				editor.invalidateAllLevelsCache();
				editor.ge.emit(ProjectSettingsChanged);
			},
			(v)->switch v {
				case Capitalize: L.t._('"My_identifier_1" -- First letter is always uppercase, the rest is up to you');
				case Uppercase: L.t._('"MY_IDENTIFIER_1" -- Full uppercase');
				case Lowercase: L.t._('"my_identifier_1" -- Full lowercase');
				case Free: L.t._('"my_IdEnTifIeR_1" -- I wON\'t cHaNge yOuR leTteR caSe');
			}
		);
		i.customConfirm = (oldV,newV)->{
			switch newV {
				case Capitalize, Uppercase, Lowercase:
					L.t._("WARNING!\nPlease make sure the game engine or importer you're using supports this kind of LDtk identifier!\nIf you proceed, all identifiers in this project will be converted to the new format!\nAre you sure?");

				case Free:
					L.t._("WARNING!\nPlease make sure the game engine or importer you're using supports this kind of LDtk identifier!\nAre you sure?");
			}
		}
		var jStyleWarning = jForms.find("#styleWarning");
		switch project.identifierStyle {
			case Capitalize, Uppercase: jStyleWarning.hide();
			case Lowercase, Free: jStyleWarning.show();
		}

		// Tiled export
		var i = Input.linkToHtmlInput( project.exportTiled, jForms.find("#tiled") );
		i.linkEvent(ProjectSettingsChanged);
		i.onValueChange = function(v) {
			if( v ) {
				new ui.modal.dialog.Message(
					Lang.t._("Disclaimer: Tiled export is only meant to load your LDtk project in a game framework that only supports Tiled files. It is recommended to write your own LDtk JSON parser, as some LDtk features may not be supported.\nIt's not so complicated, I promise :)"), "project",
					()->recommendSaving()
				);
			}
		}
		var jLocate = jForms.find("#tiled").siblings(".locate").empty();
		if( project.exportTiled )
			jLocate.append( JsTools.makeLocateLink(project.getAbsExternalFilesDir()+"/tiled", false) );


		// Custom commands
		var jCommands = jForms.find(".customCommands");
		jCommands.find("ul").empty();
		function _createCommandJquery(cmd:ldtk.Json.CustomCommand) {
			var jCmd = jCommands.find("xml#customCommand").children().clone(false, false).wrapAll("<li/>").parent();
			jCmd.appendTo( jCommands.find("ul") );
			Input.linkToHtmlInput(cmd.command, jCmd.find(".command"));
			new form.input.EnumSelect(
				jCmd.find("select.when"),
				ldtk.Json.CustomCommandTrigger,
				false,
				()->cmd.when,
				(v)->cmd.when = v,
				(v)->switch v {
					case Manual: App.isMac() ? L.t._("Run manually (CMD-R)") : L.t._("Run manually (CTRL-R)");
					case AfterLoad: L.t._("Run after loading");
					case BeforeSave: L.t._("Run before saving");
					case AfterSave: L.t._("Run after saving");
				}
			);
			var jRem = jCmd.find("button.remove");
			jRem.click(_->{
				function _removeCmd() {
					project.customCommands.remove(cmd);
					editor.ge.emit(ProjectSettingsChanged);
				}
				if( cmd.command=="" )
					_removeCmd();
				else
					new ui.modal.dialog.Confirm(jRem, L.t._("Are you sure?"), ()->{
						new LastChance(L.t._("Project command removed"), project);
						_removeCmd();
					});
			});
		}
		var jAdd = jCommands.find("button.add");
		jAdd.off().click( _->{
			var cmd : ldtk.Json.CustomCommand = { command:"", when:Manual }
			project.customCommands.push(cmd);
			editor.ge.emit(ProjectSettingsChanged);
		});
		for( cmd in project.customCommands )
			_createCommandJquery(cmd);
		JsTools.makeSortable(jCommands.find("ul"), (ev:sortablejs.Sortable.SortableDragEvent)->{
			var from = ev.oldIndex;
			var to = ev.newIndex;

			if( from<0 || from>=project.customCommands.length || from==to )
				return;

			if( to<0 || to>=project.customCommands.length )
				return;

			var moved = project.customCommands.splice(from,1)[0];
			project.customCommands.insert(to, moved);
			editor.ge.emit( ProjectSettingsChanged );
		});

		// Commands trust
		if( settings.isProjectTrusted(project.iid) )
			jCommands.find(".untrusted").hide();
		else if( settings.isProjectUntrusted(project.iid) )
			jCommands.find(".trusted").hide();
		else {
			jCommands.find(".untrusted").hide();
			jCommands.find(".trusted").hide();
		}
		jCommands.find(".trusted a, .untrusted a").click(_->{
			settings.clearProjectTrust(project.iid);
			editor.ge.emit( ProjectSettingsChanged );
		});


		// Level grid size
		var i = Input.linkToHtmlInput( project.defaultGridSize, jForms.find("[name=defaultGridSize]") );
		i.setBounds(1,Const.MAX_GRID_SIZE);
		i.linkEvent(ProjectSettingsChanged);


		// Default entity size
		var i = Input.linkToHtmlInput( project.defaultEntityWidth, jForms.find("[name=defaultEntityWidth]") );
		i.setBounds(1,Const.MAX_GRID_SIZE);
		i.linkEvent(ProjectSettingsChanged);

		var i = Input.linkToHtmlInput( project.defaultEntityHeight, jForms.find("[name=defaultEntityHeight]") );
		i.setBounds(1,Const.MAX_GRID_SIZE);
		i.linkEvent(ProjectSettingsChanged);

		// Workspace bg
		var i = Input.linkToHtmlInput( project.bgColor, jForms.find("[name=bgColor]"));
		i.linkEvent(ProjectSettingsChanged);

		// Level bg
		var i = Input.linkToHtmlInput( project.defaultLevelBgColor, jForms.find("[name=defaultLevelbgColor]"));
		i.onChange = ()->{
			for(w in project.worlds)
			for(l in w.levels)
				if( l.isUsingDefaultBgColor() )
					editor.ge.emit(LevelSettingsChanged(l));
		}
		i.linkEvent(ProjectSettingsChanged);

		// Default entity pivot
		var pivot = jForms.find(".pivot");
		pivot.empty();
		pivot.append( JsTools.createPivotEditor(
			project.defaultPivotX, project.defaultPivotY,
			0x0,
			function(x,y) {
				project.defaultPivotX = x;
				project.defaultPivotY = y;
				editor.ge.emit(ProjectSettingsChanged);
			}
		));

		// Level name pattern
		levelNamePatternEditor.ofString(project.levelNamePattern);

		// Pathfinding settings
		var i = Input.linkToHtmlInput( project.showPathfindingPaths, jForms.find("#showPathfindingPaths") );
		i.linkEvent(ProjectSettingsChanged);

		jForms.find("button.generatePaths").click( function(ev) {
			// Initialize pathfindingPaths at the project level
			project.pathfindingPaths = {
				nodes: []
			};

			// Create a temporary map to store all nodes
			var nodeMap = new Map<String, { id:String, connections:Map<String, Int> }>();
			
			// Find max grid coordinates and create level map
			var levelSize:Float = 0; // to jest szerokość poziomów na mapie świata, czyli np 5 x 5 poziomów
			// Poprawka: Użyj danych z pierwszego świata i rzutuj na Int
			var levelWidth:Int = Std.int(project.worlds[0].defaultLevelWidth / project.defaultGridSize);
			var levelsByGridPos = new Map<String, data.Level>();
			
			// Step 1: Map levels and find grid boundaries
			for(w in project.worlds) {
				for(l in w.levels) {
					var gridCoords = extractGridCoords(l.identifier);
					if(gridCoords != null) {
						levelSize = Math.max(levelSize, gridCoords.x);
						var gridKey = Std.int(gridCoords.x) + "_" + Std.int(gridCoords.y);
						levelsByGridPos.set(gridKey, l);
					}
				}
			}

			// Step 3: Create valid connections between adjacent cells
			for (x in 0...Std.int(levelSize+1)) {
				for (y in 0...Std.int(levelSize+1)) {
					var currentId = x + "_" + y;
					var currentLevel = levelsByGridPos.get(currentId);
					
					// Define possible directions (right, bottom)
					var directions = [
						{ dx: 1, dy: 0, name: "right", reverse: "left" },
						{ dx: 0, dy: 1, name: "bottom", reverse: "top" }
					];
					
					for (dir in directions) {
						var nx = x + dir.dx;
						var ny = y + dir.dy;
						
						// Check if neighbor is within grid bounds
						if (nx <= levelSize && ny <= levelSize) {
							var neighborId = nx + "_" + ny;
							var neighborLevel = levelsByGridPos.get(neighborId);
							
							// Get collision layers for validation
							var fromCollisionLayer = currentLevel != null ? currentLevel.collisionLayer : null;
							var toCollisionLayer = neighborLevel != null ? neighborLevel.collisionLayer : null;
							
							// Get all transition points instead of just checking if transition is valid
							// Poprawka: Przekazujemy levelWidth, który jest teraz Int
							var transitionPoints = getTransitionPoints(fromCollisionLayer, toCollisionLayer, dir.name, levelWidth);
							
							// Create transition nodes for each transition point
							// Ten fragment powinien teraz działać, bo transitionPoints jest poprawnie typowane jako Array<Int>
							for (position in transitionPoints) {
								// Create transition node with position information
								var transitionId = currentId + "⎯" + neighborId + "⎯" + dir.name + "⎯" + position;
								nodeMap.set(transitionId, { id: transitionId, connections: new Map<String, Int>() });
							}
						}
					}
				}
			}

			for (currentNodeId => nodeInfo in nodeMap) {
				// Example currentNodeId: "5_0⎯5_1⎯bottom⎯16"
				// Find all other nodes connected to this one via shared levels and A* pathfinding.
				findAndAddConnectionsForNode(currentNodeId, nodeMap, levelsByGridPos, levelWidth);
			}

			// Step 5: Convert nodeMap to final format
			for (node in nodeMap) {
				var connections = [];
				for (targetId => weight in node.connections) {
					connections.push({
						nodeId: targetId,
						weight: weight
					});
				}
				project.pathfindingPaths.nodes.push({
					id: node.id,
					connections: connections
				});
			}

			var finalPaths = [];

			// --- A* Test Start ---
			// TEMPORARILY COMMENTED OUT FOR DEBUGGING
			// var testGrid: Array<Array<Int>> = [
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
			// 	[1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1],
			// 	[1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1],
			// 	[1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
			// 	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
			// ];
			// var startPoint: Point = { x: 2, y: 2 };
			// var endPoint: Point = { x: 24, y: 4 };

			// trace('Grid dimensions: ${testGrid.length}x${testGrid[0].length}');
			// trace('Start point: ${startPoint.x},${startPoint.y}');
			// trace('End point: ${endPoint.x},${endPoint.y}');
			// var path = AStar.findPath(testGrid, startPoint, endPoint);

			// if (path != null) {
			// 	trace("Path found:");
			// 	for (p in path) {
			// 		trace('- (${p.x}, ${p.y})');
			// 	}
			// } else {
			// 	trace("Path not found");
			// }
			// --- A* Test End ---

			// Update project
			// project.changed();
			// updateProjectForm();
			// Update UI and notify success
			editor.ge.emit(ProjectSettingsChanged);
			N.success(L.t._('Pathfinding nodes and connections generated successfully.'));
		});

		// Advanced options
		var jAdvanceds = jForms.filter(".advanced");
		if( showAdvanced ) {
			jContent.find(".collapser.collapsed").click();
			// jForms.find("a.showAdv").hide();
			// jAdvanceds.addClass("visible");
		}
		else {
			// jForms.find("a.showAdv").show().click(ev->{
			// 	jAdvanceds.addClass("visible");
			// 	showAdvanced = true;
			// 	jWrapper.scrollTop( jWrapper.innerHeight() );
			// 	ev.getThis().hide();
			// });
		}
		var jAdvancedFlags = jAdvanceds.find("ul.advFlags");
		jAdvancedFlags.empty();
		for( flag in allAdvancedOptions ) {
			var jLi = new J('<li/>');
			jLi.appendTo(jAdvancedFlags);

			var jInput = new J('<input type="checkbox" id="$flag"/>');
			jInput.appendTo(jLi);

			var jLabel = new J('<label for="$flag"/>');
			jLabel.appendTo(jLi);
			var jDesc = new J('<div class="desc"/>');
			jDesc.appendTo(jLi);
			inline function _setDesc(str) {
				jDesc.html('<p>'+str.split("\n").join("</p><p>")+'</p>');
			}
			switch flag {
				case ExportPreCsvIntGridFormat:
					jLabel.text("Export legacy pre-CSV IntGrid layers data");
					_setDesc( L.t._("If enabled, the exported JSON file will also contain the now deprecated array \"intGrid\". The file will be significantly larger.\nOnly use this if your game API only supports LDtk 0.8.x or less.") );

				case PrependIndexToLevelFileNames:
					jLabel.text("Prefix level file names with their index in array");
					_setDesc( L.t._("If enabled, external level file names will be prefixed with an index reflecting their position in the internal array.\nThis is NOT recommended because, with versioning systems (such as GIT), inserting a new level means renaming files of all subsequent levels in the array.\nThis option used to be the default behavior but was changed in version 1.0.0.") );

				case MultiWorlds:
					jLabel.text("Multi-worlds support");
					_setDesc( L.t._("If enabled, levels will be stored in a 'worlds' array at the root of the project JSON instead of the root itself directly.\nThis option is still experimental and is not yet supported if Separate Levels option is enabled.") );
					jInput.prop("disabled", project.worlds.length>1 );

				case UseMultilinesType:
					jLabel.text('Use "Multilines" instead of "String" for fields in JSON');
					_setDesc( L.t._("If enabled, the JSON value \"__type\" for Field Instances and Field Definitions will be \"Multilines\" instead of \"String\" for all fields of Multilines type.") );

				case ExportOldTableOfContentData:
					jLabel.text('Export old entity table-of-content data');
					_setDesc( L.t._("If enabled, the 'toc' field in the project JSON will contain an 'instances' array in addition of the new 'instanceData' array (see JSON online doc for more info).") );

				case _:
			}

			var i = new form.input.BoolInput(
				jInput,
				()->project.hasFlag(flag),
				(v)->{
					editor.invalidateAllLevelsCache();
					editor.setProjectFlag(flag,v);
				}
			);
		}

		// Sample description
		var i = new form.input.StringInput(
			jForms.find("[name=tutorialDesc]"),
			()->project.tutorialDesc,
			(v)->{
				v = dn.Lib.trimEmptyLines(v);
				if( v=="" )
					v = null;
				project.tutorialDesc = v;
				editor.ge.emit(ProjectSettingsChanged);
			}
		);

		JsTools.parseComponents(jForms);
		checkBackup();
	}
}
