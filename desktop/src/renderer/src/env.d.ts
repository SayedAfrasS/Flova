/**
 * WORKFLOW OF THIS FILE:
 * 1. Declares the window.flova API types for strict renderer type checking.
 * 2. Includes the history rows returned by the SQLite store.
 * 3. Includes getProgress to read current bytes from the transport layer.
 */
export {}

declare global {
  interface Window {
    flova: {
      getServer: () => Promise<{ host: string; port: number }>
      getState: () => Promise<'waiting' | 'paired'>
      getPeerName: () => Promise<string | null>
      onPeerConnected: (cb: (name: string) => void) => () => void
      onPeerDisconnected: (cb: () => void) => () => void

      pickFile: () => Promise<string | null>
      pickMultipleFiles: () => Promise<string[]>
      getFileStats: (path: string) => Promise<{ name: string; size: number } | null>
      sendFile: (path: string) => Promise<boolean>
      sendMultipleFiles: (paths: string[]) => Promise<boolean>
      cancelQueue: () => Promise<boolean>
      getQueueInfo: () => Promise<{ queue: { filePath: string; name: string; size: number }[]; currentIndex: number }>
      getIncomingOffer: () => Promise<{ name: string; size: number } | null>
      acceptIncoming: () => Promise<boolean>
      declineIncoming: () => Promise<boolean>
      onIncomingOffer: (cb: (d: { name: string; size: number }) => void) => () => void
      onSendAccepted: (cb: () => void) => () => void
      onSendDeclined: (cb: () => void) => () => void
      onFileTransferStart: (cb: (m: { name: string; size: number; isSending: boolean; resumed?: number; queueIndex?: number; queueTotal?: number }) => void) => () => void
      onFileProgress: (cb: (d: { bytes: number; isSending: boolean }) => void) => () => void
      onFileDone: (cb: (d: { name: string; isSending: boolean; verified: boolean }) => void) => () => void
      onQueueAdvance: (cb: (d: { completed: number; total: number }) => void) => () => void
      getCurrentTransfer: () => Promise<{ name: string; size: number; isSending: boolean; verified?: boolean; resumed?: number; queueIndex?: number; queueTotal?: number } | null>
      getLastTransfer: () => Promise<{ name: string; size: number; isSending: boolean; verified?: boolean; resumed?: number } | null>
      getProgress: () => Promise<{ bytes: number; isSending: boolean } | null>
      getHistory: () => Promise<{ id: number; name: string; size: number; direction: string; ok: number; ts: number }[]>
    }
  }
}