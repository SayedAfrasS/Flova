/**
 * WORKFLOW OF THIS FILE:
 * 1. Declares the TypeScript types for the window.flova API.
 * 2. Ensures the renderer has strict type checking for IPC calls and events.
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
      sendFile: (path: string) => Promise<boolean>
      onFileProgress: (cb: (data: { bytes: number; isSending: boolean }) => void) => () => void
      onFileDone: (cb: (data: { name: string; isSending: boolean }) => void) => () => void
    }
  }
}