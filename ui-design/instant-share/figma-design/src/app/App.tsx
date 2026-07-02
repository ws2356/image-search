import { useState, useEffect } from "react";
import { clsx } from "clsx";
import {
  Check, X, Copy, Share2, FolderOpen, AlertTriangle,
  Wifi, RefreshCw, Download, ChevronRight,
} from "lucide-react";

// ─── Flow / State Config ────────────────────────────────────────────────────

type FlowKey = "m2p" | "p2m" | "global";

const FLOWS = {
  m2p: {
    label: "Mobile → PC",
    states: [
      { id: "m2p-empty",     label: "Device Selector — Empty",    mobile: "sel-empty",    pc: "pc-idle"      },
      { id: "m2p-scan",      label: "Device Selector — Scanning", mobile: "sel-scanning", pc: "pc-idle"      },
      { id: "m2p-found",     label: "Device Selector — Found",    mobile: "sel-found",    pc: "pc-idle"      },
      { id: "m2p-pin",       label: "PIN Verification",           mobile: "m-pin",        pc: "pc-pin"       },
      { id: "m2p-done-file", label: "Complete — Image / File",    mobile: "m-sent",       pc: "pc-recv-file" },
      { id: "m2p-done-text", label: "Complete — Text",            mobile: "m-sent",       pc: "pc-recv-text" },
    ],
  },
  p2m: {
    label: "PC → Mobile",
    states: [
      { id: "p2m-qr",    label: "QR Code Window",         mobile: "m-waiting",    pc: "pc-qr"     },
      { id: "p2m-text",  label: "Received — Text",        mobile: "m-recv-text",  pc: "pc-closed" },
      { id: "p2m-image", label: "Received — Images",      mobile: "m-recv-image", pc: "pc-closed" },
      { id: "p2m-files", label: "Received — Files",       mobile: "m-recv-files", pc: "pc-closed" },
    ],
  },
  global: {
    label: "Global",
    states: [
      { id: "global-loading", label: "Loading State", mobile: "m-loading", pc: "pc-qr"    },
      { id: "global-error",   label: "Error State",   mobile: "m-error",   pc: "pc-error" },
    ],
  },
};

// ─── QR Code ───────────────────────────────────────────────────────────────

function makeQRGrid(n = 25): boolean[][] {
  const g: boolean[][] = Array.from({ length: n }, () => Array(n).fill(false));
  const finder = (ox: number, oy: number) => {
    for (let y = 0; y < 7; y++)
      for (let x = 0; x < 7; x++)
        g[oy + y][ox + x] =
          y === 0 || y === 6 || x === 0 || x === 6 ||
          (y >= 2 && y <= 4 && x >= 2 && x <= 4);
  };
  finder(0, 0); finder(18, 0); finder(0, 18);
  for (let i = 8; i < 17; i++) { g[6][i] = i % 2 === 0; g[i][6] = i % 2 === 0; }
  for (let dy = -2; dy <= 2; dy++)
    for (let dx = -2; dx <= 2; dx++)
      g[18 + dy][18 + dx] = Math.abs(dy) === 2 || Math.abs(dx) === 2 || (dy === 0 && dx === 0);
  let s = 0xdeadbeef >>> 0;
  const rand = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
  const isFixed = (x: number, y: number) =>
    (x <= 7 && y <= 7) || (x >= 17 && y <= 7) || (x <= 7 && y >= 17) ||
    x === 6 || y === 6 || (x >= 16 && x <= 20 && y >= 16 && y <= 20);
  for (let y = 0; y < n; y++)
    for (let x = 0; x < n; x++)
      if (!isFixed(x, y)) g[y][x] = rand() > 0.46;
  return g;
}

const QR_GRID = makeQRGrid();

function QRCodeSVG({ size = 180 }: { size?: number }) {
  const m = size / 25;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} shapeRendering="crispEdges">
      {QR_GRID.flatMap((row, y) =>
        row.map((on, x) =>
          on ? <rect key={`${x}-${y}`} x={x * m} y={y * m} width={m} height={m} fill="currentColor" /> : null
        )
      )}
    </svg>
  );
}

// ─── Photo Thumbnails ──────────────────────────────────────────────────────

const PHOTO_STOPS: [string, string][] = [
  ["#667eea", "#764ba2"],
  ["#f6d365", "#fda085"],
  ["#a1c4fd", "#c2e9fb"],
  ["#84fab0", "#8fd3f4"],
  ["#fbc2eb", "#a18cd1"],
  ["#ffecd2", "#fcb69f"],
  ["#a1ffce", "#faffd1"],
  ["#d4fc79", "#96e6a1"],
  ["#f093fb", "#f5576c"],
];

function PhotoThumb({
  index, selected, onClick,
}: { index: number; selected: boolean; onClick: () => void }) {
  const [a, b] = PHOTO_STOPS[index % PHOTO_STOPS.length];
  return (
    <div
      onClick={onClick}
      className={clsx(
        "relative aspect-square cursor-pointer overflow-hidden transition-all duration-150",
        selected
          ? "ring-[2.5px] ring-blue-500 ring-offset-[2px] ring-offset-white"
          : "ring-0"
      )}
      style={{ background: `linear-gradient(140deg, ${a}, ${b})` }}
    >
      <div className="absolute bottom-1.5 left-1.5">
        <div
          className={clsx(
            "w-[18px] h-[18px] rounded-full border-[1.5px] flex items-center justify-center transition-all",
            selected
              ? "bg-blue-500 border-blue-500"
              : "bg-black/20 border-white/80 backdrop-blur-sm"
          )}
        >
          {selected && <Check size={10} className="text-white" strokeWidth={3} />}
        </div>
      </div>
    </div>
  );
}

// ─── Shared sub-components ─────────────────────────────────────────────────

