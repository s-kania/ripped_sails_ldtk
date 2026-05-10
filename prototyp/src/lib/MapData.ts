import { TERRAIN, TerrainType, MapParams, StreamPath, IslandRegion, Settlement, PointOfInterest, TravelRoute } from './types';

// ============================================================================
// MODULE: TILE DATA & MAP STATE
// ============================================================================
export class Tile {
    public x: number;
    public y: number;
    public elevation: number;
    public moisture: number;
    public terrain: TerrainType;
    public isNavigable: boolean;
    public walkable: boolean;
    public steepness?: number;
    public islandId: number | null;

    constructor(x: number, y: number) {
        this.x = x;
        this.y = y;
        this.elevation = 0.0;
        this.moisture = 0.0;
        this.terrain = TERRAIN.DEEP_SEA;
        this.isNavigable = true;
        this.walkable = false;
        this.islandId = null;
    }
}

export class MapData {
    public width: number;
    public height: number;
    public params: MapParams;
    public tiles: Tile[];
    public cities: Settlement[];
    public routes: TravelRoute[];
    public streams: StreamPath[];
    public islands: IslandRegion[];
    public pointsOfInterest: PointOfInterest[];

    constructor(width: number, height: number, params: MapParams) {
        this.width = width;
        this.height = height;
        this.params = params; // store generation params for JSON export
        this.tiles = Array.from({ length: width * height }, (_, i) => {
            return new Tile(i % width, Math.floor(i / width));
        });
        this.cities = []; // Placeholder for expansion
        this.routes = []; // Trade / sailing routes
        this.streams = [];
        this.islands = [];
        this.pointsOfInterest = [];
    }

    getTile(x: number, y: number): Tile | null {
        if (x < 0 || x >= this.width || y < 0 || y >= this.height) return null;
        return this.tiles[y * this.width + x];
    }
}
