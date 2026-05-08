package worldmap;

import js.Browser;
import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;
import js.html.ImageData;

typedef Rgb = {
	r:Int,
	g:Int,
	b:Int,
}

typedef CloudShape = {
	cx:Int,
	cy:Int,
	parts:Array<{ ox:Int, oy:Int }>,
}

class WorldMapRenderer {
	var canvas:CanvasElement;
	var ctx:CanvasRenderingContext2D;
	var baseImgData:Null<ImageData>;
	var colors:Dynamic;
	var animationId:Null<Int> = null;
	var cloudOffset = 0.;
	var clouds:Array<CloudShape> = [];
	var windSpeed = 1.;

	public var mapData:Null<WorldMapData> = null;
	public var params:Null<WorldMapParams> = null;
	public var activeBorderHighlight:Null<String> = null;
	public var activeIslandId:Null<Int> = null;
	public var selectedIslandId:Null<Int> = null;
	public var activeLocation:Null<ActiveLocation> = null;

	public function new(canvas:CanvasElement) {
		this.canvas = canvas;
		ctx = canvas.getContext2d();
		colors = {
			oceanDeep:{ r:8, g:38, b:84 },
			oceanMid:{ r:12, g:54, b:110 },
			oceanLight:{ r:22, g:83, b:145 },
			transition:{ r:35, g:120, b:173 },
			shallowMid:{ r:45, g:145, b:189 },
			shallowLight:{ r:55, g:168, b:201 },
			shallowGlow:{ r:99, g:196, b:210 },
			sand:{ r:215, g:181, b:109 },
			sandBright:{ r:235, g:210, b:145 },
			landBase:{ r:112, g:138, b:52 },
			landLight:{ r:140, g:163, b:75 },
			landHighlight:{ r:168, g:184, b:95 },
			landDryBase:{ r:132, g:148, b:62 },
			landDryLight:{ r:160, g:173, b:85 },
			landDryHighlight:{ r:188, g:194, b:105 },
			hillBase:{ r:95, g:115, b:45 },
			hillLight:{ r:120, g:140, b:60 },
			hillHighlight:{ r:148, g:165, b:80 },
			forestBase:{ r:46, g:79, b:32 },
			forestDark:{ r:32, g:59, b:22 },
			forestHighlight:{ r:65, g:105, b:45 },
			mount1:{ r:92, g:76, b:35 },
			mount2:{ r:110, g:94, b:45 },
			mount3:{ r:130, g:112, b:56 },
			mount4:{ r:155, g:130, b:74 },
			mount5:{ r:185, g:151, b:104 },
			mount6:{ r:217, g:183, b:135 },
			mount7:{ r:235, g:213, b:178 },
			streamDark:{ r:36, g:116, b:164 },
			streamLight:{ r:88, g:184, b:212 },
			cloudTop:{ r:255, g:255, b:255 },
			cloudBot:{ r:190, g:205, b:220 },
			cloudShadow:{ r:4, g:20, b:45 },
		};
	}

	public function dispose() {
		if( animationId!=null ) {
			Browser.window.cancelAnimationFrame(animationId);
			animationId = null;
		}
	}

	public function updateParams(params:WorldMapParams) {
		this.params = params.clone();
		windSpeed = params.windSpeed;
	}

