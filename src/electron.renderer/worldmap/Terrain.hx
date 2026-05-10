package worldmap;

enum abstract Terrain(Int) from Int to Int {
	var DeepSea = 0;
	var ShallowWater = 1;
	var Reef = 2;
	var Beach = 3;
	var Plains = 4;
	var Forest = 5;
	var Hills = 6;
	var Mountains = 7;
}
