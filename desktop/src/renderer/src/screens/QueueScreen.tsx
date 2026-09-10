/**
 * WORKFLOW OF THIS FILE:
 * 1. This screen shows the transfer queue: moving files and finished files.
 * 2. A timer adds a little progress to every active (moving) file every 100ms.
 * 3. When an active file reaches 100%, it becomes a finished row
 *    (quieter look with a green check).
 * 4. Pause freezes one file, Resume continues it.
 * 5. Cancel removes a moving file. Remove deletes a finished file.
 * 6. When the list is empty, we show a calm empty state with one action.
 *
 * FUNCTIONS:
 *  - QueueScreen() : main screen, owns the list state and the timer.
 *  - TinyButton()  : small round icon button (pause / cancel / remove).
 */
import { useEffect, useState, type ReactNode } from "react";
import { Button } from "../components/primitives";
import { useNav } from "../state/nav";

type QueueItem = {
  id: number;
  name: string;
  size: string;
  active: boolean;   // true = still moving
  paused: boolean;   // true = frozen by user
  progress: number;  // 0 to 1
  note: string;      // shown under name when finished
};

const START_ITEMS: QueueItem[] = [
  { id: 1, name: "Video.mp4", size: "220 MB", active: true, paused: false, progress: 0.35, note: "" },
  { id: 2, name: "Project.zip", size: "84 MB", active: false, paused: false, progress: 1, note: "Sent to Phone" },
  { id: 3, name: "Photos.zip", size: "148 MB", active: false, paused: false, progress: 1, note: "Received from Phone" },
];

function TinyButton({ label, onClick, children }: { label: string; onClick: () => void; children: ReactNode }) {
  return (
    <button
      aria-label={label}
      title={label}
      onClick={onClick}
      className="flex size-8 items-center justify-center rounded-full text-ink-2 transition-colors hover:bg-section hover:text-ink"
    >
      {children}
    </button>
  );
}

export function QueueScreen() {
  const go = useNav((s) => s.go);
  const [items, setItems] = useState<QueueItem[]>(START_ITEMS);

  // timer: move every active file a little forward, finish it at 100%
  useEffect(() => {
    const id = setInterval(() => {
      setItems((list) =>
        list.map((it) => {
          if (!it.active || it.paused) return it;
          const next = Math.min(1, it.progress + 0.004 + Math.random() * 0.004);
          const done = next >= 1;
          return { ...it, progress: next, active: !done, note: done ? "Sent to Phone" : it.note };
        }),
      );
    }, 100);
    return () => clearInterval(id);
  }, []);

  // freeze or unfreeze one file
  const togglePause = (id: number) =>
    setItems((list) => list.map((it) => (it.id === id ? { ...it, paused: !it.paused } : it)));

  // delete one file from the list (cancel or remove)
  const remove = (id: number) => setItems((list) => list.filter((it) => it.id !== id));

  // calm empty state when nothing is left
  if (items.length === 0) {
    return (
      <div className="flex w-full max-w-md mx-auto flex-col items-center justify-center gap-4 p-8 text-center">
        <p className="text-[16px] font-medium text-ink">No transfers right now</p>
        <p className="text-[14px] text-ink-2">Files you send or receive will appear here.</p>
        <Button variant="secondary" onClick={() => go("send")}>Send a file</Button>
      </div>
    );
  }

  return (
    <div className="w-full max-w-2xl mx-auto p-8">
      <h1 className="text-[24px] font-semibold tracking-tight text-ink mb-6">Transfers</h1>
      <div className="flex flex-col gap-3">
        {items.map((it) => {
          const pct = Math.round(it.progress * 100);
          return it.active ? (
            // ----- moving file: loud row with progress bar -----
            <div key={it.id} className="flex items-center gap-4 rounded-card border border-line bg-canvas p-4">
              <div className="flex size-10 items-center justify-center rounded-control bg-accent-soft">
                <svg viewBox="0 0 24 24" className="size-5 text-accent" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><polyline points="14 2 14 8 20 8" /></svg>
              </div>
              <div className="flex-1">
                <div className="flex items-center justify-between">
                  <p className="text-[14px] font-medium text-ink">{it.name}</p>
                  <span className="text-[13px] font-semibold text-accent">{pct}%</span>
                </div>
                <div className="mt-2 h-1.5 rounded-full bg-line">
                  <div className="h-full rounded-full bg-accent transition-[width] duration-100" style={{ width: `${pct}%` }} />
                </div>
                <p className="mt-1 text-[12px] text-ink-3">{it.paused ? "Paused" : it.size}</p>
              </div>
              <div className="flex gap-1">
                <TinyButton label={it.paused ? "Resume" : "Pause"} onClick={() => togglePause(it.id)}>
                  {it.paused ? (
                    <svg viewBox="0 0 24 24" className="size-4" fill="currentColor"><polygon points="6 4 20 12 6 20" /></svg>
                  ) : (
                    <svg viewBox="0 0 24 24" className="size-4" fill="currentColor"><rect x="5" y="4" width="4" height="16" rx="1" /><rect x="15" y="4" width="4" height="16" rx="1" /></svg>
                  )}
                </TinyButton>
                <TinyButton label="Cancel" onClick={() => remove(it.id)}>
                  <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" /></svg>
                </TinyButton>
              </div>
            </div>
          ) : (
            // ----- finished file: quiet row with green check -----
            <div key={it.id} className="flex items-center gap-4 rounded-card border border-transparent bg-surface p-4">
              <div className="flex size-10 items-center justify-center rounded-full bg-success/10">
                <svg viewBox="0 0 24 24" className="size-4 text-success" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12" /></svg>
              </div>
              <div className="flex-1">
                <p className="text-[14px] font-medium text-ink">{it.name}</p>
                <p className="text-[12px] text-ink-3">{it.note} · {it.size}</p>
              </div>
              <TinyButton label="Remove" onClick={() => remove(it.id)}>
                <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" /></svg>
              </TinyButton>
            </div>
          );
        })}
      </div>
    </div>
  );
}