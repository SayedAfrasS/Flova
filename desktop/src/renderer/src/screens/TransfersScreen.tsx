/**
 * WORKFLOW OF THIS FILE:
 * 1. Transfers page shows history only (completed and failed transfers).
 * 2. Rows are loaded from SQLite via window.flova.getHistory() on mount.
 * 3. If a transfer finishes while this page is open, the list refreshes live.
 * 4. Each row shows a direction icon, name, size, time and status.
 * 5. Shows a calm empty state when there is no history yet.
 */
import { useEffect, useState } from 'react'

type HistoryRow = { id: number; name: string; size: number; direction: string; ok: number; ts: number }

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`
  return `${Math.round(bytes / 1024)} KB`
}

function formatTime(ts: number): string {
  const d = new Date(ts)
  const now = new Date()
  if (d.toDateString() === now.toDateString()) {
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  }
  return d.toLocaleDateString([], { month: 'short', day: 'numeric' })
}

export function TransfersScreen() {
  const [history, setHistory] = useState<HistoryRow[]>([])

  useEffect(() => {
    if (!window.flova) return
    const reload = () => window.flova.getHistory().then(setHistory)
    reload()

    // refresh when a transfer finishes while this page is open
    const offDone = window.flova.onFileDone(() => reload())
    return () => {
      offDone()
    }
  }, [])

  return (
    <div className="w-full max-w-2xl mx-auto p-8">
      <h1 className="text-[24px] font-semibold tracking-tight text-ink mb-6">Transfers</h1>

      {history.length === 0 ? (
        <p className="text-[13px] text-ink-3 py-8 text-center">
          No transfers yet. Files you send or receive will appear here.
        </p>
      ) : (
        <div className="divide-y divide-line">
          {history.map((row) => (
            <div key={row.id} className="flex items-center gap-4 py-3">
              <div className="size-9 rounded-control bg-section flex items-center justify-center">
                {row.direction === 'sent' ? (
                  <svg viewBox="0 0 24 24" className="size-4 text-ink-2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="22" y1="2" x2="11" y2="13" />
                    <polygon points="22 2 15 22 11 13 2 9 22 2" />
                  </svg>
                ) : (
                  <svg viewBox="0 0 24 24" className="size-4 text-ink-2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                    <polyline points="7 10 12 15 17 10" />
                    <line x1="12" y1="15" x2="12" y2="3" />
                  </svg>
                )}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-[14px] font-medium text-ink truncate">{row.name}</p>
                <p className="text-[12px] text-ink-3">
                  {formatBytes(row.size)} · {row.direction === 'sent' ? 'Sent to phone' : 'Received from phone'} · {formatTime(row.ts)}
                </p>
              </div>
              <span className={`text-[13px] font-medium ${row.ok === 1 ? 'text-success' : 'text-error'}`}>
                {row.ok === 1 ? 'Completed' : 'Failed'}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}