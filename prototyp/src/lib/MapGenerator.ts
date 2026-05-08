import { PRNG } from './PRNG';
import { Noise } from './Noise';
import { MapData } from './MapData';
import { TERRAIN, MapParams, StreamPath, TerrainType, IslandBorderSegment, Settlement, PointOfInterest, SettlementKind, PointOfInterestKind, LocationRef, TravelRoute, TravelRoutePoint } from './types';

type RouteLocationNode = {
    ref: LocationRef;
    x: number;
    y: number;
    islandId: number;
    hubScore: number;
    degree: number;
    anchor: TravelRoutePoint | null;
};

type RouteCandidate = {
    from: RouteLocationNode;
    to: RouteLocationNode;
    distanceTiles: number;
    distanceKm: number;
    cost: number;
};

type RouteSearchNode = {
    x: number;
    y: number;
    g: number;
    f: number;
};

// ============================================================================
// MODULE: MAP GENERATOR (The Core Logic)
// ============================================================================
export class MapGenerator {
    private static readonly MAX_ROUTED_RESOLUTION = 512;

    public params: MapParams;
    public prng: PRNG;
    public noise: Noise;
    public map: MapData;
    private waterComponentIds: Int32Array | null;

    constructor(params: MapParams) {
        this.params = params;
        this.prng = new PRNG(params.seed);
        this.noise = new Noise(this.prng);
        const w = params.resolution;
        const h = Math.round(w / 1.6180339887);
        this.map = new MapData(w, h, params);
        this.waterComponentIds = null;
    }

    generate(onProgress?: (msg: string) => void): MapData {
        if (onProgress) onProgress("Generating Island Seeds...");

        // 1. Setup base island centers/shapes (Radial basis masks)
        const islandCenters = this._distributeClusters();

        if (onProgress) onProgress("Applying FBM Noise & Coastlines...");

        // 2. Iterate map and calculate base terrain maps
        for (let y = 0; y < this.map.height; y++) {
            for (let x = 0; x < this.map.width; x++) {

                // Use resolution-independent frequencies
                const baseFreq = 256.0 / this.map.width; // Normalize to 256px equivalent

                // Reduce warping scale relative to resolution so it doesn't tear islands apart
                const warpScale = this.map.width * 0.04;
                const warpFreq = 0.02 * baseFreq;

                // Center the FBM output [-1, 1] so warping doesn't drift the whole map
                const warpX = (this.noise.fbm(x, y, 4, 0.5, 2.0, warpFreq) - 0.5) * 2.0 * warpScale;
                const warpY = (this.noise.fbm(x + 1000, y + 1000, 4, 0.5, 2.0, warpFreq) - 0.5) * 2.0 * warpScale;

                const wx = x + warpX;
                const wy = y + warpY;

                // Get base mask value based on distance to nearest islands
                let maskVal = this._getIslandMaskValue(wx, wy, islandCenters);

                let continentVal = this._getContinentalMask(wx, wy);
                maskVal = Math.max(maskVal, continentVal);

                // FBM base noise for the terrain
                const terrainFreq = 0.03 * baseFreq;
                let noiseVal = this.noise.fbm(wx, wy, 6, 0.5, 2.0, terrainFreq);

                // Combine mask and noise based on "coast irregularity"
                let irreg = this.params.coastIrregularity;

                // Shift noise to [-1, 1] for perturbation
                let centeredNoise = (noiseVal - 0.5) * 2.0;

                // Scale the noise amplitude so it primarily affects the coasts.
                // The envelope ensures we don't spawn noise-islands perfectly in the middle of mask = 0 (deep ocean).
                let noiseEnvelope = Math.min(maskVal * 3.0, 1.0);
                let noiseAmplitude = irreg * 0.5; // max half elevation shift

                let elevation = maskVal + (centeredNoise * noiseAmplitude * noiseEnvelope);

                // Enforce an outer deep sea boundary fade
                elevation *= this._getEdgeFalloff(x, y);

                // Shield against negative values, but don't cap at 1.0 
                // so we can find true mountain peaks later dynamically.
                const tile = this.map.getTile(x, y);
                if (tile) {
                    tile.elevation = Math.max(0, elevation);
                    // Secondary noise for forests / features
                    tile.moisture = this.noise.fbm(wx, wy, 4, 0.5, 2.0, 0.03 * baseFreq);
                }
            }
        }

        if (this.params.blurElevation) {
            if (onProgress) onProgress("Applying Elevation Blur...");
            this._applyElevationBlur();
        }

        if (onProgress) onProgress("Assigning Terrain & Biomes...");

        // 3. Classify biomes & terrain types based on ranges
        this._classifyTerrain();

        if (this.params.smoothTerrain) {
            if (onProgress) onProgress("Smoothing Terrain (Cellular Automata)...");
            this._smoothTerrainCellular();
        }

        this._detectIslands();

        this._generateSettlementsAndPointsOfInterest();

        if (this.params.enableRoutes && this.map.width <= MapGenerator.MAX_ROUTED_RESOLUTION) {
            this._generateRoutes();
        } else {
            if (this.params.enableRoutes && onProgress) onProgress(`Skipping sea routes above ${MapGenerator.MAX_ROUTED_RESOLUTION}px.`);
            this.map.routes = [];
        }

        if (this.params.enableStreams && this.params.streamCount > 0) {
            this._generateStreams();
        }

        if (onProgress) onProgress("Generation Complete.");
        return this.map;
    }

    private _applyElevationBlur() {
        const passes = this.params.blurElevationStrength || 1;

        for (let p = 0; p < passes; p++) {
            const newElevations = new Float32Array(this.map.width * this.map.height);
            const kernel = [
                1 / 16, 2 / 16, 1 / 16,
                2 / 16, 4 / 16, 2 / 16,
                1 / 16, 2 / 16, 1 / 16
            ];

            for (let y = 0; y < this.map.height; y++) {
                for (let x = 0; x < this.map.width; x++) {
                    let blurredElev = 0;
                    for (let ky = -1; ky <= 1; ky++) {
                        for (let kx = -1; kx <= 1; kx++) {
                            let nx = x + kx;
                            let ny = y + ky;
                            if (nx < 0) nx = 0; if (nx >= this.map.width) nx = this.map.width - 1;
                            if (ny < 0) ny = 0; if (ny >= this.map.height) ny = this.map.height - 1;

                            const neighbor = this.map.getTile(nx, ny);
                            const weight = kernel[(ky + 1) * 3 + (kx + 1)];
                            if (neighbor) {
                                blurredElev += neighbor.elevation * weight;
                            }
                        }
                    }
                    newElevations[y * this.map.width + x] = blurredElev;
                }
            }

            for (let i = 0; i < newElevations.length; i++) {
                this.map.tiles[i].elevation = newElevations[i];
            }
        }
    }

