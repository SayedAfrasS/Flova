/**
 * WORKFLOW OF THIS FILE:
 * 1. This screen shows old transfers grouped by day: Today and Earlier.
 * 2. The data is fake (mock) for now. Real data will come from the
 *    local database later (Phase 13).
 * 3. Each row shows: file icon, name, direction + size, status, time.
 * 4. Rows are separated by thin lines, no heavy cards (calm look).
 *
 * FUNCTIONS:
 *  - HistoryScreen() : draws the two day sections.
 *  - Section()       : draws one day title + its rows.
 *  - HistoryRow()    : draws one transfer row.
 */
type HistoryItem = { name: string; size: string; direction: string; time: string };

const TODAY: HistoryItem[] = [
  { name: "document.pdf", size: "2.4 MB", direction: "Sent to Phone", time: "10:42 AM" },
  { name: "Vacation Video.mp4", size: "1.8 GB", direction: "Received from Phone", time: "9:15 AM" },
];

const EARLIER: HistoryItem[] = [
  { name: "Project.zip", size: "84 MB", direction: "Sent to Phone", time: "Yesterday" },
  { name: "Photos.zip", size: "148 MB", direction: "Received from Phone", time: "Monday" },
];

function HistoryRow({ item }: { item: HistoryItem }) {
  return (
    <div className="flex items-center gap-4 py-3 border-b border-line last:border-0">
      <div className="size-9 rounded-control bg-section flex items-center justify-center">
        <svg viewBox="0 0 24 24" className="size-4 text-ink-2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><polyline points="14 2 14 8 20 8" /></svg>
      </div>
      <div className="flex-1">
        <p className="text-[14px] font-medium text-ink">{item.name}</p>
        <p className="text-[12px] text-ink-3">{item.direction} · {item.size}</p>
      </div>
      <div className="text-right">
        <p className="text-[13px] font-medium text-success">Completed</p>
        <p className="text-[12px] text-ink-3">{item.time}</p>
      </div>
    </div>
  );
}

function Section({ title, items }: { title: string; items: HistoryItem[] }) {
  return (
    <section className="mb-8">
      <h2 className="text-[15px] font-semibold text-ink mb-2">{title}</h2>
      <div>{items.map((item) => <HistoryRow key={item.name + item.time} item={item} />)}</div>
    </section>
  );
}

export function HistoryScreen() {
  return (
    <div className="w-full max-w-2xl mx-auto p-8">
      <h1 className="text-[24px] font-semibold tracking-tight text-ink mb-6">History</h1>
      <Section title="Today" items={TODAY} />
      <Section title="Earlier" items={EARLIER} />
    </div>
  );
}