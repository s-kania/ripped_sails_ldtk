package data;

import utils.AStar;

typedef TransitionConnection = {
	var weight:Int;
	var path:Array<{x:Int, y:Int}>;
	var chunk:String;
	var positionStart:Null<{x:Int, y:Int}>;
	var positionEnd:Null<{x:Int, y:Int}>;
}

typedef TransitionNode = {
	var id:String;
	var positionStart:Null<Int>;
	var positionEnd:Null<Int>;
	var connections:Map<String, TransitionConnection>;
};

class PathfindingPaths {
	static function extractGridCoords(levelId:String): {x:Float, y:Float} {
		var parts = levelId.split("_");
		if( parts.length>=3 ) {
			var x = Std.parseFloat(parts[parts.length - 2]);
			var y = Std.parseFloat(parts[parts.length - 1]);
			if( x!=null && y!=null )
				return { x:x, y:y };
		}
		return null;
	}

	static function createVirtualCollisionLayer(levelWidth:Int, levelHeight:Int):Array<Array<Int>> {
		var layer = [];
		for( y in 0...levelHeight ) {
			var row = [];
			for( x in 0...levelWidth )
				row.push(0);
			layer.push(row);
		}
		return layer;
	}

	static function getTransitionPoints(fromCollisionLayer:Array<Array<Int>>, toCollisionLayer:Array<Array<Int>>, direction:String, levelSize:Int):Array<{start:Int, end:Int}> {
		var transitionPoints = [];
		inline function addSegment(segmentStart:Int, segmentEnd:Int) {
			var clampedStart = Std.int(Math.max(segmentStart, 0));
			var clampedEnd = Std.int(Math.max(segmentEnd, clampedStart));
			transitionPoints.push({
				start: clampedStart,
				end: clampedEnd,
			});
		}
		if( levelSize<=0 )
			return transitionPoints;

		if( fromCollisionLayer==null && toCollisionLayer==null ) {
			addSegment(0, levelSize - 1);
			return transitionPoints;
		}

		switch direction {
			case "right":
				var startY = -1;
				for( y in 0...levelSize ) {
					var fromRightEdge = fromCollisionLayer==null
						? true
						: (
							y < fromCollisionLayer.length
							&& fromCollisionLayer[y] != null
							&& fromCollisionLayer[y].length > 0
							&& fromCollisionLayer[y][fromCollisionLayer[y].length - 1] == 0
						);

					var toLeftEdge = toCollisionLayer==null
						? true
						: (
							y < toCollisionLayer.length
							&& toCollisionLayer[y] != null
							&& toCollisionLayer[y].length > 0
							&& toCollisionLayer[y][0] == 0
						);

					if( fromRightEdge && toLeftEdge ) {
						if( startY==-1 )
							startY = y;
					}
					else if( startY!=-1 ) {
						addSegment(startY, y - 1);
						startY = -1;
					}
				}
				if( startY!=-1 )
					addSegment(startY, levelSize - 1);

			case "bottom":
				var startX = -1;
				for( x in 0...levelSize ) {
					var fromBottomEdge = fromCollisionLayer==null
						? true
						: (
							fromCollisionLayer.length > 0
							&& fromCollisionLayer[fromCollisionLayer.length - 1] != null
							&& x < fromCollisionLayer[fromCollisionLayer.length - 1].length
							&& fromCollisionLayer[fromCollisionLayer.length - 1][x] == 0
						);

					var toTopEdge = toCollisionLayer==null
						? true
						: (
							toCollisionLayer.length > 0
							&& toCollisionLayer[0] != null
							&& x < toCollisionLayer[0].length
							&& toCollisionLayer[0][x] == 0
						);

					if( fromBottomEdge && toTopEdge ) {
						if( startX==-1 )
							startX = x;
					}
					else if( startX!=-1 ) {
						addSegment(startX, x - 1);
						startX = -1;
					}
				}
				if( startX!=-1 )
					addSegment(startX, levelSize - 1);

			case "left":
				return getTransitionPoints(toCollisionLayer, fromCollisionLayer, "right", levelSize);

			case "top":
				return getTransitionPoints(toCollisionLayer, fromCollisionLayer, "bottom", levelSize);

			case _:
		}

		return transitionPoints;
	}

	static function isValidPosition(x:Int, y:Int, collisionLayer:Array<Array<Int>>):Bool {
		if( collisionLayer==null ) return false;
		if( y < 0 || y >= collisionLayer.length ) return false;
		if( x < 0 || x >= collisionLayer[y].length ) return false;
		return collisionLayer[y][x] == 0;
	}

