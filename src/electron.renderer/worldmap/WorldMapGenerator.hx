package worldmap;

typedef IslandCenter = {
	x:Float,
	y:Float,
	r:Float,
	type:String,
}

typedef MountainParams = {
	intensity:Float,
	steepness:Float,
}

typedef RouteSearchNode = {
	x:Int,
	y:Int,
	g:Float,
	f:Float,
}

class WorldMapGenerator {
	static inline var MAX_ROUTED_RESOLUTION = 512;

	public var params:WorldMapParams;
	public var prng:WorldMapPrng;
	public var noise:WorldMapNoise;
	public var map:WorldMapData;
	var waterComponentIds:Null<Array<Int>> = null;

	public function new(params:WorldMapParams) {
		this.params = params.clone();
		prng = new WorldMapPrng(this.params.seed);
		noise = new WorldMapNoise(prng);
		var w = this.params.resolution;
		var h = Math.round(w / WorldMapParams.GOLDEN_RATIO);
		map = new WorldMapData(w, h, this.params);
	}

	public function generate(?onProgress:String->Void):WorldMapData {
		if( onProgress!=null ) onProgress("Generating island seeds...");
		var centers = distributeClusters();

		if( onProgress!=null ) onProgress("Applying coast noise...");
		var baseFreq = 256.0 / map.width;
		for( y in 0...map.height )
		for( x in 0...map.width ) {
			var warpScale = map.width * 0.04;
			var warpFreq = 0.02 * baseFreq;
			var warpX = (noise.fbm(x, y, 4, 0.5, 2.0, warpFreq) - 0.5) * 2.0 * warpScale;
			var warpY = (noise.fbm(x + 1000, y + 1000, 4, 0.5, 2.0, warpFreq) - 0.5) * 2.0 * warpScale;
			var wx = x + warpX;
			var wy = y + warpY;
			var maskVal = Math.max(getIslandMaskValue(wx, wy, centers), getContinentalMask(wx, wy));
			var noiseVal = noise.fbm(wx, wy, 6, 0.5, 2.0, 0.03 * baseFreq);
			var centeredNoise = (noiseVal - 0.5) * 2.0;
			var noiseEnvelope = Math.min(maskVal * 3.0, 1.0);
			var elevation = maskVal + centeredNoise * params.coastIrregularity * 0.5 * noiseEnvelope;
			elevation *= getEdgeFalloff(x, y);

			var tile = map.getTile(x, y);
			tile.elevation = Math.max(0, elevation);
			tile.moisture = noise.fbm(wx, wy, 4, 0.5, 2.0, 0.03 * baseFreq);
		}

		if( params.blurElevation ) {
			if( onProgress!=null ) onProgress("Blurring elevation...");
			applyElevationBlur();
		}

		if( onProgress!=null ) onProgress("Classifying terrain...");
		classifyTerrain();

		if( params.smoothTerrain )
			smoothTerrainCellular();

		detectIslands();
		generateSettlementsAndPointsOfInterest();

		if( params.enableRoutes && map.width<=MAX_ROUTED_RESOLUTION )
			generateRoutes();
		else {
			if( params.enableRoutes && onProgress!=null )
				onProgress('Skipping sea routes above ${MAX_ROUTED_RESOLUTION}px.');
			map.routes = [];
		}

		if( params.enableStreams && params.streamCount>0 )
			generateStreams();

		if( onProgress!=null ) onProgress("Generation complete.");
		return map;
	}

	function applyElevationBlur() {
		var passes = Std.int(Math.max(1, params.blurElevationStrength));
		var kernel = [1/16, 2/16, 1/16, 2/16, 4/16, 2/16, 1/16, 2/16, 1/16];
		for( p in 0...passes ) {
			var next = [];
			for( y in 0...map.height )
			for( x in 0...map.width ) {
				var v = 0.;
				var ki = 0;
				for( ky in -1...2 )
				for( kx in -1...2 ) {
					var nx = clampInt(x+kx, 0, map.width-1);
					var ny = clampInt(y+ky, 0, map.height-1);
					v += map.getTile(nx, ny).elevation * kernel[ki++];
				}
				next[map.index(x,y)] = v;
			}
			for( i in 0...next.length )
				map.tiles[i].elevation = next[i];
		}
	}

	function smoothTerrainCellular() {
		var passes = Math.round(1 + params.smoothTerrainStrength / 3);
		var bias = Math.max(0, 4 - Math.floor(params.smoothTerrainStrength / 2.5));
		for( p in 0...passes ) {
			var next:Array<Int> = [];
			for( y in 0...map.height )
			for( x in 0...map.width ) {
				var tile = map.getTile(x, y);
				if( !tile.walkable || tile.terrain==Terrain.Beach ) {
					next[map.index(x,y)] = tile.terrain;
					continue;
				}

				var counts:Map<Int,Int> = new Map();
				for( t in [Terrain.Plains, Terrain.Hills, Terrain.Forest, Terrain.Mountains] )
					counts.set(t, 0);
				for( ky in -1...2 )
				for( kx in -1...2 ) {
					var n = map.getTile(x+kx, y+ky);
					if( n!=null && n.walkable && n.terrain!=Terrain.Beach )
						counts.set(n.terrain, counts.get(n.terrain)+1);
				}
				counts.set(tile.terrain, counts.get(tile.terrain) + Std.int(bias));

				var best:Int = tile.terrain;
				var bestCount = -1;
				for( key in counts.keys() )
					if( counts.get(key)>bestCount ) {
						best = key;
						bestCount = counts.get(key);
					}
				next[map.index(x,y)] = best;
			}

			for( i in 0...next.length ) {
				var tile = map.tiles[i];
				if( tile.walkable && tile.terrain!=Terrain.Beach )
					tile.terrain = next[i];
			}
		}
	}

