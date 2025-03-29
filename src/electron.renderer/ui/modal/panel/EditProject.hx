package ui.modal.panel;

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
				
				for (y in 0...fromCollisionLayer.length) {
					// Sprawdź czy punkt na prawej krawędzi pierwszego poziomu jest przechodni (0)
					var fromRightEdge = (y < fromCollisionLayer.length && 
						fromCollisionLayer[y] != null && 
						fromCollisionLayer[y][fromCollisionLayer[y].length - 1] == 0);
					
					// Sprawdź czy punkt na lewej krawędzi drugiego poziomu jest przechodni (0)
					var toLeftEdge = (y < toCollisionLayer.length && 
						toCollisionLayer[y] != null && 
						toCollisionLayer[y][0] == 0);
					
					// Jeśli oba punkty są przechodnie, mamy przejście
					if (fromRightEdge && toLeftEdge) {
						// Jeśli to początek nowego segmentu
						if (startY == -1) {
							startY = y;
						}
						// Jeśli to ostatni punkt, zapisz środek segmentu
						if (y == fromCollisionLayer.length - 1 && startY != -1) {
							var middleY = Math.floor((startY + y) / 2);
							transitionPoints.push(middleY);
						}
					} else if (startY != -1) {
						// Koniec ciągłego segmentu, zapisz środek
						var middleY = Math.floor((startY + (y - 1)) / 2);
						transitionPoints.push(middleY);
						startY = -1; // Reset dla nowego segmentu
					}
				}
				
			case "bottom":
				// Sprawdzamy dolną granicę pierwszego poziomu i górną granicę drugiego poziomu
				if (fromCollisionLayer.length > 0 && toCollisionLayer.length > 0) {
					var width = fromCollisionLayer[0].length;
					var startX = -1; // Początek ciągłego segmentu przejścia
					
					for (x in 0...width) {
						// Sprawdź czy punkt na dolnej krawędzi pierwszego poziomu jest przechodni (0)
						var fromBottomEdge = (fromCollisionLayer[fromCollisionLayer.length - 1] != null && 
							x < fromCollisionLayer[fromCollisionLayer.length - 1].length && 
							fromCollisionLayer[fromCollisionLayer.length - 1][x] == 0);
						
						// Sprawdź czy punkt na górnej krawędzi drugiego poziomu jest przechodni (0)
						var toTopEdge = (toCollisionLayer[0] != null && 
							x < toCollisionLayer[0].length && 
							toCollisionLayer[0][x] == 0);
						
						// Jeśli oba punkty są przechodnie, mamy przejście
						if (fromBottomEdge && toTopEdge) {
							// Jeśli to początek nowego segmentu
							if (startX == -1) {
								startX = x;
							}
							// Jeśli to ostatni punkt, zapisz środek segmentu
							if (x == width - 1 && startX != -1) {
								var middleX = Math.floor((startX + x) / 2);
								transitionPoints.push(middleX);
							}
						} else if (startX != -1) {
							// Koniec ciągłego segmentu, zapisz środek
							var middleX = Math.floor((startX + (x - 1)) / 2);
							transitionPoints.push(middleX);
							startX = -1; // Reset dla nowego segmentu
						}
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

	// function hasValidTransition(fromCollisionLayer:Array<Array<Int>>, toCollisionLayer:Array<Array<Int>>, direction:String):Bool {
	// 	// Wykorzystanie nowej funkcji getTransitionPoints
	// 	var points = getTransitionPoints(fromCollisionLayer, toCollisionLayer, direction, project.defaultGridSize);
	// 	return points.length > 0;
	// }

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
			var levelSize:Float = 0;
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
							var transitionPoints = getTransitionPoints(fromCollisionLayer, toCollisionLayer, dir.name, project.defaultGridSize);
							
							// Create transition nodes for each transition point
							for (position in transitionPoints) {
								// Create transition node with position information
								var transitionId = currentId + "⎯" + neighborId + "⎯" + dir.name + "⎯" + position;
								nodeMap.set(transitionId, { id: transitionId, connections: new Map<String, Int>() });
							}
						}
					}
				}
			}

			// Step 4: Connect transitions that share levels
			for (nodeId1 => node1 in nodeMap) {
				for (nodeId2 => node2 in nodeMap) {
					if (nodeId1 != nodeId2) {
						var parts1 = nodeId1.split("⎯");
						var parts2 = nodeId2.split("⎯");
						
						// Only proceed if both are transition nodes (have at least 3 parts)
						if (parts1.length >= 3 && parts2.length >= 3) {
							// Connect transitions if they share a level
							if (parts1[0] == parts2[0] || parts1[0] == parts2[1] || 
								parts1[1] == parts2[0] || parts1[1] == parts2[1]) {
								node1.connections.set(nodeId2, 1);
							}
						}
					}
				}
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