	public function render(mapData:WorldMapData, params:WorldMapParams) {
		this.mapData = mapData;
		this.params = params.clone();
		windSpeed = params.windSpeed;

		if( animationId!=null ) {
			Browser.window.cancelAnimationFrame(animationId);
			animationId = null;
		}

		canvas.width = mapData.width;
		canvas.height = mapData.height;

		var imgData = ctx.createImageData(mapData.width, mapData.height);
		var data = imgData.data;
		var lightAngleRad = params.lightAngleDeg * Math.PI / 180;
		var lx = Math.cos(lightAngleRad);
		var ly = Math.sin(lightAngleRad);
		var lz = 0.5;

		for( y in 0...mapData.height )
		for( x in 0...mapData.width ) {
			var tile = mapData.getTile(x, y);
			if( tile==null )
				continue;
			var color:Rgb = colors.oceanDeep;

			if( params.showHeightMap ) {
				var v = clampColor(Math.floor(tile.elevation * 255));
				color = { r:v, g:v, b:v };
			}
			else if( tile.walkable ) {
				var hC = getElevation(x, y);
				var hR = getElevation(x+1, y);
				var hD = getElevation(x, y+1);
				var nx = hC - hR;
				var ny = hC - hD;
				var nz = 1.;
				var len = Math.sqrt(nx*nx + ny*ny + nz*nz);
				var diffuse = ((nx/len)*lx + (ny/len)*ly + (nz/len)*lz + 0.3) * params.shadowIntensity;
				if( !params.enableShadows )
					diffuse = 0.55;
				else if( params.ditherShadows )
					diffuse += ((x ^ y) % 2)==0 ? 0.08 : -0.08;
				diffuse = Math.max(0, Math.min(1, diffuse));
				var shadowed = getTerrainColor(tile, diffuse);
				if( params.shadowAlpha<1 ) {
					var base = getTerrainColor(tile, 0.55);
					color = {
						r:Math.round(base.r*(1-params.shadowAlpha) + shadowed.r*params.shadowAlpha),
						g:Math.round(base.g*(1-params.shadowAlpha) + shadowed.g*params.shadowAlpha),
						b:Math.round(base.b*(1-params.shadowAlpha) + shadowed.b*params.shadowAlpha),
					}
				}
				else
					color = shadowed;
			}
			else {
				color = getWaterColor(tile, x, y, params);
			}

			setPixel(data, mapData.width, x, y, color);
		}

		if( !params.showHeightMap && params.showStreams )
			drawStreamsToImageData(data);

		baseImgData = imgData;
		setupClouds();
		cloudOffset = 0;
		animate();
	}

	function getElevation(x:Int, y:Int):Float {
		var m = mapData;
		if( m==null )
			return 0;
		var t = m.getTile(x, y);
		if( t==null )
			return 0;
		var h = t.elevation * 100;
		if( !t.walkable )
			return h * 0.1;
		if( t.terrain==Terrain.Forest )
			h += t.moisture * 15;
		if( t.terrain==Terrain.Mountains )
			h += (t.elevation - m.params.seaLevel) * (50 + t.steepness * 400);
		return h;
	}

	function getTerrainColor(tile:WorldMapTile, diffuse:Float):Rgb {
		var isL = diffuse>0.65;
		var isHL = diffuse>0.85;
		var isS = diffuse<0.45;
		var isDS = diffuse<0.25;
		if( tile.terrain==Terrain.Beach || isCoastalEdge(tile.x, tile.y) )
			return isHL ? colors.sandBright : (isS ? colors.mount1 : colors.sand);

		if( tile.terrain==Terrain.Mountains ) {
			var mountH = (tile.elevation - mapData.params.seaLevel) / (1 - mapData.params.seaLevel);
			if( isHL ) return mountH>0.8 ? colors.mount7 : (mountH>0.5 ? colors.mount6 : (mountH>0.3 ? colors.mount5 : colors.mount4));
			if( isL ) return mountH>0.75 ? colors.mount6 : (mountH>0.55 ? colors.mount5 : colors.mount4);
			if( isDS ) return mountH>0.8 ? colors.mount3 : (mountH>0.5 ? colors.mount2 : colors.forestDark);
			if( isS ) return mountH>0.8 ? colors.mount4 : colors.mount2;
			return mountH>0.75 ? colors.mount5 : (mountH>0.45 ? colors.mount4 : colors.mount3);
		}

		if( tile.terrain==Terrain.Forest ) {
			var c:Rgb = isL ? colors.forestHighlight : (isDS ? colors.oceanDeep : (isS ? colors.forestDark : colors.forestBase));
			var dither = hashRand(tile.x, tile.y);
			return dither<0.35 ? (isL ? colors.forestBase : colors.forestDark) : c;
		}

		if( tile.terrain==Terrain.Hills ) {
			var c:Rgb = isHL ? colors.hillHighlight : (isL ? colors.hillLight : (isDS ? colors.forestDark : (isS ? colors.forestBase : colors.hillBase)));
			return hashRand(tile.x, tile.y)<0.25 ? (isL ? colors.hillBase : colors.forestBase) : c;
		}

		var isDry = tile.moisture > mapData.params.forestDensity + 0.15;
		var c:Rgb = isDry
			? (isHL ? colors.landDryHighlight : (isL ? colors.landDryLight : (isDS ? colors.forestBase : (isS ? colors.forestBase : colors.landDryBase))))
			: (isHL ? colors.landHighlight : (isL ? colors.landLight : (isDS ? colors.forestBase : (isS ? colors.forestBase : colors.landBase))));
		return hashRand(tile.x, tile.y)<0.15 ? (isL ? (isDry ? colors.landDryBase : colors.landBase) : colors.forestBase) : c;
	}

