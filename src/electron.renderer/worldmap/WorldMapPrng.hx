package worldmap;

class WorldMapPrng {
	var seed:Int;

	public function new(seedStr:String) {
		seed = xmur3(seedStr);
	}

	public function next():Float {
		seed = seed + 0x6D2B79F5;
		var t = seed;
		t = imul(t ^ (t >>> 15), t | 1);
		t ^= t + imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296.0;
	}

	public function nextInt(min:Int, max:Int):Int {
		return Std.int(Math.floor(next() * (max - min + 1))) + min;
	}

	static function xmur3(str:String):Int {
		var h = 1779033703 ^ str.length;
		for( i in 0...str.length ) {
			h = imul(h ^ str.charCodeAt(i), -862048943);
			h = (h << 13) | (h >>> 19);
		}
		h = imul(h ^ (h >>> 16), -2048144789);
		h = imul(h ^ (h >>> 13), -1028477387);
		return (h ^ (h >>> 16)) >>> 0;
	}

	static inline function imul(a:Int, b:Int):Int {
		return js.Syntax.code("Math.imul({0}, {1})", a, b);
	}
}