	function detectIslands() {
		map.islands = [];
		for( tile in map.tiles )
			tile.islandId = null;

		var visited:Map<Int,Bool> = new Map();
		var nextId = 1;
		for( y in 0...map.height )
		for( x in 0...map.width ) {
			var start = map.getTile(x, y);
			var startIndex = map.index(x, y);
			if( start==null || !start.walkable || visited.exists(startIndex) )
				continue;

			var id = nextId++;
			var queue:Array<MapPoint> = [{ x:x, y:y }];
			var tiles:Array<MapPoint> = [];
			var head = 0;
			var minX = x;
			var minY = y;
			var maxX = x;
			var maxY = y;
			var sumX = 0.;
			var sumY = 0.;
			visited.set(startIndex, true);

			while( head<queue.length ) {
				var cur = queue[head++];
				var tile = map.getTile(cur.x, cur.y);
				if( tile==null )
					continue;
				tile.islandId = id;
				tiles.push({ x:cur.x, y:cur.y });
				minX = Math.floor(Math.min(minX, cur.x));
				minY = Math.floor(Math.min(minY, cur.y));
				maxX = Math.floor(Math.max(maxX, cur.x));
				maxY = Math.floor(Math.max(maxY, cur.y));
				sumX += cur.x;
				sumY += cur.y;

				for( n in [{x:cur.x+1,y:cur.y}, {x:cur.x-1,y:cur.y}, {x:cur.x,y:cur.y+1}, {x:cur.x,y:cur.y-1}] ) {
					var nt = map.getTile(n.x, n.y);
					var ni = map.index(n.x, n.y);
					if( nt!=null && nt.walkable && !visited.exists(ni) ) {
						visited.set(ni, true);
						queue.push(n);
					}
				}
			}

			map.islands.push({
				id: id,
				name: generateIslandName(id),
				tiles: tiles,
				bounds: { minX:minX, minY:minY, maxX:maxX, maxY:maxY },
				center: { x:sumX/tiles.length, y:sumY/tiles.length },
				borderSegments: getIslandBorderSegments(tiles),
			});
		}
	}

	function getIslandBorderSegments(tiles:Array<MapPoint>):Array<IslandBorderSegment> {
		var segments:Array<IslandBorderSegment> = [];
		for( t in tiles ) {
			var n = map.getTile(t.x, t.y-1);
			if( n==null || !n.walkable )
				segments.push({ x1:t.x, y1:t.y, x2:t.x+1, y2:t.y });
			n = map.getTile(t.x+1, t.y);
			if( n==null || !n.walkable )
				segments.push({ x1:t.x+1, y1:t.y, x2:t.x+1, y2:t.y+1 });
			n = map.getTile(t.x, t.y+1);
			if( n==null || !n.walkable )
				segments.push({ x1:t.x+1, y1:t.y+1, x2:t.x, y2:t.y+1 });
			n = map.getTile(t.x-1, t.y);
			if( n==null || !n.walkable )
				segments.push({ x1:t.x, y1:t.y+1, x2:t.x, y2:t.y });
		}
		return segments;
	}

	function generateSettlementsAndPointsOfInterest() {
		map.cities = [];
		map.pointsOfInterest = [];
		var nextSettlementId = 1;
		var nextPoiId = 1;
		var minDistanceTiles = Std.int(Math.max(1, Math.round(params.coastalLocationMinDistanceKm / params.kmPerTile)));

		for( island in map.islands ) {
			var areaKm2 = getIslandAreaKm2(island.tiles.length);
			var coastal = island.tiles.filter(t -> isCoastalLandTile(t.x, t.y));
			coastal.sort((a,b) -> Reflect.compare(getCoastalScore(b.x,b.y,0.75), getCoastalScore(a.x,a.y,0.75)));
			if( coastal.length==0 )
				continue;

			var occupied:Array<MapPoint> = [];
			if( params.enableSettlements && areaKm2>=3 ) {
				var areaLimit = Math.floor(areaKm2 * 0.08 * params.cityDensity);
				var cityCount = Std.int(Math.min(5, Math.max(0, areaLimit + (areaKm2>=6 ? 1 : 0))));
				for( i in 0...cityCount ) {
					var spot = pickCoastalLocation(coastal, occupied, '${island.id}:city:$i', minDistanceTiles);
					if( spot==null )
						continue;
					var kind = getSettlementKind(i, cityCount, spot.x, spot.y);
					var id = nextSettlementId++;
					map.cities.push({
						id: id,
						name: generateSettlementName(id, kind),
						x: spot.x,
						y: spot.y,
						islandId: island.id,
						kind: kind,
						populationTier: clampInt(Math.ceil(areaKm2/20) + (kind=="capital" ? 1 : 0), 1, 5),
					});
					occupied.push({ x:spot.x, y:spot.y });
				}
			}

			if( params.enablePointsOfInterest && areaKm2>=1 ) {
				var poiCount = Std.int(Math.min(
					Math.max(1, Math.ceil(areaKm2 * 0.035 * params.poiDensity)),
					Math.max(1, Math.ceil(coastal.length / 20))
				));
				for( i in 0...poiCount ) {
					var spot = pickCoastalLocation(coastal, occupied, '${island.id}:poi:$i', minDistanceTiles);
					if( spot==null )
						continue;
					var kind = getPointOfInterestKind(island.id, i);
					var id = nextPoiId++;
					map.pointsOfInterest.push({
						id: id,
						name: generatePointOfInterestName(id, kind),
						x: spot.x,
						y: spot.y,
						islandId: island.id,
						kind: kind,
						rarity: getPointOfInterestRarity(kind),
					});
					occupied.push({ x:spot.x, y:spot.y });
				}
			}
		}
	}