	function getWaterColor(tile:WorldMapTile, x:Int, y:Int, params:WorldMapParams):Rgb {
		var d = mapData.params.seaLevel - tile.elevation;
		var color:Rgb;
		if( d<=0.02 ) color = colors.shallowGlow;
		else if( d<=0.05 ) color = ((x^y)&1)!=0 ? colors.shallowGlow : colors.shallowLight;
		else if( d<=0.12 ) color = colors.shallowLight;
		else if( d<=0.16 ) color = ((x+y)%2)==0 ? colors.shallowLight : colors.shallowMid;
		else if( d<=0.25 ) color = colors.shallowMid;
		else if( d<=0.30 ) color = ((x^y)&1)!=0 ? colors.shallowMid : colors.transition;
		else if( d<=0.45 ) color = colors.transition;
		else if( d<=0.52 ) color = ((x^y)&1)!=0 ? colors.transition : colors.oceanLight;
		else if( d<=0.65 ) color = colors.oceanLight;
		else if( d<=0.72 ) color = ((x^y)&1)!=0 ? colors.oceanLight : colors.oceanMid;
		else color = colors.oceanDeep;

		if( tile.terrain==Terrain.Reef ) {
			var rd = hashRand(x, y);
			color = rd<0.2 ? colors.oceanMid : (rd<0.5 ? colors.shallowMid : colors.transition);
		}

		var rhumb = ((x-y)%64)==0 || ((x+y)%64)==0 || x%128==0 || y%128==0;
		if( params.showCartographicLines && rhumb && d>0.05 && tile.terrain!=Terrain.Reef )
			color = { r:clampColor(color.r+15), g:clampColor(color.g+25), b:clampColor(color.b+35) };
		return color;
	}

	function drawStreamsToImageData(data:js.lib.Uint8ClampedArray) {
		for( stream in mapData.streams )
		for( i in 0...stream.points.length ) {
			var p = stream.points[i];
			var tile = mapData.getTile(p.x, p.y);
			if( tile==null || !tile.walkable )
				continue;
			var color:Rgb = i%5==0 || stream.kind=="estuary" ? colors.streamLight : colors.streamDark;
			setPixel(data, mapData.width, p.x, p.y, color);
			if( Math.round(p.width)>1 ) {
				var next = i+1<stream.points.length ? stream.points[i+1] : (i>0 ? stream.points[i-1] : null);
				var horizontal = next==null || Math.abs(next.x-p.x)>=Math.abs(next.y-p.y);
				var sx = horizontal ? 0 : 1;
				var sy = horizontal ? 1 : 0;
				var side = mapData.getTile(p.x+sx, p.y+sy);
				if( side!=null && side.walkable )
					setPixel(data, mapData.width, p.x+sx, p.y+sy, color);
			}
		}
	}

	function setupClouds() {
		clouds = [];
		if( mapData==null || params==null )
			return;
		var rng = new WorldMapPrng(mapData.params.seed + "clouds");
		var count = Math.floor((mapData.width * mapData.height / 12000) * params.cloudDensity);
		for( i in 0...count ) {
			var parts:Array<{ ox:Int, oy:Int }> = [];
			var blobs = rng.nextInt(3, 7);
			for( b in 0...blobs ) {
				var ox = rng.nextInt(-10, 10);
				var oy = rng.nextInt(-5, 5);
				var r = rng.nextInt(4, 9);
			for( py in (-r)...(r+1) )
			for( px in (-r)...(r+1) )
					if( px*px + py*py <= r*r )
						parts.push({ ox:ox+px, oy:oy+py });
			}
			clouds.push({ cx:rng.nextInt(0, mapData.width), cy:rng.nextInt(0, mapData.height), parts:parts });
		}
	}

