import { MapData } from './MapData';
import { TERRAIN, MapParams, LocationRef, TravelRoutePoint } from './types';
import { PRNG } from './PRNG';

type ActiveLocation = { type: 'city' | 'poi'; id: number } | null;

// ============================================================================
// MODULE: RENDERER
// ============================================================================
export class Renderer {
    private canvas: HTMLCanvasElement;
    private ctx: CanvasRenderingContext2D;
    private colors: any;
    private animationId: number | null;
    private cloudOffset: number;
    private clouds: any[];
    public mapData: MapData | null;
    public activeBorderHighlight: string | null;
    public activeIslandId: number | null;
    public selectedIslandId: number | null;
    public activeLocation: ActiveLocation;
    private windSpeed: number;
    private baseImgData: ImageData | null;
    private params: MapParams | null;

    constructor(canvas: HTMLCanvasElement) {
        this.canvas = canvas;
        this.ctx = this.canvas.getContext('2d', { alpha: false }) as CanvasRenderingContext2D;

        this.colors = {
            oceanDeep: { r: 8, g: 38, b: 84 },        // #082654
            oceanMid: { r: 12, g: 54, b: 110 },       // #0c366e
            oceanLight: { r: 22, g: 83, b: 145 },      // #165391
            transition: { r: 35, g: 120, b: 173 },     // #2378ad
            shallowMid: { r: 45, g: 145, b: 189 },    // #2d91bd
            shallowLight: { r: 55, g: 168, b: 201 },  // #37a8c9 
            shallowGlow: { r: 99, g: 196, b: 210 },   // #63c4d2
            sand: { r: 215, g: 181, b: 109 },         // #d7b56d
            sandBright: { r: 235, g: 210, b: 145 },   // #ebd291
            landBase: { r: 112, g: 138, b: 52 },      // #708a34
            landLight: { r: 140, g: 163, b: 75 },     // #8ca34b
            landHighlight: { r: 168, g: 184, b: 95 }, // #a8b85f
            landDryBase: { r: 132, g: 148, b: 62 },
            landDryLight: { r: 160, g: 173, b: 85 },
            landDryHighlight: { r: 188, g: 194, b: 105 },
            hillBase: { r: 95, g: 115, b: 45 },
            hillLight: { r: 120, g: 140, b: 60 },
            hillHighlight: { r: 148, g: 165, b: 80 },
            forestBase: { r: 46, g: 79, b: 32 },      // #2e4f20
            forestDark: { r: 32, g: 59, b: 22 },      // #203b16
            forestHighlight: { r: 65, g: 105, b: 45 },// #41692d
            mount1: { r: 92, g: 76, b: 35 },          // #5c4c23 (Base / Shadow)
            mount2: { r: 110, g: 94, b: 45 },         // #6e5e2d
            mount3: { r: 130, g: 112, b: 56 },        // #827038 (Mid)
            mount4: { r: 155, g: 130, b: 74 },        // #9b824a
            mount5: { r: 185, g: 151, b: 104 },       // #b99768
            mount6: { r: 217, g: 183, b: 135 },       // #d9b787 (Peak)
            mount7: { r: 235, g: 213, b: 178 },       // #ebd5b2 (Highlight)
            streamDark: { r: 36, g: 116, b: 164 },
            streamLight: { r: 88, g: 184, b: 212 },
            cloudTop: { r: 255, g: 255, b: 255 },
            cloudBot: { r: 190, g: 205, b: 220 },
            cloudShadow: { r: 4, g: 20, b: 45 }
        };

        this.animationId = null;
        this.cloudOffset = 0;
        this.clouds = [];
        this.mapData = null;
        this.activeBorderHighlight = null;
        this.activeIslandId = null;
        this.selectedIslandId = null;
        this.activeLocation = null;
        this.windSpeed = 1.0;
        this.baseImgData = null;
        this.params = null;
    }

    // Call this to update rendering params without a full re-render
    updateParams(params: MapParams) {
        this.params = params;
    }

