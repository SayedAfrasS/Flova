/**
 * WORKFLOW OF THIS FILE:
 * 1. Shows live progress for the active file (sending or receiving).
 * 2. The queue pill shows "File N of M" during multi-file transfers.
 * 3. Every file-transfer-start event resets the ring for the next file.
 * 4. Queue position lives in refs so the done-handler never reads stale
 *    state: when the LAST file's done event arrives it navigates to the
 *    Complete screen through the nav store (go('complete')).
 * 5. At 100% the subtitle shows "Checking file..." until the verify
 *    verdict arrives, then the done event fires.
 *
 * FUNCTIONS:
 *  - formatBytes() : human readable byte strings.
 *  - Ring()        : circular SVG progress indicator.
 *  - ProgressScreen(): subscribes to transfer events and renders state.
 */
import { useEffect, useRef, useState } from 'react'
import { useNav } from '../state/nav'

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`
  return `${Math.round(bytes / 1024)} KB`
}

function Ring({ pct }: { pct: number }) {
  const R = 84
  const C = 2 * Math.PI * R
  return (
    <div className="relative size-[200px]">
      <svg viewBox="0 0 200 200" className="size-full -rotate-90">
        <circle cx="100" cy="100" r={R} fill="none" stroke="#E5E7EB" strokeWidth="10" />
        <circle
          cx="100"
          cy="100"
          r={R}
          fill="none"
          stroke="#2563EB"
          strokeWidth="10"
          strokeLinecap="round"
          strokeDasharray={C}
          strokeDashoffset={C * (1 - pct / 100)}
          style={{ transition: 'stroke-dashoffset 120ms linear' }}
        />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center">
        <span className="text-[40px] font-semibold tracking-tight text-ink">{pct}%</span>
      </div>
    </div>
  )
}

export function ProgressScreen() {
  const go = useNav((s) => s.go)
  const [fileName, setFileName] = useState('Preparing...')
  const [transferred, setTransferred] = useState(0)
  const [totalBytes, setTotalBytes] = useState(0)
  const [isSending, setIsSending] = useState(true)
  const [speed, setSpeed] = useState(0)
  const [queueIndex, setQueueIndex] = useState(0)
  const [queueTotal, setQueueTotal] = useState(1)

  const bytesRef = useRef(0)
  const windowStartRef = useRef(Date.now())
  const windowBytesRef = useRef(0)
  const queueIndexRef = useRef(0)
  const queueTotalRef = useRef(1)
  const navigatedRef = useRef(false)

  useEffect(() => {
    if (!window.flova) return
    let cancelled = false

    // seed from whatever transfer is active right now
    window.flova.getCurrentTransfer().then((t) => {
      if (cancelled || !t) return
      const seed = t.resumed ?? 0
      bytesRef.current = seed
      windowBytesRef.current = seed
      windowStartRef.current = Date.now()
      setTransferred(seed)
      setFileName(t.name)
      setTotalBytes(t.size)
      setIsSending(t.isSending)
      const qi = t.queueIndex ?? 0
      const qt = t.queueTotal ?? 1
      queueIndexRef.current = qi
      queueTotalRef.current = qt
      setQueueIndex(qi)
      setQueueTotal(qt)
    })

    // each new file in the queue resets the ring
    const offStart = window.flova.onFileTransferStart((meta) => {
      const seed = meta.resumed ?? 0
      bytesRef.current = seed
      windowBytesRef.current = seed
      windowStartRef.current = Date.now()
      setTransferred(seed)
      setSpeed(0)
      setFileName(meta.name)
      setTotalBytes(meta.size)
      setIsSending(meta.isSending)
      const qi = meta.queueIndex ?? 0
      const qt = meta.queueTotal ?? 1
      queueIndexRef.current = qi
      queueTotalRef.current = qt
      setQueueIndex(qi)
      setQueueTotal(qt)
      navigatedRef.current = false
    })

    const offProgress = window.flova.onFileProgress(({ bytes }) => {
      bytesRef.current += bytes
      const now = Date.now()
      const dt = (now - windowStartRef.current) / 1000
      if (dt >= 0.5) {
        const delta = bytesRef.current - windowBytesRef.current
        setSpeed(delta / dt)
        windowStartRef.current = now
        windowBytesRef.current = bytesRef.current
      }
      setTransferred(bytesRef.current)
    })

    const offAdvance = window.flova.onQueueAdvance(({ completed, total }) => {
      queueIndexRef.current = completed
      queueTotalRef.current = total
      setQueueIndex(completed)
      setQueueTotal(total)
    })

    // navigate to Complete ONLY after the last file finishes
    const offDone = window.flova.onFileDone(() => {
      const isLast = queueIndexRef.current + 1 >= queueTotalRef.current
      if (isLast && !navigatedRef.current) {
        navigatedRef.current = true
        setTimeout(() => go('complete'), 500)
      }
    })

    return () => {
      cancelled = true
      offStart()
      offProgress()
      offAdvance()
      offDone()
    }
  }, [go])

  const pct = totalBytes > 0 ? Math.min(100, Math.round((transferred / totalBytes) * 100)) : 0
  const checking = totalBytes > 0 && transferred >= totalBytes
  const secondsLeft = speed > 0 ? Math.max(1, Math.round((totalBytes - transferred) / speed)) : 0

  return (
    <div className="flex w-full max-w-2xl mx-auto flex-col items-center justify-center gap-6 p-8">
      {queueTotal > 1 && (
        <div className="w-full max-w-md mx-auto rounded-full border border-line bg-surface px-4 py-2 text-center">
          <p className="text-[13px] font-medium text-ink">
            File {queueIndex + 1} of {queueTotal}
          </p>
        </div>
      )}

      <header className="text-center">
        <h1 className="text-[20px] font-semibold tracking-tight text-ink">
          {isSending ? 'Sending file' : 'Receiving file'}
        </h1>
        <p className="mt-1 text-[14px] text-ink-2">{fileName}</p>
      </header>

      <Ring pct={pct} />

      <div className="space-y-1 text-center">
        <p className="text-[14px] text-ink">
          {formatBytes(transferred)} of {formatBytes(totalBytes)}
        </p>
        <p className="text-[13px] text-ink-2">{speed > 0 && !checking ? `${formatBytes(speed)}/s` : ''}</p>
        <p className="text-[13px] text-ink-3">
          {checking ? 'Checking file...' : speed > 0 ? `About ${secondsLeft} seconds left` : ''}
        </p>
      </div>

      <button
        onClick={() => go('home')}
        className="text-[13px] text-ink-2 hover:text-ink transition-colors"
      >
        Cancel
      </button>
    </div>
  )
}