	function animate(?_) {
		if( baseImgData==null || mapData==null || params==null )
			return;

		var renderImgData = ctx.createImageData(mapData.width, mapData.height);
		untyped renderImgData.data.set(baseImgData.data);
		var data = renderImgData.data;
		if( params.showClouds )
			drawClouds(data);
		applyPostProcessing(data);
		ctx.putImageData(renderImgData, 0, 0);
		drawVectorOverlays();
		animationId = Browser.window.requestAnimationFrame(animate);
	}

	function drawClouds(data:js.lib.Uint8ClampedArray) {
		var w = mapData.width;
		var h = mapData.height;
		for( cloud in clouds ) {
			var cx = wrapInt(Math.floor(cloud.cx - cloudOffset), w);
			for( p in cloud.parts ) {
				var sx = wrapInt(cx + p.ox + 18, w);
				var sy = cloud.cy + p.oy + 18;
				var tile = mapData.getTile(sx, sy);
				if( sy>=0 && sy<h && tile!=null && !tile.walkable )
					setPixel(data, w, sx, sy, colors.cloudShadow);
			}

			var minY = 9999;
			var maxY = -9999;
			for( p in cloud.parts ) {
				minY = Std.int(Math.min(minY, p.oy));
				maxY = Std.int(Math.max(maxY, p.oy));
			}
			var midY = minY + (maxY-minY)*0.6;
			for( p in cloud.parts ) {
				var px = wrapInt(cx + p.ox, w);
				var py = cloud.cy + p.oy;
				if( py>=0 && py<h ) {
					var bottom = p.oy > midY + Math.sin(p.ox*0.5)*2;
					setPixel(data, w, px, py, bottom ? colors.cloudBot : colors.cloudTop);
				}
			}
		}
		cloudOffset += 0.2 * windSpeed;
	}

	function applyPostProcessing(data:js.lib.Uint8ClampedArray) {
		if( params.saturation==1 && params.sepia<=0 && params.vignette<=0 && params.scanlines<=0 )
			return;
		var w = mapData.width;
		var h = mapData.height;
		for( y in 0...h ) {
			var dy = params.vignette>0 ? y/h - 0.5 : 0;
			for( x in 0...w ) {
				var idx = (y*w+x)*4;
				var r:Float = data[idx];
				var g:Float = data[idx+1];
				var b:Float = data[idx+2];

				if( params.scanlines>0 && y%2==0 ) {
					var fade = 1 - params.scanlines*0.5;
					r *= fade;
					g *= fade;
					b *= fade;
				}

				if( params.saturation!=1 ) {
					var lum = 0.299*r + 0.587*g + 0.114*b;
					r = lum + (r-lum)*params.saturation;
					g = lum + (g-lum)*params.saturation;
					b = lum + (b-lum)*params.saturation;
				}

				if( params.sepia>0 ) {
					var tr = r*0.393 + g*0.769 + b*0.189;
					var tg = r*0.349 + g*0.686 + b*0.168;
					var tb = r*0.272 + g*0.534 + b*0.131;
					r = r*(1-params.sepia) + tr*params.sepia;
					g = g*(1-params.sepia) + tg*params.sepia;
					b = b*(1-params.sepia) + tb*params.sepia;
				}

				if( params.vignette>0 ) {
					var dx = x/w - 0.5;
					var dist = Math.sqrt(dx*dx + dy*dy) * 2;
					var fade = Math.max(0, 1 - dist*params.vignette);
					r *= fade;
					g *= fade;
					b *= fade;
				}

				data[idx] = clampColor(Math.round(r));
				data[idx+1] = clampColor(Math.round(g));
				data[idx+2] = clampColor(Math.round(b));
			}
		}
	}

	function drawVectorOverlays() {
		if( params.showRoutes )
			drawRoutes();
		if( params.showSettlements )
			for( city in mapData.cities )
				drawCity(city);
		if( params.showPointsOfInterest )
			for( point in mapData.pointsOfInterest )
				drawPointOfInterest(point);
		drawActiveLocation();
		drawBorderHighlight();
		drawIslandHighlight(activeIslandId, "rgba(255, 32, 32, 0.9)", 1.5, true);
		if( selectedIslandId!=null && selectedIslandId!=activeIslandId )
			drawIslandHighlight(selectedIslandId, "rgba(255, 210, 60, 0.95)", 2, false);
	}

