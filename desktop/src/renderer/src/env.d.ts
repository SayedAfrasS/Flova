/**
 * WORKFLOW OF THIS FILE:
 * 1. Tells TypeScript about the window.flova API added by the preload script.
 * 2. Without this file, every use of window.flova would be a type error.
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
    }
  }
}