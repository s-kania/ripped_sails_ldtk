import { useState, useEffect, useRef, useCallback } from 'react';
import { SidebarControls } from './components/SidebarControls';
import { MapCanvas } from './components/MapCanvas';
import { MapParams } from './lib/types';
import { MapGenerator } from './lib/MapGenerator';
import { MapData } from './lib/MapData';

const DEFAULT_PARAMS: MapParams = {
    seed: 'GoldenAge',
    resolution: 256,
    clusters: 4,
    largeIslands: 2,
    medIslands: 8,
    smallIslands: 40,
    seaLevel: 0.55,
    coastIrregularity: 0.6,
    forestDensity: 0.5,
    mountainIntensity: 0.4,
    mountainSteepness: 0.5,
    beachWidth: 0.04,
    reefFreq: 0.5,
    enableStreams: true,
    showStreams: true,
    streamCount: 6,
    streamMeander: 0.45,
    streamTributaries: 1,
    streamSourceBias: 0.55,
    enableSettlements: true,
    enablePointsOfInterest: true,
    showSettlements: true,
    showPointsOfInterest: true,
    kmPerTile: 0.5,
    coastalLocationMinDistanceKm: 2.5,
    cityDensity: 0.7,
    poiDensity: 0.8,
    enableRoutes: true,
    showRoutes: true,
    routeMaxDistanceKm: 35,
    routeDensity: 0.65,
    routeHubBias: 0.6,
    routeMinConnections: 1,
    routeMaxConnections: 4,
    caribbeanness: 0.8,
    contNorth: 0.0,
    contSouth: 0.7,
    contEast: 0.0,
    contWest: 0.7,
    contNorthMountain: 0.4,
    contSouthMountain: 0.4,
    contEastMountain: 0.4,
    contWestMountain: 0.4,
    contNorthSteepness: 0.5,
    contSouthSteepness: 0.5,
    contEastSteepness: 0.5,
    contWestSteepness: 0.5,
    contNorthAttach: false,
    contSouthAttach: true,
    contEastAttach: false,
    contWestAttach: true,
    smoothTerrain: true,
    smoothTerrainStrength: 2,
    blurElevation: true,
    blurElevationStrength: 1,
    enableShadows: true,
    ditherShadows: true,
    shadowIntensity: 1.1,
    shadowAlpha: 0.4,
    lightAngleDeg: 315,
    saturation: 1.0,
    sepia: 0.0,
    vignette: 0.0,
    scanlines: 0.0,
    showClouds: true,
    showHeightMap: false,
    showCartographicLines: true,
    cloudDensity: 1.0,
    windSpeed: 1.0
};

const GENERATOR_PARAMS = new Set([
    'seed', 'resolution', 'clusters', 'largeIslands', 'medIslands', 'smallIslands',
    'seaLevel', 'coastIrregularity', 'forestDensity', 'mountainIntensity', 'mountainSteepness',
    'beachWidth', 'reefFreq', 'enableStreams', 'streamCount', 'streamMeander', 'streamTributaries', 'streamSourceBias',
    'enableSettlements', 'enablePointsOfInterest', 'kmPerTile', 'coastalLocationMinDistanceKm', 'cityDensity', 'poiDensity',
    'enableRoutes', 'routeMaxDistanceKm', 'routeDensity', 'routeHubBias', 'routeMinConnections', 'routeMaxConnections',
    'caribbeanness', 'contNorth', 'contSouth', 'contEast', 'contWest',
    'contNorthMountain', 'contSouthMountain', 'contEastMountain', 'contWestMountain',
    'contNorthSteepness', 'contSouthSteepness', 'contEastSteepness', 'contWestSteepness',
    'contNorthAttach', 'contSouthAttach', 'contEastAttach', 'contWestAttach',
    'smoothTerrain', 'smoothTerrainStrength', 'blurElevation', 'blurElevationStrength'
]);

const SAVED_SETTINGS_KEY = 'archipelago-generator-settings';

const loadSavedParams = (): MapParams => {
    try {
        const savedParams = localStorage.getItem(SAVED_SETTINGS_KEY);
        if (!savedParams) return DEFAULT_PARAMS;
        return { ...DEFAULT_PARAMS, ...JSON.parse(savedParams) };
    } catch {
        return DEFAULT_PARAMS;
    }
};