	function generateRoutes() {
		map.routes = [];
		var nodes = buildRouteNodes().filter(n -> n.anchor!=null);
		if( nodes.length<2 ) {
			map.cities = [];
			map.pointsOfInterest = [];
			return;
		}

		var candidates = buildRouteCandidates(nodes);
		var connected:Map<String,Bool> = new Map();
		var routeKeys:Map<String,Bool> = new Map();
		var nextRouteId = 1;

		var sortedByHub = nodes.copy();
		sortedByHub.sort((a,b) -> Reflect.compare(b.hubScore, a.hubScore));
		connected.set(getLocationKey(sortedByHub[0].ref), true);
		var connectedCount = 1;

		while( connectedCount<nodes.length ) {
			var chosen:Null<RouteCandidate> = null;
			for( c in candidates ) {
				var fromConnected = connected.exists(getLocationKey(c.from.ref));
				var toConnected = connected.exists(getLocationKey(c.to.ref));
				if( fromConnected!=toConnected && !routeKeys.exists(getRouteKey(c.from.ref, c.to.ref)) ) {
					chosen = c;
					break;
				}
			}

			if( chosen==null )
				break;

			var route = createRouteFromCandidate(chosen, nextRouteId, "regional");
			routeKeys.set(getRouteKey(chosen.from.ref, chosen.to.ref), true);
			if( route!=null ) {
				map.routes.push(route);
				nextRouteId++;
				chosen.from.degree++;
				chosen.to.degree++;

				var fromKey = getLocationKey(chosen.from.ref);
				var toKey = getLocationKey(chosen.to.ref);
				if( !connected.exists(fromKey) ) {
					connected.set(fromKey, true);
					connectedCount++;
				}
				if( !connected.exists(toKey) ) {
					connected.set(toKey, true);
					connectedCount++;
				}
			}
		}

		var minConnections = Std.int(Math.max(1, Math.round(params.routeMinConnections)));

		for( node in nodes ) {
			while( node.degree<minConnections ) {
				var chosen:Null<RouteCandidate> = null;
				for( c in candidates ) {
					if( routeKeys.exists(getRouteKey(c.from.ref, c.to.ref)) )
						continue;
					if( c.from!=node && c.to!=node )
						continue;
					var other = c.from==node ? c.to : c.from;
					if( other.degree >= params.routeMaxConnections+1 )
						continue;
					chosen = c;
					break;
				}
				if( chosen==null )
					break;
				var route = createRouteFromCandidate(chosen, nextRouteId, "repair");
				routeKeys.set(getRouteKey(chosen.from.ref, chosen.to.ref), true);
				if( route!=null ) {
					map.routes.push(route);
					nextRouteId++;
					chosen.from.degree++;
					chosen.to.degree++;
				}
			}
		}

		var targetExtraRoutes = Std.int(Math.round(nodes.length * Math.max(0, params.routeDensity)));
		var added = 0;
		for( c in candidates ) {
			if( added>=targetExtraRoutes )
				break;
			if( routeKeys.exists(getRouteKey(c.from.ref, c.to.ref)) )
				continue;
			var fromLimit = c.from.hubScore>=0.75 ? params.routeMaxConnections+2 : params.routeMaxConnections;
			var toLimit = c.to.hubScore>=0.75 ? params.routeMaxConnections+2 : params.routeMaxConnections;
			if( c.from.degree>=fromLimit || c.to.degree>=toLimit )
				continue;
			var kind = c.from.hubScore>=0.75 || c.to.hubScore>=0.75 ? "hub" : (c.from.islandId==c.to.islandId ? "local" : "regional");
			var route = createRouteFromCandidate(c, nextRouteId, kind);
			routeKeys.set(getRouteKey(c.from.ref, c.to.ref), true);
			if( route!=null ) {
				map.routes.push(route);
				nextRouteId++;
				c.from.degree++;
				c.to.degree++;
				added++;
			}
		}

		pruneUnconnectedLocations();
	}

	function generateStreams() {
		map.streams = [];
		var sources = findStreamSources();
		var used:Map<String,Bool> = new Map();
		var created = 0;
		for( source in sources ) {
			if( created>=params.streamCount )
				break;
			var key = source.x+","+source.y;
			if( used.exists(key) )
				continue;
			used.set(key, true);
			var main = traceStream(source.x, source.y, "main", null);
			if( main.points.length<Math.max(10, Math.floor(map.width*0.04)) || !streamReachesWater(main) )
				continue;
			map.streams.push(main);
			addTributaries(main);
			addEstuary(main);
			created++;
		}
	}

	function distributeClusters():Array<IslandCenter> {
		var centers:Array<IslandCenter> = [];
		var clusters:Array<{x:Float,y:Float}> = [];
		for( i in 0...params.clusters ) {
			var cx:Float;
			var cy:Float;
			if( prng.next()<params.caribbeanness ) {
				var t = prng.next();
				cx = map.width*0.1 + t*map.width*0.8 + (prng.next()-0.5)*map.width*0.2;
				cy = map.height*0.2 + Math.sin(t*Math.PI)*map.height*0.6 + (prng.next()-0.5)*map.height*0.2;
			}
			else {
				cx = map.width*0.2 + prng.next()*map.width*0.6;
				cy = map.height*0.2 + prng.next()*map.height*0.6;
			}
			clusters.push({x:cx, y:cy});
		}
		addIslands(centers, clusters, "big", params.largeIslands);
		addIslands(centers, clusters, "med", params.medIslands);
		addIslands(centers, clusters, "small", params.smallIslands);
		return centers;
	}

	function addIslands(centers:Array<IslandCenter>, clusters:Array<{x:Float,y:Float}>, sizeGroup:String, count:Int) {
		for( i in 0...count ) {
			var c = clusters[prng.nextInt(0, clusters.length-1)];
			var radiusScatter = sizeGroup=="big" ? map.width*0.1 : (sizeGroup=="med" ? map.width*0.2 : map.width*0.3);
			var ix = c.x + (prng.next()-0.5)*radiusScatter;
			var iy = c.y + (prng.next()-0.5)*radiusScatter;
			var ir = switch sizeGroup {
				case "big": map.width * prng.next() * 0.15 + map.width*0.1;
				case "med": map.width*0.05 + prng.next()*map.width*0.05;
				case _: map.width*0.01 + prng.next()*map.width*0.03;
			}
			centers.push({x:ix, y:iy, r:ir, type:sizeGroup});
		}
	}

	function getIslandMaskValue(x:Float, y:Float, centers:Array<IslandCenter>):Float {
		var maxInfluence = 0.;
		for( c in centers ) {
			var dx = c.x - x;
			var dy = c.y - y;
			var influenceRadius = c.r * 1.5;
			var distSq = dx*dx + dy*dy;
			if( distSq<influenceRadius*influenceRadius ) {
				var t = Math.max(0, 1 - Math.sqrt(distSq)/influenceRadius);
				maxInfluence = Math.max(maxInfluence, t*t*(3-2*t));
			}
		}
		return maxInfluence;
	}

	function getEdgeFalloff(x:Int, y:Int):Float {
		var nx = x / map.width;
		var ny = y / map.height;
		var margin = 0.15;
		var falloffX = 1.;
		var falloffY = 1.;
		if( !params.contWestAttach && nx<margin )
			falloffX = nx/margin;
		else if( !params.contEastAttach && nx>1-margin )
			falloffX = (1-nx)/margin;
		if( !params.contNorthAttach && ny<margin )
			falloffY = ny/margin;
		else if( !params.contSouthAttach && ny>1-margin )
			falloffY = (1-ny)/margin;
		return smoothstep(falloffX) * smoothstep(falloffY);
	}

