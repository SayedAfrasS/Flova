/**
 * WORKFLOW OF THIS FILE:
 * 1. Desktop home screen showing connection status and send/receive actions.
 * 2. When paired, fetches the session fingerprint from main process and
 *    displays it as a small badge next to the peer name. Both devices show
 *    the same 8-character code when the encrypted session is healthy,
 *    giving the user a visual way to verify no MITM is present.
 */
import { useEffect, useState } from 'react'
import { useNav } from '../state/nav'
import { FlovaMark } from '../components/primitives'

export function HomeScreen() {
  const go = useNav((s) => s.go)
  const [peerName, setPeerName] = useState<string | null>(null)
  const [fingerprint, setFingerprint] = useState<string>('')

  useEffect(() => {
    if (!window.flova) return
    window.flova.getPeerName().then(setPeerName)
    window.flova.getFingerprint().then(setFingerprint)
    const off = window.flova.onPeerConnected((name) => {
      setPeerName(name)
      window.flova.getFingerprint().then(setFingerprint)
    })
    const offDisc = window.flova.onPeerDisconnected(() => {
      setPeerName(null)
      setFingerprint('')
    })
    return () => { off(); offDisc() }
  }, [])

  return (
    <div className="w-full max-w-sm mx-auto flex flex-col items-center justify-center gap-8 p-8 text-center">
      <div className="flex items-center gap-2">
        <FlovaMark />
        <span className="text-[20px] font-semibold tracking-tight text-ink">flova</span>
      </div>

      <div>
        <h1 className="text-[28px] font-semibold tracking-tight text-ink">
          {peerName ? 'Laptop connected' : 'Waiting for phone'}
        </h1>
        <div className="mt-2 flex items-center justify-center gap-2">
          <span className={`size-2 rounded-full ${peerName ? 'bg-success' : 'bg-error'}`} />
          <span className="text-[14px] text-ink-2">{peerName ?? 'Scan the QR code to connect'}</span>
        </div>
        {peerName && fingerprint && fingerprint !== '----' && (
          <div className="mt-3 inline-flex items-center gap-2 rounded-full border border-line bg-surface px-3 py-1">
            <svg viewBox="0 0 24 24" className="size-3.5 text-success" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
              <path d="M7 11V7a5 5 0 0 1 10 0v4" />
            </svg>
            <span className="text-[12px] font-mono tracking-wider text-ink-2">
              {fingerprint}
            </span>
          </div>
        )}
      </div>

      <div className="flex w-full flex-col gap-3">
        <button
          onClick={() => go('send')}
          disabled={!peerName}
          className="w-full rounded-control bg-accent py-3 text-[14px] font-medium text-white shadow-sm hover:bg-accent-hover disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
        >
          Send a file
        </button>
        <button
          onClick={() => go('receive')}
          disabled={!peerName}
          className="w-full rounded-control border border-line bg-surface py-3 text-[14px] font-medium text-ink hover:bg-section disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
        >
          Receive a file
        </button>
      </div>
    </div>
  )
}