    render(mapData: MapData, params: MapParams) {
        this.params = params;
        if (this.animationId) {
            cancelAnimationFrame(this.animationId);
            this.animationId = null;
        }

        this.canvas.width = mapData.width;
        this.canvas.height = mapData.height;

        const imgData = this.ctx.createImageData(this.canvas.width, this.canvas.height);
        const data = imgData.data;

        const setPixel = (imgD: Uint8ClampedArray, width: number, height: number, x: number, y: number, color: any) => {
            if (x < 0 || x >= width || y < 0 || y >= height) return;
            const idx = (y * width + x) * 4;
            imgD[idx] = color.r;
            imgD[idx + 1] = color.g;
            imgD[idx + 2] = color.b;
            imgD[idx + 3] = 255;
        };

        const colors = this.colors;
        const showHeightMap = params.showHeightMap;
        const showCartographicLines = params.showCartographicLines;

        const enableShadows = params.enableShadows;
        const ditherShadows = params.ditherShadows;
        const shadowIntensity = params.shadowIntensity;
        const shadowAlpha = params.shadowAlpha;
        const lightAngleDeg = params.lightAngleDeg;

        const lightAngleRad = lightAngleDeg * Math.PI / 180;
        const lx = Math.cos(lightAngleRad);
        const ly = Math.sin(lightAngleRad);
        const lz = 0.5;

        const getElevation = (tx: number, ty: number) => {
            const t = mapData.getTile(tx, ty);
            if (!t) return 0;
            let h = t.elevation * 100;
            if (!t.walkable) {
                return h * 0.1; // flat water
            }
            if (t.terrain === TERRAIN.FOREST) h += t.moisture * 15; // slightly bumpy forest
            if (t.terrain === TERRAIN.MOUNTAINS) {
                let strictSteepness = t.steepness !== undefined ? t.steepness : 0.5;
                h += (t.elevation - mapData.params.seaLevel) * (50 + strictSteepness * 400); // mountain bumpiness based on param
            }
            return h;
        };

        for (let y = 0; y < mapData.height; y++) {
            for (let x = 0; x < mapData.width; x++) {
                const tile = mapData.getTile(x, y);
                if (!tile) continue;

                let color = colors.oceanDeep;

                if (showHeightMap) {
                    let v = Math.max(0, Math.min(255, Math.floor(tile.elevation * 255)));
                    color = { r: v, g: v, b: v };
                } else {
                    // Calculate normal vector for lighting
                    const hC = getElevation(x, y);
                    const hR = getElevation(x + 1, y);
                    const hD = getElevation(x, y + 1);

                    // Normal vector from gradients
                    const nx = hC - hR;
                    const ny = hC - hD;
                    const nz = 1.0; // strength of normal

                    // Normalize
                    const len = Math.sqrt(nx * nx + ny * ny + nz * nz);
                    const nX = nx / len;
                    const nY = ny / len;
                    const nZ = nz / len;

                    // Diffuse light intensity (dot product)
                    let diffuse = (nX * lx + nY * ly + nZ * lz);
                    diffuse = (diffuse + 0.3) * shadowIntensity;

                    if (!enableShadows) {
                        diffuse = 0.55; // Neutral light
                    } else if (ditherShadows) {
                        if ((x ^ y) % 2 === 0) diffuse += 0.08;
                        else diffuse -= 0.08;
                    }

                    diffuse = Math.max(0, Math.min(1, diffuse));

                    const isLit = diffuse > 0.65;
                    const isHighlyLit = diffuse > 0.85;
                    const isShaded = diffuse < 0.45;
                    const isDeepShadow = diffuse < 0.25;

                    const getTerrainColor = (diffValue: number) => {
                        let c = colors.landBase;
                        const isL = diffValue > 0.65;
                        const isHL = diffValue > 0.85;
                        const isS = diffValue < 0.45;
                        const isDS = diffValue < 0.25;

                        if (tile.terrain === TERRAIN.BEACH) {
                            c = isHL ? colors.sandBright : (isS ? colors.mount1 : colors.sand);
                        } else {
                            if (tile.terrain === TERRAIN.MOUNTAINS) {
                                const mountH = (tile.elevation - mapData.params.seaLevel) / (1.0 - mapData.params.seaLevel);

                                if (isHL) {
                                    if (mountH > 0.8) c = colors.mount7;
                                    else if (mountH > 0.5) c = colors.mount6;
                                    else if (mountH > 0.3) c = colors.mount5;
                                    else c = colors.mount4;
                                } else if (isL) {
                                    if (mountH > 0.75) c = colors.mount6;
                                    else if (mountH > 0.55) c = colors.mount5;
                                    else c = colors.mount4;
                                } else if (isDS) {
                                    if (mountH > 0.8) c = colors.mount3;
                                    else if (mountH > 0.5) c = colors.mount2;
                                    else c = colors.forestDark;
                                } else if (isS) {
                                    if (mountH > 0.8) c = colors.mount4;
                                    else c = colors.mount2;
                                } else {
                                    if (mountH > 0.75) c = colors.mount5;
                                    else if (mountH > 0.45) c = colors.mount4;
                                    else c = colors.mount3;
                                }

                                // Random noise without linear artifacts
                                const hashRand = (Math.sin(x * 12.9898 + y * 78.233) * 43758.5453);
                                const dither = hashRand - Math.floor(hashRand);

                                // Dither mountain texture slightly
                                if (dither < 0.2 && diffValue > 0.3) {
                                    c = colors.mount3;
                                }

                            } else if (tile.terrain === TERRAIN.FOREST) {
                                c = isL ? colors.forestHighlight : (isDS ? colors.oceanDeep : (isS ? colors.forestDark : colors.forestBase));

                                const hashRand = (Math.sin(x * 12.9898 + y * 78.233) * 43758.5453);
                                const dither = hashRand - Math.floor(hashRand);
                                // Stippled forest texture to look like canopy
                                if (dither < 0.35) {
                                    c = isL ? colors.forestBase : colors.forestDark;
                                }
                            } else {
                                // Plains / Hills
                                // Determine Sub-Biome based on moisture noise to create natural patches
                                const isDry = tile.moisture > (mapData.params.forestDensity + 0.15);

                                if (tile.terrain === TERRAIN.HILLS) {
                                    c = isHL ? colors.hillHighlight : (isL ? colors.hillLight : (isDS ? colors.forestDark : (isS ? colors.forestBase : colors.hillBase)));
                                } else { // Plains
                                    if (isDry) {
                                        c = isHL ? colors.landDryHighlight : (isL ? colors.landDryLight : (isDS ? colors.forestBase : (isS ? colors.forestBase : colors.landDryBase)));
                                    } else {
                                        c = isHL ? colors.landHighlight : (isL ? colors.landLight : (isDS ? colors.forestBase : (isS ? colors.forestBase : colors.landBase)));
                                    }
                                }

                                // Very subtle dither for texture
                                const hashRand = (Math.sin(x * 12.9898 + y * 78.233) * 43758.5453);
                                const dither = hashRand - Math.floor(hashRand);

                                if (tile.terrain === TERRAIN.HILLS && dither < 0.25) {
                                    c = isL ? colors.hillBase : colors.forestBase;
                                } else if (tile.terrain === TERRAIN.PLAINS && dither < 0.15) {
                                    c = isL ? (isDry ? colors.landDryBase : colors.landBase) : colors.forestBase;
                                }
                            }

                            // Smooth coastal edge
                            let isCoastalEdge = false;
                            const offsets = [[-1, 0], [1, 0], [0, -1], [0, 1]];
                            for (let o of offsets) {
                                const nt = mapData.getTile(x + o[0], y + o[1]);
                                if (nt && !nt.walkable) {
                                    isCoastalEdge = true; break;
                                }
                            }
                            if (isCoastalEdge) {
                                c = isHL ? colors.sandBright : (isS ? colors.mount1 : colors.sand);
                            }
                        }
                        return c;
                    };

                    if (tile.walkable) {
                        let shadowedColor = getTerrainColor(diffuse);
                        if (shadowAlpha < 1.0) {
                            let baseColor = getTerrainColor(0.55); // Neutral flat light
                            color = {
                                r: Math.round(baseColor.r * (1 - shadowAlpha) + shadowedColor.r * shadowAlpha),
                                g: Math.round(baseColor.g * (1 - shadowAlpha) + shadowedColor.g * shadowAlpha),
                                b: Math.round(baseColor.b * (1 - shadowAlpha) + shadowedColor.b * shadowAlpha)
                            };
                        } else {
                            color = shadowedColor;
                        }
                    } else {
                        // Water rendering with precise pixel-art layers
                        const d = mapData.params.seaLevel - tile.elevation;

                        // Rhumb line rendering
                        const isRhumbLine = ((x - y) % 64 === 0) || ((x + y) % 64 === 0) || (x % 128 === 0) || (y % 128 === 0);

                        if (d <= 0.02) {
                            color = colors.shallowGlow;
                        } else if (d <= 0.05) {
                            color = ((x ^ y) & 1) ? colors.shallowGlow : colors.shallowLight;
                        } else if (d <= 0.12) {
                            color = colors.shallowLight;
                        } else if (d <= 0.16) {
                            color = ((x + y) % 2 === 0) ? colors.shallowLight : colors.shallowMid;
                        } else if (d <= 0.25) {
                            color = colors.shallowMid;
                        } else if (d <= 0.30) {
                            color = ((x ^ y) & 1) ? colors.shallowMid : colors.transition;
                        } else if (d <= 0.45) {
                            color = colors.transition;
                        } else if (d <= 0.52) {
                            color = ((x ^ y) & 1) ? colors.transition : colors.oceanLight;
                        } else if (d <= 0.65) {
                            color = colors.oceanLight;
                        } else if (d <= 0.72) {
                            color = ((x ^ y) & 1) ? colors.oceanLight : colors.oceanMid;
                        } else if (d <= 0.85) {
                            color = colors.oceanMid;
                        } else if (d <= 0.90) {
                            color = ((x ^ y) & 1) ? colors.oceanMid : colors.oceanDeep;
                        } else {
                            color = colors.oceanDeep;
                        }

                        if (tile.terrain === TERRAIN.REEF) {
                            // Jagged reef pattern using noise instead of bitwise math
                            const hashRand = (Math.sin(x * 12.9898 + y * 78.233) * 43758.5453);
                            const reefDither = hashRand - Math.floor(hashRand);

                            if (reefDither < 0.2) color = colors.oceanMid;
                            else if (reefDither < 0.5) color = colors.shallowMid;
                            else color = colors.transition;
                        }

                        // Draw rhumb lines (navigation lines) on water
                        if (showCartographicLines && !showHeightMap && isRhumbLine && d > 0.05 && tile.terrain !== TERRAIN.REEF) {
                            // lighten the color slightly for the line
                            color = {
                                r: Math.min(255, color.r + 15),
                                g: Math.min(255, color.g + 25),
                                b: Math.min(255, color.b + 35)
                            };
                        }
                    }
                }

                setPixel(data, mapData.width, mapData.height, x, y, color);
            }
        }

        if (!showHeightMap && params.showStreams) {
            for (let stream of mapData.streams) {
                for (let i = 0; i < stream.points.length; i++) {
                    const point = stream.points[i];
                    const tile = mapData.getTile(point.x, point.y);
                    if (!tile?.walkable) continue;

                    const color = (i % 5 === 0 || stream.kind === 'estuary') ? colors.streamLight : colors.streamDark;
                    const width = Math.min(2, Math.max(1, Math.round(point.width)));

                    setPixel(data, mapData.width, mapData.height, point.x, point.y, color);

                    if (width > 1) {
                        const next = stream.points[i + 1] || stream.points[i - 1];
                        const horizontal = !next || Math.abs(next.x - point.x) >= Math.abs(next.y - point.y);
                        const sx = horizontal ? 0 : 1;
                        const sy = horizontal ? 1 : 0;
                        const sideTile = mapData.getTile(point.x + sx, point.y + sy);

                        if (sideTile?.walkable) {
                            setPixel(data, mapData.width, mapData.height, point.x + sx, point.y + sy, color);
                        }
                    }
                }
            }
        }

        this.baseImgData = imgData;

        const cloudDensity = params.cloudDensity;
        const windSpeed = params.windSpeed;
        this.windSpeed = windSpeed;

        // Clouds setup
        const PRNGCloud = new PRNG(mapData.params.seed + "clouds");
        const numClouds = Math.floor((mapData.width * mapData.height / 12000) * cloudDensity);

        const drawCloudBlob = (r: number) => {
            const pixels: any[] = [];
            for (let oy = -r; oy <= r; oy++) {
                for (let ox = -r; ox <= r; ox++) {
                    if (ox * ox + oy * oy <= r * r) {
                        pixels.push({ ox: ox, oy: oy });
                    }
                }
            }
            return pixels;
        };

        this.clouds = [];
        for (let i = 0; i < numClouds; i++) {
            const cx = PRNGCloud.nextInt(0, mapData.width);
            const cy = PRNGCloud.nextInt(0, mapData.height);

            const parts: any[] = [];
            const count = PRNGCloud.nextInt(3, 7);
            for (let p = 0; p < count; p++) {
                const ox = PRNGCloud.nextInt(-10, 10);
                const oy = PRNGCloud.nextInt(-5, 5);
                const r = PRNGCloud.nextInt(4, 9);

                // calculate relative blob
                const blob = drawCloudBlob(r);
                blob.forEach(b => {
                    parts.push({ ox: ox + b.ox, oy: oy + b.oy });
                });
            }
            this.clouds.push({ cx, cy, parts });
        }

        this.mapData = mapData;
        this.cloudOffset = 0;

        this.animate();
    }