function SharePayloadBadge({ name, meta }: { name: string; meta: string }) {
  return (
    <div className="bg-slate-50 border border-slate-100 rounded-2xl p-3 flex items-center gap-3 mb-5">
      <div className="w-11 h-11 bg-blue-50 border border-blue-100 rounded-xl flex items-center justify-center flex-shrink-0">
        <svg className="w-5 h-5 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909m-18 3.75h16.5a1.5 1.5 0 001.5-1.5V6a1.5 1.5 0 00-1.5-1.5H3.75A1.5 1.5 0 002.25 6v12a1.5 1.5 0 001.5 1.5zm10.5-11.25h.008v.008h-.008V8.25zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z" />
        </svg>
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold text-slate-800 truncate">{name}</p>
        <p className="text-xs text-slate-400 mt-0.5">{meta}</p>
      </div>
    </div>
  );
}

function Spinner({ size = 16, className = "" }: { size?: number; className?: string }) {
  return (
    <div
      className={clsx("rounded-full border-2 border-t-transparent animate-spin flex-shrink-0", className)}
      style={{ width: size, height: size }}
    />
  );
}

// ─── Mobile Screens ────────────────────────────────────────────────────────

function MSelEmpty() {
  return (
    <div className="absolute inset-0 bg-white flex flex-col">
      <div className="absolute inset-0 bg-slate-900/40 flex items-center justify-center">
        <p className="text-white/20 text-xs">App content</p>
      </div>
      <div className="mt-auto bg-white rounded-t-[28px] shadow-[0_-12px_48px_-5px_rgba(0,0,0,0.18)] px-5 pt-3 pb-7 flex flex-col z-10">
        <div className="w-10 h-[4px] bg-slate-200 rounded-full mx-auto mb-5" />
        <SharePayloadBadge name="vacation_photo.jpg" meta="2.4 MB · Ready to share" />
        <div className="flex items-center justify-between mb-3">
          <span className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">Send To</span>
          <span className="text-[11px] bg-slate-100 text-slate-400 px-2 py-0.5 rounded-full font-medium">0 found</span>
        </div>
        <div className="border-2 border-dashed border-slate-200 rounded-2xl py-7 px-5 flex flex-col items-center text-center mb-5 bg-slate-50/60">
          <Wifi size={22} className="text-slate-300 mb-2" />
          <p className="text-xs font-semibold text-slate-500">No Devices Found</p>
          <p className="text-[11px] text-slate-400 mt-1 max-w-[170px]">Open Instant Share on your Mac to appear here</p>
        </div>
        <button className="w-full bg-slate-200 text-slate-400 font-semibold py-3.5 rounded-xl text-sm cursor-not-allowed">
          Send
        </button>
      </div>
    </div>
  );
}

function MSelScanning() {
  return (
    <div className="absolute inset-0 bg-white flex flex-col">
      <div className="absolute inset-0 bg-slate-900/40 flex items-center justify-center">
        <p className="text-white/20 text-xs">App content</p>
      </div>
      <div className="mt-auto bg-white rounded-t-[28px] shadow-[0_-12px_48px_-5px_rgba(0,0,0,0.18)] px-5 pt-3 pb-7 flex flex-col z-10">
        <div className="w-10 h-[4px] bg-slate-200 rounded-full mx-auto mb-5" />
        <SharePayloadBadge name="vacation_photo.jpg" meta="2.4 MB · Ready to share" />
        <div className="flex items-center justify-between mb-3">
          <span className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">Send To</span>
          <span className="text-[11px] bg-blue-50 text-blue-600 px-2 py-0.5 rounded-full font-semibold animate-pulse">Scanning…</span>
        </div>
        <div className="border border-slate-100 rounded-2xl px-4 py-4 flex items-center gap-3 mb-5 bg-slate-50/70">
          <Spinner size={16} className="border-blue-500" />
          <p className="text-xs text-slate-500 font-medium">Searching local network…</p>
        </div>
        <button className="w-full bg-slate-200 text-slate-400 font-semibold py-3.5 rounded-xl text-sm cursor-not-allowed">
          Send
        </button>
      </div>
    </div>
  );
}

function MSelFound() {
  return (
    <div className="absolute inset-0 bg-white flex flex-col">
      <div className="absolute inset-0 bg-slate-900/40 flex items-center justify-center">
        <p className="text-white/20 text-xs">App content</p>
      </div>
      <div className="mt-auto bg-white rounded-t-[28px] shadow-[0_-12px_48px_-5px_rgba(0,0,0,0.18)] px-5 pt-3 pb-7 flex flex-col z-10">
        <div className="w-10 h-[4px] bg-slate-200 rounded-full mx-auto mb-5" />
        <SharePayloadBadge name="vacation_photo.jpg" meta="2.4 MB · Ready to share" />
        <div className="flex items-center justify-between mb-3">
          <span className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">Send To</span>
          <span className="text-[11px] bg-emerald-50 text-emerald-600 px-2 py-0.5 rounded-full font-semibold">1 found</span>
        </div>
        <button className="border-2 border-blue-500 bg-blue-50/40 rounded-2xl px-3.5 py-3 flex items-center gap-3 mb-5 w-full text-left hover:bg-blue-50/60 transition-colors">
          <div className="w-10 h-10 bg-blue-100 rounded-xl flex items-center justify-center flex-shrink-0">
            <svg className="w-5 h-5 text-blue-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M9 17.25v1.007a3 3 0 01-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0115 18.257V17.25m6-12V15a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 15V5.25m18 0A2.25 2.25 0 0018.75 3H5.25A2.25 2.25 0 003 5.25m18 0H3" />
            </svg>
          </div>
          <div className="flex-1 min-w-0 text-left">
            <p className="text-sm font-bold text-slate-800">MacBook Pro</p>
            <p className="text-[10px] font-mono text-slate-400 mt-0.5">192.168.1.5:60141</p>
          </div>
          <div className="w-5 h-5 bg-blue-600 rounded-full flex items-center justify-center flex-shrink-0">
            <Check size={11} className="text-white" strokeWidth={3} />
          </div>
        </button>
        <button className="w-full bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white font-semibold py-3.5 rounded-xl text-sm shadow-lg shadow-blue-600/25 transition-colors">
          Send to MacBook Pro
        </button>
      </div>
    </div>
  );
}

