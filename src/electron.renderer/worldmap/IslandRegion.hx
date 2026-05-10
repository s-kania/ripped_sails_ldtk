package worldmap;

typedef IslandRegion = {
	id:Int,
	name:String,
	tiles:Array<MapPoint>,
	bounds:IslandBounds,
	center:{ x:Float, y:Float },
	borderSegments:Array<IslandBorderSegment>,
}
