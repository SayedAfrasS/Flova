/**
 * WORKFLOW OF THIS FILE:
 * 1. Shows live progress for the active transfer (sending or receiving).
 * 2. Bytes accumulate in refs; speed math runs in the IPC event handler.
 * 3. RESUME: when a transfer start event carries "resumed" bytes (a transfer
 *    continuing after reconnect), the counters seed from that value so the
 *    ring opens at e.g. 61% and climbs from there instead of restarting.
 * 4. While receiving, at 100% the subtitle shows "Checking file..." until
 *    the hash verdict arrives, then navigates to Complete.
 */
import { useEffect, useRef, useState } from "react";
import { Button } from "../components/primitives";
import { useNav } from "../state/nav";

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
        <circle cx="100" cy="100" r={R} fill="none" stroke="#2563EB" strokeWidth="10" strokeLinecap="round"
          strokeDasharray={C} strokeDashoffset={C * (1 - pct / 100)}
          style={{ transition: "stroke-dashoffset 120ms linear" }} />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center">
        <span className="text-[40px] font-semibold tracking-tight text-ink">{pct}%</span>
      </div>
    </div>
  );
}

export function ProgressScreen() {
  const go = useNav((s) => s.go);
  const [fileName, setFileName] = useState("Preparing...");
  const [transferred, setTransferred] = useState(0);
  const [totalBytes, setTotalBytes] = useState(0);
  const [isSending, setIsSending] = useState(true);
  const [speed, setSpeed] = useState(0);

  const bytesRef = useRef(0);
  const windowStartRef = useRef(Date.now());
  const windowBytesRef = useRef(0);

  useEffect(() => {
    if (!window.flova) return;
    let cancelled = false;

    window.flova.getCurrentTransfer().then((t) => {
      if (cancelled || !t) return;
      const seed = t.resumed ?? 0;
      bytesRef.current = seed; windowBytesRef.current = seed; windowStartRef.current = Date.now();
      setTransferred(seed);
      setFileName(t.name); setTotalBytes(t.size); setIsSending(t.isSending);
    });

    const offStart = window.flova.onFileTransferStart(({ name, size, isSending: sending, resumed }) => {
      const seed = resumed ?? 0;
      bytesRef.current = seed; windowBytesRef.current = seed; windowStartRef.current = Date.now();
      setTransferred(seed); setSpeed(0);
      setFileName(name); setTotalBytes(size); setIsSending(sending);
    });

    const offProgress = window.flova.onFileProgress(({ bytes }) => {
      bytesRef.current += bytes;
      const now = Date.now();
      const dt = (now - windowStartRef.current) / 1000;
      if (dt >= 0.5) {
        const delta = bytesRef.current - windowBytesRef.current;
        setSpeed(delta / dt);
        windowStartRef.current = now;
        windowBytesRef.current = bytesRef.current;
      }
      setTransferred(bytesRef.current);
    });

    const offDone = window.flova.onFileDone(() => {
      setTimeout(() => go("complete"), 500);
    });

    return () => { cancelled = true; offStart(); offProgress(); offDone(); };
  }, [go]);

  const pct = totalBytes > 0 ? Math.min(100, Math.round((transferred / totalBytes) * 100)) : 0;
  const checking = !isSending && totalBytes > 0 && transferred >= totalBytes;
  const secondsLeft = speed > 0 ? Math.max(1, Math.round((totalBytes - transferred) / speed)) : 0;

  return (
    <div className="flex w-full max-w-2xl mx-auto flex-col items-center justify-center gap-8 p-8">
      <header className="text-center">
        <h1 className="text-[20px] font-semibold tracking-tight text-ink">
          {isSending ? "Sending file" : "Receiving file"}
        </h1>
        <p className="mt-1 text-[14px] text-ink-2">{fileName}</p>
      </header>

      <Ring pct={pct} />

      <div className="space-y-1 text-center">
        <p className="text-[14px] text-ink">{formatBytes(transferred)} of {formatBytes(totalBytes)}</p>
        <p className="text-[13px] text-ink-2">{speed > 0 && !checking ? `${formatBytes(speed)}/s` : ""}</p>
        <p className="text-[13px] text-ink-3">
          {checking ? "Checking file..." : speed > 0 ? `About ${secondsLeft} seconds left` : ""}
        </p>
      </div>

      <Button variant="ghost" onClick={() => go("home")}>Cancel</Button>
    </div>
  );
}