	function getContinentalMask(x:Float, y:Float):Float {
		var w = map.width;
		var h = map.height;
		var finalVal = 0.;
		var edgeWidth = w * 0.18;
		var edgeHeight = h * 0.18;
		if( params.contWest>0 )
			finalVal = Math.max(finalVal, smoothstep(1 - x/edgeWidth) * params.contWest * 1.5);
		if( params.contEast>0 )
			finalVal = Math.max(finalVal, smoothstep(1 - (w-x)/edgeWidth) * params.contEast * 1.5);
		if( params.contNorth>0 )
			finalVal = Math.max(finalVal, smoothstep(1 - y/edgeHeight) * params.contNorth * 1.5);
		if( params.contSouth>0 )
			finalVal = Math.max(finalVal, smoothstep(1 - (h-y)/edgeHeight) * params.contSouth * 1.5);
		return finalVal;
	}

	function getMountainParams(x:Int, y:Int):MountainParams {
		var w = map.width;
		var h = map.height;
		var edgeWidth = w * 0.18;
		var edgeHeight = h * 0.18;
		var west = params.contWest>0 ? smoothstep(1 - x/edgeWidth) * params.contWest * 1.5 : 0;
		var east = params.contEast>0 ? smoothstep(1 - (w-x)/edgeWidth) * params.contEast * 1.5 : 0;
		var north = params.contNorth>0 ? smoothstep(1 - y/edgeHeight) * params.contNorth * 1.5 : 0;
		var south = params.contSouth>0 ? smoothstep(1 - (h-y)/edgeHeight) * params.contSouth * 1.5 : 0;
		var maxC = Math.max(Math.max(west, east), Math.max(north, south));
		var intensity = params.mountainIntensity;
		var steepness = params.mountainSteepness;
		if( maxC>0 ) {
			var cWeight = Math.min(1, maxC*1.5);
			var ci = params.mountainIntensity;
			var cs = params.mountainSteepness;
			if( maxC==west ) { ci = params.contWestMountain; cs = params.contWestSteepness; }
			else if( maxC==east ) { ci = params.contEastMountain; cs = params.contEastSteepness; }
			else if( maxC==north ) { ci = params.contNorthMountain; cs = params.contNorthSteepness; }
			else if( maxC==south ) { ci = params.contSouthMountain; cs = params.contSouthSteepness; }
			intensity = (1-cWeight)*params.mountainIntensity + cWeight*ci;
			steepness = (1-cWeight)*params.mountainSteepness + cWeight*cs;
		}
		return { intensity:intensity, steepness:steepness };
	}

	function classifyTerrain() {
		var sea = params.seaLevel;
		var bw = params.beachWidth;
		var maxElevOld = 0.;
		for( tile in map.tiles )
			maxElevOld = Math.max(maxElevOld, tile.elevation);
		var landPeakOld = Math.max(maxElevOld, sea + bw + 0.1);
		var landRangeOld = landPeakOld - (sea + bw);

		for( tile in map.tiles ) {
			var mp = getMountainParams(tile.x, tile.y);
			tile.steepness = mp.steepness;
			if( tile.elevation>sea+bw ) {
				var norm = (tile.elevation - (sea+bw)) / landRangeOld;
				if( mp.steepness>0.01 && norm>0.05 ) {
					var xx = tile.x * 0.4;
					var yy = tile.y * 0.4;
					var crag = Math.sin(xx)*Math.cos(yy) + Math.sin(xx*2.1 + yy*1.7)*0.5;
					tile.elevation += Math.pow(norm, 1.3)*mp.steepness*0.7 + crag*0.15*mp.steepness*norm;
				}
			}
		}

		var maxElev = 0.;
		for( tile in map.tiles )
			maxElev = Math.max(maxElev, tile.elevation);
		var landPeak = Math.max(maxElev, sea + bw + 0.1);
		var landRange = landPeak - (sea + bw);

		for( tile in map.tiles ) {
			var mp = getMountainParams(tile.x, tile.y);
			var e = tile.elevation;
			var mtnT = 0.97 - mp.intensity * 0.97;
			var hillsT = 0.60 - mp.intensity * 0.60;
			var mtnThreshold = sea + bw + landRange * mtnT;
			var hillsThreshold = sea + bw + landRange * hillsT;

			if( e<sea ) {
				tile.walkable = false;
				tile.isNavigable = true;
				if( e<sea-0.15 )
					tile.terrain = Terrain.DeepSea;
				else {
					tile.terrain = Terrain.ShallowWater;
					if( params.reefFreq>0 && e>sea-0.08 ) {
						var reefNoise = noise.fbm(tile.x*5, tile.y*5, 2, 0.5, 2.0, 0.1);
						if( reefNoise < params.reefFreq*0.7 ) {
							tile.terrain = Terrain.Reef;
							tile.isNavigable = false;
						}
					}
				}
			}
			else {
				tile.walkable = true;
				tile.isNavigable = false;
				if( e<sea+bw )
					tile.terrain = Terrain.Beach;
				else if( e>mtnThreshold )
					tile.terrain = Terrain.Mountains;
				else if( e>hillsThreshold )
					tile.terrain = tile.moisture<params.forestDensity ? Terrain.Forest : Terrain.Hills;
				else
					tile.terrain = tile.moisture<params.forestDensity*1.2 ? Terrain.Forest : Terrain.Plains;
			}
		}
	}

	function buildRouteNodes():Array<RouteLocationNode> {
		var nodes:Array<RouteLocationNode> = [];
		for( city in map.cities )
			nodes.push({
				ref:{ type:"city", id:city.id },
				x:city.x, y:city.y, islandId:city.islandId,
				hubScore:getLocationHubScore({ type:"city", id:city.id }),
				degree:0,
				anchor:findNearestWaterAnchor(city.x, city.y),
			});
		for( point in map.pointsOfInterest )
			nodes.push({
				ref:{ type:"poi", id:point.id },
				x:point.x, y:point.y, islandId:point.islandId,
				hubScore:getLocationHubScore({ type:"poi", id:point.id }),
				degree:0,
				anchor:findNearestWaterAnchor(point.x, point.y),
			});
		return nodes;
	}