    private _smoothTerrainCellular() {
        const strength = this.params.smoothTerrainStrength || 2;
        const passes = Math.round(1 + (strength / 3)); // 1 to 4 passes
        const bias = Math.max(0, 4 - Math.floor(strength / 2.5)); // Drops from 4 to 0 based on strength

        for (let p = 0; p < passes; p++) {
            const newTerrains = new Uint8Array(this.map.width * this.map.height);

            for (let y = 0; y < this.map.height; y++) {
                for (let x = 0; x < this.map.width; x++) {
                    const tile = this.map.getTile(x, y);
                    if (!tile) continue;

                    // Don't modify water or beaches, but do keep their values
                    if (!tile.walkable || tile.terrain === TERRAIN.BEACH) {
                        newTerrains[y * this.map.width + x] = tile.terrain;
                        continue;
                    }

                    // Tally neighbors for land tiles
                    const counts: Record<number, number> = {};
                    counts[TERRAIN.PLAINS] = 0;
                    counts[TERRAIN.HILLS] = 0;
                    counts[TERRAIN.FOREST] = 0;
                    counts[TERRAIN.MOUNTAINS] = 0;

                    // Includes self to bias towards keeping current type slightly
                    for (let ky = -1; ky <= 1; ky++) {
                        for (let kx = -1; kx <= 1; kx++) {
                            const neighbor = this.map.getTile(x + kx, y + ky);
                            if (neighbor && neighbor.walkable && neighbor.terrain !== TERRAIN.BEACH) {
                                counts[neighbor.terrain] = (counts[neighbor.terrain] || 0) + 1;
                            }
                        }
                    }

                    // Give current terrain a bias to prevent runaway homogenization
                    counts[tile.terrain] += bias;

                    let maxType = tile.terrain;
                    let maxCount = 0;

                    for (let [type, count] of Object.entries(counts)) {
                        if (count > maxCount) {
                            maxCount = count;
                            maxType = parseInt(type) as any;
                        }
                    }

                    newTerrains[y * this.map.width + x] = maxType;
                }
            }

            // Apply back exactly what changed
            for (let y = 0; y < this.map.height; y++) {
                for (let x = 0; x < this.map.width; x++) {
                    const tile = this.map.getTile(x, y);
                    if (tile && tile.walkable && tile.terrain !== TERRAIN.BEACH) {
                        tile.terrain = newTerrains[y * this.map.width + x] as TerrainType;
                    }
                }
            }
        }
    }

    private _generateStreams() {
        this.map.streams = [];

        const sources = this._findStreamSources();
        const used = new Set<string>();
        const targetCount = Math.round(this.params.streamCount);
        let created = 0;

        for (let i = 0; i < sources.length && created < targetCount; i++) {
            const source = sources[i];
            const key = `${source.x},${source.y}`;

            if (used.has(key)) continue;
            used.add(key);

            const main = this._traceStream(source.x, source.y, 'main', null);

            if (main.points.length < Math.max(10, Math.floor(this.map.width * 0.04))) continue;
            if (!this._streamReachesWater(main)) continue;

            this.map.streams.push(main);
            this._addTributaries(main);
            this._addEstuary(main);
            created++;
        }
    }

    private _detectIslands() {
        this.map.islands = [];

        for (const tile of this.map.tiles) {
            tile.islandId = null;
        }

        const visited = new Uint8Array(this.map.width * this.map.height);
        let nextId = 1;

        for (let y = 0; y < this.map.height; y++) {
            for (let x = 0; x < this.map.width; x++) {
                const start = this.map.getTile(x, y);
                const startIndex = y * this.map.width + x;

                if (!start || !start.walkable || visited[startIndex]) continue;

                const id = nextId++;
                const queue = [{ x, y }];
                const tiles: { x: number; y: number }[] = [];
                let head = 0;
                let minX = x;
                let minY = y;
                let maxX = x;
                let maxY = y;
                let sumX = 0;
                let sumY = 0;

                visited[startIndex] = 1;
                start.islandId = id;

                while (head < queue.length) {
                    const current = queue[head++];
                    const tile = this.map.getTile(current.x, current.y);

                    if (!tile) continue;

                    tile.islandId = id;
                    tiles.push(current);
                    minX = Math.min(minX, current.x);
                    minY = Math.min(minY, current.y);
                    maxX = Math.max(maxX, current.x);
                    maxY = Math.max(maxY, current.y);
                    sumX += current.x;
                    sumY += current.y;

                    const neighbors = [
                        { x: current.x + 1, y: current.y },
                        { x: current.x - 1, y: current.y },
                        { x: current.x, y: current.y + 1 },
                        { x: current.x, y: current.y - 1 }
                    ];

                    for (const neighbor of neighbors) {
                        const neighborTile = this.map.getTile(neighbor.x, neighbor.y);
                        const neighborIndex = neighbor.y * this.map.width + neighbor.x;

                        if (!neighborTile || !neighborTile.walkable || visited[neighborIndex]) continue;

                        visited[neighborIndex] = 1;
                        neighborTile.islandId = id;
                        queue.push(neighbor);
                    }
                }

                this.map.islands.push({
                    id,
                    name: this._generateIslandName(id),
                    tiles,
                    bounds: { minX, minY, maxX, maxY },
                    center: {
                        x: sumX / tiles.length,
                        y: sumY / tiles.length
                    },
                    borderSegments: this._getIslandBorderSegments(tiles)
                });
            }
        }
    }

    private _getIslandBorderSegments(tiles: { x: number; y: number }[]): IslandBorderSegment[] {
        const segments: IslandBorderSegment[] = [];

        for (const tile of tiles) {
            if (!this.map.getTile(tile.x, tile.y - 1)?.walkable) {
                segments.push({ x1: tile.x, y1: tile.y, x2: tile.x + 1, y2: tile.y });
            }

            if (!this.map.getTile(tile.x + 1, tile.y)?.walkable) {
                segments.push({ x1: tile.x + 1, y1: tile.y, x2: tile.x + 1, y2: tile.y + 1 });
            }

            if (!this.map.getTile(tile.x, tile.y + 1)?.walkable) {
                segments.push({ x1: tile.x + 1, y1: tile.y + 1, x2: tile.x, y2: tile.y + 1 });
            }

            if (!this.map.getTile(tile.x - 1, tile.y)?.walkable) {
                segments.push({ x1: tile.x, y1: tile.y + 1, x2: tile.x, y2: tile.y });
            }
        }

        return segments;
    }

    private _generateIslandName(id: number): string {
        const rng = new PRNG(`${this.params.seed}:island:${id}`);
        const prefixes = ['Isla', 'Cayo', 'Port', 'Cape', 'Old', 'Saint', 'Skull', 'Black', 'Golden', 'Storm'];
        const roots = ['Dorada', 'Calavera', 'Marisol', 'Blackwater', 'Redwind', 'Saltmere', 'Tortuga', 'Moonfall', 'Crowsrest', 'Seabone', 'Amber', 'Drift'];
        const suffixes = ['Cay', 'Isle', 'Haven', 'Reach', 'Point', 'Harbor', 'Key', 'Rock'];

        if (rng.next() < 0.45) {
            return `${prefixes[rng.nextInt(0, prefixes.length - 1)]} ${roots[rng.nextInt(0, roots.length - 1)]}`;
        }

        return `${roots[rng.nextInt(0, roots.length - 1)]} ${suffixes[rng.nextInt(0, suffixes.length - 1)]}`;
    }

