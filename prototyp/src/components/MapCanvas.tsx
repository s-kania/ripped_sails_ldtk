import { useEffect, useRef, useState, type MouseEvent } from 'react';
import { MapData } from '../lib/MapData';
import { Renderer } from '../lib/Renderer';
import { MapParams } from '../lib/types';
import { MapLegend } from './MapLegend';

type HoveredLocation = { type: 'city' | 'poi'; id: number } | null;

interface MapCanvasProps {
    mapData: MapData | null;
    params: MapParams;
    showLegend: boolean;
    isFullscreen: boolean;
    onFullscreenChange: (val: boolean) => void;
    activeBorderHighlight: string | null;
    activeIslandId: number | null;
    onHoverIsland: (id: number | null) => void;
    selectedIslandId: number | null;
    onSelectIsland: (id: number | null) => void;
    statusText: string;
}

export function MapCanvas({ mapData, params, showLegend, isFullscreen, onFullscreenChange, activeBorderHighlight, activeIslandId, onHoverIsland, selectedIslandId, onSelectIsland, statusText }: MapCanvasProps) {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const containerRef = useRef<HTMLDivElement>(null);
    const rendererRef = useRef<Renderer | null>(null);
    const prevParams = useRef<MapParams>(params);
    const prevMapData = useRef<MapData | null>(null);
    const [hoveredLocation, setHoveredLocation] = useState<HoveredLocation>(null);

    useEffect(() => {
        if (canvasRef.current && !rendererRef.current) {
            rendererRef.current = new Renderer(canvasRef.current);
        }

        if (rendererRef.current) {
            rendererRef.current.activeBorderHighlight = activeBorderHighlight;
            rendererRef.current.activeIslandId = activeIslandId;
            rendererRef.current.selectedIslandId = selectedIslandId;
            rendererRef.current.activeLocation = hoveredLocation;

            const mapDataChanged = mapData !== prevMapData.current;

            const changedKeys = Object.keys(params).filter(
                k => params[k as keyof MapParams] !== prevParams.current[k as keyof MapParams]
            );

            const requiresRender = mapDataChanged || changedKeys.some(k => [
                'enableShadows', 'ditherShadows', 'shadowIntensity', 'shadowAlpha',
                'lightAngleDeg', 'showHeightMap', 'showCartographicLines', 'showStreams', 'showRoutes'
            ].includes(k));

            if (requiresRender && mapData) {
                // Generates base image data and restarts animation
                rendererRef.current.render(mapData, params);

                // Resize logic
                if (containerRef.current) {
                    const frame = containerRef.current.querySelector('#viewportFrame') as HTMLElement;
                    if (frame) {
                        let availW = containerRef.current.clientWidth - (isFullscreen ? 0 : 48);
                        let availH = containerRef.current.clientHeight - (isFullscreen ? 0 : 48);

                        const mapRatio = mapData.width / mapData.height;
                        const availRatio = availW / availH;

                        if (mapRatio > availRatio) {
                            frame.style.width = availW + 'px';
                            frame.style.height = (availW / mapRatio) + 'px';
                        } else {
                            frame.style.height = availH + 'px';
                            frame.style.width = (availH * mapRatio) + 'px';
                        }
                    }
                }
            } else if (!mapDataChanged && rendererRef.current.mapData) {
                // Post-processing only parameters changed
                rendererRef.current.updateParams(params);
            }

            prevParams.current = params;
            prevMapData.current = mapData;
        }
    }, [mapData, params, activeBorderHighlight, activeIslandId, selectedIslandId, hoveredLocation, isFullscreen]);

    const getMapPointFromMouseEvent = (e: MouseEvent<HTMLCanvasElement>): { x: number; y: number } | null => {
        if (!mapData || !canvasRef.current) return null;

        const rect = canvasRef.current.getBoundingClientRect();
        const x = Math.floor(((e.clientX - rect.left) / rect.width) * mapData.width);
        const y = Math.floor(((e.clientY - rect.top) / rect.height) * mapData.height);
        return { x, y };
    };

    const getIslandIdFromMouseEvent = (e: MouseEvent<HTMLCanvasElement>): number | null => {
        if (!mapData) return null;

        const point = getMapPointFromMouseEvent(e);
        if (!point) return null;

        const tile = mapData.getTile(point.x, point.y);

        return tile?.islandId ?? null;
    };

    const getLocationFromMouseEvent = (e: MouseEvent<HTMLCanvasElement>): HoveredLocation => {
        if (!mapData) return null;

        const point = getMapPointFromMouseEvent(e);
        if (!point) return null;

        const maxDistanceSq = 25;
        let nearest: HoveredLocation = null;
        let nearestDistanceSq = maxDistanceSq;

        if (params.showSettlements) {
            for (const city of mapData.cities) {
                const dx = city.x + 0.5 - point.x;
                const dy = city.y + 0.5 - point.y;
                const distanceSq = dx * dx + dy * dy;

                if (distanceSq <= nearestDistanceSq) {
                    nearest = { type: 'city', id: city.id };
                    nearestDistanceSq = distanceSq;
                }
            }
        }

        if (params.showPointsOfInterest) {
            for (const pointOfInterest of mapData.pointsOfInterest) {
                const dx = pointOfInterest.x + 0.5 - point.x;
                const dy = pointOfInterest.y + 0.5 - point.y;
                const distanceSq = dx * dx + dy * dy;

                if (distanceSq <= nearestDistanceSq) {
                    nearest = { type: 'poi', id: pointOfInterest.id };
                    nearestDistanceSq = distanceSq;
                }
            }
        }

        return nearest;
    };

    const handleMouseMove = (e: MouseEvent<HTMLCanvasElement>) => {
        const location = getLocationFromMouseEvent(e);
        setHoveredLocation(location);
        onHoverIsland(location ? null : getIslandIdFromMouseEvent(e));
    };

    const handleClick = (e: MouseEvent<HTMLCanvasElement>) => {
        onSelectIsland(getIslandIdFromMouseEvent(e));
    };

    useEffect(() => {
        const handleFullscreenChange = () => {
            onFullscreenChange(document.fullscreenElement === containerRef.current);
        };

        document.addEventListener('fullscreenchange', handleFullscreenChange);
        return () => document.removeEventListener('fullscreenchange', handleFullscreenChange);
    }, [onFullscreenChange]);

    const handleToggleFullscreen = async () => {
        if (!document.fullscreenElement) {
            await containerRef.current?.requestFullscreen();
        } else {
            await document.exitFullscreen();
        }
    };
    // Handle window resize
    useEffect(() => {
        const handleResize = () => {
            if (mapData && containerRef.current) {
                const frame = containerRef.current.querySelector('#viewportFrame') as HTMLElement;
                if (frame) {
                    let availW = containerRef.current.clientWidth - (isFullscreen ? 0 : 48);
                    let availH = containerRef.current.clientHeight - (isFullscreen ? 0 : 48);

                    const mapRatio = mapData.width / mapData.height;
                    const availRatio = availW / availH;

                    if (mapRatio > availRatio) {
                        frame.style.width = availW + 'px';
                        frame.style.height = (availW / mapRatio) + 'px';
                    } else {
                        frame.style.height = availH + 'px';
                        frame.style.width = (availH * mapRatio) + 'px';
                    }
                }
            }
        };

        window.addEventListener('resize', handleResize);
        return () => window.removeEventListener('resize', handleResize);
    }, [mapData, isFullscreen]);

    return (
        <div ref={containerRef} id="canvasParent" className={`flex-1 relative bg-slate-950 ${isFullscreen ? 'p-0' : 'p-6'} flex flex-col items-center justify-center overflow-hidden min-w-0 min-h-0`}>
            <button
                className="absolute top-4 right-4 z-20 bg-black/60 px-3 py-1.5 text-[10px] uppercase tracking-widest border border-white/10 rounded font-mono text-yellow-500 hover:bg-yellow-900/30"
                onClick={handleToggleFullscreen}
            >
                {isFullscreen ? 'Exit Full Map' : 'Full Map'}
            </button>

            <div id="viewportFrame" className="viewport-frame relative bg-[var(--bg-ocean-deep)] overflow-hidden rounded-sm transition-all duration-300">
                <canvas ref={canvasRef} id="mapCanvas" className="w-full h-full block" style={{ imageRendering: 'pixelated' }} onMouseMove={handleMouseMove} onMouseLeave={() => { setHoveredLocation(null); onHoverIsland(null); }} onClick={handleClick}></canvas>
                <div className="absolute inset-0 pointer-events-none shadow-[inset_0_0_40px_rgba(5,49,95,0.8)]"></div>
            </div>

            <MapLegend visible={showLegend} />

            {mapData && selectedIslandId !== null && (() => {
                const island = mapData.islands.find(item => item.id === selectedIslandId);
                if (!island) return null;

                const cities = mapData.cities.filter(city => city.islandId === island.id);
                const pointsOfInterest = mapData.pointsOfInterest.filter(point => point.islandId === island.id);
                const areaKm2 = island.tiles.length * params.kmPerTile * params.kmPerTile;

                return (
                    <div className="absolute top-4 left-1/2 -translate-x-1/2 z-20 bg-black/75 px-4 py-3 text-[11px] border border-yellow-700/50 rounded font-mono text-yellow-100 shadow-xl min-w-[260px] pointer-events-none">
                        <div className="text-sm text-yellow-500 font-serif mb-1">{island.name}</div>
                        <div className="grid grid-cols-3 gap-3 text-slate-300">
                            <span>Pow.: <strong className="text-yellow-200">{areaKm2.toFixed(2)} km²</strong></span>
                            <span>Miasta: <strong className="text-yellow-200">{cities.length}</strong></span>
                            <span>POI: <strong className="text-yellow-200">{pointsOfInterest.length}</strong></span>
                        </div>
                    </div>
                );
            })()}

            <div className="absolute bottom-4 left-4 bg-black/60 px-3 py-1.5 text-[10px] uppercase tracking-widest border border-white/10 rounded font-mono text-yellow-500">
                {statusText}
            </div>
        </div>
    );
}