	function buildRouteCandidates(nodes:Array<RouteLocationNode>):Array<RouteCandidate> {
		var candidates:Array<RouteCandidate> = [];
		var maxDistTiles = Math.max(1, params.routeMaxDistanceKm / params.kmPerTile);
		var relaxedDistTiles = maxDistTiles * 1.75;
		for( i in 0...nodes.length )
		for( j in (i+1)...nodes.length ) {
			var from = nodes[i];
			var to = nodes[j];
			var distanceTiles = distance(from.x, from.y, to.x, to.y);
			if( distanceTiles>relaxedDistTiles && from.hubScore<0.75 && to.hubScore<0.75 )
				continue;
			var rng = new WorldMapPrng('${params.seed}:route-candidate:${getRouteKey(from.ref,to.ref)}');
			var hubBonus = (from.hubScore+to.hubScore) * params.routeHubBias * maxDistTiles * 0.18;
			var sameIslandPenalty = from.islandId==to.islandId ? maxDistTiles*0.08 : 0;
			var longPenalty = distanceTiles>maxDistTiles ? (distanceTiles-maxDistTiles)*1.8 : 0;
			var jitter = rng.next() * maxDistTiles * 0.08;
			candidates.push({
				from:from,
				to:to,
				distanceTiles:distanceTiles,
				distanceKm:distanceTiles*params.kmPerTile,
				cost:distanceTiles + sameIslandPenalty + longPenalty - hubBonus + jitter,
			});
		}
		candidates.sort((a,b) -> Reflect.compare(a.cost, b.cost));
		return candidates;
	}

	function createRouteFromCandidate(c:RouteCandidate, id:Int, kind:String):Null<TravelRoute> {
		if( c.from.anchor==null || c.to.anchor==null )
			return null;
		var points = findWaterPath(c.from.anchor, c.to.anchor, c.distanceTiles);
		if( points==null || points.length<2 )
			return null;
		return {
			id:id,
			from:c.from.ref,
			to:c.to.ref,
			distanceKm:Math.round(points.length * params.kmPerTile * 100)/100,
			kind:kind,
			points:simplifyRoutePoints(points),
		};
	}

	function findWaterPath(start:TravelRoutePoint, goal:TravelRoutePoint, directDistanceTiles:Float):Null<Array<TravelRoutePoint>> {
		if( getWaterComponentId(start.x, start.y)!=getWaterComponentId(goal.x, goal.y) )
			return null;
		var startIndex = map.index(start.x, start.y);
		var goalIndex = map.index(goal.x, goal.y);
		var open:Array<RouteSearchNode> = [];
		pushOpenNode(open, { x:start.x, y:start.y, g:0, f:distance(start.x, start.y, goal.x, goal.y) });
		var cameFrom:haxe.ds.IntMap<Int> = new haxe.ds.IntMap();
		var gScore:haxe.ds.IntMap<Float> = new haxe.ds.IntMap();
		var closed:haxe.ds.IntMap<Bool> = new haxe.ds.IntMap();
		gScore.set(startIndex, 0);

		var margin = Std.int(Math.max(12, Math.ceil(directDistanceTiles * 0.35)));
		var minX = clampInt(Std.int(Math.min(start.x, goal.x)) - margin, 0, map.width-1);
		var maxX = clampInt(Std.int(Math.max(start.x, goal.x)) + margin, 0, map.width-1);
		var minY = clampInt(Std.int(Math.min(start.y, goal.y)) - margin, 0, map.height-1);
		var maxY = clampInt(Std.int(Math.max(start.y, goal.y)) + margin, 0, map.height-1);
		var visitLimit = Std.int(Math.min(map.width * map.height, Math.max(800, Math.ceil(directDistanceTiles * directDistanceTiles * 3))));
		var visits = 0;

		while( open.length>0 && visits<visitLimit ) {
			var current = popOpenNode(open);
			if( current==null )
				break;
			var currentIndex = map.index(current.x, current.y);
			if( closed.exists(currentIndex) )
				continue;
			if( currentIndex==goalIndex )
				return reconstructWaterPath(cameFrom, currentIndex);

			closed.set(currentIndex, true);
			visits++;

			for( oy in -1...2 )
			for( ox in -1...2 ) {
				if( ox==0 && oy==0 )
					continue;
				var nx = current.x + ox;
				var ny = current.y + oy;
				if( nx<minX || nx>maxX || ny<minY || ny>maxY )
					continue;
				var tile = map.getTile(nx, ny);
				if( tile==null || tile.walkable || !tile.isNavigable )
					continue;

				var neighborIndex = map.index(nx, ny);
				if( closed.exists(neighborIndex) )
					continue;
				var stepCost = ox!=0 && oy!=0 ? 1.414 : 1.0;
				var reefPenalty = tile.terrain==Terrain.Reef ? 0.35 : 0.0;
				var shorePenalty = isNearLand(nx, ny) ? 0.08 : 0.0;
				var tentativeG = current.g + stepCost + reefPenalty + shorePenalty;
				var existingG = gScore.exists(neighborIndex) ? gScore.get(neighborIndex) : 1e30;
				if( tentativeG>=existingG )
					continue;

				cameFrom.set(neighborIndex, currentIndex);
				gScore.set(neighborIndex, tentativeG);
				pushOpenNode(open, {
					x:nx,
					y:ny,
					g:tentativeG,
					f:tentativeG + distance(nx, ny, goal.x, goal.y),
				});
			}
		}

		return null;
	}

	function getWaterComponentId(x:Int, y:Int):Int {
		if( waterComponentIds==null )
			buildWaterComponents();
		var ids = waterComponentIds;
		if( ids==null )
			return -1;
		return ids[map.index(x, y)];
	}

	function buildWaterComponents() {
		var ids:Array<Int> = [];
		for( i in 0...(map.width*map.height) )
			ids[i] = -1;
		var nextId = 0;
		for( y in 0...map.height )
		for( x in 0...map.width ) {
			var idx = map.index(x, y);
			if( ids[idx]>=0 )
				continue;
			var start = map.getTile(x, y);
			if( start==null || start.walkable || !start.isNavigable )
				continue;

			var queue:Array<MapPoint> = [{ x:x, y:y }];
			var head = 0;
			ids[idx] = nextId;
			while( head<queue.length ) {
				var cur = queue[head++];
				for( oy in -1...2 )
				for( ox in -1...2 ) {
					if( ox==0 && oy==0 )
						continue;
					var nx = cur.x + ox;
					var ny = cur.y + oy;
					if( nx<0 || nx>=map.width || ny<0 || ny>=map.height )
						continue;
					var ni = map.index(nx, ny);
					if( ids[ni]>=0 )
						continue;
					var tile = map.getTile(nx, ny);
					if( tile==null || tile.walkable || !tile.isNavigable )
						continue;
					ids[ni] = nextId;
					queue.push({ x:nx, y:ny });
				}
			}
			nextId++;
		}
		waterComponentIds = ids;
	}

	static function pushOpenNode(open:Array<RouteSearchNode>, node:RouteSearchNode) {
		open.push(node);
		var i = open.length-1;
		while( i>0 ) {
			var parent = Std.int((i-1)/2);
			if( !routeNodeLess(open[i], open[parent]) )
				break;
			var tmp = open[i];
			open[i] = open[parent];
			open[parent] = tmp;
			i = parent;
		}
	}

