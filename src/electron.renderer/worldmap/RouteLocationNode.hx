package worldmap;

typedef RouteLocationNode = {
	ref:LocationRef,
	x:Int,
	y:Int,
	islandId:Int,
	hubScore:Float,
	degree:Int,
	anchor:Null<TravelRoutePoint>,
}
