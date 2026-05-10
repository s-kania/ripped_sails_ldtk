export const TERRAIN = {
    DEEP_SEA: 0,
    SHALLOW_WATER: 1,
    REEF: 2,
    BEACH: 3,
    PLAINS: 4,
    FOREST: 5,
    HILLS: 6,
    MOUNTAINS: 7
} as const;

export type TerrainType = typeof TERRAIN[keyof typeof TERRAIN];

export interface StreamPoint {
    x: number;
    y: number;
    width: number;
    flow?: number;
}

export interface StreamPath {
    points: StreamPoint[];
    kind: 'main' | 'tributary' | 'estuary';
}

export interface IslandBorderSegment {
    x1: number;
    y1: number;
    x2: number;
    y2: number;
}

export interface IslandRegion {
    id: number;
    name: string;
    tiles: { x: number; y: number }[];
    bounds: { minX: number; minY: number; maxX: number; maxY: number };
    center: { x: number; y: number };
    borderSegments: IslandBorderSegment[];
}

export type SettlementKind = 'town' | 'port' | 'fort' | 'capital';
export type PointOfInterestKind = 'blackCove' | 'treasureSite' | 'pirateHaven' | 'lostMission' | 'smugglerCamp' | 'ancientRuins';

export interface Settlement {
    id: number;
    name: string;
    x: number;
    y: number;
    islandId: number;
    kind: SettlementKind;
    populationTier: number;
}

export interface PointOfInterest {
    id: number;
    name: string;
    x: number;
    y: number;
    islandId: number;
    kind: PointOfInterestKind;
    rarity: number;
}

export type LocationRef = {
    type: 'city' | 'poi';
    id: number;
};

export interface TravelRoutePoint {
    x: number;
    y: number;
}

export interface TravelRoute {
    id: number;
    from: LocationRef;
    to: LocationRef;
    distanceKm: number;
    kind: 'local' | 'regional' | 'hub' | 'repair';
    points: TravelRoutePoint[];
}

export interface MapParams {
    seed: string;
    resolution: number;
    clusters: number;
    largeIslands: number;
    medIslands: number;
    smallIslands: number;
    seaLevel: number;
    coastIrregularity: number;
    forestDensity: number;
    mountainIntensity: number;
    mountainSteepness: number;
    beachWidth: number;
    reefFreq: number;
    enableStreams: boolean;
    showStreams: boolean;
    streamCount: number;
    streamMeander: number;
    streamTributaries: number;
    streamSourceBias: number;
    enableSettlements: boolean;
    enablePointsOfInterest: boolean;
    showSettlements: boolean;
    showPointsOfInterest: boolean;
    kmPerTile: number;
    coastalLocationMinDistanceKm: number;
    cityDensity: number;
    poiDensity: number;
    enableRoutes: boolean;
    showRoutes: boolean;
    routeMaxDistanceKm: number;
    routeDensity: number;
    routeHubBias: number;
    routeMinConnections: number;
    routeMaxConnections: number;
    caribbeanness: number;
    contNorth: number;
    contSouth: number;
    contEast: number;
    contWest: number;
    contNorthMountain: number;
    contSouthMountain: number;
    contEastMountain: number;
    contWestMountain: number;
    contNorthSteepness: number;
    contSouthSteepness: number;
    contEastSteepness: number;
    contWestSteepness: number;
    contNorthAttach: boolean;
    contSouthAttach: boolean;
    contEastAttach: boolean;
    contWestAttach: boolean;
    smoothTerrain: boolean;
    smoothTerrainStrength: number;
    blurElevation: boolean;
    blurElevationStrength: number;
    // Post Processing & Rendering
    enableShadows: boolean;
    ditherShadows: boolean;
    shadowIntensity: number;
    shadowAlpha: number;
    lightAngleDeg: number;
    saturation: number;
    sepia: number;
    vignette: number;
    scanlines: number;
    showClouds: boolean;
    showHeightMap: boolean;
    showCartographicLines: boolean;
    cloudDensity: number;
    windSpeed: number;
}
