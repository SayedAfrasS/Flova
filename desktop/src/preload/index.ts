/**
 * WORKFLOW OF THIS FILE:
 * 1. Runs in a safe sandbox between the main process and the renderer.
 * 2. Exposes a tiny "flova" API to window.flova via contextBridge.
 * 3. The renderer uses this API to ask for server info and peer state.
 * 4. The renderer can also subscribe to peer-connected / peer-disconnected events.
 *
 * FUNCTIONS:
 *  - getServer()        : returns { host, port } of the laptop's WS server.
 *  - getState()         : returns "waiting" or "paired".
 *  - getPeerName()      : returns the paired phone's name, or null.
 *  - onPeerConnected()  : registers a callback, returns unsubscribe function.
 *  - onPeerDisconnected() : same for disconnect events.
 */
import { contextBridge, ipcRenderer, type IpcRendererEvent } from 'electron'

const api = {
  getServer: () => ipcRenderer.invoke('net:getServer') as Promise<{ host: string; port: number }>,
  getState: () => ipcRenderer.invoke('net:getState') as Promise<'waiting' | 'paired'>,
  getPeerName: () => ipcRenderer.invoke('net:getPeerName') as Promise<string | null>,

  onPeerConnected: (cb: (name: string) => void) => {
    const listener = (_e: IpcRendererEvent, name: string) => cb(name)
    ipcRenderer.on('net:peer-connected', listener)
    return () => ipcRenderer.removeListener('net:peer-connected', listener)
  },
  onPeerDisconnected: (cb: () => void) => {
    const listener = () => cb()
    ipcRenderer.on('net:peer-disconnected', listener)
    return () => ipcRenderer.removeListener('net:peer-disconnected', listener)
  },
}

contextBridge.exposeInMainWorld('flova', api)