function MPinEntry() {
  const [digits, setDigits] = useState<string[]>([]);
  const pin = digits.slice(0, 4).join("");
  const addDigit = (d: string) => { if (pin.length < 4) setDigits(p => [...p, d]); };
  const del = () => setDigits(p => p.slice(0, -1));
  const keys = ["1","2","3","4","5","6","7","8","9","","0","del"];
  const subs: Record<string, string> = { "2":"ABC","3":"DEF","4":"GHI","5":"JKL","6":"MNO","7":"PQRS","8":"TUV","9":"WXYZ" };

  return (
    <div className="absolute inset-0 bg-white flex flex-col">
      <div className="flex-1 flex flex-col items-center justify-center px-6 text-center">
        <div className="w-14 h-14 bg-blue-50 rounded-2xl flex items-center justify-center mb-5">
          <svg className="w-7 h-7 text-blue-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
          </svg>
        </div>
        <h2 className="text-2xl font-bold text-slate-900 tracking-tight mb-1.5">Enter PIN</h2>
        <p className="text-sm text-slate-400 max-w-[210px] mb-7">Enter the 4-digit code displayed on your Mac</p>
        <div className="flex gap-3 mb-7">
          {[0, 1, 2, 3].map(i => (
            <div
              key={i}
              className={clsx(
                "w-[62px] h-[68px] rounded-2xl border-2 flex items-center justify-center text-2xl font-bold transition-all duration-150",
                i === pin.length && pin.length < 4
                  ? "border-blue-500 bg-blue-50/70 shadow-[0_0_0_4px_rgba(59,130,246,0.1)]"
                  : pin[i]
                  ? "border-slate-200 bg-white text-slate-900 shadow-sm"
                  : "border-slate-150 bg-slate-50/80 text-transparent"
              )}
            >
              {pin[i] ?? "·"}
            </div>
          ))}
        </div>
        <button
          onClick={() => setDigits([])}
          className="text-sm font-semibold text-blue-600 bg-blue-50 hover:bg-blue-100 px-5 py-2 rounded-full transition-colors"
        >
          Cancel
        </button>
      </div>
      <div className="bg-slate-50/90 border-t border-slate-100 p-2 grid grid-cols-3 gap-1.5 flex-shrink-0">
        {keys.map((k, i) => {
          if (k === "") return <div key={i} />;
          if (k === "del") return (
            <button key={i} onClick={del} className="py-3 rounded-xl flex items-center justify-center hover:bg-slate-200/60 active:bg-slate-200 transition-colors">
              <svg className="w-6 h-6 text-slate-700" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9.75L14.25 12m0 0l2.25 2.25M14.25 12l2.25-2.25M14.25 12L12 14.25m-2.58 4.92l-6.374-6.375a1.125 1.125 0 010-1.59L9.42 4.83c.211-.211.498-.33.796-.33H19.5a2.25 2.25 0 012.25 2.25v10.5a2.25 2.25 0 01-2.25 2.25h-9.284c-.298 0-.585-.119-.796-.33z" />
              </svg>
            </button>
          );
          return (
            <button
              key={i}
              onClick={() => addDigit(k)}
              className="bg-white hover:bg-slate-50 active:bg-slate-200 py-3 rounded-xl font-semibold text-xl text-slate-800 shadow-sm flex flex-col items-center justify-center gap-0.5 leading-none transition-colors"
            >
              {k}
              {subs[k] && <span className="text-[8px] text-slate-400 font-normal tracking-wider">{subs[k]}</span>}
            </button>
          );
        })}
      </div>
    </div>
  );
}

function MSent() {
  return (
    <div className="absolute inset-0 bg-white flex flex-col items-center justify-between px-6 pt-14 pb-8">
      <div className="flex-1 flex flex-col items-center justify-center text-center">
        <div className="relative mb-6">
          <div className="w-20 h-20 bg-emerald-100 rounded-full flex items-center justify-center">
            <Check size={36} className="text-emerald-600" strokeWidth={2.5} />
          </div>
          <div className="absolute -inset-3 rounded-full border border-emerald-200/60" />
        </div>
        <h2 className="text-2xl font-bold text-slate-900 tracking-tight mb-2">Sent!</h2>
        <p className="text-sm text-slate-400 max-w-[200px]">Delivered to MacBook Pro</p>
        <div className="mt-6 bg-slate-50 border border-slate-100 rounded-2xl px-4 py-2.5 flex items-center gap-2">
          <div className="w-2 h-2 bg-emerald-500 rounded-full" />
          <span className="text-xs text-slate-500 font-medium">vacation_photo.jpg · 2.4 MB</span>
        </div>
      </div>
      <button className="w-full bg-slate-900 hover:bg-slate-800 active:bg-black text-white font-semibold py-3.5 rounded-xl text-sm transition-colors">
        Done
      </button>
    </div>
  );
}

function MWaiting() {
  return (
    <div className="absolute inset-0 bg-white/95 backdrop-blur-sm flex flex-col items-center justify-center p-6 text-center">
      <div className="relative w-16 h-16 mb-6">
        <div className="absolute inset-0 rounded-full border-[3px] border-slate-100" />
        <div className="absolute inset-0 rounded-full border-[3px] border-blue-500 border-t-transparent animate-spin" />
        <div className="absolute inset-[6px] rounded-full bg-blue-50 flex items-center justify-center">
          <svg className="w-5 h-5 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M6.827 6.175A2.31 2.31 0 015.186 7.23c-.38.054-.757.112-1.134.175C2.999 7.58 2.25 8.507 2.25 9.574V18a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9.574c0-1.067-.75-1.994-1.802-2.169a47.865 47.865 0 00-1.134-.175 2.31 2.31 0 01-1.64-1.055l-.822-1.316a2.192 2.192 0 00-1.736-1.039 48.774 48.774 0 00-5.232 0 2.192 2.192 0 00-1.736 1.039l-.821 1.316z" />
          </svg>
        </div>
      </div>
      <h3 className="text-lg font-bold text-slate-900 mb-1.5">Point Camera at QR</h3>
      <p className="text-sm text-slate-400 max-w-[200px]">Scan the code shown on your Mac screen to receive content</p>
    </div>
  );
}

