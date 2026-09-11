/**
 * WORKFLOW OF THIS FILE:
 * 1. Reads the last finished transfer from the main process on mount.
 * 2. Shows the real file name, size, and the correct destination text:
 *    "Sent to your phone" when sending, "Saved to Downloads" when receiving.
 */
import { useEffect, useState } from "react";
import { Button } from "../components/primitives";
import { useNav } from "../state/nav";

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${Math.round(bytes / 1024)} KB`;
}

export function CompleteScreen() {
  const go = useNav((s) => s.go);
  const [info, setInfo] = useState<{ name: string; size: number; isSending: boolean } | null>(null);

  useEffect(() => {
    let cancelled = false;
    window.flova?.getLastTransfer().then((t) => { if (!cancelled && t) setInfo(t); });
    return () => { cancelled = true; };
  }, []);

  return (
    <div className="flex w-full max-w-md mx-auto flex-col items-center justify-center gap-6 p-8 text-center">
      <style>{`@keyframes pop { 0% { transform: scale(0.5); opacity: 0 } 70% { transform: scale(1.06) } 100% { transform: scale(1); opacity: 1 } }`}</style>

      <div className="flex size-16 items-center justify-center rounded-full bg-success/10"
        style={{ animation: "pop 450ms cubic-bezier(0.34, 1.56, 0.64, 1) both" }}>
        <svg viewBox="0 0 24 24" className="size-8 text-success" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12" /></svg>
      </div>

      <div>
        <h1 className="text-[28px] font-semibold tracking-tight text-ink">Transfer complete</h1>
        <p className="mt-2 text-[14px] text-ink-2">Your file has been transferred successfully.</p>
      </div>

      <div className="w-full rounded-card border border-line bg-surface p-4 text-left">
        <p className="text-[14px] font-medium text-ink">{info?.name ?? "File"}</p>
        <p className="mt-0.5 text-[13px] text-ink-2">{info ? formatBytes(info.size) : ""}</p>
        <div className="my-3 h-px bg-line" />
        <p className="text-[13px] text-ink-2">{info?.isSending ? "Sent to your phone" : "Saved to Downloads → Flova"}</p>
      </div>

      <div className="flex w-full flex-col gap-2">
        <Button onClick={() => {}}>Open folder</Button>
        <Button variant="secondary" onClick={() => go("home")}>Send another</Button>
      </div>
    </div>
  );
}