	function drawRoutes() {
		for( route in mapData.routes ) {
			if( route.points.length<2 )
				continue;
			var active = activeLocation!=null && (sameLocation(route.from, activeLocation) || sameLocation(route.to, activeLocation));
			ctx.save();
			ctx.lineCap = "round";
			ctx.lineJoin = "round";
			ctx.setLineDash(active ? [4, 2] : [2, 3]);
			ctx.strokeStyle = active ? "rgba(255, 245, 185, 0.95)" : "rgba(255, 255, 255, 0.42)";
			ctx.lineWidth = active ? 2 : 1;
			ctx.beginPath();
			ctx.moveTo(route.points[0].x+0.5, route.points[0].y+0.5);
			if( route.points.length==2 )
				ctx.lineTo(route.points[1].x+0.5, route.points[1].y+0.5);
			else {
			for( i in 1...(route.points.length-1) ) {
					var cur = route.points[i];
					var next = route.points[i+1];
					ctx.quadraticCurveTo(cur.x+0.5, cur.y+0.5, (cur.x+next.x)/2+0.5, (cur.y+next.y)/2+0.5);
				}
				var last = route.points[route.points.length-1];
				ctx.lineTo(last.x+0.5, last.y+0.5);
			}
			ctx.stroke();
			ctx.restore();
		}
	}

	function drawCity(city:Settlement) {
		ctx.save();
		ctx.fillStyle = city.kind=="capital" ? "rgba(255, 245, 170, 0.98)" : "rgba(255, 218, 96, 0.95)";
		ctx.strokeStyle = "rgba(60, 35, 10, 0.9)";
		ctx.lineWidth = 1;
		ctx.beginPath();
		ctx.arc(city.x+0.5, city.y+0.5, city.kind=="capital" ? 3 : 2.2, 0, Math.PI*2);
		ctx.fill();
		ctx.stroke();
		ctx.restore();
	}

	function drawPointOfInterest(point:PointOfInterest) {
		var r = point.rarity>=3 ? 3 : 2.4;
		ctx.save();
		ctx.fillStyle = point.rarity>=3 ? "rgba(255, 120, 150, 0.96)" : "rgba(218, 90, 120, 0.92)";
		ctx.strokeStyle = "rgba(45, 8, 18, 0.9)";
		ctx.lineWidth = 1;
		ctx.beginPath();
		ctx.moveTo(point.x+0.5, point.y+0.5-r);
		ctx.lineTo(point.x+0.5+r, point.y+0.5);
		ctx.lineTo(point.x+0.5, point.y+0.5+r);
		ctx.lineTo(point.x+0.5-r, point.y+0.5);
		ctx.closePath();
		ctx.fill();
		ctx.stroke();
		ctx.restore();
	}

	function drawActiveLocation() {
		if( activeLocation==null )
			return;
		var name:Null<String> = null;
		var kind:Null<String> = null;
		var x = 0;
		var y = 0;
		var isCity = activeLocation.type=="city";
		if( isCity && params.showSettlements )
			for( city in mapData.cities )
				if( city.id==activeLocation.id ) {
					name = city.name;
					kind = switch city.kind { case "capital": "Stolica"; case "port": "Port"; case "fort": "Fort"; case _: "Miasto"; }
					x = city.x;
					y = city.y;
					break;
				}
		if( !isCity && params.showPointsOfInterest )
			for( point in mapData.pointsOfInterest )
				if( point.id==activeLocation.id ) {
					name = point.name;
					kind = switch point.kind {
						case "blackCove": "Czarna zatoka";
						case "treasureSite": "Skarb";
						case "pirateHaven": "Piracka przystan";
						case "lostMission": "Opuszczona misja";
						case "smugglerCamp": "Oboz przemytnikow";
						case "ancientRuins": "Starozytne ruiny";
						case _: "POI";
					}
					x = point.x;
					y = point.y;
					break;
				}
		if( name==null || kind==null )
			return;

		ctx.save();
		ctx.strokeStyle = "rgba(255, 255, 220, 0.95)";
		ctx.lineWidth = 1.5;
		ctx.beginPath();
		ctx.arc(x+0.5, y+0.5, isCity ? 4.2 : 4.8, 0, Math.PI*2);
		ctx.stroke();
		drawLabel(name+" - "+kind, x+0.5, Math.max(12, y-8), isCity ? "rgba(255, 220, 80, 0.95)" : "rgba(255, 120, 150, 0.95)");
		ctx.restore();
	}