    animate() {
        if (!this.baseImgData || !this.mapData || !this.params) return;

        // Copy base image fast
        const renderImgData = new ImageData(
            new Uint8ClampedArray(this.baseImgData.data),
            this.baseImgData.width,
            this.baseImgData.height
        );
        const data = renderImgData.data;

        const showClouds = this.params.showClouds;
        const mapWidth = this.mapData.width;
        const mapHeight = this.mapData.height;

        const setPixel = (x: number, y: number, color: any) => {
            if (x < 0 || x >= mapWidth || y < 0 || y >= mapHeight) return;
            const idx = (Math.floor(y) * mapWidth + Math.floor(x)) * 4;
            data[idx] = color.r;
            data[idx + 1] = color.g;
            data[idx + 2] = color.b;
        };

        if (showClouds) {
            const shadowOffset = 18;

            this.clouds.forEach(cloud => {
                const baseCx = cloud.cx - this.cloudOffset;
                const cx = ((baseCx % mapWidth) + mapWidth) % mapWidth;

                // shadows first
                cloud.parts.forEach((p: any) => {
                    const sx = Math.floor(cx + p.ox + shadowOffset);
                    const sy = Math.floor(cloud.cy + p.oy + shadowOffset);
                    const wrappedSx = ((sx % mapWidth) + mapWidth) % mapWidth;
                    if (sy >= 0 && sy < mapHeight) {
                        const t = this.mapData!.getTile(wrappedSx, sy);
                        if (t && !t.walkable) {
                            setPixel(wrappedSx, sy, this.colors.cloudShadow);
                        }
                    }
                });

                let minY = 9999, maxY = -9999;
                cloud.parts.forEach((p: any) => {
                    if (p.oy < minY) minY = p.oy;
                    if (p.oy > maxY) maxY = p.oy;
                });
                const midY = minY + (maxY - minY) * 0.6;

                cloud.parts.forEach((p: any) => {
                    const px = Math.floor(cx + p.ox);
                    const py = Math.floor(cloud.cy + p.oy);
                    const wrappedPx = ((px % mapWidth) + mapWidth) % mapWidth;

                    if (py >= 0 && py < mapHeight) {
                        const isBottom = p.oy > midY + (Math.sin(p.ox * 0.5) * 2);
                        setPixel(wrappedPx, py, isBottom ? this.colors.cloudBot : this.colors.cloudTop);
                    }
                });
            });

            this.cloudOffset += 0.2 * this.windSpeed;
        }

        // --- POST PROCESSING (Per-Pixel) ---
        const saturation = this.params.saturation;
        const sepia = this.params.sepia;
        const vignette = this.params.vignette;
        const scanlines = this.params.scanlines;

        if (saturation !== 1.0 || sepia > 0 || vignette > 0 || scanlines > 0) {
            let srcData = null;
            if (scanlines > 0) {
                srcData = new Uint8ClampedArray(data);
            }

            for (let y = 0; y < mapHeight; y++) {
                let dy = 0;
                if (vignette > 0) dy = (y / mapHeight) - 0.5;

                for (let x = 0; x < mapWidth; x++) {
                    let srcX = x;
                    let srcY = y;

                    if (scanlines > 0) {
                        // CRT Curvature mapping
                        // Normalize coords from -1 to 1
                        let nx = (x / mapWidth) * 2.0 - 1.0;
                        let ny = (y / mapHeight) * 2.0 - 1.0;

                        // Barrel distortion math
                        let distortion = scanlines * 0.4;
                        let r2 = nx * nx + ny * ny;
                        nx *= 1.0 + r2 * distortion;
                        ny *= 1.0 + r2 * distortion;

                        // Map back to 0-width
                        srcX = Math.round(((nx + 1.0) / 2.0) * mapWidth);
                        srcY = Math.round(((ny + 1.0) / 2.0) * mapHeight);
                    }

                    const idx = (y * mapWidth + x) * 4;
                    let r = 0, g = 0, b = 0;

                    if (srcX >= 0 && srcX < mapWidth && srcY >= 0 && srcY < mapHeight) {
                        let readIdx = (srcY * mapWidth + srcX) * 4;
                        r = srcData ? srcData[readIdx] : data[readIdx];
                        g = srcData ? srcData[readIdx + 1] : data[readIdx + 1];
                        b = srcData ? srcData[readIdx + 2] : data[readIdx + 2];

                        if (scanlines > 0) {
                            // Chromatic Aberration
                            let shift = Math.max(1, Math.floor(scanlines * 6));
                            if (srcX + shift < mapWidth) {
                                r = srcData![(srcY * mapWidth + srcX + shift) * 4];
                            }
                            if (srcX - shift >= 0) {
                                b = srcData![(srcY * mapWidth + srcX - shift) * 4 + 2];
                            }

                            // Scanlines
                            let rowScanlineFade = (y % 2 === 0) ? (1.0 - scanlines * 0.5) : 1.0;
                            r *= rowScanlineFade;
                            g *= rowScanlineFade;
                            b *= rowScanlineFade;

                            // Corner darkening (tube border)
                            let cnx = (x / mapWidth) * 2.0 - 1.0;
                            let cny = (y / mapHeight) * 2.0 - 1.0;
                            let tubeDist = Math.max(Math.abs(cnx), Math.abs(cny));
                            if (tubeDist > 0.9) {
                                let tubeGlow = 1.0 - ((tubeDist - 0.9) * 10.0);
                                r *= Math.max(0, tubeGlow);
                                g *= Math.max(0, tubeGlow);
                                b *= Math.max(0, tubeGlow);
                            }
                        }

                        if (saturation !== 1.0) {
                            const lum = 0.299 * r + 0.587 * g + 0.114 * b;
                            r = lum + (r - lum) * saturation;
                            g = lum + (g - lum) * saturation;
                            b = lum + (b - lum) * saturation;
                        }

                        if (sepia > 0) {
                            const tr = (r * 0.393) + (g * 0.769) + (b * 0.189);
                            const tg = (r * 0.349) + (g * 0.686) + (b * 0.168);
                            const tb = (r * 0.272) + (g * 0.534) + (b * 0.131);
                            r = r * (1 - sepia) + tr * sepia;
                            g = g * (1 - sepia) + tg * sepia;
                            b = b * (1 - sepia) + tb * sepia;
                        }

                        if (vignette > 0) {
                            const dx = (x / mapWidth) - 0.5;
                            const dist = Math.sqrt(dx * dx + dy * dy) * 2.0;
                            const vFade = Math.max(0, 1.0 - (dist * vignette));
                            r *= vFade;
                            g *= vFade;
                            b *= vFade;
                        }
                    }

                    data[idx] = Math.min(255, Math.max(0, r));
                    data[idx + 1] = Math.min(255, Math.max(0, g));
                    data[idx + 2] = Math.min(255, Math.max(0, b));
                }
            }
        }

        this.ctx.putImageData(renderImgData, 0, 0);

        if (this.params.showRoutes) {
            this._drawRoutes();
        }

        if (this.params.showSettlements) {
            for (const city of this.mapData.cities) {
                this.ctx.save();
                this.ctx.fillStyle = city.kind === 'capital' ? "rgba(255, 245, 170, 0.98)" : "rgba(255, 218, 96, 0.95)";
                this.ctx.strokeStyle = "rgba(60, 35, 10, 0.9)";
                this.ctx.lineWidth = 1;
                this.ctx.beginPath();
                this.ctx.arc(city.x + 0.5, city.y + 0.5, city.kind === 'capital' ? 3 : 2.2, 0, Math.PI * 2);
                this.ctx.fill();
                this.ctx.stroke();
                this.ctx.restore();
            }
        }

        if (this.params.showPointsOfInterest) {
            for (const point of this.mapData.pointsOfInterest) {
                const r = point.rarity >= 3 ? 3 : 2.4;
                this.ctx.save();
                this.ctx.fillStyle = point.kind === 'blackCove' ? "rgba(125, 38, 170, 0.95)" : "rgba(210, 45, 70, 0.92)";
                this.ctx.strokeStyle = "rgba(255, 210, 210, 0.9)";
                this.ctx.lineWidth = 1;
                this.ctx.beginPath();
                this.ctx.moveTo(point.x + 0.5, point.y + 0.5 - r);
                this.ctx.lineTo(point.x + 0.5 + r, point.y + 0.5);
                this.ctx.lineTo(point.x + 0.5, point.y + 0.5 + r);
                this.ctx.lineTo(point.x + 0.5 - r, point.y + 0.5);
                this.ctx.closePath();
                this.ctx.fill();
                this.ctx.stroke();
                this.ctx.restore();
            }
        }

        const activeCity = this.activeLocation?.type === 'city' && this.params.showSettlements
            ? this.mapData.cities.find(city => city.id === this.activeLocation?.id)
            : null;
        const activePoint = this.activeLocation?.type === 'poi' && this.params.showPointsOfInterest
            ? this.mapData.pointsOfInterest.find(point => point.id === this.activeLocation?.id)
            : null;
        const activeName = activeCity?.name ?? activePoint?.name;
        const activeX = activeCity?.x ?? activePoint?.x;
        const activeY = activeCity?.y ?? activePoint?.y;
        const activeKind = activeCity
            ? ({ town: 'Miasto', port: 'Port', fort: 'Fort', capital: 'Stolica' } as const)[activeCity.kind]
            : activePoint
                ? ({ blackCove: 'Czarna zatoka', treasureSite: 'Skarb', pirateHaven: 'Piracka przystań', lostMission: 'Opuszczona misja', smugglerCamp: 'Obóz przemytników', ancientRuins: 'Starożytne ruiny' } as const)[activePoint.kind]
                : null;

        if (activeName && activeX !== undefined && activeY !== undefined && activeKind) {
            this.ctx.save();
            this.ctx.strokeStyle = "rgba(255, 255, 220, 0.95)";
            this.ctx.lineWidth = 1.5;
            this.ctx.beginPath();
            this.ctx.arc(activeX + 0.5, activeY + 0.5, activeCity ? 4.2 : 4.8, 0, Math.PI * 2);
            this.ctx.stroke();

            const fontSize = Math.max(9, Math.min(15, Math.floor(mapWidth / 52)));
            const label = `${activeName} · ${activeKind}`;
            const labelX = Math.max(4, Math.min(mapWidth - 4, activeX + 0.5));
            const labelY = Math.max(fontSize + 8, activeY - 8);

            this.ctx.font = `bold ${fontSize}px serif`;
            this.ctx.textAlign = "center";
            this.ctx.textBaseline = "middle";

            const metrics = this.ctx.measureText(label);
            const paddingX = 5;
            const paddingY = 3;
            const boxW = metrics.width + paddingX * 2;
            const boxH = fontSize + paddingY * 2;
            const boxX = Math.max(2, Math.min(mapWidth - boxW - 2, labelX - boxW / 2));
            const boxY = Math.max(2, Math.min(mapHeight - boxH - 2, labelY - boxH / 2));

            this.ctx.fillStyle = "rgba(18, 12, 6, 0.82)";
            this.ctx.fillRect(boxX, boxY, boxW, boxH);
            this.ctx.strokeStyle = activeCity ? "rgba(255, 220, 80, 0.95)" : "rgba(255, 120, 150, 0.95)";
            this.ctx.lineWidth = 1;
            this.ctx.strokeRect(boxX, boxY, boxW, boxH);
            this.ctx.fillStyle = "rgba(255, 238, 190, 0.98)";
            this.ctx.fillText(label, boxX + boxW / 2, boxY + boxH / 2);
            this.ctx.restore();
        }

        if (this.activeBorderHighlight) {
            this.ctx.save();
            this.ctx.strokeStyle = "rgba(255, 0, 0, 0.8)";
            this.ctx.lineWidth = 2; // Slightly thicker to be visible clearly
            this.ctx.setLineDash([4, 4]); // Dashed line
            this.ctx.beginPath();

            const ew = Math.floor(mapWidth * 0.18);
            const eh = Math.floor(mapHeight * 0.18);

            if (this.activeBorderHighlight === 'north') {
                this.ctx.moveTo(0, eh);
                this.ctx.lineTo(mapWidth, eh);
            } else if (this.activeBorderHighlight === 'south') {
                this.ctx.moveTo(0, mapHeight - eh);
                this.ctx.lineTo(mapWidth, mapHeight - eh);
            } else if (this.activeBorderHighlight === 'east') {
                this.ctx.moveTo(mapWidth - ew, 0);
                this.ctx.lineTo(mapWidth - ew, mapHeight);
            } else if (this.activeBorderHighlight === 'west') {
                this.ctx.moveTo(ew, 0);
                this.ctx.lineTo(ew, mapHeight);
            }

            this.ctx.stroke();
            this.ctx.restore();
        }

        if (this.activeIslandId !== null) {
            const island = this.mapData.islands.find(item => item.id === this.activeIslandId);

            if (island) {
                this.ctx.save();
                this.ctx.strokeStyle = "rgba(255, 32, 32, 0.9)";
                this.ctx.lineWidth = 1.5;
                this.ctx.setLineDash([4, 3]);
                this.ctx.beginPath();

                for (const segment of island.borderSegments) {
                    this.ctx.moveTo(segment.x1, segment.y1);
                    this.ctx.lineTo(segment.x2, segment.y2);
                }

                this.ctx.stroke();
                this.ctx.setLineDash([]);

                const fontSize = Math.max(10, Math.min(18, Math.floor(mapWidth / 45)));
                const labelX = Math.max(4, Math.min(mapWidth - 4, island.center.x));
                const labelY = Math.max(fontSize + 4, island.bounds.minY - 4);

                this.ctx.font = `bold ${fontSize}px serif`;
                this.ctx.textAlign = "center";
                this.ctx.textBaseline = "middle";

                const metrics = this.ctx.measureText(island.name);
                const paddingX = 5;
                const paddingY = 3;
                const boxW = metrics.width + paddingX * 2;
                const boxH = fontSize + paddingY * 2;
                const boxX = Math.max(2, Math.min(mapWidth - boxW - 2, labelX - boxW / 2));
                const boxY = Math.max(2, Math.min(mapHeight - boxH - 2, labelY - boxH / 2));

                this.ctx.fillStyle = "rgba(20, 8, 8, 0.78)";
                this.ctx.fillRect(boxX, boxY, boxW, boxH);
                this.ctx.strokeStyle = "rgba(255, 64, 64, 0.9)";
                this.ctx.lineWidth = 1;
                this.ctx.strokeRect(boxX, boxY, boxW, boxH);
                this.ctx.fillStyle = "rgba(255, 230, 190, 0.96)";
                this.ctx.fillText(island.name, boxX + boxW / 2, boxY + boxH / 2);
                this.ctx.restore();
            }
        }

        if (this.selectedIslandId !== null && this.selectedIslandId !== this.activeIslandId) {
            const island = this.mapData.islands.find(item => item.id === this.selectedIslandId);

            if (island) {
                this.ctx.save();
                this.ctx.strokeStyle = "rgba(255, 210, 60, 0.95)";
                this.ctx.lineWidth = 2;
                this.ctx.setLineDash([6, 3]);
                this.ctx.beginPath();

                for (const segment of island.borderSegments) {
                    this.ctx.moveTo(segment.x1, segment.y1);
                    this.ctx.lineTo(segment.x2, segment.y2);
                }

                this.ctx.stroke();
                this.ctx.restore();
            }
        }

        this.animationId = requestAnimationFrame(() => this.animate());
    }