function MRecvText() {
  const [copied, setCopied] = useState(false);
  return (
    <div className="absolute inset-0 bg-white flex flex-col">
      <div className="px-5 py-4 border-b border-slate-100 flex items-center justify-between flex-shrink-0">
        <div>
          <h2 className="text-[15px] font-bold text-slate-900">Received</h2>
          <p className="text-[11px] text-slate-400 mt-0.5">from MacBook Pro · just now</p>
        </div>
        <span className="text-[11px] bg-blue-50 text-blue-600 font-semibold px-2.5 py-1 rounded-lg">Plain Text</span>
      </div>
      <div className="flex-1 p-4 overflow-y-auto">
        <pre className="bg-slate-50 border border-slate-100 rounded-2xl p-4 text-[12px] font-mono text-slate-700 whitespace-pre-wrap leading-relaxed">
{`x.gllue.com
Gllue
Remember me  Sign In

hire58.com.cn
谷露gllue官网 - 知名的招聘管理SaaS供
应商,致力于为企业级客户提供高度定制化
的招聘管理系统和专业的系统解决方案。
成立于2012年,总部位于上海。`}
        </pre>
      </div>
      <div className="p-4 border-t border-slate-100 flex flex-col gap-2 flex-shrink-0">
        <button
          onClick={() => { setCopied(true); setTimeout(() => setCopied(false), 2000); }}
          className={clsx(
            "w-full font-semibold py-3.5 rounded-xl flex items-center justify-center gap-2 text-sm transition-colors",
            copied ? "bg-emerald-600 text-white" : "bg-blue-600 hover:bg-blue-700 text-white shadow-sm shadow-blue-600/25"
          )}
        >
          {copied ? <Check size={15} strokeWidth={2.5} /> : <Copy size={15} />}
          {copied ? "Copied!" : "Copy to Clipboard"}
        </button>
        <button className="w-full bg-slate-100 hover:bg-slate-200 text-slate-700 font-semibold py-3 rounded-xl flex items-center justify-center gap-2 text-sm transition-colors">
          <Share2 size={15} />
          Share Content
        </button>
      </div>
    </div>
  );
}

function MRecvImage() {
  const [selected, setSelected] = useState<Set<number>>(new Set([0, 1, 2, 3, 4, 5, 6, 7, 8]));
  const total = 9;
  const toggle = (i: number) =>
    setSelected(s => { const n = new Set(s); n.has(i) ? n.delete(i) : n.add(i); return n; });

  return (
    <div className="absolute inset-0 bg-white flex flex-col">
      <div className="px-5 py-4 border-b border-slate-100 flex items-center justify-between flex-shrink-0">
        <div>
          <h2 className="text-[15px] font-bold text-slate-900">Received</h2>
          <p className="text-[11px] text-slate-400 mt-0.5">{total} images from MacBook Pro</p>
        </div>
        <button
          className="text-[12px] font-semibold text-blue-600"
          onClick={() => setSelected(selected.size === total ? new Set() : new Set(Array.from({ length: total }, (_, i) => i)))}
        >
          {selected.size === total ? "Deselect All" : "Select All"}
        </button>
      </div>

      <div className="flex-1 overflow-y-auto bg-black">
        {/* Hero row: 1 large + 2 small stacked */}
        <div className="flex gap-[1px]">
          <PhotoThumb index={0} selected={selected.has(0)} onClick={() => toggle(0)} />
          <div className="flex flex-col gap-[1px] w-1/3 flex-shrink-0">
            <PhotoThumb index={1} selected={selected.has(1)} onClick={() => toggle(1)} />
            <PhotoThumb index={2} selected={selected.has(2)} onClick={() => toggle(2)} />
          </div>
        </div>
        {/* Equal 3-column grid */}
        <div className="grid grid-cols-3 gap-[1px] mt-[1px]">
          {Array.from({ length: 6 }, (_, i) => (
            <PhotoThumb key={i + 3} index={i + 3} selected={selected.has(i + 3)} onClick={() => toggle(i + 3)} />
          ))}
        </div>
      </div>

      <div className="p-4 border-t border-slate-100 bg-white flex-shrink-0">
        {selected.size > 0 ? (
          <div className="flex gap-2">
            <button className="flex-1 bg-blue-600 text-white font-semibold py-3 rounded-xl flex items-center justify-center gap-1.5 text-sm shadow-sm shadow-blue-600/25">
              <Download size={14} />
              Save {selected.size}
            </button>
            <button className="flex-1 bg-slate-100 text-slate-700 font-semibold py-3 rounded-xl flex items-center justify-center gap-1.5 text-sm">
              <Share2 size={14} />
              Share
            </button>
          </div>
        ) : (
          <p className="text-center text-sm text-slate-400 py-1.5">Tap images to select</p>
        )}
      </div>
    </div>
  );
}

