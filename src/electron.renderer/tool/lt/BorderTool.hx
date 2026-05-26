package tool.lt;

class BorderTool extends tool.LayerTool<Bool> {
	static inline var HOVER_COLOR = 0xffcc00;

	var lastEditedPointKey : Null<String>;
	var lastPaintedPoint : Null<data.DataTypes.BlockedBorderPoint>;

	public function new() {
		super();
	}

	override function getDefaultValue() : Bool {
		return true;
	}

	override function startUsing(ev:hxd.Event, m:Coords, ?extraParam:String) {
		lastEditedPointKey = null;
		lastPaintedPoint = null;
		super.startUsing(ev, m, extraParam);
	}

	inline function pointKey(gx:Int, gy:Int) {
		return gx+","+gy;
	}

	function getNearestPoint(m:Coords) : Null<data.DataTypes.BlockedBorderPoint> {
		var li = curLayerInstance;
		if( li==null || !li.def.isBorderLayer() )
			return null;

		var cx = m.cx;
		var cy = m.cy;
		if( !li.isValid(cx,cy) )
			return null;

		var localX = m.layerX - cx * li.def.gridSize;
		var localY = m.layerY - cy * li.def.gridSize;
		var lx = M.imax(0, M.imin(2, M.round(localX / li.def.gridSize * 2)));
		var ly = M.imax(0, M.imin(2, M.round(localY / li.def.gridSize * 2)));
		var gx = cx*2 + lx;
		var gy = cy*2 + ly;

		return li.isValidBorderPoint(gx,gy) ? { gx:gx, gy:gy } : null;
	}

	override function customCursor(ev:hxd.Event, m:Coords) {
		super.customCursor(ev,m);

		var pt = getNearestPoint(m);
		if( pt==null ) {
			if( editor.curLevel.inBounds(m.levelX, m.levelY) ) {
				editor.cursor.set(Forbidden);
				ev.cancel = true;
			}
			return;
		}

		editor.cursor.set(BorderPointGrid(curLayerInstance, m.cx, m.cy, pt.gx, pt.gy, HOVER_COLOR));
		ev.cancel = true;
	}

	function applyPoint(gx:Int, gy:Int) {
		var key = pointKey(gx,gy);
		if( key==lastEditedPointKey )
			return false;
		lastEditedPointKey = key;

		var changed = switch curMode {
			case null: false;
			case Add: curLayerInstance.setBlockedBorderPoint(gx, gy, true);
			case Remove: curLayerInstance.removeBlockedBorderPoint(gx, gy, true);
		}

		if( changed ) {
			var cx = M.floor(gx/2);
			var cy = M.floor(gy/2);
			editor.curLevelTimeline.markGridChange(curLayerInstance, M.imin(cx, curLayerInstance.cWid-1), M.imin(cy, curLayerInstance.cHei-1));
			editor.levelRender.invalidateLayerArea(
				curLayerInstance,
				M.imax(0, cx-1),
				M.imin(curLayerInstance.cWid-1, cx+1),
				M.imax(0, cy-1),
				M.imin(curLayerInstance.cHei-1, cy+1),
				false
			);
		}

		return changed;
	}

	override function useAt(m:Coords, isOnStop:Bool) : Bool {
		var pt = getNearestPoint(m);
		if( pt==null )
			return false;

		var anyChange = false;
		if( lastPaintedPoint==null )
			anyChange = applyPoint(pt.gx, pt.gy);
		else {
			dn.geom.Bresenham.iterateThinLine(lastPaintedPoint.gx, lastPaintedPoint.gy, pt.gx, pt.gy, (gx,gy)->{
				anyChange = applyPoint(gx,gy) || anyChange;
			});
		}

		lastPaintedPoint = pt;
		return anyChange;
	}
}