	static function getCoordsFromNodeId(nodeId:String, onLevelId:String, levelWidth:Int, levelHeight:Int):Null<{x:Int, y:Int}> {
		var parts = nodeId.split("⎯");
		if( parts.length!=4 )
			return null;

		var levelA_ID = parts[0];
		var levelB_ID = parts[1];
		var direction = parts[2];
		var position = Std.parseInt(parts[3]);
		if( position==null )
			return null;

		if( onLevelId!=levelA_ID && onLevelId!=levelB_ID )
			return null;

		var isSourceLevelPerspective = (onLevelId == levelA_ID);

		switch direction.toLowerCase() {
			case "bottom":
				return isSourceLevelPerspective
					? { x: position, y: levelHeight - 1 }
					: { x: position, y: 0 };

			case "right":
				return isSourceLevelPerspective
					? { x: levelWidth - 1, y: position }
					: { x: 0, y: position };

			case _:
				return null;
		}
	}

	static function checkConnectionsOnLevel(targetLevelId:String, targetLevel:data.Level, currentNodeId:String, currentNodeCoords:{x:Int, y:Int}, nodeInfo:TransitionNode, nodeMap:Map<String, TransitionNode>, levelsByGridPos:Map<String, data.Level>, levelWidth:Int, levelHeight:Int):Void {
		var isOceanLevel = (targetLevel.collisionLayer == null || targetLevel.collisionLayer.length == 0);
		var collisionLayer = isOceanLevel ? createVirtualCollisionLayer(levelWidth, levelHeight) : targetLevel.collisionLayer;

		for( otherNodeId => otherNodeInfo in nodeMap ) {
			if( otherNodeId==currentNodeId )
				continue;

			var otherParts = otherNodeId.split("⎯");
			if( otherParts.length!=4 )
				continue;

			var otherLevelA = otherParts[0];
			var otherLevelB = otherParts[1];
			if( otherLevelA!=targetLevelId && otherLevelB!=targetLevelId )
				continue;

			var otherNodeCoords = getCoordsFromNodeId(otherNodeId, targetLevelId, levelWidth, levelHeight);
			if( otherNodeCoords==null )
				continue;

			var path:Array<{x:Int, y:Int}> = null;
			if( isValidPosition(currentNodeCoords.x, currentNodeCoords.y, collisionLayer) && isValidPosition(otherNodeCoords.x, otherNodeCoords.y, collisionLayer) ) {
				path = AStar.findPath(
					collisionLayer,
					{ x: currentNodeCoords.x, y: currentNodeCoords.y },
					{ x: otherNodeCoords.x, y: otherNodeCoords.y }
				);
			}

			if( path!=null && path.length>0 ) {
				nodeInfo.connections.set(otherNodeId, {
					weight: path.length,
					path: path,
					chunk: targetLevelId,
					positionStart: currentNodeCoords,
					positionEnd: otherNodeCoords
				});

				var reversePath = path.copy();
				reversePath.reverse();

				otherNodeInfo.connections.set(currentNodeId, {
					weight: path.length,
					path: reversePath,
					chunk: targetLevelId,
					positionStart: otherNodeCoords,
					positionEnd: currentNodeCoords
				});
			}
		}
	}

	static function findAndAddConnectionsForNode(currentNodeId:String, nodeMap:Map<String, TransitionNode>, levelsByGridPos:Map<String, data.Level>, levelWidth:Int):Void {
		var parts = currentNodeId.split("⎯");
		if( parts.length!=4 )
			return;

		var levelA_ID = parts[0];
		var levelB_ID = parts[1];
		var position = Std.parseInt(parts[3]);
		if( position==null )
			return;

		var nodeInfo = nodeMap.get(currentNodeId);
		if( nodeInfo==null )
			return;

		var levelA = levelsByGridPos.get(levelA_ID);
		var levelB = levelsByGridPos.get(levelB_ID);

		var levelHeight = levelWidth;

		if( levelA!=null ) {
			var coordsA = getCoordsFromNodeId(currentNodeId, levelA_ID, levelWidth, levelHeight);
			if( coordsA!=null )
				checkConnectionsOnLevel(levelA_ID, levelA, currentNodeId, coordsA, nodeInfo, nodeMap, levelsByGridPos, levelWidth, levelHeight);
		}

		if( levelB!=null ) {
			var coordsB = getCoordsFromNodeId(currentNodeId, levelB_ID, levelWidth, levelHeight);
			if( coordsB!=null )
				checkConnectionsOnLevel(levelB_ID, levelB, currentNodeId, coordsB, nodeInfo, nodeMap, levelsByGridPos, levelWidth, levelHeight);
		}
	}