function MRecvFiles() {
  const files = [
    { name: "screenshot_monday.png", size: "63.8 KB", ext: "PNG", status: "done" as const },
    { name: "project_brief_v3.pdf",  size: "1.2 MB",  ext: "PDF", status: "syncing" as const },
    { name: "design_assets.zip",      size: "24.7 MB", ext: "ZIP", status: "queued" as const },
  ];

  return (
    <div className="absolute inset-0 bg-white flex flex-col">
      <div className="px-5 py-4 border-b border-slate-100 flex items-center justify-between flex-shrink-0">
        <div>
          <h2 className="text-[15px] font-bold text-slate-900">Received</h2>
          <p className="text-[11px] text-slate-400 mt-0.5">3 files from MacBook Pro</p>
        </div>
        <button className="text-sm font-semibold text-slate-400">Done</button>
      </div>

      <div className="flex-1 px-4 py-3 space-y-2.5 overflow-y-auto">
        <div className="bg-blue-50 border border-blue-100 rounded-xl px-4 py-2.5 flex items-center gap-2.5">
          <Spinner size={14} className="border-blue-500" />
          <p className="text-xs font-semibold text-blue-700">Receiving file 2 of 3…</p>
        </div>

        {files.map(f => (
          <div
            key={f.name}
            className={clsx(
              "bg-white border rounded-2xl p-3.5 flex items-center gap-3 transition-all",
              f.status === "done" ? "border-slate-200" :
              f.status === "syncing" ? "border-blue-200 shadow-[0_0_0_3px_rgba(59,130,246,0.06)]" :
              "border-slate-100 opacity-50"
            )}
          >
            <div className={clsx(
              "w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0",
              f.status === "done" ? "bg-emerald-50" :
              f.status === "syncing" ? "bg-blue-50" : "bg-slate-100"
            )}>
              <span className={clsx(
                "text-[9px] font-black tracking-wide",
                f.status === "done" ? "text-emerald-600" :
                f.status === "syncing" ? "text-blue-600" : "text-slate-400"
              )}>{f.ext}</span>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-xs font-semibold text-slate-800 truncate">{f.name}</p>
              <p className={clsx(
                "text-[11px] font-medium mt-0.5",
                f.status === "done" ? "text-slate-400" :
                f.status === "syncing" ? "text-blue-500 animate-pulse" : "text-slate-400"
              )}>
                {f.size} · {f.status === "done" ? "Received" : f.status === "syncing" ? "Receiving…" : "Queued"}
              </p>
            </div>
            <div className="flex-shrink-0">
              {f.status === "done" && (
                <div className="w-6 h-6 bg-emerald-100 rounded-full flex items-center justify-center">
                  <Check size={12} className="text-emerald-600" strokeWidth={3} />
                </div>
              )}
              {f.status === "syncing" && <Spinner size={16} className="border-blue-500" />}
              {f.status === "queued" && (
                <svg className="w-4 h-4 text-slate-300" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              )}
            </div>
          </div>
        ))}
      </div>

      <div className="px-4 py-3 border-t border-slate-100 flex-shrink-0">
        <div className="bg-slate-50 rounded-xl px-4 py-2.5 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Spinner size={14} className="border-slate-400" />
            <span className="text-xs text-slate-500 font-medium">Receiving 2 of 3</span>
          </div>
          <span className="text-[11px] font-mono text-slate-400">1.2 MB / 1.2 MB</span>
        </div>
      </div>
    </div>
  );
}

function MLoading() {
  return (
    <div className="absolute inset-0 bg-white/96 backdrop-blur-sm flex flex-col items-center justify-center p-6 text-center">
      <div className="relative w-16 h-16 mb-6">
        <div className="absolute inset-0 rounded-full border-[3px] border-slate-100" />
        <div className="absolute inset-0 rounded-full border-[3px] border-blue-500 border-t-transparent animate-spin" />
      </div>
      <h3 className="text-[17px] font-bold text-slate-900 mb-1.5">Connecting…</h3>
      <p className="text-sm text-slate-400 max-w-[180px]">Establishing secure connection to your Mac</p>
    </div>
  );
}

function MError() {
  return (
    <div className="absolute inset-0 bg-white/96 backdrop-blur-sm flex flex-col items-center justify-center p-6 text-center">
      <div className="w-16 h-16 bg-red-50 rounded-full flex items-center justify-center mb-5">
        <AlertTriangle size={28} className="text-red-500" />
      </div>
      <h3 className="text-[17px] font-bold text-slate-900 mb-1.5">Connection Failed</h3>
      <p className="text-sm text-slate-400 max-w-[200px] mb-7">
        Ensure both devices are on the same Wi‑Fi network and try again.
      </p>
      <button className="bg-slate-900 hover:bg-slate-800 text-white text-sm font-semibold px-6 py-2.5 rounded-xl transition-colors flex items-center gap-2">
        <RefreshCw size={14} />
        Try Again
      </button>
    </div>
  );
}

// ─── PC Screens ────────────────────────────────────────────────────────────

function PCQRCode() {
  return (
    <div className="absolute inset-0 flex flex-col p-6">
      <div className="text-center mb-4">
        <h2 className="text-xl font-bold text-slate-900 tracking-tight">Scan to Receive</h2>
        <p className="text-xs text-slate-400 mt-1">
          from <span className="font-semibold text-slate-700">MacBook-Pro.local</span>
        </p>
      </div>
      <div className="flex-1 flex items-center justify-center">
        <div className="relative">
          <div className="bg-white p-5 rounded-3xl border border-slate-200/80 shadow-[0_4px_24px_-4px_rgba(0,0,0,0.1)]">
            <div className="text-slate-900">
              <QRCodeSVG size={184} />
            </div>
          </div>
          {/* Corner accents */}
          <div className="absolute -top-1 -left-1 w-5 h-5 border-t-2 border-l-2 border-blue-500 rounded-tl-md" />
          <div className="absolute -top-1 -right-1 w-5 h-5 border-t-2 border-r-2 border-blue-500 rounded-tr-md" />
          <div className="absolute -bottom-1 -left-1 w-5 h-5 border-b-2 border-l-2 border-blue-500 rounded-bl-md" />
          <div className="absolute -bottom-1 -right-1 w-5 h-5 border-b-2 border-r-2 border-blue-500 rounded-br-md" />
        </div>
      </div>
      <div className="text-center">
        <p className="text-[11px] font-mono bg-slate-100 border border-slate-200/60 rounded-lg py-1.5 px-3 inline-block text-slate-500 mb-4">
          192.168.1.5:58686
        </p>
        <button className="w-full bg-slate-100 hover:bg-slate-200 text-slate-600 font-medium py-2.5 rounded-xl transition-colors text-sm border border-slate-200/60">
          Cancel
        </button>
      </div>
    </div>
  );
}

