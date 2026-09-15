/**
 * WORKFLOW OF THIS FILE:
 * 1. Shows the multi-file transfer queue status.
 * 2. On mount it reads the queue from the main process (name, size of each
 *    file) and the current index.
 * 3. Listens to file:done events to mark each file as completed or failed
 *    as the transfer progresses.
 * 4. Each file row shows name, size, and a status: completed (green check),
 *    in progress (blue ring), or pending (gray dot).
 * 5. "Cancel queue" aborts the entire batch and returns home.
 */
import { useEffect, useState } from "react";
import { Button } from "../components/primitives";
import { useNav } from "../state/nav";

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${Math.round(bytes / 1024)} KB`;
}

type QueueItem = {
  name: string;
  size: number;
  status: "completed" | "failed" | "active" | "pending";
};

export function QueueScreen() {
  const go = useNav((s) => s.go);
  const [items, setItems] = useState<QueueItem[]>([]);

  useEffect(() => {
    if (!window.flova) return;
    let cancelled = false;

    window.flova.getQueueInfo().then((info) => {
      if (cancelled || !info) return;
      setItems(
        info.queue.map((f, i) => ({
          name: f.name,
          size: f.size,
          status: i < info.currentIndex ? "completed" : i === info.currentIndex ? "active" : "pending",
        }))
      );
    });

    const offDone = window.flova.onFileDone(({ name, verified }) => {
      setItems((prev) => {
        const copy = [...prev];
        const idx = copy.findIndex((x) => x.name === name);
        if (idx >= 0) copy[idx] = { ...copy[idx], status: verified ? "completed" : "failed" };
        // advance the active pointer to the next pending
        const nextActive = copy.findIndex((x) => x.status === "active");
        if (nextActive < 0) {
          const firstPending = copy.findIndex((x) => x.status === "pending");
          if (firstPending >= 0) copy[firstPending] = { ...copy[firstPending], status: "active" };
        }
        return copy;
      });
    });

    const offAdvance = window.flova.onQueueAdvance(({ completed, total }) => {
      setItems((prev) =>
        prev.map((it, i) => {
          if (i < completed) return { ...it, status: it.status === "failed" ? "failed" : "completed" };
          if (i === completed && completed < total) return { ...it, status: "active" };
          return { ...it, status: "pending" };
        })
      );
    });

    return () => { cancelled = true; offDone(); offAdvance(); };
  }, []);

  const completed = items.filter((i) => i.status === "completed").length;
  const total = items.length;

  const handleCancel = async () => {
    if (window.flova) await window.flova.cancelQueue();
    go("home");
  };

  return (
    <div className="flex w-full max-w-lg mx-auto flex-col gap-6 p-8">
      <header className="text-center">
        <h1 className="text-[20px] font-semibold tracking-tight text-ink">Transfer queue</h1>
        <p className="mt-1 text-[14px] text-ink-2">
          {completed} of {total} files completed
        </p>
      </header>

      <div className="rounded-card border border-line bg-surface divide-y divide-line">
        {items.map((item) => (
          <div key={item.name} className="flex items-center gap-3 p-4">
            <div className="size-6 flex items-center justify-center shrink-0">
              {item.status === "completed" && (
                <svg viewBox="0 0 24 24" className="size-5 text-success" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="20 6 9 17 4 12" />
                </svg>
              )}
              {item.status === "failed" && (
                <svg viewBox="0 0 24 24" className="size-5 text-error" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                  <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              )}
              {item.status === "active" && (
                <div className="size-4 rounded-full border-2 border-accent border-t-transparent animate-spin" />
              )}
              {item.status === "pending" && (
                <div className="size-2 rounded-full bg-ink-3" />
              )}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-[14px] font-medium text-ink truncate">{item.name}</p>
              <p className="text-[12px] text-ink-2">{formatBytes(item.size)}</p>
            </div>
          </div>
        ))}
      </div>

      {completed < total && (
        <Button variant="secondary" onClick={handleCancel}>Cancel queue</Button>
      )}
      {completed === total && total > 0 && (
        <Button onClick={() => go("complete")}>View summary</Button>
      )}
    </div>
  );
}