	function drawBorderHighlight() {
		if( activeBorderHighlight==null )
			return;
		var ew = Math.floor(mapData.width * 0.18);
		var eh = Math.floor(mapData.height * 0.18);
		ctx.save();
		ctx.strokeStyle = "rgba(255, 44, 44, 0.9)";
		ctx.lineWidth = 2;
		ctx.setLineDash([4, 4]);
		ctx.beginPath();
		switch activeBorderHighlight {
			case "north": ctx.moveTo(0, eh); ctx.lineTo(mapData.width, eh);
			case "south": ctx.moveTo(0, mapData.height-eh); ctx.lineTo(mapData.width, mapData.height-eh);
			case "east": ctx.moveTo(mapData.width-ew, 0); ctx.lineTo(mapData.width-ew, mapData.height);
			case "west": ctx.moveTo(ew, 0); ctx.lineTo(ew, mapData.height);
			case _:
		}
		ctx.stroke();
		ctx.restore();
	}

	function drawIslandHighlight(id:Null<Int>, stroke:String, width:Float, label:Bool) {
		if( id==null )
			return;
		var island:Null<IslandRegion> = null;
		for( item in mapData.islands )
			if( item.id==id ) {
				island = item;
				break;
			}
		if( island==null )
			return;

		ctx.save();
		ctx.strokeStyle = stroke;
		ctx.lineWidth = width;
		ctx.setLineDash([5, 3]);
		ctx.beginPath();
		for( segment in island.borderSegments ) {
			ctx.moveTo(segment.x1, segment.y1);
			ctx.lineTo(segment.x2, segment.y2);
		}
		ctx.stroke();
		ctx.setLineDash([]);
		if( label )
			drawLabel(island.name, island.center.x, Math.max(12, island.bounds.minY-4), "rgba(255, 64, 64, 0.9)");
		ctx.restore();
	}

	function drawLabel(label:String, x:Float, y:Float, stroke:String) {
		var fontSize = Math.max(10, Math.min(16, Math.floor(mapData.width / 48)));
		ctx.font = 'bold ${fontSize}px serif';
		ctx.textAlign = "center";
		ctx.textBaseline = "middle";
		var metrics = ctx.measureText(label);
		var boxW = metrics.width + 10;
		var boxH = fontSize + 6;
		var boxX = Math.max(2, Math.min(mapData.width-boxW-2, x-boxW/2));
		var boxY = Math.max(2, Math.min(mapData.height-boxH-2, y-boxH/2));
		ctx.fillStyle = "rgba(18, 12, 6, 0.82)";
		ctx.fillRect(boxX, boxY, boxW, boxH);
		ctx.strokeStyle = stroke;
		ctx.lineWidth = 1;
		ctx.strokeRect(boxX, boxY, boxW, boxH);
		ctx.fillStyle = "rgba(255, 238, 190, 0.98)";
		ctx.fillText(label, boxX+boxW/2, boxY+boxH/2);
	}

	function isCoastalEdge(x:Int, y:Int):Bool {
		for( offset in [{x:-1,y:0}, {x:1,y:0}, {x:0,y:-1}, {x:0,y:1}] ) {
			var t = mapData.getTile(x+offset.x, y+offset.y);
			if( t!=null && !t.walkable )
				return true;
		}
		return false;
	}

	inline function sameLocation(a:LocationRef, b:ActiveLocation):Bool return a.type==b.type && a.id==b.id;

	static inline function setPixel(data:js.lib.Uint8ClampedArray, width:Int, x:Int, y:Int, color:Rgb) {
		var idx = (y*width+x)*4;
		data[idx] = color.r;
		data[idx+1] = color.g;
		data[idx+2] = color.b;
		data[idx+3] = 255;
	}

	static inline function clampColor(v:Int):Int return Std.int(Math.max(0, Math.min(255, v)));

	static function hashRand(x:Int, y:Int):Float {
		var v = Math.sin(x*12.9898 + y*78.233) * 43758.5453;
		return v - Math.floor(v);
	}

	static inline function wrapInt(v:Int, max:Int):Int {
		var out = v % max;
		return out<0 ? out+max : out;
	}
}
