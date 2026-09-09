import { Button } from "../components/primitives";
import { useNav, type FileInfo } from "../state/nav";

export const SEND_FILE: FileInfo = {
  name: "Project Presentation.pdf",
  size: "24.8 MB",
  bytes: 24.8 * 1024 ** 2,
};

export function SendScreen() {
  const go = useNav((s) => s.go);
  const startTransfer = useNav((s) => s.startTransfer);

  return (
    <div className="flex w-full max-w-sm mx-auto flex-col items-center justify-center gap-6 p-8">
      <div className="flex size-20 items-center justify-center rounded-card border border-line bg-surface">
        <svg viewBox="0 0 24 24" className="size-9 text-accent" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><polyline points="14 2 14 8 20 8" /></svg>
      </div>

      <div className="text-center">
        <h1 className="text-[20px] font-semibold tracking-tight text-ink">{SEND_FILE.name}</h1>
        <p className="mt-1 text-[13px] text-ink-2">{SEND_FILE.size}</p>
      </div>

      <div className="flex w-full items-center gap-3 rounded-card border border-line bg-surface p-4">
        <span className="text-[13px] text-ink-2">Sending to</span>
        <svg viewBox="0 0 24 24" className="size-4 text-ink-2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="7" y="2" width="10" height="20" rx="2" /><line x1="12" y1="18" x2="12.01" y2="18" /></svg>
        <span className="text-[14px] font-medium text-ink">Afras's Phone</span>
      </div>

      <div className="flex w-full flex-col gap-2">
        <Button onClick={() => startTransfer("send", SEND_FILE)}>Send file</Button>
        <Button variant="secondary" onClick={() => go("home")}>Cancel</Button>
      </div>
    </div>
  );
}