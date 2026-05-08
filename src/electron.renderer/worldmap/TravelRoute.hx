package worldmap;

typedef TravelRoute = {
	id:Int,
	from:LocationRef,
	to:LocationRef,
	distanceKm:Float,
	kind:String,
	points:Array<TravelRoutePoint>,
}