function PCPinDisplay() {
  return (
    <div className="absolute inset-0 flex flex-col p-6 gap-4">
      <div className="text-center pt-2">
        <div className="w-11 h-11 bg-amber-50 border border-amber-100 rounded-2xl flex items-center justify-center mx-auto mb-3.5">
          <svg className="w-5 h-5 text-amber-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
          </svg>
        </div>
        <h2 className="text-xl font-bold text-slate-900">Verify Device</h2>
        <p className="text-xs text-slate-400 mt-1.5 max-w-[240px] mx-auto">
          Enter this PIN on your iPhone to authorize the secure pairing.
        </p>
      </div>

      <div className="flex-1 flex flex-col items-center justify-center gap-5">
        <div className="font-mono text-5xl font-black tracking-[14px] text-slate-900 bg-slate-50 border border-slate-200/70 rounded-2xl py-5 px-6 shadow-inner select-all">
          3847
        </div>
        <div className="flex items-center gap-2">
          <div className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />
          <p className="text-xs text-slate-400">Waiting for PIN entry on iPhone…</p>
        </div>
        <div className="w-full bg-slate-100 rounded-full h-1 overflow-hidden">
          <div
            className="h-full bg-blue-500 rounded-full"
            style={{ width: "35%", transition: "width 1s linear" }}
          />
        </div>
      </div>

      <button className="w-full bg-slate-100 hover:bg-slate-200 text-slate-600 font-medium py-2.5 rounded-xl transition-colors text-sm border border-slate-200/60">
        Cancel Request
      </button>
    </div>
  );
}

function PCIdle() {
  return (
    <div className="absolute inset-0 flex flex-col items-center justify-center p-6 text-center">
      <div className="w-12 h-12 rounded-2xl bg-slate-100 flex items-center justify-center mb-4">
        <Wifi size={20} className="text-slate-400" />
      </div>
      <h3 className="text-sm font-semibold text-slate-700 mb-1.5">Ready to Receive</h3>
      <p className="text-xs text-slate-400 max-w-[200px]">Instant Share is listening for a nearby device connection.</p>
    </div>
  );
}

function PCRecvFile() {
  return (
    <div className="absolute inset-0 flex flex-col justify-between p-6">
      <div className="flex-1 flex flex-col items-center justify-center text-center">
        <div className="relative mb-5">
          <div className="w-14 h-14 bg-emerald-100 rounded-full flex items-center justify-center">
            <Check size={26} className="text-emerald-600" strokeWidth={2.5} />
          </div>
          <div className="absolute -inset-2 rounded-full border border-emerald-200/60" />
        </div>
        <h2 className="text-xl font-bold text-slate-900 mb-1">File Received</h2>
        <p className="text-xs text-slate-400 max-w-[220px] mt-1">Saved to your Downloads folder.</p>

        <div className="w-full max-w-[270px] mt-5 bg-slate-50 border border-slate-200 rounded-2xl p-3.5 flex items-center gap-3 text-left">
          <div className="w-10 h-10 rounded-xl bg-[linear-gradient(140deg,#a1c4fd,#c2e9fb)] flex-shrink-0 flex items-center justify-center">
            <span className="text-[8px] font-black text-blue-700">JPG</span>
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-xs font-semibold text-slate-800 truncate">vacation_photo.jpg</p>
            <p className="text-[11px] text-slate-400 mt-0.5">2.4 MB · ~/Downloads</p>
          </div>
          <ChevronRight size={14} className="text-slate-300 flex-shrink-0" />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2.5">
        <button className="bg-slate-100 hover:bg-slate-200 text-slate-700 font-medium py-2.5 rounded-xl transition-colors text-sm border border-slate-200/60">
          Close
        </button>
        <button className="bg-slate-900 hover:bg-slate-800 text-white font-medium py-2.5 rounded-xl transition-colors text-sm flex items-center justify-center gap-1.5">
          <FolderOpen size={14} />
          Show in Finder
        </button>
      </div>
    </div>
  );
}

function PCRecvText() {
  const [copied, setCopied] = useState(false);
  return (
    <div className="absolute inset-0 flex flex-col justify-between p-6">
      <div className="flex-1 flex flex-col items-center justify-center text-center">
        <div className="relative mb-5">
          <div className="w-14 h-14 bg-emerald-100 rounded-full flex items-center justify-center">
            <Check size={26} className="text-emerald-600" strokeWidth={2.5} />
          </div>
          <div className="absolute -inset-2 rounded-full border border-emerald-200/60" />
        </div>
        <h2 className="text-xl font-bold text-slate-900 mb-1">Text Received</h2>
        <p className="text-xs text-slate-400 max-w-[220px] mt-1">Ready to paste anywhere on your Mac.</p>

        <div className="w-full max-w-[280px] mt-5 bg-slate-50 border border-slate-200 rounded-2xl p-3.5 text-left">
          <p className="text-[11px] font-mono text-slate-600 leading-relaxed line-clamp-4">
            x.gllue.com · Gllue · Remember me Sign In · hire58.com.cn · 谷露gllue官网 · 知名的招聘管理SaaS供应商…
          </p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2.5">
        <button className="bg-slate-100 hover:bg-slate-200 text-slate-700 font-medium py-2.5 rounded-xl transition-colors text-sm border border-slate-200/60">
          Close
        </button>
        <button
          onClick={() => { setCopied(true); setTimeout(() => setCopied(false), 2000); }}
          className={clsx(
            "font-medium py-2.5 rounded-xl transition-colors text-sm flex items-center justify-center gap-1.5",
            copied ? "bg-emerald-600 text-white" : "bg-blue-600 hover:bg-blue-700 text-white"
          )}
        >
          {copied ? <Check size={14} strokeWidth={3} /> : <Copy size={14} />}
          {copied ? "Copied!" : "Copy Text"}
        </button>
      </div>
    </div>
  );
}