    private _generateSettlementsAndPointsOfInterest() {
        this.map.cities = [];
        this.map.pointsOfInterest = [];

        let nextSettlementId = 1;
        let nextPoiId = 1;
        const minIslandKm2ForCity = 3;
        const minIslandKm2ForPoi = 1;
        const maxCitiesPerKm2 = 0.08;
        const maxCitiesPerIsland = 5;
        const coastalBias = 0.75;
        const locationMinDistanceTiles = Math.max(1, Math.round(this.params.coastalLocationMinDistanceKm / this.params.kmPerTile));

        for (const island of this.map.islands) {
            const areaKm2 = this._getIslandAreaKm2(island.tiles.length);
            const coastalTiles = island.tiles
                .filter(tile => this._isCoastalLandTile(tile.x, tile.y))
                .sort((a, b) => this._getCoastalScore(b.x, b.y, coastalBias) - this._getCoastalScore(a.x, a.y, coastalBias));

            if (coastalTiles.length === 0) continue;

            const occupied: { x: number; y: number }[] = [];

            if (this.params.enableSettlements && areaKm2 >= minIslandKm2ForCity) {
                const areaLimit = Math.floor(areaKm2 * maxCitiesPerKm2 * this.params.cityDensity);
                const sizeBonus = areaKm2 >= minIslandKm2ForCity * 2 ? 1 : 0;
                const cityCount = Math.min(
                    maxCitiesPerIsland,
                    Math.max(0, areaLimit + sizeBonus)
                );

                for (let i = 0; i < cityCount; i++) {
                    const spot = this._pickCoastalLocation(coastalTiles, occupied, `${island.id}:city:${i}`, locationMinDistanceTiles, coastalBias);
                    if (!spot) continue;

                    const kind = this._getSettlementKind(i, cityCount, spot.x, spot.y);
                    const settlement: Settlement = {
                        id: nextSettlementId++,
                        name: this._generateSettlementName(nextSettlementId, kind),
                        x: spot.x,
                        y: spot.y,
                        islandId: island.id,
                        kind,
                        populationTier: Math.max(1, Math.min(5, Math.ceil(areaKm2 / 20) + (kind === 'capital' ? 1 : 0)))
                    };

                    this.map.cities.push(settlement);
                    occupied.push({ x: spot.x, y: spot.y });
                }
            }

            if (this.params.enablePointsOfInterest && areaKm2 >= minIslandKm2ForPoi) {
                const poiCount = Math.min(
                    Math.max(1, Math.ceil(areaKm2 * 0.035 * this.params.poiDensity)),
                    Math.max(1, Math.ceil(coastalTiles.length / 20))
                );

                for (let i = 0; i < poiCount; i++) {
                    const spot = this._pickCoastalLocation(coastalTiles, occupied, `${island.id}:poi:${i}`, locationMinDistanceTiles, coastalBias);
                    if (!spot) continue;

                    const kind = this._getPointOfInterestKind(island.id, i);
                    const poi: PointOfInterest = {
                        id: nextPoiId++,
                        name: this._generatePointOfInterestName(nextPoiId, kind),
                        x: spot.x,
                        y: spot.y,
                        islandId: island.id,
                        kind,
                        rarity: this._getPointOfInterestRarity(kind)
                    };

                    this.map.pointsOfInterest.push(poi);
                    occupied.push({ x: spot.x, y: spot.y });
                }
            }
        }
    }

    private _generateRoutes() {
        this.map.routes = [];

        const nodes = this._buildRouteNodes().filter(node => node.anchor);
        if (nodes.length < 2) {
            this.map.cities = [];
            this.map.pointsOfInterest = [];
            return;
        }

        const candidates = this._buildRouteCandidates(nodes);
        const connected = new Set<string>();
        const routeKeys = new Set<string>();
        let nextRouteId = 1;

        const sortedByHub = [...nodes].sort((a, b) => b.hubScore - a.hubScore);
        connected.add(this._getLocationKey(sortedByHub[0].ref));

        while (connected.size < nodes.length) {
            const candidate = candidates.find(item => {
                const fromConnected = connected.has(this._getLocationKey(item.from.ref));
                const toConnected = connected.has(this._getLocationKey(item.to.ref));
                return fromConnected !== toConnected && !routeKeys.has(this._getRouteKey(item.from.ref, item.to.ref));
            });

            if (!candidate) break;

            const route = this._createRouteFromCandidate(candidate, nextRouteId, 'regional');
            routeKeys.add(this._getRouteKey(candidate.from.ref, candidate.to.ref));

            if (!route) continue;

            this.map.routes.push(route);
            nextRouteId++;
            candidate.from.degree++;
            candidate.to.degree++;
            connected.add(this._getLocationKey(candidate.from.ref));
            connected.add(this._getLocationKey(candidate.to.ref));
        }

        nextRouteId = this._repairRouteDegrees(nodes, candidates, routeKeys, nextRouteId);
        nextRouteId = this._addExtraRoutes(nodes, candidates, routeKeys, nextRouteId);

        this._pruneUnconnectedLocations();
    }

    private _buildRouteNodes(): RouteLocationNode[] {
        const cityNodes: RouteLocationNode[] = this.map.cities.map(city => ({
            ref: { type: 'city', id: city.id },
            x: city.x,
            y: city.y,
            islandId: city.islandId,
            hubScore: this._getLocationHubScore({ type: 'city', id: city.id }),
            degree: 0,
            anchor: this._findNearestWaterAnchor(city.x, city.y)
        }));

        const poiNodes: RouteLocationNode[] = this.map.pointsOfInterest.map(point => ({
            ref: { type: 'poi', id: point.id },
            x: point.x,
            y: point.y,
            islandId: point.islandId,
            hubScore: this._getLocationHubScore({ type: 'poi', id: point.id }),
            degree: 0,
            anchor: this._findNearestWaterAnchor(point.x, point.y)
        }));

        return [...cityNodes, ...poiNodes];
    }

    private _getLocationHubScore(ref: LocationRef): number {
        if (ref.type === 'city') {
            const city = this.map.cities.find(item => item.id === ref.id);
            if (!city) return 0;
            if (city.kind === 'capital') return 1;
            if (city.kind === 'port') return 0.85;
            if (city.kind === 'fort') return 0.55;
            return 0.4;
        }

        const point = this.map.pointsOfInterest.find(item => item.id === ref.id);
        if (!point) return 0;
        if (point.kind === 'pirateHaven') return 0.85;
        if (point.kind === 'blackCove') return 0.75;
        if (point.kind === 'ancientRuins' || point.kind === 'treasureSite') return 0.65;
        return 0.35;
    }

    private _findNearestWaterAnchor(x: number, y: number): TravelRoutePoint | null {
        for (let radius = 1; radius <= 5; radius++) {
            const candidates: TravelRoutePoint[] = [];

            for (let oy = -radius; oy <= radius; oy++) {
                for (let ox = -radius; ox <= radius; ox++) {
                    if (Math.max(Math.abs(ox), Math.abs(oy)) !== radius) continue;

                    const tile = this.map.getTile(x + ox, y + oy);
                    if (tile && !tile.walkable && tile.isNavigable) {
                        candidates.push({ x: tile.x, y: tile.y });
                    }
                }
            }

            if (candidates.length > 0) {
                return candidates.sort((a, b) => this._distance(x, y, a.x, a.y) - this._distance(x, y, b.x, b.y))[0];
            }
        }

        return null;
    }

    private _buildRouteCandidates(nodes: RouteLocationNode[]): RouteCandidate[] {
        const candidates: RouteCandidate[] = [];
        const maxDistanceTiles = Math.max(1, this.params.routeMaxDistanceKm / this.params.kmPerTile);
        const relaxedDistanceTiles = maxDistanceTiles * 1.75;

        for (let i = 0; i < nodes.length; i++) {
            for (let j = i + 1; j < nodes.length; j++) {
                const from = nodes[i];
                const to = nodes[j];
                const distanceTiles = this._distance(from.x, from.y, to.x, to.y);

                if (distanceTiles > relaxedDistanceTiles && from.hubScore < 0.75 && to.hubScore < 0.75) continue;

                const distanceKm = distanceTiles * this.params.kmPerTile;
                const rng = new PRNG(`${this.params.seed}:route-candidate:${this._getRouteKey(from.ref, to.ref)}`);
                const hubBonus = (from.hubScore + to.hubScore) * this.params.routeHubBias * maxDistanceTiles * 0.18;
                const sameIslandPenalty = from.islandId === to.islandId ? maxDistanceTiles * 0.08 : 0;
                const longPenalty = distanceTiles > maxDistanceTiles ? (distanceTiles - maxDistanceTiles) * 1.8 : 0;
                const jitter = rng.next() * maxDistanceTiles * 0.08;

                candidates.push({
                    from,
                    to,
                    distanceTiles,
                    distanceKm,
                    cost: distanceTiles + sameIslandPenalty + longPenalty - hubBonus + jitter
                });
            }
        }

        return candidates.sort((a, b) => a.cost - b.cost);
    }

