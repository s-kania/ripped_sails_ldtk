package worldmap;

class WorldMapData {
	public var width:Int;
	public var height:Int;
	public var params:WorldMapParams;
	public var tiles:Array<WorldMapTile>;
	public var cities:Array<Settlement> = [];
	public var routes:Array<TravelRoute> = [];
	public var streams:Array<StreamPath> = [];
	public var islands:Array<IslandRegion> = [];
	public var pointsOfInterest:Array<PointOfInterest> = [];

	public function new(width:Int, height:Int, params:WorldMapParams) {
		this.width = width;
		this.height = height;
		this.params = params.clone();
		tiles = [];
		for( y in 0...height )
		for( x in 0...width )
			tiles.push(new WorldMapTile(x, y));
	}

	public inline function index(x:Int, y:Int) return y * width + x;

	public function getTile(x:Int, y:Int):Null<WorldMapTile> {
		return x<0 || x>=width || y<0 || y>=height ? null : tiles[index(x, y)];
	}
}