function PCClosedSuccess() {
  return (
    <div className="absolute inset-0 flex flex-col items-center justify-center p-6 text-center">
      <div className="w-12 h-12 bg-emerald-100 rounded-full flex items-center justify-center mb-3.5">
        <Check size={22} className="text-emerald-600" strokeWidth={2.5} />
      </div>
      <h3 className="text-sm font-bold text-slate-800 mb-1">Transfer Complete</h3>
      <p className="text-xs text-slate-400 max-w-[180px]">This window closed automatically after sharing completed.</p>
    </div>
  );
}

function PCError() {
  return (
    <div className="absolute inset-0 flex flex-col items-center justify-center p-6 text-center">
      <div className="w-12 h-12 bg-red-50 rounded-full flex items-center justify-center mb-3.5">
        <AlertTriangle size={22} className="text-red-500" />
      </div>
      <h3 className="text-sm font-bold text-slate-800 mb-1">Connection Lost</h3>
      <p className="text-xs text-slate-400 max-w-[200px] mb-5">
        Handshake failed. Ensure both devices are on the same Wi‑Fi network.
      </p>
      <button className="bg-slate-900 text-white text-xs font-semibold px-5 py-2.5 rounded-xl hover:bg-slate-800 transition-colors flex items-center gap-1.5">
        <RefreshCw size={12} />
        Retry
      </button>
    </div>
  );
}

// ─── Screen Renderers ──────────────────────────────────────────────────────

function renderMobile(screen: string) {
  switch (screen) {
    case "sel-empty":    return <MSelEmpty />;
    case "sel-scanning": return <MSelScanning />;
    case "sel-found":    return <MSelFound />;
    case "m-pin":        return <MPinEntry />;
    case "m-sent":       return <MSent />;
    case "m-waiting":    return <MWaiting />;
    case "m-recv-text":  return <MRecvText />;
    case "m-recv-image": return <MRecvImage />;
    case "m-recv-files": return <MRecvFiles />;
    case "m-loading":    return <MLoading />;
    case "m-error":      return <MError />;
    default:             return <MLoading />;
  }
}

function renderPC(screen: string) {
  switch (screen) {
    case "pc-qr":        return <PCQRCode />;
    case "pc-pin":       return <PCPinDisplay />;
    case "pc-idle":      return <PCIdle />;
    case "pc-recv-file": return <PCRecvFile />;
    case "pc-recv-text": return <PCRecvText />;
    case "pc-closed":    return <PCClosedSuccess />;
    case "pc-error":     return <PCError />;
    default:             return <PCIdle />;
  }
}

// ─── Device Frames ─────────────────────────────────────────────────────────

function MobilePhoneFrame({ screen }: { screen: string }) {
  const [time, setTime] = useState(() => {
    const d = new Date();
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  });
  useEffect(() => {
    const t = setInterval(() => {
      const d = new Date();
      setTime(`${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`);
    }, 30000);
    return () => clearInterval(t);
  }, []);

  return (
    <div className="flex flex-col items-center">
      <span className="text-[10px] font-semibold uppercase tracking-[0.15em] text-white/30 mb-3">Mobile</span>
      <div
        className="relative rounded-[52px] p-[10px]"
        style={{
          width: 335,
          background: "linear-gradient(160deg, #1c1c1e, #0a0a0a)",
          boxShadow: "0 40px 80px -10px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.07), inset 0 0 0 1px rgba(255,255,255,0.04)",
        }}
      >
        {/* Dynamic Island */}
        <div className="absolute top-[14px] left-1/2 -translate-x-1/2 w-[110px] h-[26px] bg-black rounded-full z-30" />

        {/* Volume / side buttons */}
        <div className="absolute left-[-3px] top-[100px] w-[3px] h-8 bg-[#2a2a2a] rounded-l-md" />
        <div className="absolute left-[-3px] top-[148px] w-[3px] h-10 bg-[#2a2a2a] rounded-l-md" />
        <div className="absolute left-[-3px] top-[196px] w-[3px] h-10 bg-[#2a2a2a] rounded-l-md" />
        <div className="absolute right-[-3px] top-[148px] w-[3px] h-14 bg-[#2a2a2a] rounded-r-md" />

        {/* Screen */}
        <div className="bg-white rounded-[42px] overflow-hidden flex flex-col" style={{ height: 680 }}>
          {/* Status bar */}
          <div className="px-7 pt-[18px] pb-2 flex justify-between items-center flex-shrink-0">
            <span className="text-[11px] font-semibold text-slate-900 font-mono">{time}</span>
            <div className="flex items-center gap-1.5">
              {/* Signal bars */}
              <div className="flex items-end gap-[2.5px]">
                {[4, 5, 7, 9].map((h, i) => (
                  <div key={i} style={{ height: h }} className="w-[3px] bg-slate-900 rounded-sm" />
                ))}
              </div>
              {/* WiFi */}
              <svg viewBox="0 0 16 12" width={14} height={10} fill="currentColor" className="text-slate-900">
                <path d="M8 2.4C5.5 2.4 3.2 3.3 1.5 5L0 3.5C2.1 1.3 5 0 8 0s5.9 1.3 8 3.5L14.5 5C12.8 3.3 10.5 2.4 8 2.4zm0 3.2C6.4 5.6 5 6.2 4 7.2L2.5 5.7C3.9 4.3 5.9 3.5 8 3.5s4.1.8 5.5 2.2L12 7.2c-1-.9-2.5-1.6-4-1.6zm0 3.2c-.9 0-1.7.3-2.3.9L8 12l2.3-2.3c-.6-.6-1.4-.9-2.3-.9z" />
              </svg>
              {/* Battery */}
              <div className="flex items-center gap-[1px]">
                <div className="w-[22px] h-[11px] border-[1.5px] border-slate-900 rounded-[3px] p-[1.5px]">
                  <div className="h-full w-[80%] bg-slate-900 rounded-[1px]" />
                </div>
                <div className="w-[2px] h-[5px] bg-slate-900 rounded-r-sm" />
              </div>
            </div>
          </div>

          {/* Screen content */}
          <div className="flex-1 relative overflow-hidden">
            {renderMobile(screen)}
          </div>

          {/* Home indicator */}
          <div className="pb-[10px] pt-1 flex justify-center flex-shrink-0">
            <div className="w-28 h-[4px] bg-slate-900/15 rounded-full" />
          </div>
        </div>
      </div>
    </div>
  );
}