    private _repairRouteDegrees(nodes: RouteLocationNode[], candidates: RouteCandidate[], routeKeys: Set<string>, nextRouteId: number): number {
        const minConnections = Math.max(1, Math.round(this.params.routeMinConnections));

        for (const node of nodes) {
            while (node.degree < minConnections) {
                const candidate = candidates.find(item => {
                    const touchesNode = item.from === node || item.to === node;
                    if (!touchesNode) return false;
                    if (routeKeys.has(this._getRouteKey(item.from.ref, item.to.ref))) return false;

                    const other = item.from === node ? item.to : item.from;
                    return other.degree < Math.max(this.params.routeMaxConnections + 1, minConnections);
                });

                if (!candidate) break;

                const route = this._createRouteFromCandidate(candidate, nextRouteId, 'repair');
                routeKeys.add(this._getRouteKey(candidate.from.ref, candidate.to.ref));

                if (!route) continue;

                this.map.routes.push(route);
                nextRouteId++;
                candidate.from.degree++;
                candidate.to.degree++;
            }
        }

        return nextRouteId;
    }

    private _addExtraRoutes(nodes: RouteLocationNode[], candidates: RouteCandidate[], routeKeys: Set<string>, nextRouteId: number): number {
        const targetExtraRoutes = Math.round(nodes.length * Math.max(0, this.params.routeDensity));
        let added = 0;

        for (const candidate of candidates) {
            if (added >= targetExtraRoutes) break;
            if (routeKeys.has(this._getRouteKey(candidate.from.ref, candidate.to.ref))) continue;

            const fromLimit = candidate.from.hubScore >= 0.75 ? this.params.routeMaxConnections + 2 : this.params.routeMaxConnections;
            const toLimit = candidate.to.hubScore >= 0.75 ? this.params.routeMaxConnections + 2 : this.params.routeMaxConnections;
            if (candidate.from.degree >= fromLimit || candidate.to.degree >= toLimit) continue;

            const routeKind: TravelRoute['kind'] = candidate.from.hubScore >= 0.75 || candidate.to.hubScore >= 0.75 ? 'hub' : candidate.from.islandId === candidate.to.islandId ? 'local' : 'regional';
            const route = this._createRouteFromCandidate(candidate, nextRouteId, routeKind);
            routeKeys.add(this._getRouteKey(candidate.from.ref, candidate.to.ref));

            if (!route) continue;

            this.map.routes.push(route);
            nextRouteId++;
            added++;
            candidate.from.degree++;
            candidate.to.degree++;
        }

        return nextRouteId;
    }

    private _createRouteFromCandidate(candidate: RouteCandidate, id: number, kind: TravelRoute['kind']): TravelRoute | null {
        if (!candidate.from.anchor || !candidate.to.anchor) return null;

        const points = this._findWaterPath(candidate.from.anchor, candidate.to.anchor, candidate.distanceTiles);
        if (!points) return null;

        return {
            id,
            from: candidate.from.ref,
            to: candidate.to.ref,
            distanceKm: Math.round(points.length * this.params.kmPerTile * 100) / 100,
            kind,
            points: this._simplifyRoutePoints(points)
        };
    }

    private _findWaterPath(start: TravelRoutePoint, goal: TravelRoutePoint, directDistanceTiles: number): TravelRoutePoint[] | null {
        if (this._getWaterComponentId(start.x, start.y) !== this._getWaterComponentId(goal.x, goal.y)) return null;
        const startIndex = start.y * this.map.width + start.x;
        const goalIndex = goal.y * this.map.width + goal.x;
        const open: RouteSearchNode[] = [];
        this._pushOpenNode(open, { x: start.x, y: start.y, g: 0, f: this._distance(start.x, start.y, goal.x, goal.y) });
        const cameFrom = new Map<number, number>();
        const gScore = new Map<number, number>([[startIndex, 0]]);
        const closed = new Set<number>();
        const margin = Math.max(12, Math.ceil(directDistanceTiles * 0.35));
        const minX = Math.max(0, Math.min(start.x, goal.x) - margin);
        const maxX = Math.min(this.map.width - 1, Math.max(start.x, goal.x) + margin);
        const minY = Math.max(0, Math.min(start.y, goal.y) - margin);
        const maxY = Math.min(this.map.height - 1, Math.max(start.y, goal.y) + margin);
        const visitLimit = Math.min(this.map.width * this.map.height, Math.max(800, Math.ceil(directDistanceTiles * directDistanceTiles * 3)));
        let visits = 0;

        while (open.length > 0 && visits < visitLimit) {
            const current = this._popOpenNode(open)!;
            const currentIndex = current.y * this.map.width + current.x;

            if (closed.has(currentIndex)) continue;
            if (currentIndex === goalIndex) return this._reconstructWaterPath(cameFrom, currentIndex);

            closed.add(currentIndex);
            visits++;

            for (let oy = -1; oy <= 1; oy++) {
                for (let ox = -1; ox <= 1; ox++) {
                    if (ox === 0 && oy === 0) continue;

                    const nx = current.x + ox;
                    const ny = current.y + oy;
                    if (nx < minX || nx > maxX || ny < minY || ny > maxY) continue;

                    const tile = this.map.getTile(nx, ny);
                    if (!tile || tile.walkable || !tile.isNavigable) continue;

                    const neighborIndex = ny * this.map.width + nx;
                    if (closed.has(neighborIndex)) continue;

                    const stepCost = ox !== 0 && oy !== 0 ? 1.414 : 1;
                    const reefPenalty = tile.terrain === TERRAIN.REEF ? 0.35 : 0;
                    const shorePenalty = this._isNearLand(nx, ny) ? 0.08 : 0;
                    const tentativeG = current.g + stepCost + reefPenalty + shorePenalty;

                    if (tentativeG >= (gScore.get(neighborIndex) ?? Infinity)) continue;

                    cameFrom.set(neighborIndex, currentIndex);
                    gScore.set(neighborIndex, tentativeG);
                    this._pushOpenNode(open, {
                        x: nx,
                        y: ny,
                        g: tentativeG,
                        f: tentativeG + this._distance(nx, ny, goal.x, goal.y)
                    });
                }
            }
        }

        return null;
    }

    private _getWaterComponentId(x: number, y: number): number {
        if (!this.waterComponentIds) this._buildWaterComponents();
        return this.waterComponentIds![y * this.map.width + x];
    }

    private _buildWaterComponents() {
        const ids = new Int32Array(this.map.width * this.map.height);
        ids.fill(-1);
        let nextId = 0;

        for (let y = 0; y < this.map.height; y++) {
            for (let x = 0; x < this.map.width; x++) {
                const idx = y * this.map.width + x;
                if (ids[idx] >= 0) continue;
                const start = this.map.getTile(x, y);
                if (!start || start.walkable || !start.isNavigable) continue;

                const queue: { x: number; y: number }[] = [{ x, y }];
                let head = 0;
                ids[idx] = nextId;

                while (head < queue.length) {
                    const current = queue[head++];
                    for (let oy = -1; oy <= 1; oy++) {
                        for (let ox = -1; ox <= 1; ox++) {
                            if (ox === 0 && oy === 0) continue;
                            const nx = current.x + ox;
                            const ny = current.y + oy;
                            if (nx < 0 || nx >= this.map.width || ny < 0 || ny >= this.map.height) continue;
                            const ni = ny * this.map.width + nx;
                            if (ids[ni] >= 0) continue;
                            const tile = this.map.getTile(nx, ny);
                            if (!tile || tile.walkable || !tile.isNavigable) continue;
                            ids[ni] = nextId;
                            queue.push({ x: nx, y: ny });
                        }
                    }
                }

                nextId++;
            }
        }

        this.waterComponentIds = ids;
    }

