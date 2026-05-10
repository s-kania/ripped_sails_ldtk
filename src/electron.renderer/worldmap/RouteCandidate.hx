package worldmap;

typedef RouteCandidate = {
	from:RouteLocationNode,
	to:RouteLocationNode,
	distanceTiles:Float,
	distanceKm:Float,
	cost:Float,
}