export default function App() {
    const [params, setParams] = useState<MapParams>(loadSavedParams);
    const [mapData, setMapData] = useState<MapData | null>(null);
    const [showLegend, setShowLegend] = useState(false);
    const [isMapFullscreen, setIsMapFullscreen] = useState(false);
    const [statusText, setStatusText] = useState("Ready");
    const [activeBorderHighlight, setActiveBorderHighlight] = useState<string | null>(null);
    const [activeIslandId, setActiveIslandId] = useState<number | null>(null);
    const [selectedIslandId, setSelectedIslandId] = useState<number | null>(null);
    const generateTimeoutRef = useRef<number | null>(null);
    const prevParamsRef = useRef<MapParams>(DEFAULT_PARAMS);

    const generateMap = useCallback((currentParams: MapParams = params) => {
        setTimeout(() => {
            const t0 = performance.now();
            const generator = new MapGenerator(currentParams);
            const map = generator.generate();

            setMapData(map);
            const t1 = performance.now();
            setStatusText(`Generated in ${Math.round(t1 - t0)}ms`);
        }, 10);
    }, [params]);

    useEffect(() => {
        generateMap(params);
    }, []);

    useEffect(() => {
        // Find which keys changed
        const changedKeys = Object.keys(params).filter(
            k => params[k as keyof MapParams] !== prevParamsRef.current[k as keyof MapParams]
        );

        const requiresGenerate = changedKeys.some(k => GENERATOR_PARAMS.has(k));

        if (requiresGenerate) {
            if (generateTimeoutRef.current) clearTimeout(generateTimeoutRef.current);
            setStatusText("Generating...");
            generateTimeoutRef.current = window.setTimeout(() => {
                generateMap(params);
            }, 150);
        }

        prevParamsRef.current = params;
    }, [params, generateMap]);

    const handleParamChange = (key: keyof MapParams, value: any) => {
        setParams(prev => ({ ...prev, [key]: value }));
    };

    const handleRandomizeSeed = () => {
        const words = ['PIRATE', 'SAIL', 'RUM', 'ISLAND', 'GOLD', 'CANNON', 'WIND', 'SKULL', 'BONE', 'TIDE', 'STORM', 'CURSE'];
        const r1 = words[Math.floor(Math.random() * words.length)];
        const r2 = words[Math.floor(Math.random() * words.length)];
        const num = Math.floor(Math.random() * 9999);
        handleParamChange('seed', `${r1}_${r2}_${num}`);
    };

    const handleReset = () => {
        localStorage.removeItem(SAVED_SETTINGS_KEY);
        setParams({ ...DEFAULT_PARAMS });
        setStatusText("Default settings restored");
    };

    const handleSaveSettings = () => {
        localStorage.setItem(SAVED_SETTINGS_KEY, JSON.stringify(params));
        setStatusText("Settings saved");
    };

    const exportPNG = () => {
        const canvas = document.getElementById('mapCanvas') as HTMLCanvasElement;
        if (!canvas) return;
        const link = document.createElement('a');
        link.download = `ripped_sails_${params.seed}.png`;
        link.href = canvas.toDataURL('image/png');
        link.click();
    };

    const exportJSON = () => {
        if (!mapData) return;

        const exportData = {
            width: mapData.width,
            height: mapData.height,
            params: mapData.params,
            streams: mapData.streams,
            islands: mapData.islands.map(island => ({
                id: island.id,
                name: island.name,
                bounds: island.bounds,
                center: island.center,
                areaKm2: Math.round(island.tiles.length * params.kmPerTile * params.kmPerTile * 100) / 100,
                cityCount: mapData.cities.filter(city => city.islandId === island.id).length,
                poiCount: mapData.pointsOfInterest.filter(poi => poi.islandId === island.id).length
            })),
            cities: mapData.cities,
            pointsOfInterest: mapData.pointsOfInterest,
            routes: mapData.routes,
            tiles: mapData.tiles.map(t => ({
                e: Math.round(t.elevation * 100) / 100,
                m: Math.round(t.moisture * 100) / 100,
                t: t.terrain,
                n: t.isNavigable ? 1 : 0,
                w: t.walkable ? 1 : 0,
                i: t.islandId
            }))
        };

        const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(exportData));
        const link = document.createElement('a');
        link.setAttribute("href", dataStr);
        link.setAttribute("download", `map_${params.seed}.json`);
        link.click();
    };

    const exportLocationsJSON = () => {
        if (!mapData) return;

        const exportData = {
            seed: params.seed,
            width: mapData.width,
            height: mapData.height,
            cities: mapData.cities.map(({ islandId, ...city }) => city),
            pointsOfInterest: mapData.pointsOfInterest.map(({ islandId, rarity, ...poi }) => poi)
        };

        const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(exportData, null, 2));
        const link = document.createElement('a');
        link.setAttribute("href", dataStr);
        link.setAttribute("download", `locations_${params.seed}.json`);
        link.click();
    };

    return (
        <div className="flex h-screen w-screen overflow-hidden">
            {!isMapFullscreen && (
                <SidebarControls
                    params={params}
                    onChange={handleParamChange}
                    onGenerate={generateMap}
                    onRandomizeSeed={handleRandomizeSeed}
                    onReset={handleReset}
                    onSaveSettings={handleSaveSettings}
                    onExportPNG={exportPNG}
                    onExportJSON={exportJSON}
                    onExportLocationsJSON={exportLocationsJSON}
                    showLegend={showLegend}
                    onToggleLegend={setShowLegend}
                    onHoverBorder={setActiveBorderHighlight}
                />
            )}
            <MapCanvas
                mapData={mapData}
                params={params}
                showLegend={showLegend}
                isFullscreen={isMapFullscreen}
                onFullscreenChange={setIsMapFullscreen}
                activeBorderHighlight={activeBorderHighlight}
                activeIslandId={activeIslandId}
                onHoverIsland={setActiveIslandId}
                selectedIslandId={selectedIslandId}
                onSelectIsland={setSelectedIslandId}
                statusText={statusText}
            />
        </div>
    );
}