    private _pushOpenNode(open: RouteSearchNode[], node: RouteSearchNode) {
        open.push(node);
        let i = open.length - 1;
        while (i > 0) {
            const parent = Math.floor((i - 1) / 2);
            if (!this._routeNodeLess(open[i], open[parent])) break;
            const tmp = open[i];
            open[i] = open[parent];
            open[parent] = tmp;
            i = parent;
        }
    }

    private _popOpenNode(open: RouteSearchNode[]): RouteSearchNode | null {
        if (open.length === 0) return null;
        const first = open[0];
        const last = open.pop();
        if (open.length > 0 && last) {
            open[0] = last;
            let i = 0;
            while (true) {
                const left = i * 2 + 1;
                if (left >= open.length) break;
                const right = left + 1;
                let best = left;
                if (right < open.length && this._routeNodeLess(open[right], open[left])) best = right;
                if (!this._routeNodeLess(open[best], open[i])) break;
                const tmp = open[i];
                open[i] = open[best];
                open[best] = tmp;
                i = best;
            }
        }
        return first;
    }

    private _routeNodeLess(a: RouteSearchNode, b: RouteSearchNode): boolean {
        return a.f < b.f || (a.f === b.f && a.g > b.g);
    }

    private _reconstructWaterPath(cameFrom: Map<number, number>, currentIndex: number): TravelRoutePoint[] {
        const points: TravelRoutePoint[] = [];
        let key: number | undefined = currentIndex;

        while (key !== undefined) {
            points.push({ x: key % this.map.width, y: Math.floor(key / this.map.width) });
            key = cameFrom.get(key);
        }

        return points.reverse();
    }

    private _simplifyRoutePoints(points: TravelRoutePoint[]): TravelRoutePoint[] {
        if (points.length <= 2) return points;

        const simplified: TravelRoutePoint[] = [points[0]];
        let prevDx = 0;
        let prevDy = 0;

        for (let i = 1; i < points.length - 1; i++) {
            const prev = points[i - 1];
            const current = points[i];
            const next = points[i + 1];
            const dx = Math.sign(next.x - prev.x);
            const dy = Math.sign(next.y - prev.y);
            const directionChanged = i > 1 && (dx !== prevDx || dy !== prevDy);

            if (directionChanged || i % 5 === 0) {
                simplified.push(current);
            }

            prevDx = dx;
            prevDy = dy;
        }

        simplified.push(points[points.length - 1]);
        return simplified;
    }

    private _pruneUnconnectedLocations() {
        const connected = new Set<string>();

        for (const route of this.map.routes) {
            connected.add(this._getLocationKey(route.from));
            connected.add(this._getLocationKey(route.to));
        }

        this.map.cities = this.map.cities.filter(city => connected.has(this._getLocationKey({ type: 'city', id: city.id })));
        this.map.pointsOfInterest = this.map.pointsOfInterest.filter(point => connected.has(this._getLocationKey({ type: 'poi', id: point.id })));

        const valid = new Set<string>([
            ...this.map.cities.map(city => this._getLocationKey({ type: 'city', id: city.id })),
            ...this.map.pointsOfInterest.map(point => this._getLocationKey({ type: 'poi', id: point.id }))
        ]);

        this.map.routes = this.map.routes.filter(route => valid.has(this._getLocationKey(route.from)) && valid.has(this._getLocationKey(route.to)));
    }

    private _isNearLand(x: number, y: number): boolean {
        for (let oy = -1; oy <= 1; oy++) {
            for (let ox = -1; ox <= 1; ox++) {
                if (ox === 0 && oy === 0) continue;
                if (this.map.getTile(x + ox, y + oy)?.walkable) return true;
            }
        }

        return false;
    }

    private _getLocationKey(ref: LocationRef): string {
        return `${ref.type}:${ref.id}`;
    }

    private _getRouteKey(a: LocationRef, b: LocationRef): string {
        const keyA = this._getLocationKey(a);
        const keyB = this._getLocationKey(b);
        return keyA < keyB ? `${keyA}|${keyB}` : `${keyB}|${keyA}`;
    }

    private _getIslandAreaKm2(tileCount: number): number {
        return tileCount * this.params.kmPerTile * this.params.kmPerTile;
    }

    private _isCoastalLandTile(x: number, y: number): boolean {
        const tile = this.map.getTile(x, y);
        if (!tile?.walkable) return false;

        for (let oy = -1; oy <= 1; oy++) {
            for (let ox = -1; ox <= 1; ox++) {
                if (ox === 0 && oy === 0) continue;
                const neighbor = this.map.getTile(x + ox, y + oy);
                if (neighbor && !neighbor.walkable) return true;
            }
        }

        return false;
    }

    private _getCoastalScore(x: number, y: number, coastalBias: number): number {
        const tile = this.map.getTile(x, y);
        if (!tile) return 0;

        let waterNeighbors = 0;
        let score = tile.terrain === TERRAIN.BEACH ? 2.5 : 1;

        for (let oy = -1; oy <= 1; oy++) {
            for (let ox = -1; ox <= 1; ox++) {
                if (ox === 0 && oy === 0) continue;
                const neighbor = this.map.getTile(x + ox, y + oy);
                if (neighbor && !neighbor.walkable) waterNeighbors++;
            }
        }

        score += waterNeighbors * (0.5 + coastalBias);
        score += this.noise.fbm(x + 211, y + 419, 2, 0.5, 2.0, 0.08);

        return score;
    }

    private _pickCoastalLocation(tiles: { x: number; y: number }[], occupied: { x: number; y: number }[], salt: string, minDistance: number, coastalBias: number): { x: number; y: number } | null {
        const rng = new PRNG(`${this.params.seed}:coastal:${salt}`);
        const candidates = tiles
            .map(tile => ({
                ...tile,
                score: this._getCoastalScore(tile.x, tile.y, coastalBias) + rng.next() * 0.75
            }))
            .sort((a, b) => b.score - a.score);

        for (const candidate of candidates) {
            if (!this._isCoastalLandTile(candidate.x, candidate.y)) continue;
            if (occupied.some(item => this._distance(item.x, item.y, candidate.x, candidate.y) < minDistance)) continue;
            return { x: candidate.x, y: candidate.y };
        }

        return null;
    }

    private _distance(x1: number, y1: number, x2: number, y2: number): number {
        const dx = x1 - x2;
        const dy = y1 - y2;
        return Math.sqrt(dx * dx + dy * dy);
    }

    private _getSettlementKind(index: number, total: number, x: number, y: number): SettlementKind {
        if (index === 0 && total >= 3) return 'capital';
        if (this.map.getTile(x, y)?.terrain === TERRAIN.BEACH) return 'port';
        return index % 4 === 0 ? 'fort' : 'town';
    }

    private _getPointOfInterestKind(islandId: number, index: number): PointOfInterestKind {
        const rng = new PRNG(`${this.params.seed}:poi-kind:${islandId}:${index}`);
        const kinds: PointOfInterestKind[] = ['blackCove', 'treasureSite', 'pirateHaven', 'lostMission', 'smugglerCamp', 'ancientRuins'];
        return kinds[rng.nextInt(0, kinds.length - 1)];
    }

