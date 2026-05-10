// ============================================================================
// MODULE: PRNG (Seedable Randomness)
// ============================================================================
export class PRNG {
    public seed: number;
    private randomFunc: () => number;

    /**
     * Initialize Mulberry32 PRNG with a string seed hashed to 32 bits
     */
    constructor(seedStr: string) {
        this.seed = this.xmur3(seedStr)();
        this.randomFunc = this.mulberry32(this.seed);
    }

    // Returns float between 0 and 1
    next(): number {
        return this.randomFunc();
    }

    // Returns int between min and max (inclusive)
    nextInt(min: number, max: number): number {
        return Math.floor(this.next() * (max - min + 1)) + min;
    }

    // Simple hash
    private xmur3(str: string): () => number {
        for (var i = 0, h = 1779033703 ^ str.length; i < str.length; i++) {
            h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
            h = h << 13 | h >>> 19;
        } return function() {
            h = Math.imul(h ^ (h >>> 16), 2246822507);
            h = Math.imul(h ^ (h >>> 13), 3266489909);
            return (h ^= h >>> 16) >>> 0;
        }
    }

    // Mulberry32
    private mulberry32(a: number): () => number {
        return function() {
            var t = a += 0x6D2B79F5;
            t = Math.imul(t ^ t >>> 15, t | 1);
            t ^= t + Math.imul(t ^ t >>> 7, t | 61);
            return ((t ^ t >>> 14) >>> 0) / 4294967296;
        }
    }
}
