/**
 * WORKFLOW OF THIS FILE:
 * 1. Declares the window.flova API types for strict renderer type checking.
 * 2. Transfer metadata and the done event now include the verified flag.
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
      getFileStats: (path: string) => Promise<{ name: string; size: number } | null>
      sendFile: (path: string) => Promise<boolean>
      onSendAccepted: (cb: () => void) => () => void
      onSendDeclined: (cb: () => void) => () => void

      getIncomingOffer: () => Promise<{ name: string; size: number } | null>
      acceptIncoming: () => Promise<boolean>
      declineIncoming: () => Promise<boolean>
      onIncomingOffer: (cb: (d: { name: string; size: number }) => void) => () => void

      getCurrentTransfer: () => Promise<{ name: string; size: number; isSending: boolean; verified?: boolean } | null>
      getLastTransfer: () => Promise<{ name: string; size: number; isSending: boolean; verified?: boolean } | null>
      onFileTransferStart: (cb: (m: { name: string; size: number; isSending: boolean }) => void) => () => void
      onFileProgress: (cb: (d: { bytes: number; isSending: boolean }) => void) => () => void
      onFileDone: (cb: (d: { name: string; isSending: boolean; verified: boolean }) => void) => () => void
    }
  }
}