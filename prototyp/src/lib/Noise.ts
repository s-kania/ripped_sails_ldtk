import { PRNG } from './PRNG';

// ============================================================================
// MODULE: NOISE (Simple 2D Value/Perlin mix)
// ============================================================================
export class Noise {
    private p: Uint8Array;

    constructor(prng: PRNG) {
        this.p = new Uint8Array(512);
        for (let i = 0; i < 256; i++) {
            this.p[i] = Math.floor(prng.next() * 256);
        }
        // Duplicate to avoid wrap-around checks
        for (let i = 0; i < 256; i++) {
            this.p[256 + i] = this.p[i];
        }
    }

    private fade(t: number): number { return t * t * t * (t * (t * 6 - 15) + 10); }
    private lerp(t: number, a: number, b: number): number { return a + t * (b - a); }
    private grad(hash: number, x: number, y: number): number {
        const h = hash & 15;
        const grad = 1 + (h & 7); 
        return ((h & 8) ? -grad : grad) * x + ((h & 4) ? -grad : grad) * y;
    }

    // Standard 2D coherent noise
    public get(x: number, y: number): number {
        const X = Math.floor(x) & 255;
        const Y = Math.floor(y) & 255;
        x -= Math.floor(x);
        y -= Math.floor(y);
        const u = this.fade(x);
        const v = this.fade(y);

        const A = this.p[X] + Y, B = this.p[X + 1] + Y;
        
        return this.lerp(v, 
            this.lerp(u, this.grad(this.p[A], x, y), this.grad(this.p[B], x - 1, y)),
            this.lerp(u, this.grad(this.p[A + 1], x, y - 1), this.grad(this.p[B + 1], x - 1, y - 1))
        );
    }

    // Fractal Brownian Motion for rich detail
    public fbm(x: number, y: number, octaves: number, persistence: number, lacunarity: number, scale: number): number {
        let total = 0;
        let frequency = scale;
        let amplitude = 1;
        let maxVal = 0;  // Used for normalizing result to 0.0 - 1.0

        for(let i = 0; i < octaves; i++) {
            // map get() from roughly -1..1 to 0..1 scale inherently before adding
            total += (this.get(x * frequency, y * frequency) * 0.5 + 0.5) * amplitude;
            maxVal += amplitude;
            amplitude *= persistence;
            frequency *= lacunarity;
        }
        return total / maxVal;
    }
}
