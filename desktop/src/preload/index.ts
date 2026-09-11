/**
 * WORKFLOW OF THIS FILE:
 * 1. Exposes a safe API to the renderer process via contextBridge.
 * 2. Provides methods to query network state, pick files, and read file stats.
 * 3. Provides subscription methods for real-time peer and file transfer events.
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

  pickFile: () => ipcRenderer.invoke('file:pick') as Promise<string | null>,
  getFileStats: (path: string) => ipcRenderer.invoke('file:getStats', path) as Promise<{ name: string; size: number } | null>,
  sendFile: (path: string) => ipcRenderer.invoke('file:send', path) as Promise<boolean>,
  getCurrentTransfer: () => ipcRenderer.invoke('file:getCurrentTransfer') as Promise<{ name: string; size: number; isSending: boolean } | null>,
  
  onFileTransferStart: (cb: (data: { name: string; size: number; isSending: boolean }) => void) => {
    const listener = (_e: IpcRendererEvent, data: { name: string; size: number; isSending: boolean }) => cb(data)
    ipcRenderer.on('file:transfer-start', listener)
    return () => ipcRenderer.removeListener('file:transfer-start', listener)
  },
  onFileProgress: (cb: (data: { bytes: number; isSending: boolean }) => void) => {
    const listener = (_e: IpcRendererEvent, data: { bytes: number; isSending: boolean }) => cb(data)
    ipcRenderer.on('file:progress', listener)
    return () => ipcRenderer.removeListener('file:progress', listener)
  },
  onFileDone: (cb: (data: { name: string; isSending: boolean }) => void) => {
    const listener = (_e: IpcRendererEvent, data: { name: string; isSending: boolean }) => cb(data)
    ipcRenderer.on('file:done', listener)
    return () => ipcRenderer.removeListener('file:done', listener)
  }
}

contextBridge.exposeInMainWorld('flova', api)