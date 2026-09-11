/**
 * WORKFLOW OF THIS FILE:
 * 1. Real receive screen: waits for a file-offer from the phone.
 * 2. Shows a calm waiting state until an offer arrives.
 * 3. When an offer arrives, shows name + size with Accept / Decline.
 * 4. Accept opens the disk sink in the main process, replies file-accept,
 *    and navigates to the Progress screen which tracks the real bytes.
 */
import { useEffect, useState } from "react";
import { Button } from "../components/primitives";
import { useNav } from "../state/nav";

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${Math.round(bytes / 1024)} KB`;
}

export function ReceiveScreen() {
  const go = useNav((s) => s.go);
  const [offer, setOffer] = useState<{ name: string; size: number } | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!window.flova) return;
    let cancelled = false;
    window.flova.getIncomingOffer().then((o) => { if (!cancelled && o) setOffer(o); });
    const off = window.flova.onIncomingOffer((o) => setOffer(o));
    return () => { cancelled = true; off(); };
  }, []);

  const accept = async () => {
    if (!window.flova) return;
    setBusy(true);
    await window.flova.acceptIncoming();
    go("progress");
  };

  const decline = async () => {
    if (!window.flova) return;
    await window.flova.declineIncoming();
    setOffer(null);
  };

  return (
    <div className="flex w-full max-w-sm mx-auto flex-col items-center justify-center gap-6 p-8 text-center">
      {offer === null ? (
        <>
          <div className="size-12 rounded-full border-2 border-line border-t-accent animate-spin" />
          <div>
            <h1 className="text-[20px] font-semibold tracking-tight text-ink">Waiting for file…</h1>
            <p className="mt-2 text-[14px] text-ink-2">Choose a file on your phone and send it.</p>
          </div>
          <Button variant="ghost" onClick={() => go("home")}>Back</Button>
        </>
      ) : (
        <>
          <div className="flex size-20 items-center justify-center rounded-card border border-line bg-surface">
            <svg viewBox="0 0 24 24" className="size-9 text-accent" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><polyline points="14 2 14 8 20 8" /></svg>
          </div>
          <div>
            <h1 className="text-[20px] font-semibold tracking-tight text-ink">Incoming file</h1>
            <p className="mt-1 text-[14px] text-ink">{offer.name}</p>
            <p className="text-[13px] text-ink-2">{formatBytes(offer.size)}</p>
          </div>
          <div className="flex w-full flex-col gap-2">
            <Button onClick={accept} disabled={busy}>{busy ? "Preparing…" : "Accept"}</Button>
            <Button variant="secondary" onClick={decline} disabled={busy}>Decline</Button>
          </div>
        </>
      )}
    </div>
  );
}