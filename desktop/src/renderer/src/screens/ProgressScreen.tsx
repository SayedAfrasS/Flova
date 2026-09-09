import { useEffect, useRef, useState } from "react";
import { Button } from "../components/primitives";
import { useNav } from "../state/nav";

const TOTAL_BYTES = 1.8 * 1024 ** 3;

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${Math.round(bytes / 1024)} KB`;
}

function Ring({ pct }: { pct: number }) {
  const R = 84;
  const C = 2 * Math.PI * R;
  return (
    <div className="relative size-[200px]">
      <svg viewBox="0 0 200 200" className="size-full -rotate-90">
        <circle cx="100" cy="100" r={R} fill="none" stroke="#E5E7EB" strokeWidth="10" />
        <circle
          cx="100" cy="100" r={R} fill="none" stroke="#2563EB" strokeWidth="10" strokeLinecap="round"
          strokeDasharray={C} strokeDashoffset={C * (1 - pct / 100)}
          style={{ transition: "stroke-dashoffset 120ms linear" }}
        />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center">
        <span className="text-[40px] font-semibold tracking-tight text-ink">{pct}%</span>
      </div>
    </div>
  );
}

export function ProgressScreen() {
  const go = useNav((s) => s.go);
  const [progress, setProgress] = useState(0);
  const [speed, setSpeed] = useState(45);
  const [paused, setPaused] = useState(false);
  const pausedRef = useRef(paused);
  pausedRef.current = paused;
  const doneRef = useRef(false);

  useEffect(() => {
    const id = setInterval(() => {
      if (pausedRef.current || doneRef.current) return;
      setSpeed(38 + Math.random() * 14);
      setProgress((p) => {
        const next = Math.min(1, p + 0.004 + Math.random() * 0.004);
        if (next >= 1 && !doneRef.current) {
          doneRef.current = true;
          setTimeout(() => go("complete"), 700);
        }
        return next;
      });
    }, 100);
    return () => clearInterval(id);
  }, [go]);

  const pct = Math.round(progress * 100);
  const transferred = TOTAL_BYTES * progress;
  const secondsLeft = Math.max(1, Math.round((TOTAL_BYTES - transferred) / (speed * 1024 ** 2)));

  return (
    <div className="flex w-full max-w-2xl mx-auto flex-col items-center justify-center gap-8 p-8">
      <style>{`
        @keyframes travel { 0% { left: 0%; opacity: 0 } 12% { opacity: 1 } 88% { opacity: 1 } 100% { left: 100%; opacity: 0 } }
        .dot-travel { animation: travel 1.6s cubic-bezier(0.45, 0, 0.55, 1) infinite; }
      `}</style>

      <header className="text-center">
        <div className="flex items-center justify-center gap-2">
          <svg viewBox="0 0 24 24" className="size-5 text-accent" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><polyline points="14 2 14 8 20 8" /></svg>
          <h1 className="text-[20px] font-semibold tracking-tight text-ink">Vacation Video.mp4</h1>
        </div>
        <p className="mt-1 text-[13px] text-ink-2">1.8 GB</p>
      </header>

      <Ring pct={pct} />

      <div className="flex items-center gap-5">
        <svg viewBox="0 0 24 24" className="size-7 text-ink-2" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="5" width="18" height="11" rx="1.5" /><path d="M2 19h20" /></svg>
        <div className="relative h-[2px] w-36 rounded-full bg-line">
          <span className={`dot-travel absolute top-1/2 size-2 -translate-y-1/2 rounded-full bg-accent ${paused ? "[animation-play-state:paused]" : ""}`} />
        </div>
        <svg viewBox="0 0 24 24" className="size-7 text-ink-2" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="7" y="2" width="10" height="20" rx="2" /><line x1="12" y1="18" x2="12.01" y2="18" /></svg>
      </div>

      <div className="space-y-1 text-center">
        <p className="text-[14px] text-ink">{formatBytes(transferred)} of {formatBytes(TOTAL_BYTES)}</p>
        <p className="text-[13px] text-ink-2">{paused ? "Paused" : `${Math.round(speed)} MB/s`}</p>
        <p className="text-[13px] text-ink-3">{paused ? "Transfer paused" : `About ${secondsLeft} seconds left`}</p>
      </div>

      <div className="flex items-center gap-3">
        <Button variant="secondary" onClick={() => setPaused((v) => !v)}>{paused ? "Resume" : "Pause"}</Button>
        <Button variant="ghost" onClick={() => go("home")}>Cancel</Button>
      </div>
    </div>
  );
}