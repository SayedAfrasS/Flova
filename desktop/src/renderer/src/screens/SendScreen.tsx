/**
 * WORKFLOW OF THIS FILE:
 * 1. Lets the user pick one or multiple files using the native OS dialog.
 * 2. Shows the selected files with names and sizes.
 * 3. "Send files" queues them via sendMultipleFiles IPC and navigates to
 *    the Progress screen for the first file.
 * 4. The Progress screen tracks per-file progress and queue advancement.
 */
import { useState } from "react";
import { Button } from "../components/primitives";
import { useNav } from "../state/nav";

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${Math.round(bytes / 1024)} KB`;
}

export function SendScreen() {
  const go = useNav((s) => s.go);
  const [files, setFiles] = useState<{ path: string; name: string; size: number }[]>([]);
  const [isSending, setIsSending] = useState(false);

  const handlePick = async () => {
    if (!window.flova) return;
    const picked = await window.flova.pickMultipleFiles();
    if (picked && picked.length > 0) {
      const stats = await Promise.all(
        picked.map(async (p) => {
          const s = await window.flova.getFileStats(p);
          return s ? { path: p, name: s.name, size: s.size } : null;
        })
      );
      setFiles(stats.filter(Boolean) as { path: string; name: string; size: number }[]);
    }
  };

  const handleSend = async () => {
    if (files.length === 0 || !window.flova) return;
    setIsSending(true);
    await window.flova.sendMultipleFiles(files.map((f) => f.path));
    go("progress");
  };

  return (
    <div className="flex w-full max-w-sm mx-auto flex-col items-center justify-center gap-6 p-8">
      <div className="flex size-20 items-center justify-center rounded-card border border-line bg-surface">
        <svg viewBox="0 0 24 24" className="size-9 text-accent" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><polyline points="14 2 14 8 20 8" /></svg>
      </div>

      <div className="text-center">
        <h1 className="text-[20px] font-semibold tracking-tight text-ink">
          {files.length === 0 ? "No files selected" : `${files.length} file${files.length > 1 ? "s" : ""} selected`}
        </h1>
        {files.length > 0 && <p className="mt-1 text-[13px] text-ink-2">{formatBytes(files.reduce((s, f) => s + f.size, 0))} total</p>}
      </div>

      {files.length > 0 && (
        <div className="w-full max-h-48 overflow-y-auto rounded-card border border-line bg-surface p-3 space-y-2">
          {files.map((f) => (
            <div key={f.path} className="text-[13px] text-ink-2 truncate">
              {f.name} · {formatBytes(f.size)}
            </div>
          ))}
        </div>
      )}

      {files.length === 0 ? (
        <Button onClick={handlePick} className="w-full">Browse files</Button>
      ) : (
        <div className="flex w-full flex-col gap-2">
          <Button onClick={handleSend} disabled={isSending}>
            {isSending ? "Starting..." : "Send files"}
          </Button>
          <Button variant="secondary" onClick={() => go("home")}>Cancel</Button>
        </div>
      )}
    </div>
  );
}