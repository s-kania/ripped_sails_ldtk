package exporter;

class Walls extends Exporter {
	public function new() {
		super();
	}

	override function convert() {
		super.convert();

		setOutputPath( p.getAbsExternalFilesDir() + "/walls", true );

		for(w in p.worlds)
			for(l in w.levels) {
				// Generate sea walls (from pathfinding collision layers)
				l.generateCombinedCollisionLayer();
				var seaWalls:Array<Array<Int>> = [];
				if( l.collisionLayer != null ) {
					for(y in 0...l.collisionLayer.length) {
						var row = l.collisionLayer[y];
						for(x in 0...row.length)
							if( row[x] == 1 )
								seaWalls.push([x+1, y+1]);
					}
				}

				// Generate land walls (from landNonTraversable IntGrid values and rules)
				var landWallsGrid = l.generateLandWalls();
				var landWalls:Array<Array<Int>> = [];
				for(y in 0...landWallsGrid.length) {
					var row = landWallsGrid[y];
					for(x in 0...row.length)
						if( row[x] == 1 )
							landWalls.push([x+1, y+1]);
				}

				var fp = outputPath.clone();
				fp.fileName = l.identifier;
				fp.extension = "json";
				var json = dn.data.JsonPretty.stringify({ sea_walls:seaWalls, land_walls:landWalls }, Minified);
				addOuputFile(fp.full, haxe.io.Bytes.ofString(json));
			}
	}
}
