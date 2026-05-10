import type { ChangeEvent } from 'react';
import { MapParams } from '../lib/types';

interface SidebarControlsProps {
    params: MapParams;
    onChange: (key: keyof MapParams, value: any) => void;
    onGenerate: () => void;
    onRandomizeSeed: () => void;
    onReset: () => void;
    onSaveSettings: () => void;
    onExportPNG: () => void;
    onExportJSON: () => void;
    onExportLocationsJSON: () => void;
    showLegend: boolean;
    onToggleLegend: (val: boolean) => void;
    onHoverBorder: (border: string | null) => void;
}

export function SidebarControls({
    params,
    onChange,
    onGenerate,
    onRandomizeSeed,
    onReset,
    onSaveSettings,
    onExportPNG,
    onExportJSON,
    onExportLocationsJSON,
    showLegend,
    onToggleLegend,
    onHoverBorder
}: SidebarControlsProps) {

    const handleChange = (e: ChangeEvent<HTMLInputElement>) => {
        const key = e.target.id.replace('p_', '') as keyof MapParams;
        let val: any;

        if (e.target.type === 'checkbox') {
            val = e.target.checked;
        } else if (e.target.type === 'range') {
            val = parseFloat(e.target.value);
        } else {
            val = e.target.value;
        }

        onChange(key, val);
    };

    return (
        <div className="w-[340px] glass-panel p-5 flex flex-col gap-4 overflow-y-auto shrink-0 z-10">
            <div className="border-b border-yellow-900/50 pb-2 mb-2">
                <h1 className="text-xl text-center">Archipelago Generator</h1>
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Seed <span className="text-[10px] text-yellow-500">{params.seed}</span></label>
                <input type="text" id="p_seed" value={params.seed} onChange={handleChange} className="bg-slate-900 border border-slate-700 p-1.5 rounded text-xs w-full text-yellow-500 font-mono" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Map Resolution <span className="text-[10px] text-yellow-500">{params.resolution} x {Math.round(params.resolution / 1.6180339887)}</span></label>
                <input type="range" id="p_resolution" min="128" max="1536" step="32" value={params.resolution} onChange={handleChange} className="w-full custom-range" />
                <span className="tooltip">Width (height is locked to Golden Ratio)</span>
            </div>

            <div className="h-px w-full bg-yellow-900/40 my-2"></div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Clusters (Archipelagos) <span className="text-[10px] text-yellow-500">{params.clusters}</span></label>
                <input type="range" id="p_clusters" min="1" max="10" step="1" value={params.clusters} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Large Landmasses <span className="text-[10px] text-yellow-500">{params.largeIslands}</span></label>
                <input type="range" id="p_largeIslands" min="0" max="4" step="1" value={params.largeIslands} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Medium Islands <span className="text-[10px] text-yellow-500">{params.medIslands}</span></label>
                <input type="range" id="p_medIslands" min="0" max="15" step="1" value={params.medIslands} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Small Islands <span className="text-[10px] text-yellow-500">{params.smallIslands}</span></label>
                <input type="range" id="p_smallIslands" min="10" max="100" step="1" value={params.smallIslands} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="h-px w-full bg-yellow-900/40 my-2"></div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Sea Level <span className="text-[10px] text-yellow-500">{params.seaLevel.toFixed(2)}</span></label>
                <input type="range" id="p_seaLevel" min="0.1" max="0.9" step="0.05" value={params.seaLevel} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Coast Irregularity <span className="text-[10px] text-yellow-500">{params.coastIrregularity.toFixed(2)}</span></label>
                <input type="range" id="p_coastIrregularity" min="0" max="1" step="0.05" value={params.coastIrregularity} onChange={handleChange} className="w-full custom-range" />
                <span className="tooltip">FBM noise weight against island bases</span>
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Forest Density <span className="text-[10px] text-yellow-500">{params.forestDensity.toFixed(2)}</span></label>
                <input type="range" id="p_forestDensity" min="0" max="1" step="0.05" value={params.forestDensity} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Mountain Coverage <span className="text-[10px] text-yellow-500">{params.mountainIntensity.toFixed(2)}</span></label>
                <input type="range" id="p_mountainIntensity" min="0" max="1" step="0.05" value={params.mountainIntensity} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Mountain Steepness <span className="text-[10px] text-yellow-500">{params.mountainSteepness.toFixed(2)}</span></label>
                <input type="range" id="p_mountainSteepness" min="0" max="1" step="0.05" value={params.mountainSteepness} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Beach Width <span className="text-[10px] text-yellow-500">{params.beachWidth.toFixed(2)}</span></label>
                <input type="range" id="p_beachWidth" min="0" max="0.2" step="0.01" value={params.beachWidth} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Reef & Shallows Freq. <span className="text-[10px] text-yellow-500">{params.reefFreq.toFixed(2)}</span></label>
                <input type="range" id="p_reefFreq" min="0" max="1" step="0.05" value={params.reefFreq} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="h-px w-full bg-yellow-900/40 my-2"></div>
            <div className="text-sm font-bold text-yellow-600 font-serif mb-2">Strumyki</div>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Generate stream sources and rivers on the map">
                <input type="checkbox" id="p_enableStreams" checked={params.enableStreams} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Generuj źródełka i rzeczki
            </label>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Liczba strumyków <span className="text-[10px] text-yellow-500">{params.streamCount}</span></label>
                <input type="range" id="p_streamCount" min="0" max="16" step="1" value={params.streamCount} onChange={handleChange} className="w-full custom-range" />
                <span className="tooltip">Mniej: mapa prawie sucha. Więcej: więcej źródeł z gór i krawędzi kontynentów.</span>
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Krętość strumyków <span className="text-[10px] text-yellow-500">{params.streamMeander.toFixed(2)}</span></label>
                <input type="range" id="p_streamMeander" min="0" max="1" step="0.05" value={params.streamMeander} onChange={handleChange} className="w-full custom-range" />
                <span className="tooltip">Mniej: prostszy spływ w dół. Więcej: mocniejsze meandry i boczne odchylenia.</span>
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Dopływy <span className="text-[10px] text-yellow-500">{params.streamTributaries}</span></label>
                <input type="range" id="p_streamTributaries" min="0" max="3" step="1" value={params.streamTributaries} onChange={handleChange} className="w-full custom-range" />
                <span className="tooltip">Mniej: pojedyncze nitki. Więcej: krótkie boczne strumyki wpadające do głównego nurtu.</span>
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Źródła przy krawędzi <span className="text-[10px] text-yellow-500">{params.streamSourceBias.toFixed(2)}</span></label>
                <input type="range" id="p_streamSourceBias" min="0" max="1" step="0.05" value={params.streamSourceBias} onChange={handleChange} className="w-full custom-range" />
                <span className="tooltip">Mniej: źródła głównie z gór w środku lądu. Więcej: częściej z gór przy krawędziach kontynentów.</span>
            </div>

            <div className="h-px w-full bg-yellow-900/40 my-3"></div>
            <div className="text-sm font-bold text-yellow-600 font-serif mb-2">Miasta i punkty zainteresowania</div>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Generate coastal towns and ports">
                <input type="checkbox" id="p_enableSettlements" checked={params.enableSettlements} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Generuj miasta przy wybrzeżach
            </label>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Generate coastal points of interest">
                <input type="checkbox" id="p_enablePointsOfInterest" checked={params.enablePointsOfInterest} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Generuj punkty zainteresowania przy wybrzeżach
            </label>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Show city markers">
                <input type="checkbox" id="p_showSettlements" checked={params.showSettlements} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Pokaż miasta
            </label>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Show point of interest markers">
                <input type="checkbox" id="p_showPointsOfInterest" checked={params.showPointsOfInterest} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Pokaż punkty zainteresowania
            </label>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Skala km / tile <span className="text-[10px] text-yellow-500">{params.kmPerTile.toFixed(2)}</span></label>
                <input type="range" id="p_kmPerTile" min="0.1" max="2" step="0.1" value={params.kmPerTile} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Min. odstęp lokacji <span className="text-[10px] text-yellow-500">{params.coastalLocationMinDistanceKm.toFixed(1)} km</span></label>
                <input type="range" id="p_coastalLocationMinDistanceKm" min="0.5" max="20" step="0.5" value={params.coastalLocationMinDistanceKm} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Ilość miast <span className="text-[10px] text-yellow-500">{params.cityDensity.toFixed(2)}</span></label>
                <input type="range" id="p_cityDensity" min="0" max="2" step="0.05" value={params.cityDensity} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Ilość punktów specjalnych <span className="text-[10px] text-yellow-500">{params.poiDensity.toFixed(2)}</span></label>
                <input type="range" id="p_poiDensity" min="0" max="2" step="0.05" value={params.poiDensity} onChange={handleChange} className="w-full custom-range" />
                <span className="tooltip">Miasta i POI są zawsze wybierane tylko z kafelków lądu sąsiadujących z wodą.</span>
            </div>

            <div className="h-px w-full bg-yellow-900/40 my-3"></div>
            <div className="text-sm font-bold text-yellow-600 font-serif mb-2">Połączenia morskie</div>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Generate legal sea routes between cities and points of interest">
                <input type="checkbox" id="p_enableRoutes" checked={params.enableRoutes} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Generuj połączenia
            </label>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Show dashed sea route overlay">
                <input type="checkbox" id="p_showRoutes" checked={params.showRoutes} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Pokaż połączenia
            </label>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Maks. dystans trasy <span className="text-[10px] text-yellow-500">{params.routeMaxDistanceKm.toFixed(0)} km</span></label>
                <input type="range" id="p_routeMaxDistanceKm" min="5" max="120" step="5" value={params.routeMaxDistanceKm} onChange={handleChange} className="w-full custom-range" />
                <span className="tooltip">Preferowany zasięg połączeń. Trasy naprawcze mogą próbować dłuższych obejść, jeśli to jedyny sposób połączenia lokacji.</span>
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Gęstość połączeń <span className="text-[10px] text-yellow-500">{params.routeDensity.toFixed(2)}</span></label>
                <input type="range" id="p_routeDensity" min="0" max="2" step="0.05" value={params.routeDensity} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Preferuj huby <span className="text-[10px] text-yellow-500">{params.routeHubBias.toFixed(2)}</span></label>
                <input type="range" id="p_routeHubBias" min="0" max="1" step="0.05" value={params.routeHubBias} onChange={handleChange} className="w-full custom-range" />
                <span className="tooltip">Huby to stolice, porty oraz ważne pirackie lub rzadkie punkty zainteresowania.</span>
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Min. połączeń <span className="text-[10px] text-yellow-500">{params.routeMinConnections}</span></label>
                <input type="range" id="p_routeMinConnections" min="1" max="3" step="1" value={params.routeMinConnections} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1">
                <label className="flex justify-between items-center text-xs text-slate-400">Max. połączeń <span className="text-[10px] text-yellow-500">{params.routeMaxConnections}</span></label>
                <input type="range" id="p_routeMaxConnections" min="2" max="8" step="1" value={params.routeMaxConnections} onChange={handleChange} className="w-full custom-range" />
                <span className="tooltip">Lokacje bez żadnej legalnej trasy wodnej są usuwane z finalnej mapy.</span>
            </div>

            <div className="h-px w-full bg-yellow-900/40 my-3"></div>
            <div className="text-sm font-bold text-yellow-600 font-serif mb-2">Lighting & Shadows</div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400 cursor-pointer hover:text-slate-200">
                    <span>Enable Shadows</span>
                    <input type="checkbox" id="p_enableShadows" checked={params.enableShadows} onChange={handleChange} className="accent-[var(--brass)] cursor-pointer" />
                </label>
            </div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400 cursor-pointer hover:text-slate-200">
                    <span>Dither Shadows</span>
                    <input type="checkbox" id="p_ditherShadows" checked={params.ditherShadows} onChange={handleChange} className="accent-[var(--brass)] cursor-pointer" />
                </label>
            </div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400">Shadow Intensity <span className="text-[10px] text-yellow-500">{params.shadowIntensity.toFixed(1)}</span></label>
                <input type="range" id="p_shadowIntensity" min="0" max="2" step="0.1" value={params.shadowIntensity} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400">Shadow Alpha / Blend <span className="text-[10px] text-yellow-500">{params.shadowAlpha.toFixed(2)}</span></label>
                <input type="range" id="p_shadowAlpha" min="0" max="1" step="0.05" value={params.shadowAlpha} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400">Light Direction Angle <span className="text-[10px] text-yellow-500">{params.lightAngleDeg}°</span></label>
                <input type="range" id="p_lightAngleDeg" min="0" max="360" step="5" value={params.lightAngleDeg} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="h-px w-full bg-yellow-900/40 my-3"></div>
            <div className="text-sm font-bold text-yellow-600 font-serif mb-2">Post Processing</div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400">Color Saturation <span className="text-[10px] text-yellow-500">{params.saturation.toFixed(1)}</span></label>
                <input type="range" id="p_saturation" min="0" max="2" step="0.1" value={params.saturation} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400">Sepia Overlay <span className="text-[10px] text-yellow-500">{params.sepia.toFixed(2)}</span></label>
                <input type="range" id="p_sepia" min="0" max="1" step="0.05" value={params.sepia} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400">Vignette Intensity <span className="text-[10px] text-yellow-500">{params.vignette.toFixed(2)}</span></label>
                <input type="range" id="p_vignette" min="0" max="1" step="0.05" value={params.vignette} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400">CRT Effect <span className="text-[10px] text-yellow-500">{params.scanlines.toFixed(2)}</span></label>
                <input type="range" id="p_scanlines" min="0" max="0.5" step="0.05" value={params.scanlines} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400 cursor-pointer hover:text-slate-200">
                    <span>Cellular Automaton Smoothing</span>
                    <input type="checkbox" id="p_smoothTerrain" checked={params.smoothTerrain} onChange={handleChange} className="accent-[var(--brass)] cursor-pointer" />
                </label>
                <span className="tooltip">Groups terrain types (reduces labyrinth look)</span>
                <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-slate-500 w-12">Strength</span>
                    <input type="range" id="p_smoothTerrainStrength" min="1" max="10" step="1" value={params.smoothTerrainStrength} onChange={handleChange} className="w-full custom-range" />
                    <span className="text-[10px] text-yellow-500 w-4 text-right">{params.smoothTerrainStrength}</span>
                </div>
            </div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400 cursor-pointer hover:text-slate-200">
                    <span>Elevation Blur</span>
                    <input type="checkbox" id="p_blurElevation" checked={params.blurElevation} onChange={handleChange} className="accent-[var(--brass)] cursor-pointer" />
                </label>
                <span className="tooltip">Softens jagged coastlines and mainland</span>
                <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-slate-500 w-12">Strength</span>
                    <input type="range" id="p_blurElevationStrength" min="1" max="5" step="1" value={params.blurElevationStrength} onChange={handleChange} className="w-full custom-range" />
                    <span className="text-[10px] text-yellow-500 w-4 text-right">{params.blurElevationStrength}</span>
                </div>
            </div>

            <div className="h-px w-full bg-yellow-900/40 my-3"></div>
            <div className="text-sm font-bold text-yellow-600 font-serif mb-2">Continental Borders</div>

            {/* North Border */}
            <div className="space-y-1 mb-2 border border-slate-700/50 bg-slate-800/20 p-2 rounded">
                <div className="flex justify-between items-center text-xs text-slate-400">
                    <label className="flex items-center gap-1 group">North <span className="text-[10px] text-yellow-500">{params.contNorth.toFixed(2)}</span>
                        <span onMouseEnter={() => onHoverBorder('north')} onMouseLeave={() => onHoverBorder(null)} className="ml-1 text-[8px] px-1 cursor-help border border-slate-600 rounded bg-slate-800 text-slate-400 group-hover:text-red-400 group-hover:border-red-400 transition-colors" title="Hover to show area">👁️</span>
                    </label>
                    <label className="flex items-center cursor-pointer hover:text-slate-200" title="Attach land to the edge">
                        <input type="checkbox" id="p_contNorthAttach" checked={params.contNorthAttach} onChange={handleChange} className="mr-1 accent-[var(--brass)] cursor-pointer" />
                        <span className="text-[10px]">Attach</span>
                    </label>
                </div>
                <input type="range" id="p_contNorth" min="0" max="1" step="0.05" value={params.contNorth} onChange={handleChange} className="w-full custom-range" />
                <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-slate-500 w-16">Mount. Coverage</span>
                    <input type="range" id="p_contNorthMountain" min="0" max="1" step="0.05" value={params.contNorthMountain} onChange={handleChange} className="w-full custom-range" />
                    <span className="text-[10px] text-yellow-500 w-4 text-right">{params.contNorthMountain.toFixed(2)}</span>
                </div>
                <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-slate-500 w-16">Mount. Steepness</span>
                    <input type="range" id="p_contNorthSteepness" min="0" max="1" step="0.05" value={params.contNorthSteepness} onChange={handleChange} className="w-full custom-range" />
                    <span className="text-[10px] text-yellow-500 w-4 text-right">{params.contNorthSteepness.toFixed(2)}</span>
                </div>
            </div>

            {/* South Border */}
            <div className="space-y-1 mb-2 border border-slate-700/50 bg-slate-800/20 p-2 rounded">
                <div className="flex justify-between items-center text-xs text-slate-400">
                    <label className="flex items-center gap-1 group">South <span className="text-[10px] text-yellow-500">{params.contSouth.toFixed(2)}</span>
                        <span onMouseEnter={() => onHoverBorder('south')} onMouseLeave={() => onHoverBorder(null)} className="ml-1 text-[8px] px-1 cursor-help border border-slate-600 rounded bg-slate-800 text-slate-400 group-hover:text-red-400 group-hover:border-red-400 transition-colors" title="Hover to show area">👁️</span>
                    </label>
                    <label className="flex items-center cursor-pointer hover:text-slate-200" title="Attach land to the edge">
                        <input type="checkbox" id="p_contSouthAttach" checked={params.contSouthAttach} onChange={handleChange} className="mr-1 accent-[var(--brass)] cursor-pointer" />
                        <span className="text-[10px]">Attach</span>
                    </label>
                </div>
                <input type="range" id="p_contSouth" min="0" max="1" step="0.05" value={params.contSouth} onChange={handleChange} className="w-full custom-range" />
                <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-slate-500 w-16">Mount. Coverage</span>
                    <input type="range" id="p_contSouthMountain" min="0" max="1" step="0.05" value={params.contSouthMountain} onChange={handleChange} className="w-full custom-range" />
                    <span className="text-[10px] text-yellow-500 w-4 text-right">{params.contSouthMountain.toFixed(2)}</span>
                </div>
                <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-slate-500 w-16">Mount. Steepness</span>
                    <input type="range" id="p_contSouthSteepness" min="0" max="1" step="0.05" value={params.contSouthSteepness} onChange={handleChange} className="w-full custom-range" />
                    <span className="text-[10px] text-yellow-500 w-4 text-right">{params.contSouthSteepness.toFixed(2)}</span>
                </div>
            </div>

            {/* East Border */}
            <div className="space-y-1 mb-2 border border-slate-700/50 bg-slate-800/20 p-2 rounded">
                <div className="flex justify-between items-center text-xs text-slate-400">
                    <label className="flex items-center gap-1 group">East <span className="text-[10px] text-yellow-500">{params.contEast.toFixed(2)}</span>
                        <span onMouseEnter={() => onHoverBorder('east')} onMouseLeave={() => onHoverBorder(null)} className="ml-1 text-[8px] px-1 cursor-help border border-slate-600 rounded bg-slate-800 text-slate-400 group-hover:text-red-400 group-hover:border-red-400 transition-colors" title="Hover to show area">👁️</span>
                    </label>
                    <label className="flex items-center cursor-pointer hover:text-slate-200" title="Attach land to the edge">
                        <input type="checkbox" id="p_contEastAttach" checked={params.contEastAttach} onChange={handleChange} className="mr-1 accent-[var(--brass)] cursor-pointer" />
                        <span className="text-[10px]">Attach</span>
                    </label>
                </div>
                <input type="range" id="p_contEast" min="0" max="1" step="0.05" value={params.contEast} onChange={handleChange} className="w-full custom-range" />
                <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-slate-500 w-16">Mount. Coverage</span>
                    <input type="range" id="p_contEastMountain" min="0" max="1" step="0.05" value={params.contEastMountain} onChange={handleChange} className="w-full custom-range" />
                    <span className="text-[10px] text-yellow-500 w-4 text-right">{params.contEastMountain.toFixed(2)}</span>
                </div>
                <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-slate-500 w-16">Mount. Steepness</span>
                    <input type="range" id="p_contEastSteepness" min="0" max="1" step="0.05" value={params.contEastSteepness} onChange={handleChange} className="w-full custom-range" />
                    <span className="text-[10px] text-yellow-500 w-4 text-right">{params.contEastSteepness.toFixed(2)}</span>
                </div>
            </div>

            {/* West Border */}
            <div className="space-y-1 mb-2 border border-slate-700/50 bg-slate-800/20 p-2 rounded">
                <div className="flex justify-between items-center text-xs text-slate-400">
                    <label className="flex items-center gap-1 group">West <span className="text-[10px] text-yellow-500">{params.contWest.toFixed(2)}</span>
                        <span onMouseEnter={() => onHoverBorder('west')} onMouseLeave={() => onHoverBorder(null)} className="ml-1 text-[8px] px-1 cursor-help border border-slate-600 rounded bg-slate-800 text-slate-400 group-hover:text-red-400 group-hover:border-red-400 transition-colors" title="Hover to show area">👁️</span>
                    </label>
                    <label className="flex items-center cursor-pointer hover:text-slate-200" title="Attach land to the edge">
                        <input type="checkbox" id="p_contWestAttach" checked={params.contWestAttach} onChange={handleChange} className="mr-1 accent-[var(--brass)] cursor-pointer" />
                        <span className="text-[10px]">Attach</span>
                    </label>
                </div>
                <input type="range" id="p_contWest" min="0" max="1" step="0.05" value={params.contWest} onChange={handleChange} className="w-full custom-range" />
                <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-slate-500 w-16">Mount. Coverage</span>
                    <input type="range" id="p_contWestMountain" min="0" max="1" step="0.05" value={params.contWestMountain} onChange={handleChange} className="w-full custom-range" />
                    <span className="text-[10px] text-yellow-500 w-4 text-right">{params.contWestMountain.toFixed(2)}</span>
                </div>
                <div className="flex items-center gap-2 mt-1">
                    <span className="text-[10px] text-slate-500 w-16">Mount. Steepness</span>
                    <input type="range" id="p_contWestSteepness" min="0" max="1" step="0.05" value={params.contWestSteepness} onChange={handleChange} className="w-full custom-range" />
                    <span className="text-[10px] text-yellow-500 w-4 text-right">{params.contWestSteepness.toFixed(2)}</span>
                </div>
            </div>

            <div className="h-px w-full bg-yellow-900/40 my-2"></div>

            <div className="text-sm font-bold text-yellow-600 font-serif mb-2">Atmosphere</div>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Show moving clouds on the map">
                <input type="checkbox" id="p_showClouds" checked={params.showClouds} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Show Animated Clouds
            </label>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Show elevation height map">
                <input type="checkbox" id="p_showHeightMap" checked={params.showHeightMap} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Show Height Map
            </label>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Show cartographic navigation lines on water">
                <input type="checkbox" id="p_showCartographicLines" checked={params.showCartographicLines} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Show Cartographic Lines
            </label>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mb-2" title="Show mountain streams overlay">
                <input type="checkbox" id="p_showStreams" checked={params.showStreams} onChange={handleChange} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Pokaż strumyki
            </label>
            <span className="tooltip -mt-2 mb-2">Wyłącza tylko rysowanie warstwy; wygenerowane dane strumyków zostają w mapie.</span>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400">Cloud Density <span className="text-[10px] text-yellow-500">{params.cloudDensity.toFixed(1)}</span></label>
                <input type="range" id="p_cloudDensity" min="0.1" max="2" step="0.1" value={params.cloudDensity} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="space-y-1 mb-2">
                <label className="flex justify-between items-center text-xs text-slate-400">Wind Speed <span className="text-[10px] text-yellow-500">{params.windSpeed.toFixed(1)}</span></label>
                <input type="range" id="p_windSpeed" min="0.1" max="3" step="0.1" value={params.windSpeed} onChange={handleChange} className="w-full custom-range" />
            </div>

            <div className="h-px w-full bg-yellow-900/40 my-2"></div>

            <label className="flex items-center text-xs text-slate-400 cursor-pointer mt-2" title="Show terrain types legend">
                <input type="checkbox" id="toggleLegend" checked={showLegend} onChange={(e) => onToggleLegend(e.target.checked)} className="mr-2 accent-[var(--brass)] cursor-pointer" />
                Show Legend
            </label>

            <div className="mt-auto pt-4 space-y-2 border-t border-yellow-900/50">
                <button className="w-full py-2.5 btn-gold rounded shadow-lg text-xs" onClick={onGenerate}>Generate Map</button>
                <button className="w-full py-1.5 btn-outline rounded text-[10px]" onClick={onRandomizeSeed}>Randomize Seed</button>

                <div className="grid grid-cols-2 gap-2 mt-2">
                    <button className="btn-outline py-1.5 rounded text-[10px] hover:bg-yellow-900/20" onClick={onSaveSettings}>Save Settings</button>
                    <button className="btn-outline py-1.5 rounded text-[10px] hover:bg-yellow-900/20" onClick={onReset}>Reset Defaults</button>
                </div>

                <div className="grid grid-cols-2 gap-2 mt-2">
                    <button className="btn-outline py-1.5 rounded text-[10px] hover:bg-yellow-900/20" onClick={onExportPNG}>Export PNG</button>
                    <button className="btn-outline py-1.5 rounded text-[10px] hover:bg-yellow-900/20" onClick={onExportJSON}>Export JSON</button>
                </div>
                <button className="w-full btn-outline py-1.5 rounded text-[10px] hover:bg-yellow-900/20" onClick={onExportLocationsJSON}>Export Locations JSON</button>
            </div>
        </div>
    );
}
