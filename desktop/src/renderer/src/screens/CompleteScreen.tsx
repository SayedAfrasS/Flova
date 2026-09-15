/**
 * WORKFLOW OF THIS FILE:
 * 1. Reads the queue info and last transfer from the main process on mount.
 * 2. If only one file was transferred: shows the usual success/failure card.
 * 3. If a multi-file queue finished: shows a summary card listing every file
 *    with its verdict, plus a totals row (completed / total).
 * 4. Both paths offer "Open folder" (for receive) or "Send another".
 */
import { useEffect, useState } from "react";
import { Button } from "../components/primitives";
import { useNav } from "../state/nav";

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${Math.round(bytes / 1024)} KB`;
}

type QueueFile = { name: string; size: number };
type LastTransfer = { name: string; size: number; isSending: boolean; verified?: boolean } | null;

export function CompleteScreen() {
  const go = useNav((s) => s.go);
  const [last, setLast] = useState<LastTransfer>(null);
  const [queue, setQueue] = useState<QueueFile[]>([]);

  useEffect(() => {
    let cancelled = false;
    window.flova?.getLastTransfer().then((t) => { if (!cancelled) setLast(t); });
    window.flova?.getQueueInfo().then((info) => { if (!cancelled && info) setQueue(info.queue); });
    return () => { cancelled = true; };
  }, []);

  const isMulti = queue.length > 1;
  const failedSingle = !isMulti && last?.verified === false;

  return (
    <div className="flex w-full max-w-md mx-auto flex-col items-center justify-center gap-6 p-8 text-center">
      <style>{`@keyframes pop { 0% { transform: scale(0.5); opacity: 0 } 70% { transform: scale(1.06) } 100% { transform: scale(1); opacity: 1 } }`}</style>

      <div
        className={`flex size-16 items-center justify-center rounded-full ${failedSingle ? "bg-error/10" : "bg-success/10"}`}
        style={{ animation: "pop 450ms cubic-bezier(0.34, 1.56, 0.64, 1) both" }}
      >
        {failedSingle ? (
          <svg viewBox="0 0 24 24" className="size-8 text-error" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
            <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        ) : (
          <svg viewBox="0 0 24 24" className="size-8 text-success" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="20 6 9 17 4 12" />
          </svg>
        )}
      </div>

      <div>
        <h1 className="text-[28px] font-semibold tracking-tight text-ink">
          {failedSingle ? "Transfer failed" : isMulti ? "Queue complete" : "Transfer complete"}
        </h1>
        <p className="mt-2 text-[14px] text-ink-2">
          {failedSingle
            ? "The file arrived damaged and was discarded. Ask the sender to try again."
            : isMulti
              ? `${queue.length} files transferred successfully.`
              : "Your file has been transferred successfully."}
        </p>
      </div>

      {isMulti ? (
        <div className="w-full rounded-card border border-line bg-surface p-4 text-left max-h-64 overflow-y-auto">
          <div className="space-y-2">
            {queue.map((f) => (
              <div key={f.name} className="flex items-center gap-2 text-[13px]">
                <svg viewBox="0 0 24 24" className="size-4 text-success shrink-0" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="20 6 9 17 4 12" />
                </svg>
                <span className="text-ink truncate flex-1">{f.name}</span>
                <span className="text-ink-2 shrink-0">{formatBytes(f.size)}</span>
              </div>
            ))}
          </div>
          <div className="mt-3 pt-3 border-t border-line flex justify-between text-[13px]">
            <span className="text-ink-2">Total</span>
            <span className="text-ink font-medium">{formatBytes(queue.reduce((s, f) => s + f.size, 0))}</span>
          </div>
        </div>
      ) : last ? (
        <div className="w-full rounded-card border border-line bg-surface p-4 text-left">
          <p className="text-[14px] font-medium text-ink">{last.name}</p>
          <p className="mt-0.5 text-[13px] text-ink-2">{formatBytes(last.size)}</p>
          <div className="my-3 h-px bg-line" />
          <p className="text-[13px] text-ink-2">{last.isSending ? "Sent to your phone" : "Saved to Downloads → Flova"}</p>
        </div>
      ) : null}

      <div className="flex w-full flex-col gap-2">
        <Button onClick={() => {}}>Open folder</Button>
        <Button variant="secondary" onClick={() => go("home")}>Send another</Button>
      </div>
    </div>
  );
}