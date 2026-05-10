package worldmap;

class WorldMapTile {
	public var x:Int;
	public var y:Int;
	public var elevation:Float = 0;
	public var moisture:Float = 0;
	public var terrain:Terrain = Terrain.DeepSea;
	public var isNavigable:Bool = true;
	public var walkable:Bool = false;
	public var steepness:Float = 0.5;
	public var islandId:Null<Int> = null;

	public function new(x:Int, y:Int) {
		this.x = x;
		this.y = y;
	}
}