	public static function generate(project:data.Project):Dynamic {
		if( project==null || project.worlds==null || project.worlds.length==0 )
			return { nodes: [] };

		var maxX:Float = 0;
		var maxY:Float = 0;
		var levelWidth:Int = Std.int(project.worlds[0].defaultLevelWidth / project.defaultGridSize);
		if( levelWidth<=0 )
			levelWidth = 1;

		var levelsByGridPos = new Map<String, data.Level>();
		var virtualCollisionLayer = createVirtualCollisionLayer(levelWidth, levelWidth);

		for( w in project.worlds )
		for( l in w.levels ) {
			if( l.collisionLayer==null )
				l.generateCombinedCollisionLayer();

			var gridCoords = extractGridCoords(l.identifier);
			if( gridCoords!=null ) {
				maxX = Math.max(maxX, gridCoords.x);
				maxY = Math.max(maxY, gridCoords.y);
				var gridKey = Std.int(gridCoords.x) + "_" + Std.int(gridCoords.y);
				levelsByGridPos.set(gridKey, l);
			}
		}

		for( x in 0...Std.int(maxX + 1) )
		for( y in 0...Std.int(maxY + 1) ) {
			var gridKey = x + "_" + y;
			if( !levelsByGridPos.exists(gridKey) ) {
				var oceanLevel:Dynamic = {};
				untyped oceanLevel.identifier = "Ocean_" + gridKey;
				untyped oceanLevel.collisionLayer = virtualCollisionLayer;
				levelsByGridPos.set(gridKey, cast oceanLevel);
			}
		}

		var nodeMap = new Map<String, TransitionNode>();
		for( x in 0...Std.int(maxX + 1) )
		for( y in 0...Std.int(maxY + 1) ) {
			var currentId = x + "_" + y;
			var currentLevel = levelsByGridPos.get(currentId);

			var directions = [
				{ dx: 1, dy: 0, name: "right" },
				{ dx: 0, dy: 1, name: "bottom" },
			];

			for( dir in directions ) {
				var nx = x + dir.dx;
				var ny = y + dir.dy;
				if( nx <= maxX && ny <= maxY ) {
					var neighborId = nx + "_" + ny;
					var neighborLevel = levelsByGridPos.get(neighborId);

					var fromCollisionLayer = currentLevel != null ? (cast currentLevel).collisionLayer : null;
					var toCollisionLayer = neighborLevel != null ? (cast neighborLevel).collisionLayer : null;

					var transitionPoints = getTransitionPoints(fromCollisionLayer, toCollisionLayer, dir.name, levelWidth);
					for( segment in transitionPoints ) {
						var center = Std.int(Math.round((segment.start + segment.end) / 2));
						var transitionId = currentId + "⎯" + neighborId + "⎯" + dir.name + "⎯" + center;
						nodeMap.set(transitionId, {
							id: transitionId,
							positionStart: segment.start,
							positionEnd: segment.end,
							connections: new Map<String, TransitionConnection>(),
						});
					}
				}
			}
		}

		for( currentNodeId => nodeInfo in nodeMap )
			findAndAddConnectionsForNode(currentNodeId, nodeMap, levelsByGridPos, levelWidth);

		var out:Dynamic = { nodes: [] };
		for( node in nodeMap ) {
			var connections = [];
			for( targetId => weightAndPath in node.connections ) {
				connections.push({
					nodeId: targetId,
					weight: weightAndPath.weight,
					chunk: weightAndPath.chunk,
					positionStart: weightAndPath.positionStart,
					positionEnd: weightAndPath.positionEnd
				});
			}
			out.nodes.push({
				id: node.id,
				connections: connections,
				positionStart: node.positionStart,
				positionEnd: node.positionEnd
			});
		}
		return out;
	}

	public static function ensure(project:data.Project):Dynamic {
		if( project==null )
			return { nodes: [] };

		if( project.pathfindingPaths == null || untyped project.pathfindingPaths.nodes == null )
			project.pathfindingPaths = generate(project);

		return project.pathfindingPaths;
	}
}