    private _drawRoutes() {
        if (!this.mapData) return;

        for (const route of this.mapData.routes) {
            if (route.points.length < 2) continue;

            const active = this.activeLocation
                ? this._sameLocation(route.from, this.activeLocation) || this._sameLocation(route.to, this.activeLocation)
                : false;

            this.ctx.save();
            this.ctx.lineCap = "round";
            this.ctx.lineJoin = "round";
            this.ctx.setLineDash(active ? [5, 3] : [4, 4]);
            this.ctx.strokeStyle = active ? "rgba(255, 242, 170, 0.88)" : "rgba(230, 220, 170, 0.42)";
            this.ctx.lineWidth = active ? 1.6 : 1.1;
            this.ctx.beginPath();
            this._drawRoutePath(route.points);
            this.ctx.stroke();
            this.ctx.restore();
        }
    }

    private _drawRoutePath(points: TravelRoutePoint[]) {
        this.ctx.moveTo(points[0].x + 0.5, points[0].y + 0.5);

        if (points.length === 2) {
            this.ctx.lineTo(points[1].x + 0.5, points[1].y + 0.5);
            return;
        }

        for (let i = 1; i < points.length - 1; i++) {
            const current = points[i];
            const next = points[i + 1];
            this.ctx.quadraticCurveTo(current.x + 0.5, current.y + 0.5, (current.x + next.x) / 2 + 0.5, (current.y + next.y) / 2 + 0.5);
        }

        const last = points[points.length - 1];
        this.ctx.lineTo(last.x + 0.5, last.y + 0.5);
    }

    private _sameLocation(a: LocationRef, b: LocationRef): boolean {
        return a.type === b.type && a.id === b.id;
    }
}
