export function MapLegend({ visible }: { visible: boolean }) {
    if (!visible) return null;

    return (
        <div className="absolute top-4 right-4 glass-panel p-4 border border-white/10 rounded font-mono text-xs text-slate-300 grid gap-2 z-10 shadow-2xl">
            <div className="flex items-center"><div className="w-3.5 h-3.5 mr-2 rounded-sm border border-white/20" style={{background:'#082654'}}></div> Deep Sea</div>
            <div className="flex items-center"><div className="w-3.5 h-3.5 mr-2 rounded-sm border border-white/20" style={{background:'#2378ad'}}></div> Shallows</div>
            <div className="flex items-center"><div className="w-3.5 h-3.5 mr-2 rounded-sm border border-white/20" style={{background:'#165391'}}></div> Reefs (Hazards)</div>
            <div className="flex items-center"><div className="w-3.5 h-3.5 mr-2 rounded-sm border border-white/20" style={{background:'#d7b56d'}}></div> Beach / Sand</div>
            <div className="flex items-center"><div className="w-3.5 h-3.5 mr-2 rounded-sm border border-white/20" style={{background:'#708a34'}}></div> Plains</div>
            <div className="flex items-center"><div className="w-3.5 h-3.5 mr-2 rounded-sm border border-white/20" style={{background:'#203b16'}}></div> Forest</div>
            <div className="flex items-center"><div className="w-3.5 h-3.5 mr-2 rounded-sm border border-white/20" style={{background:'#827038'}}></div> Hills</div>
            <div className="flex items-center"><div className="w-3.5 h-3.5 mr-2 rounded-sm border border-white/20" style={{background:'#b99768'}}></div> Mountains</div>
            <div className="flex items-center"><div className="w-3.5 h-0.5 mr-2 rounded-sm border border-white/20 bg-white"></div> Trade Route</div>
        </div>
    );
}
