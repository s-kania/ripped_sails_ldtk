package worldmap;

class WorldMapNoise {
	var p:Array<Int>;

	public function new(prng:WorldMapPrng) {
		p = [];
		for( i in 0...256 )
			p[i] = Math.floor(prng.next() * 256);
		for( i in 0...256 )
			p[256+i] = p[i];
	}

	inline function fade(t:Float):Float return t*t*t*(t*(t*6-15)+10);
	inline function lerp(t:Float, a:Float, b:Float):Float return a + t*(b-a);

	function grad(hash:Int, x:Float, y:Float):Float {
		var h = hash & 15;
		var g = 1 + (h & 7);
		return ((h & 8)!=0 ? -g : g) * x + ((h & 4)!=0 ? -g : g) * y;
	}

	public function get(x:Float, y:Float):Float {
		var fx = Math.floor(x);
		var fy = Math.floor(y);
		var X = Std.int(fx) & 255;
		var Y = Std.int(fy) & 255;
		x -= fx;
		y -= fy;
		var u = fade(x);
		var v = fade(y);
		var A = p[X] + Y;
		var B = p[X+1] + Y;
		return lerp(v,
			lerp(u, grad(p[A], x, y), grad(p[B], x-1, y)),
			lerp(u, grad(p[A+1], x, y-1), grad(p[B+1], x-1, y-1))
		);
	}

	public function fbm(x:Float, y:Float, octaves:Int, persistence:Float, lacunarity:Float, scale:Float):Float {
		var total = 0.;
		var frequency = scale;
		var amplitude = 1.;
		var maxVal = 0.;
		for( i in 0...octaves ) {
			total += (get(x*frequency, y*frequency) * 0.5 + 0.5) * amplitude;
			maxVal += amplitude;
			amplitude *= persistence;
			frequency *= lacunarity;
		}
		return total / maxVal;
	}
}
