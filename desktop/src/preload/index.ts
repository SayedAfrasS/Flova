/**
 * WORKFLOW OF THIS FILE:
 * 1. Preload script runs in a sandboxed context between main and renderer.
 * 2. Exposes the flova API to the renderer via contextBridge.
 * 3. All IPC calls go through ipcRenderer to the main process.
 * 4. Event listeners are wrapped to return unsubscribe functions.
 */
import { contextBridge, ipcRenderer } from 'electron'

const api = {
  // Network
  getServer: () => ipcRenderer.invoke('net:getServer'),
  getState: () => ipcRenderer.invoke('net:getState'),
  getPeerName: () => ipcRenderer.invoke('net:getPeerName'),
  onPeerConnected: (callback: (peerName: string) => void) => {
    const listener = (_event: any, peerName: string) => callback(peerName)
    ipcRenderer.on('net:peer-connected', listener)
    return () => ipcRenderer.removeListener('net:peer-connected', listener)
  },
  onPeerDisconnected: (callback: () => void) => {
    const listener = () => callback()
    ipcRenderer.on('net:peer-disconnected', listener)
    return () => ipcRenderer.removeListener('net:peer-disconnected', listener)
  },

  // File operations
  pickFile: () => ipcRenderer.invoke('file:pick'),
  pickMultipleFiles: () => ipcRenderer.invoke('file:pickMultiple'),
  getFileStats: (path: string) => ipcRenderer.invoke('file:getStats', path),
  sendFile: (path: string) => ipcRenderer.invoke('file:send', path),
  sendMultipleFiles: (paths: string[]) => ipcRenderer.invoke('file:sendMultiple', paths),
  cancelQueue: () => ipcRenderer.invoke('file:cancelQueue'),
  getQueueInfo: () => ipcRenderer.invoke('file:getQueueInfo'),

  // Incoming files
  getIncomingOffer: () => ipcRenderer.invoke('file:getIncomingOffer'),
  acceptIncoming: () => ipcRenderer.invoke('file:acceptIncoming'),
  declineIncoming: () => ipcRenderer.invoke('file:declineIncoming'),
  onIncomingOffer: (callback: (data: { name: string; size: number }) => void) => {
    const listener = (_event: any, data: { name: string; size: number }) => callback(data)
    ipcRenderer.on('file:incoming-offer', listener)
    return () => ipcRenderer.removeListener('file:incoming-offer', listener)
  },

  // Transfer events
  onSendAccepted: (callback: () => void) => {
    const listener = () => callback()
    ipcRenderer.on('file:send-accepted', listener)
    return () => ipcRenderer.removeListener('file:send-accepted', listener)
  },
  onSendDeclined: (callback: () => void) => {
    const listener = () => callback()
    ipcRenderer.on('file:send-declined', listener)
    return () => ipcRenderer.removeListener('file:send-declined', listener)
  },
  onFileTransferStart: (callback: (meta: { name: string; size: number; isSending: boolean; resumed?: number }) => void) => {
    const listener = (_event: any, meta: { name: string; size: number; isSending: boolean; resumed?: number }) => callback(meta)
    ipcRenderer.on('file:transfer-start', listener)
    return () => ipcRenderer.removeListener('file:transfer-start', listener)
  },
  onFileProgress: (callback: (data: { bytes: number; isSending: boolean }) => void) => {
    const listener = (_event: any, data: { bytes: number; isSending: boolean }) => callback(data)
    ipcRenderer.on('file:progress', listener)
    return () => ipcRenderer.removeListener('file:progress', listener)
  },
  onFileDone: (callback: (data: { name: string; isSending: boolean; verified: boolean }) => void) => {
    const listener = (_event: any, data: { name: string; isSending: boolean; verified: boolean }) => callback(data)
    ipcRenderer.on('file:done', listener)
    return () => ipcRenderer.removeListener('file:done', listener)
  },
  onQueueAdvance: (callback: (data: { completed: number; total: number }) => void) => {
    const listener = (_event: any, data: { completed: number; total: number }) => callback(data)
    ipcRenderer.on('file:queue-advance', listener)
    return () => ipcRenderer.removeListener('file:queue-advance', listener)
  },

  // Transfer state
  getCurrentTransfer: () => ipcRenderer.invoke('file:getCurrentTransfer'),
  getLastTransfer: () => ipcRenderer.invoke('file:getLastTransfer'),
}

contextBridge.exposeInMainWorld('flova', api)