	static function popOpenNode(open:Array<RouteSearchNode>):Null<RouteSearchNode> {
		if( open.length==0 )
			return null;
		var first = open[0];
		var last = open.pop();
		if( open.length>0 && last!=null ) {
			open[0] = last;
			var i = 0;
			while( true ) {
				var left = i*2+1;
				if( left>=open.length )
					break;
				var right = left+1;
				var best = left;
				if( right<open.length && routeNodeLess(open[right], open[left]) )
					best = right;
				if( !routeNodeLess(open[best], open[i]) )
					break;
				var tmp = open[i];
				open[i] = open[best];
				open[best] = tmp;
				i = best;
			}
		}
		return first;
	}

	static inline function routeNodeLess(a:RouteSearchNode, b:RouteSearchNode):Bool {
		return a.f<b.f || (a.f==b.f && a.g>b.g);
	}

	function reconstructWaterPath(cameFrom:haxe.ds.IntMap<Int>, currentIndex:Int):Array<TravelRoutePoint> {
		var points:Array<TravelRoutePoint> = [];
		var key:Null<Int> = currentIndex;
		while( key!=null ) {
			points.push({ x:key%map.width, y:Std.int(key/map.width) });
			key = cameFrom.get(key);
		}
		points.reverse();
		return points;
	}

	function simplifyRoutePoints(points:Array<TravelRoutePoint>):Array<TravelRoutePoint> {
		if( points.length<=2 )
			return points;
		var simplified = [points[0]];
		var prevDx = 0;
		var prevDy = 0;
		for( i in 1...(points.length-1) ) {
			var prev = points[i-1];
			var next = points[i+1];
			var dx = clampInt(next.x - prev.x, -1, 1);
			var dy = clampInt(next.y - prev.y, -1, 1);
			var directionChanged = i>1 && (dx!=prevDx || dy!=prevDy);
			if( directionChanged || i%5==0 )
				simplified.push(points[i]);
			prevDx = dx;
			prevDy = dy;
		}
		simplified.push(points[points.length-1]);
		return simplified;
	}

	function findNearestWaterAnchor(x:Int, y:Int):Null<TravelRoutePoint> {
		return nearestNavigableWater(x, y, 5);
	}

	function nearestNavigableWater(x:Int, y:Int, radius:Int):Null<TravelRoutePoint> {
		var best:Null<TravelRoutePoint> = null;
		var bestD = 999999.;
		for( r in 1...(radius+1) )
		for( oy in (-r)...(r+1) )
		for( ox in (-r)...(r+1) ) {
			if( Math.max(Math.abs(ox), Math.abs(oy))!=r )
				continue;
			var tile = map.getTile(x+ox, y+oy);
			if( tile!=null && !tile.walkable && tile.isNavigable ) {
				var d = ox*ox + oy*oy;
				if( d<bestD ) {
					bestD = d;
					best = { x:tile.x, y:tile.y };
				}
			}
		}
		return best;
	}

	function pruneUnconnectedLocations() {
		var connected:Map<String,Bool> = new Map();
		for( route in map.routes ) {
			connected.set(getLocationKey(route.from), true);
			connected.set(getLocationKey(route.to), true);
		}
		map.cities = map.cities.filter(c -> connected.exists(getLocationKey({ type:"city", id:c.id })));
		map.pointsOfInterest = map.pointsOfInterest.filter(p -> connected.exists(getLocationKey({ type:"poi", id:p.id })));
		var valid:Map<String,Bool> = new Map();
		for( city in map.cities )
			valid.set(getLocationKey({ type:"city", id:city.id }), true);
		for( point in map.pointsOfInterest )
			valid.set(getLocationKey({ type:"poi", id:point.id }), true);
		map.routes = map.routes.filter(route -> valid.exists(getLocationKey(route.from)) && valid.exists(getLocationKey(route.to)));
	}

	function findStreamSources():Array<{x:Int,y:Int,score:Float}> {
		var sources:Array<{x:Int,y:Int,score:Float}> = [];
		for( tile in map.tiles ) {
			if( !tile.walkable || (tile.terrain!=Terrain.Mountains && tile.terrain!=Terrain.Hills) )
				continue;
			if( tile.elevation <= params.seaLevel + params.beachWidth + 0.08 )
				continue;
			var edgeBias = getContinentalSourceBias(tile.x, tile.y);
			var noiseBias = noise.fbm(tile.x+73, tile.y+91, 2, 0.5, 2.0, 0.05) * 0.08;
			sources.push({ x:tile.x, y:tile.y, score:tile.elevation+edgeBias+noiseBias });
		}
		sources.sort((a,b) -> Reflect.compare(b.score, a.score));
		return sources;
	}

	function traceStream(startX:Int, startY:Int, kind:String, target:Null<Map<String,Bool>>):StreamPath {
		var points:Array<StreamPoint> = [];
		var visited:Map<String,Bool> = new Map();
		var maxLength = Math.floor((map.width + map.height) * 1.4);
		var x = startX;
		var y = startY;
		var dirX = 0;
		var dirY = 1;
		var uphillSteps = 0;
		for( step in 0...maxLength ) {
			var tile = map.getTile(x, y);
			if( tile==null )
				break;
			var key = '$x,$y';
			if( visited.exists(key) )
				break;
			visited.set(key, true);
			points.push({ x:x, y:y, width: step>maxLength*0.72 && kind!="tributary" ? 2 : 1, flow:Math.min(1, step/maxLength) });
			if( target!=null && target.exists(key) )
				break;
			if( step>2 && touchesWater(x, y) )
				break;

			var best:Null<{x:Int,y:Int,score:Float,elevation:Float}> = null;
			var lowland = 1 - Math.max(0, Math.min(1, (tile.elevation - params.seaLevel) / 0.5));
			for( oy in -1...2 )
			for( ox in -1...2 ) {
				if( ox==0 && oy==0 )
					continue;
				var n = map.getTile(x+ox, y+oy);
				if( n==null || !n.walkable || touchesLand(n.x, n.y)==false )
					continue;
				var downhill = tile.elevation - n.elevation;
				var continuation = (ox*dirX + oy*dirY) * 0.018;
				var diagonalPenalty = ox!=0 && oy!=0 ? 0.012 : 0;
				var meander = (noise.fbm(n.x+startX*11, n.y+startY*13, 2, 0.5, 2.0, 0.12)-0.5) * params.streamMeander * (0.03 + lowland*0.08);
				var waterPull = touchesWater(n.x, n.y) ? 0.18 + lowland*0.25 : 0;
				var targetPull = target!=null && target.exists('${n.x},${n.y}') ? 0.5 : 0;
				var score = downhill + continuation + meander + waterPull + targetPull - diagonalPenalty;
				if( best==null || score>best.score )
					best = { x:n.x, y:n.y, score:score, elevation:n.elevation };
			}
			if( best==null )
				break;
			if( best.elevation > tile.elevation + 0.01 )
				uphillSteps++;
			else
				uphillSteps = 0;
			if( uphillSteps>3 )
				break;
			dirX = clampInt(best.x-x, -1, 1);
			dirY = clampInt(best.y-y, -1, 1);
			x = best.x;
			y = best.y;
		}
		return { points:points, kind:kind };
	}