    private _getPointOfInterestRarity(kind: PointOfInterestKind): number {
        if (kind === 'treasureSite' || kind === 'ancientRuins') return 3;
        if (kind === 'blackCove' || kind === 'pirateHaven') return 2;
        return 1;
    }

    private _generateSettlementName(id: number, kind: SettlementKind): string {
        const rng = new PRNG(`${this.params.seed}:settlement:${id}`);
        const prefixes = ['Port', 'Fort', 'San', 'Santa', 'New', 'Old', 'Puerto', 'Cape'];
        const roots = ['Royal', 'Marisol', 'Esperanza', 'Blackwater', 'Dorada', 'Tortuga', 'Verde', 'Cannon', 'Mercy', 'Crown'];

        if (kind === 'fort') return `Fort ${roots[rng.nextInt(0, roots.length - 1)]}`;
        if (kind === 'port' || kind === 'capital') return `Port ${roots[rng.nextInt(0, roots.length - 1)]}`;

        return `${prefixes[rng.nextInt(0, prefixes.length - 1)]} ${roots[rng.nextInt(0, roots.length - 1)]}`;
    }

    private _generatePointOfInterestName(id: number, kind: PointOfInterestKind): string {
        const rng = new PRNG(`${this.params.seed}:poi-name:${id}`);
        const names: Record<PointOfInterestKind, string[]> = {
            blackCove: ['Black Cove', 'Dead Man Cove', 'Nocturne Cove'],
            treasureSite: ['Buried Gold', 'Captain’s Cache', 'Lost Treasure'],
            pirateHaven: ['Pirate Haven', 'Corsair Anchorage', 'Freebooter Camp'],
            lostMission: ['Lost Mission', 'Abandoned Chapel', 'Saint’s Ruin'],
            smugglerCamp: ['Smuggler Camp', 'Hidden Landing', 'Rumrunner Shore'],
            ancientRuins: ['Ancient Ruins', 'Sunken Shrine', 'Old Idol']
        };

        const variants = names[kind];
        return variants[rng.nextInt(0, variants.length - 1)];
    }

    private _findStreamSources() {
        const mountainSources = this.map.tiles
            .filter(tile => {
                if (!tile.walkable) return false;
                if (tile.terrain !== TERRAIN.MOUNTAINS && tile.terrain !== TERRAIN.HILLS) return false;
                return tile.elevation > this.params.seaLevel + this.params.beachWidth + 0.08;
            })
            .map(tile => {
                const edgeBias = this._getContinentalSourceBias(tile.x, tile.y);
                const noiseBias = this.noise.fbm(tile.x + 73, tile.y + 91, 2, 0.5, 2.0, 0.05) * 0.08;
                return { x: tile.x, y: tile.y, score: tile.elevation + edgeBias + noiseBias };
            });

        const edgeSources = this._findEdgeStreamSources();

        return [...mountainSources, ...edgeSources].sort((a, b) => b.score - a.score);
    }

    private _findEdgeStreamSources() {
        const sources: { x: number; y: number; score: number }[] = [];
        const step = Math.max(6, Math.floor(this.map.width / 32));

        const addIfLand = (x: number, y: number, score: number) => {
            const tile = this.map.getTile(x, y);
            if (!tile || !tile.walkable) return;
            if (tile.terrain !== TERRAIN.MOUNTAINS && tile.terrain !== TERRAIN.HILLS) return;
            sources.push({ x, y, score: score + tile.elevation });
        };

        if (this.params.contNorth > 0) {
            for (let x = step; x < this.map.width - step; x += step) addIfLand(x, 1, this.params.contNorth * this.params.contNorthMountain * this.params.streamSourceBias);
        }

        if (this.params.contSouth > 0) {
            for (let x = step; x < this.map.width - step; x += step) addIfLand(x, this.map.height - 2, this.params.contSouth * this.params.contSouthMountain * this.params.streamSourceBias);
        }

        if (this.params.contWest > 0) {
            for (let y = step; y < this.map.height - step; y += step) addIfLand(1, y, this.params.contWest * this.params.contWestMountain * this.params.streamSourceBias);
        }

        if (this.params.contEast > 0) {
            for (let y = step; y < this.map.height - step; y += step) addIfLand(this.map.width - 2, y, this.params.contEast * this.params.contEastMountain * this.params.streamSourceBias);
        }

        return sources;
    }

    private _getContinentalSourceBias(x: number, y: number) {
        const w = this.map.width;
        const h = this.map.height;
        const edgeW = w * 0.18;
        const edgeH = h * 0.18;
        let bias = 0;

        if (this.params.contWest > 0) bias = Math.max(bias, Math.max(0, 1 - x / edgeW) * this.params.contWest * this.params.contWestMountain);
        if (this.params.contEast > 0) bias = Math.max(bias, Math.max(0, 1 - (w - x) / edgeW) * this.params.contEast * this.params.contEastMountain);
        if (this.params.contNorth > 0) bias = Math.max(bias, Math.max(0, 1 - y / edgeH) * this.params.contNorth * this.params.contNorthMountain);
        if (this.params.contSouth > 0) bias = Math.max(bias, Math.max(0, 1 - (h - y) / edgeH) * this.params.contSouth * this.params.contSouthMountain);

        return bias * this.params.streamSourceBias;
    }

    private _traceStream(startX: number, startY: number, kind: StreamPath['kind'], target: Set<string> | null): StreamPath {
        const points: { x: number; y: number; width: number; flow?: number }[] = [];
        const visited = new Set<string>();
        const maxLength = Math.floor((this.map.width + this.map.height) * 1.4);
        let x = startX;
        let y = startY;
        let dirX = 0;
        let dirY = 1;
        let uphillSteps = 0;

        for (let step = 0; step < maxLength; step++) {
            const tile = this.map.getTile(x, y);
            if (!tile) break;

            const key = `${x},${y}`;
            if (visited.has(key)) break;

            visited.add(key);
            points.push({ x, y, width: step > maxLength * 0.72 && kind !== 'tributary' ? 2 : 1, flow: Math.min(1, step / maxLength) });

            if (target?.has(key)) break;
            if (step > 2 && this._touchesWater(x, y)) break;

            let best: { x: number; y: number; score: number; elevation: number } | null = null;
            const lowland = Math.max(0, 1 - ((tile.elevation - this.params.seaLevel) / 0.35));

            for (let oy = -1; oy <= 1; oy++) {
                for (let ox = -1; ox <= 1; ox++) {
                    if (ox === 0 && oy === 0) continue;

                    const nx = x + ox;
                    const ny = y + oy;
                    const neighbor = this.map.getTile(nx, ny);

                    if (!neighbor) continue;
                    if (visited.has(`${nx},${ny}`)) continue;
                    if (!neighbor.walkable && !this._touchesLand(nx, ny)) continue;

                    const downhill = tile.elevation - neighbor.elevation;
                    const continuation = ((ox * dirX) + (oy * dirY)) * 0.018;
                    const diagonalPenalty = ox !== 0 && oy !== 0 ? 0.012 : 0;
                    const meanderNoise = (this.noise.fbm(nx + startX * 11, ny + startY * 13, 2, 0.5, 2.0, 0.12) - 0.5) * this.params.streamMeander * (0.03 + lowland * 0.08);
                    const waterPull = this._touchesWater(nx, ny) ? 0.18 + lowland * 0.25 : 0;
                    const targetPull = target?.has(`${nx},${ny}`) ? 0.5 : 0;
                    const score = downhill + continuation + meanderNoise + waterPull + targetPull - diagonalPenalty;

                    if (!best || score > best.score) {
                        best = { x: nx, y: ny, score, elevation: neighbor.elevation };
                    }
                }
            }

            if (!best) break;

            if (best.elevation > tile.elevation + 0.01) {
                uphillSteps++;
            } else {
                uphillSteps = 0;
            }

            if (uphillSteps > 3) break;

            dirX = Math.max(-1, Math.min(1, best.x - x));
            dirY = Math.max(-1, Math.min(1, best.y - y));
            x = best.x;
            y = best.y;
        }

        return { points, kind };
    }

