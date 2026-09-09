import { Button } from "../components/primitives";
import { useNav, type FileInfo } from "../state/nav";

const INCOMING_FILE: FileInfo = {
  name: "Beach Photos.zip",
  size: "148 MB",
  bytes: 148 * 1024 ** 2,
};

export function ReceiveScreen() {
  const go = useNav((s) => s.go);
  const startTransfer = useNav((s) => s.startTransfer);

  return (
    <div className="flex w-full max-w-sm mx-auto flex-col items-center justify-center gap-6 p-8">
      <div className="text-center">
        <h1 className="text-[28px] font-semibold tracking-tight text-ink">Incoming file</h1>
        <p className="mt-2 text-[14px] text-ink-2">Nothing is saved until you accept.</p>
      </div>

      <div className="flex w-full items-center gap-4 rounded-card border border-line bg-surface p-4">
        <div className="flex size-11 items-center justify-center rounded-control bg-section">
          <svg viewBox="0 0 24 24" className="size-5 text-ink-2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><polyline points="14 2 14 8 20 8" /></svg>
        </div>
        <div className="flex-1">
          <p className="text-[14px] font-medium text-ink">{INCOMING_FILE.name}</p>
          <p className="text-[12px] text-ink-3">{INCOMING_FILE.size}</p>
        </div>
      </div>

      <p className="text-[13px] text-ink-2">From Afras's Phone</p>

      <div className="flex w-full flex-col gap-2">
        <Button onClick={() => startTransfer("receive", INCOMING_FILE)}>Accept</Button>
        <Button variant="secondary" onClick={() => go("home")}>Decline</Button>
      </div>
    </div>
  );
}