	function streamReachesWater(stream:StreamPath):Bool {
		if( stream.points.length==0 )
			return false;
		var end = stream.points[stream.points.length-1];
		return touchesWater(end.x, end.y);
	}

	function addTributaries(main:StreamPath) {
		var count = Math.round(params.streamTributaries);
		if( count<=0 || main.points.length<18 )
			return;
		var target:Map<String,Bool> = new Map();
		for( p in main.points )
			target.set('${p.x},${p.y}', true);
		for( i in 0...count ) {
			var minIdx = Math.floor(main.points.length * 0.35);
			var maxIdx = Std.int(Math.max(Math.floor(main.points.length * 0.85), minIdx));
			var join = main.points[prng.nextInt(minIdx, maxIdx)];
			var source = findTributarySource(join.x, join.y);
			if( source==null )
				continue;
			var tributary = traceStream(source.x, source.y, "tributary", target);
			if( tributary.points.length>=6 && tributary.points.length<=main.points.length*0.7 )
				map.streams.push(tributary);
		}
	}

	function findTributarySource(joinX:Int, joinY:Int):Null<{x:Int,y:Int,score:Float}> {
		var best:Null<{x:Int,y:Int,score:Float}> = null;
		var radius = Std.int(Math.max(10, Math.floor(map.width*0.08)));
		var joinTile = map.getTile(joinX, joinY);
		if( joinTile==null )
			return null;
		var y = joinY - radius;
		while( y<=joinY+radius ) {
			var x = joinX - radius;
			while( x<=joinX+radius ) {
				var tile = map.getTile(x, y);
				if( tile!=null && tile.walkable && tile.elevation>joinTile.elevation+0.04 ) {
					var dist = distance(x, y, joinX, joinY);
					if( dist>=6 && dist<=radius ) {
						var score = tile.elevation - dist/radius*0.2 + noise.fbm(x, y, 2, 0.5, 2.0, 0.08);
						if( best==null || score>best.score )
							best = { x:x, y:y, score:score };
					}
				}
				x += 2;
			}
			y += 2;
		}
		return best;
	}

	function addEstuary(main:StreamPath) {
		if( main.points.length<6 )
			return;
		var end = main.points[main.points.length-1];
		for( side in [-1, 1] ) {
			var points:Array<StreamPoint> = [{ x:end.x, y:end.y, width:2 }];
			var x = end.x;
			var y = end.y;
			for( step in 0...4 ) {
				var next = findEstuaryStep(x, y, side);
				if( next==null )
					break;
				x = next.x;
				y = next.y;
				points.push({ x:x, y:y, width:1 });
				var tile = map.getTile(x, y);
				if( tile!=null && !tile.walkable )
					break;
			}
			if( points.length>1 )
				map.streams.push({ points:points, kind:"estuary" });
		}
	}

	function findEstuaryStep(x:Int, y:Int, sideBias:Int):Null<{x:Int,y:Int,score:Float}> {
		var best:Null<{x:Int,y:Int,score:Float}> = null;
		for( oy in -1...2 )
		for( ox in -1...2 ) {
			if( ox==0 && oy==0 )
				continue;
			var tile = map.getTile(x+ox, y+oy);
			if( tile==null )
				continue;
			var score = (tile.walkable ? 0 : 1) + ox*sideBias*0.08 - tile.elevation*0.1;
			if( best==null || score>best.score )
				best = { x:tile.x, y:tile.y, score:score };
		}
		return best;
	}

	function pickCoastalLocation(tiles:Array<MapPoint>, occupied:Array<MapPoint>, salt:String, minDistance:Int):Null<MapPoint> {
		var rng = new WorldMapPrng('${params.seed}:coastal:$salt');
		var candidates = [
			for( t in tiles )
				{ point:t, score:getCoastalScore(t.x, t.y, 0.75) + rng.next()*0.1 }
		];
		candidates.sort((a,b) -> Reflect.compare(b.score, a.score));
		for( c in candidates ) {
			var spot = c.point;
			var ok = true;
			for( other in occupied )
				if( distance(spot.x, spot.y, other.x, other.y)<minDistance ) {
					ok = false;
					break;
				}
			if( ok )
				return spot;
		}
		return candidates.length>0 ? candidates[0].point : null;
	}

	function getCoastalScore(x:Int, y:Int, coastalBias:Float):Float {
		var tile = map.getTile(x, y);
		if( tile==null )
			return 0;
		var waterNeighbors = 0;
		var score = tile.terrain==Terrain.Beach ? 2.5 : 1.0;
		for( oy in -1...2 )
		for( ox in -1...2 ) {
			if( ox==0 && oy==0 )
				continue;
			var n = map.getTile(x+ox, y+oy);
			if( n!=null && !n.walkable )
				waterNeighbors++;
		}
		return score + waterNeighbors*(0.5+coastalBias) + noise.fbm(x+211, y+419, 2, 0.5, 2.0, 0.08);
	}

	inline function getIslandAreaKm2(tileCount:Int):Float return tileCount * params.kmPerTile * params.kmPerTile;

	function isCoastalLandTile(x:Int, y:Int):Bool {
		var tile = map.getTile(x, y);
		if( tile==null || !tile.walkable )
			return false;
		for( oy in -1...2 )
		for( ox in -1...2 ) {
			if( ox==0 && oy==0 )
				continue;
			var n = map.getTile(x+ox, y+oy);
			if( n!=null && !n.walkable )
				return true;
		}
		return false;
	}