    private _streamReachesWater(stream: StreamPath) {
        const end = stream.points[stream.points.length - 1];
        return !!end && this._touchesWater(end.x, end.y);
    }

    private _addTributaries(main: StreamPath) {
        const count = Math.round(this.params.streamTributaries);
        if (count <= 0 || main.points.length < 18) return;

        const target = new Set(main.points.map(point => `${point.x},${point.y}`));

        for (let i = 0; i < count; i++) {
            const joinIndex = this.prng.nextInt(Math.floor(main.points.length * 0.35), Math.max(Math.floor(main.points.length * 0.85), Math.floor(main.points.length * 0.35)));
            const join = main.points[joinIndex];
            const source = this._findTributarySource(join.x, join.y);

            if (!source) continue;

            const tributary = this._traceStream(source.x, source.y, 'tributary', target);

            if (tributary.points.length >= 6 && tributary.points.length <= main.points.length * 0.7) {
                this.map.streams.push(tributary);
            }
        }
    }

    private _findTributarySource(joinX: number, joinY: number) {
        let best: { x: number; y: number; score: number } | null = null;
        const radius = Math.max(10, Math.floor(this.map.width * 0.08));
        const joinTile = this.map.getTile(joinX, joinY);

        if (!joinTile) return null;

        for (let y = joinY - radius; y <= joinY + radius; y += 2) {
            for (let x = joinX - radius; x <= joinX + radius; x += 2) {
                const tile = this.map.getTile(x, y);

                if (!tile || !tile.walkable) continue;
                if (tile.elevation <= joinTile.elevation + 0.04) continue;

                const dx = x - joinX;
                const dy = y - joinY;
                const dist = Math.sqrt(dx * dx + dy * dy);

                if (dist < 6 || dist > radius) continue;

                const score = tile.elevation - dist / radius * 0.2 + this.noise.fbm(x, y, 2, 0.5, 2.0, 0.08) * 0.08;

                if (!best || score > best.score) {
                    best = { x, y, score };
                }
            }
        }

        return best;
    }

    private _addEstuary(main: StreamPath) {
        const end = main.points[main.points.length - 1];
        if (!end || !this._touchesWater(end.x, end.y)) return;

        const branches: StreamPath[] = [];

        for (let i = 0; i < 2; i++) {
            const points = [{ x: end.x, y: end.y, width: 2 }];
            let x = end.x;
            let y = end.y;

            for (let step = 0; step < 4; step++) {
                const next = this._findEstuaryStep(x, y, i === 0 ? -1 : 1);
                if (!next) break;
                x = next.x;
                y = next.y;
                points.push({ x, y, width: 1 });
                if (!this.map.getTile(x, y)?.walkable) break;
            }

            if (points.length > 1) branches.push({ points, kind: 'estuary' });
        }

        this.map.streams.push(...branches);
    }

    private _findEstuaryStep(x: number, y: number, sideBias: number) {
        let best: { x: number; y: number; score: number } | null = null;

        for (let oy = -1; oy <= 1; oy++) {
            for (let ox = -1; ox <= 1; ox++) {
                if (ox === 0 && oy === 0) continue;

                const nx = x + ox;
                const ny = y + oy;
                const tile = this.map.getTile(nx, ny);

                if (!tile) continue;

                const score = (tile.walkable ? 0 : 1) + (ox * sideBias * 0.08) - tile.elevation * 0.1;

                if (!best || score > best.score) {
                    best = { x: nx, y: ny, score };
                }
            }
        }

        return best;
    }

    private _touchesWater(x: number, y: number) {
        for (let oy = -1; oy <= 1; oy++) {
            for (let ox = -1; ox <= 1; ox++) {
                const tile = this.map.getTile(x + ox, y + oy);
                if (tile && !tile.walkable) return true;
            }
        }

        return false;
    }

    private _touchesLand(x: number, y: number) {
        for (let oy = -1; oy <= 1; oy++) {
            for (let ox = -1; ox <= 1; ox++) {
                const tile = this.map.getTile(x + ox, y + oy);
                if (tile && tile.walkable) return true;
            }
        }

        return false;
    }

    private _distributeClusters() {
        const centers: any[] = [];
        const resX = this.map.width;
        const resY = this.map.height;

        let clustersX: number[] = [];
        let clustersY: number[] = [];

        // Create cluster focal points (Archipelagos)
        for (let i = 0; i < this.params.clusters; i++) {
            // Caribbean arc placement logic
            let cx, cy;
            if (this.prng.next() < this.params.caribbeanness) {
                // Place on an arc / curve
                const t = this.prng.next(); // 0 to 1
                cx = resX * 0.1 + (t * resX * 0.8);
                // Parabolic arc roughly peaking in the middle
                cy = resY * 0.2 + Math.sin(t * Math.PI) * resY * 0.6;

                // Add some variance
                cx += (this.prng.next() - 0.5) * resX * 0.2;
                cy += (this.prng.next() - 0.5) * resY * 0.2;
            } else {
                // Pure random scattered placement
                cx = resX * 0.2 + this.prng.next() * resX * 0.6;
                cy = resY * 0.2 + this.prng.next() * resY * 0.6;
            }
            clustersX.push(cx);
            clustersY.push(cy);
        }

        // Helper to add islands around a random cluster
        const addIsland = (sizeGroup: string, count: number) => {
            for (let i = 0; i < count; i++) {
                const clusIdx = this.prng.nextInt(0, this.params.clusters - 1);
                const radiusScatter = sizeGroup === 'big' ? resX * 0.1 : (sizeGroup === 'med' ? resX * 0.2 : resX * 0.3);

                const ix = clustersX[clusIdx] + (this.prng.next() - 0.5) * radiusScatter;
                const iy = clustersY[clusIdx] + (this.prng.next() - 0.5) * radiusScatter;

                // Radii proportional to resolution
                let ir;
                if (sizeGroup === 'big') ir = resX * this.prng.next() * 0.15 + (resX * 0.1);
                else if (sizeGroup === 'med') ir = resX * 0.05 + this.prng.next() * resX * 0.05;
                else ir = resX * 0.01 + this.prng.next() * resX * 0.03;

                centers.push({ x: ix, y: iy, r: ir, type: sizeGroup });
            }
        };

        addIsland('big', this.params.largeIslands);
        addIsland('med', this.params.medIslands);
        addIsland('small', this.params.smallIslands);

        return centers;
    }

    private _getIslandMaskValue(x: number, y: number, centers: any[]) {
        let maxInfluence = 0.0;
        for (let c of centers) {
            const dx = c.x - x;
            const dy = c.y - y;
            const distSq = dx * dx + dy * dy;

            // Allow overlapping influence
            const influenceRadius = c.r * 1.5;
            const rSq = influenceRadius * influenceRadius;

            if (distSq < rSq) {
                const distance = Math.sqrt(distSq);
                // Smoothstep blending for natural curve
                const t = Math.max(0, 1.0 - (distance / influenceRadius));
                const influence = t * t * (3 - 2 * t);
                maxInfluence = Math.max(maxInfluence, influence);
            }
        }
        return maxInfluence;
    }