function PCDialogFrame({ screen }: { screen: string }) {
  return (
    <div className="flex flex-col items-center">
      <span className="text-[10px] font-semibold uppercase tracking-[0.15em] text-white/30 mb-3">Desktop</span>
      <div
        className="bg-white rounded-2xl overflow-hidden flex flex-col"
        style={{
          width: 400,
          height: 480,
          boxShadow: "0 32px 80px -8px rgba(0,0,0,0.45), 0 0 0 1px rgba(0,0,0,0.1)",
        }}
      >
        {/* macOS title bar */}
        <div
          className="flex items-center px-4 py-3 flex-shrink-0 relative"
          style={{ background: "#f5f5f7", borderBottom: "1px solid rgba(0,0,0,0.08)" }}
        >
          <div className="flex gap-[6px] z-10">
            <div className="w-3 h-3 rounded-full bg-[#ff5f57]" style={{ boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.18)" }} />
            <div className="w-3 h-3 rounded-full bg-[#ffbd2e]" style={{ boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.18)" }} />
            <div className="w-3 h-3 rounded-full bg-[#28c840]" style={{ boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.18)" }} />
          </div>
          <div className="absolute inset-x-0 text-center">
            <span className="text-[12px] font-semibold" style={{ color: "#555" }}>Instant Share</span>
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 relative overflow-hidden">
          {renderPC(screen)}
        </div>
      </div>
    </div>
  );
}

// ─── App ───────────────────────────────────────────────────────────────────

export default function App() {
  const [flow, setFlow] = useState<FlowKey>("m2p");
  const [stateId, setStateId] = useState("m2p-empty");

  const handleFlowChange = (f: FlowKey) => {
    setFlow(f);
    setStateId(FLOWS[f].states[0].id);
  };

  const currentStates = FLOWS[flow].states;
  const currentState = currentStates.find(s => s.id === stateId) ?? currentStates[0];

  return (
    <div
      className="h-screen flex flex-col overflow-hidden"
      style={{
        fontFamily: "'DM Sans', system-ui, sans-serif",
        background: "radial-gradient(ellipse 80% 60% at 60% -10%, #1a2040 0%, #090b12 55%)",
      }}
    >
      {/* ── Header ── */}
      <header
        className="flex-shrink-0 flex items-center justify-between px-5 py-3 gap-4 flex-wrap"
        style={{
          borderBottom: "1px solid rgba(255,255,255,0.06)",
          background: "rgba(255,255,255,0.02)",
          backdropFilter: "blur(12px)",
        }}
      >
        {/* Brand */}
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 bg-blue-600 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ boxShadow: "0 0 0 1px rgba(59,130,246,0.4), 0 4px 12px rgba(59,130,246,0.3)" }}
          >
            <svg className="w-[15px] h-[15px] text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M7.5 21L3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5" />
            </svg>
          </div>
          <div>
            <h1 className="text-sm font-bold text-white/90 tracking-tight leading-none">Instant Share</h1>
            <p className="text-[10px] text-white/30 mt-0.5 leading-none">UI Specification</p>
          </div>
        </div>

        {/* Controls */}
        <div className="flex items-center gap-2.5 flex-wrap">
          {/* Flow tabs */}
          <div
            className="flex gap-0.5 p-0.5 rounded-xl"
            style={{ background: "rgba(255,255,255,0.06)", border: "1px solid rgba(255,255,255,0.06)" }}
          >
            {(Object.entries(FLOWS) as [FlowKey, (typeof FLOWS)[FlowKey]][]).map(([key, cfg]) => (
              <button
                key={key}
                onClick={() => handleFlowChange(key)}
                className={clsx(
                  "px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all",
                  flow === key
                    ? "bg-blue-600 text-white"
                    : "text-white/40 hover:text-white/70"
                )}
                style={flow === key ? { boxShadow: "0 1px 8px rgba(59,130,246,0.35)" } : undefined}
              >
                {cfg.label}
              </button>
            ))}
          </div>

          {/* State dropdown */}
          <select
            value={stateId}
            onChange={e => setStateId(e.target.value)}
            className="text-xs font-medium rounded-xl px-3 py-1.5 outline-none cursor-pointer"
            style={{
              background: "rgba(255,255,255,0.06)",
              border: "1px solid rgba(255,255,255,0.08)",
              color: "rgba(255,255,255,0.7)",
            }}
          >
            {currentStates.map(s => (
              <option key={s.id} value={s.id} style={{ background: "#13151f", color: "#d0d4e8" }}>
                {s.label}
              </option>
            ))}
          </select>
        </div>
      </header>

      {/* ── Canvas ── */}
      <main className="flex-1 flex items-center justify-center gap-14 overflow-auto p-8">
        {/* Subtle grid overlay */}
        <div
          className="absolute inset-0 pointer-events-none"
          style={{
            backgroundImage: "linear-gradient(rgba(255,255,255,0.025) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.025) 1px, transparent 1px)",
            backgroundSize: "40px 40px",
          }}
        />
        <MobilePhoneFrame screen={currentState.mobile} />
        <PCDialogFrame screen={currentState.pc} />
      </main>
    </div>
  );
}