	function touchesWater(x:Int, y:Int):Bool {
		for( oy in -1...2 )
		for( ox in -1...2 ) {
			var tile = map.getTile(x+ox, y+oy);
			if( tile!=null && !tile.walkable )
				return true;
		}
		return false;
	}

	function touchesLand(x:Int, y:Int):Bool {
		for( oy in -1...2 )
		for( ox in -1...2 ) {
			var tile = map.getTile(x+ox, y+oy);
			if( tile!=null && tile.walkable )
				return true;
		}
		return false;
	}

	function isNearLand(x:Int, y:Int):Bool {
		for( oy in -1...2 )
		for( ox in -1...2 ) {
			if( ox==0 && oy==0 )
				continue;
			var tile = map.getTile(x+ox, y+oy);
			if( tile!=null && tile.walkable )
				return true;
		}
		return false;
	}

	function getContinentalSourceBias(x:Int, y:Int):Float {
		var edgeW = map.width * 0.18;
		var edgeH = map.height * 0.18;
		var bias = 0.;
		if( params.contWest>0 )
			bias = Math.max(bias, Math.max(0, 1 - x/edgeW) * params.contWest * params.contWestMountain);
		if( params.contEast>0 )
			bias = Math.max(bias, Math.max(0, 1 - (map.width-x)/edgeW) * params.contEast * params.contEastMountain);
		if( params.contNorth>0 )
			bias = Math.max(bias, Math.max(0, 1 - y/edgeH) * params.contNorth * params.contNorthMountain);
		if( params.contSouth>0 )
			bias = Math.max(bias, Math.max(0, 1 - (map.height-y)/edgeH) * params.contSouth * params.contSouthMountain);
		return bias * params.streamSourceBias;
	}

	function getLocationHubScore(ref:LocationRef):Float {
		if( ref.type=="city" ) {
			var city = map.cities.filter(c -> c.id==ref.id)[0];
			if( city==null ) return 0;
			return switch city.kind {
				case "capital": 1;
				case "port": 0.85;
				case "fort": 0.55;
				case _: 0.4;
			}
		}
		var point = map.pointsOfInterest.filter(p -> p.id==ref.id)[0];
		if( point==null ) return 0;
		return switch point.kind {
			case "pirateHaven": 0.85;
			case "blackCove": 0.75;
			case "ancientRuins", "treasureSite": 0.65;
			case _: 0.35;
		}
	}

	function getLocationKey(ref:LocationRef):String return ref.type + ":" + ref.id;

	function getRouteKey(a:LocationRef, b:LocationRef):String {
		var ka = getLocationKey(a);
		var kb = getLocationKey(b);
		return ka<kb ? ka+"|"+kb : kb+"|"+ka;
	}

	function getSettlementKind(index:Int, total:Int, x:Int, y:Int):String {
		if( index==0 && total>=3 )
			return "capital";
		var tile = map.getTile(x, y);
		if( tile!=null && tile.terrain==Terrain.Beach )
			return "port";
		return index%4==0 ? "fort" : "town";
	}

	function getPointOfInterestKind(islandId:Int, index:Int):String {
		var rng = new WorldMapPrng('${params.seed}:poi-kind:$islandId:$index');
		var kinds = ["blackCove", "treasureSite", "pirateHaven", "lostMission", "smugglerCamp", "ancientRuins"];
		return kinds[rng.nextInt(0, kinds.length-1)];
	}

	function getPointOfInterestRarity(kind:String):Int {
		return switch kind {
			case "treasureSite", "ancientRuins": 3;
			case "blackCove", "pirateHaven": 2;
			case _: 1;
		}
	}

	function generateIslandName(id:Int):String {
		var rng = new WorldMapPrng('${params.seed}:island:$id');
		var prefixes = ["Isla", "Cayo", "Port", "Cape", "Old", "Saint", "Skull", "Black", "Golden", "Storm"];
		var roots = ["Dorada", "Calavera", "Marisol", "Blackwater", "Redwind", "Saltmere", "Tortuga", "Moonfall", "Crowsrest", "Seabone", "Amber", "Drift"];
		var suffixes = ["Cay", "Isle", "Haven", "Reach", "Point", "Harbor", "Key", "Rock"];
		return rng.next()<0.45
			? prefixes[rng.nextInt(0, prefixes.length-1)] + " " + roots[rng.nextInt(0, roots.length-1)]
			: roots[rng.nextInt(0, roots.length-1)] + " " + suffixes[rng.nextInt(0, suffixes.length-1)];
	}

	function generateSettlementName(id:Int, kind:String):String {
		var rng = new WorldMapPrng('${params.seed}:settlement:$id');
		var prefixes = ["Port", "Fort", "San", "Santa", "New", "Old", "Puerto", "Cape"];
		var roots = ["Royal", "Marisol", "Esperanza", "Blackwater", "Dorada", "Tortuga", "Verde", "Cannon", "Mercy", "Crown"];
		if( kind=="fort" )
			return "Fort " + roots[rng.nextInt(0, roots.length-1)];
		if( kind=="port" || kind=="capital" )
			return "Port " + roots[rng.nextInt(0, roots.length-1)];
		return prefixes[rng.nextInt(0, prefixes.length-1)] + " " + roots[rng.nextInt(0, roots.length-1)];
	}

	function generatePointOfInterestName(id:Int, kind:String):String {
		var rng = new WorldMapPrng('${params.seed}:poi-name:$id');
		var names = switch kind {
			case "blackCove": ["Black Cove", "Dead Man Cove", "Nocturne Cove"];
			case "treasureSite": ["Buried Gold", "Captain's Cache", "Lost Treasure"];
			case "pirateHaven": ["Pirate Haven", "Corsair Anchorage", "Freebooter Camp"];
			case "lostMission": ["Lost Mission", "Abandoned Chapel", "Saint's Ruin"];
			case "smugglerCamp": ["Smuggler Camp", "Hidden Landing", "Rumrunner Shore"];
			case "ancientRuins": ["Ancient Ruins", "Sunken Shrine", "Old Idol"];
			case _: ["Unknown Shore"];
		}
		return names[rng.nextInt(0, names.length-1)];
	}

	inline function smoothstep(t:Float):Float {
		t = Math.max(0, Math.min(1, t));
		return t*t*(3-2*t);
	}

	inline function distance(x1:Float, y1:Float, x2:Float, y2:Float):Float {
		var dx = x1-x2;
		var dy = y1-y2;
		return Math.sqrt(dx*dx + dy*dy);
	}

	static inline function clampInt(v:Int, min:Int, max:Int):Int return Std.int(Math.max(min, Math.min(max, v)));
}