    private _getEdgeFalloff(x: number, y: number) {
        // Determine normalized coordinates from edges [0, 1]
        const nx = x / this.map.width;
        const ny = y / this.map.height;

        // Margins (e.g. 15% falloff area)
        const margin = 0.15;

        let falloffX = 1.0;
        let falloffY = 1.0;

        if (!this.params.contWestAttach && nx < margin) {
            falloffX = nx / margin;
        } else if (!this.params.contEastAttach && nx > 1.0 - margin) {
            falloffX = (1.0 - nx) / margin;
        }

        if (!this.params.contNorthAttach && ny < margin) {
            falloffY = ny / margin;
        } else if (!this.params.contSouthAttach && ny > 1.0 - margin) {
            falloffY = (1.0 - ny) / margin;
        }

        // Use a smoothstep-like curve to soften the falloff
        const smooth = (t: number) => t * t * (3 - 2 * t);

        return smooth(falloffX) * smooth(falloffY);
    }

    private _getContinentalMask(x: number, y: number) {
        const w = this.map.width;
        const h = this.map.height;
        let finalVal = 0;

        const smoothstep = (t: number) => {
            t = Math.max(0, Math.min(1, t));
            return t * t * (3 - 2 * t);
        };

        // Create a non-linear falloff (smoothstep) for solid coastlines
        const edgeWidth = w * 0.18;
        const edgeHeight = h * 0.18;

        if (this.params.contWest > 0) {
            let val = 1.0 - (x / edgeWidth);
            finalVal = Math.max(finalVal, smoothstep(val) * this.params.contWest * 1.5);
        }
        if (this.params.contEast > 0) {
            let val = 1.0 - ((w - x) / edgeWidth);
            finalVal = Math.max(finalVal, smoothstep(val) * this.params.contEast * 1.5);
        }
        if (this.params.contNorth > 0) {
            let val = 1.0 - (y / edgeHeight);
            finalVal = Math.max(finalVal, smoothstep(val) * this.params.contNorth * 1.5);
        }
        if (this.params.contSouth > 0) {
            let val = 1.0 - ((h - y) / edgeHeight);
            finalVal = Math.max(finalVal, smoothstep(val) * this.params.contSouth * 1.5);
        }

        return finalVal;
    }

    private _getMountainParams(x: number, y: number) {
        const w = this.map.width;
        const h = this.map.height;

        const smoothstep = (t: number) => {
            t = Math.max(0, Math.min(1, t));
            return t * t * (3 - 2 * t);
        };

        const edgeWidth = w * 0.18;
        const edgeHeight = h * 0.18;

        let wWest = this.params.contWest > 0 ? smoothstep(1.0 - (x / edgeWidth)) * this.params.contWest * 1.5 : 0;
        let wEast = this.params.contEast > 0 ? smoothstep(1.0 - ((w - x) / edgeWidth)) * this.params.contEast * 1.5 : 0;
        let wNorth = this.params.contNorth > 0 ? smoothstep(1.0 - (y / edgeHeight)) * this.params.contNorth * 1.5 : 0;
        let wSouth = this.params.contSouth > 0 ? smoothstep(1.0 - ((h - y) / edgeHeight)) * this.params.contSouth * 1.5 : 0;

        let maxC = Math.max(wWest, wEast, wNorth, wSouth);

        let localIntensity = this.params.mountainIntensity;
        let localSteepness = this.params.mountainSteepness;

        if (maxC > 0) {
            let cWeight = Math.min(1.0, maxC * 1.5);

            let highestContIntensity = this.params.mountainIntensity;
            let highestContSteepness = this.params.mountainSteepness;

            if (maxC === wWest) { highestContIntensity = this.params.contWestMountain; highestContSteepness = this.params.contWestSteepness; }
            else if (maxC === wEast) { highestContIntensity = this.params.contEastMountain; highestContSteepness = this.params.contEastSteepness; }
            else if (maxC === wNorth) { highestContIntensity = this.params.contNorthMountain; highestContSteepness = this.params.contNorthSteepness; }
            else if (maxC === wSouth) { highestContIntensity = this.params.contSouthMountain; highestContSteepness = this.params.contSouthSteepness; }

            localIntensity = (1.0 - cWeight) * this.params.mountainIntensity + cWeight * highestContIntensity;
            localSteepness = (1.0 - cWeight) * this.params.mountainSteepness + cWeight * highestContSteepness;
        }

        return { intensity: localIntensity, steepness: localSteepness };
    }

    private _classifyTerrain() {
        const seaLvl = this.params.seaLevel;
        const bw = this.params.beachWidth;

        let maxElevOld = 0;
        for (let tile of this.map.tiles) {
            if (tile.elevation > maxElevOld) maxElevOld = tile.elevation;
        }
        const landPeakOld = Math.max(maxElevOld, seaLvl + bw + 0.1);
        const landRangeOld = landPeakOld - (seaLvl + bw);

        for (let tile of this.map.tiles) {
            let mountainParams = this._getMountainParams(tile.x, tile.y);
            tile.steepness = mountainParams.steepness;

            let e = tile.elevation;
            if (e > seaLvl + bw) {
                let norm = (e - (seaLvl + bw)) / landRangeOld;

                if (mountainParams.steepness > 0.01 && norm > 0.05) {
                    let xx = tile.x * 0.4;
                    let yy = tile.y * 0.4;
                    let crag = (Math.sin(xx) * Math.cos(yy) + Math.sin(xx * 2.1 + yy * 1.7) * 0.5);

                    let peakPush = Math.pow(norm, 1.3) * mountainParams.steepness * 0.7;
                    let jagged = crag * 0.15 * mountainParams.steepness * norm;

                    tile.elevation += peakPush + jagged;
                }
            }
        }

        let maxElev = 0;
        for (let tile of this.map.tiles) {
            if (tile.elevation > maxElev) maxElev = tile.elevation;
        }

        const landPeak = Math.max(maxElev, seaLvl + bw + 0.1);
        const landRange = landPeak - (seaLvl + bw);

        for (let tile of this.map.tiles) {
            const e = tile.elevation;

            let mountainParams = this._getMountainParams(tile.x, tile.y);

            const mtnT = 0.97 - (mountainParams.intensity * 0.97);
            const hillsT = 0.60 - (mountainParams.intensity * 0.60);

            const mtnThreshold = seaLvl + bw + (landRange * mtnT);
            const hillsThreshold = seaLvl + bw + (landRange * hillsT);

            if (e < seaLvl) {
                tile.walkable = false;
                tile.isNavigable = true;

                if (e < seaLvl - 0.15) {
                    tile.terrain = TERRAIN.DEEP_SEA;
                } else {
                    tile.terrain = TERRAIN.SHALLOW_WATER;

                    if (this.params.reefFreq > 0 && e > seaLvl - 0.08) {
                        const reefNoise = this.noise.fbm(tile.x * 5, tile.y * 5, 2, 0.5, 2.0, 0.1);
                        if (reefNoise < this.params.reefFreq * 0.7) {
                            tile.terrain = TERRAIN.REEF;
                            tile.isNavigable = false;
                        }
                    }
                }
            }
            else {
                tile.walkable = true;
                tile.isNavigable = false;

                if (e < seaLvl + bw) {
                    tile.terrain = TERRAIN.BEACH;
                } else if (e > mtnThreshold) {
                    tile.terrain = TERRAIN.MOUNTAINS;
                } else if (e > hillsThreshold) {
                    tile.terrain = TERRAIN.HILLS;

                    if (tile.moisture < this.params.forestDensity) {
                        tile.terrain = TERRAIN.FOREST;
                    }
                } else {
                    tile.terrain = TERRAIN.PLAINS;

                    if (tile.moisture < this.params.forestDensity * 1.2) {
                        tile.terrain = TERRAIN.FOREST;
                    }
                }
            }
        }
    }
}
