/**
 * WORKFLOW OF THIS FILE:
 * 1. Preload bridge between main process and renderer.
 * 2. Exposes network, file, transfer-event, history and fingerprint APIs.
 * 3. Event subscriptions return unsubscribe functions for clean effects.
 */
import { contextBridge, ipcRenderer } from 'electron'

const api = {
  getServer: () => ipcRenderer.invoke('net:getServer'),
  getState: () => ipcRenderer.invoke('net:getState'),
  getPeerName: () => ipcRenderer.invoke('net:getPeerName'),
  getFingerprint: () => ipcRenderer.invoke('net:getFingerprint'),
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

  pickFile: () => ipcRenderer.invoke('file:pick'),
  pickMultipleFiles: () => ipcRenderer.invoke('file:pickMultiple'),
  getFileStats: (path: string) => ipcRenderer.invoke('file:getStats', path),
  sendFile: (path: string) => ipcRenderer.invoke('file:send', path),
  sendMultipleFiles: (paths: string[]) => ipcRenderer.invoke('file:sendMultiple', paths),
  cancelQueue: () => ipcRenderer.invoke('file:cancelQueue'),
  getQueueInfo: () => ipcRenderer.invoke('file:getQueueInfo'),
  getIncomingOffer: () => ipcRenderer.invoke('file:getIncomingOffer'),
  acceptIncoming: () => ipcRenderer.invoke('file:acceptIncoming'),
  declineIncoming: () => ipcRenderer.invoke('file:declineIncoming'),
  onIncomingOffer: (callback: (data: { name: string; size: number }) => void) => {
    const listener = (_event: any, data: { name: string; size: number }) => callback(data)
    ipcRenderer.on('file:incoming-offer', listener)
    return () => ipcRenderer.removeListener('file:incoming-offer', listener)
  },
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
  onFileTransferStart: (callback: (meta: any) => void) => {
    const listener = (_event: any, meta: any) => callback(meta)
    ipcRenderer.on('file:transfer-start', listener)
    return () => ipcRenderer.removeListener('file:transfer-start', listener)
  },
  onFileProgress: (callback: (data: { bytes: number; isSending: boolean }) => void) => {
    const listener = (_event: any, data: any) => callback(data)
    ipcRenderer.on('file:progress', listener)
    return () => ipcRenderer.removeListener('file:progress', listener)
  },
  onFileDone: (callback: (data: { name: string; isSending: boolean; verified: boolean }) => void) => {
    const listener = (_event: any, data: any) => callback(data)
    ipcRenderer.on('file:done', listener)
    return () => ipcRenderer.removeListener('file:done', listener)
  },
  onQueueAdvance: (callback: (data: { completed: number; total: number }) => void) => {
    const listener = (_event: any, data: any) => callback(data)
    ipcRenderer.on('file:queue-advance', listener)
    return () => ipcRenderer.removeListener('file:queue-advance', listener)
  },
  getCurrentTransfer: () => ipcRenderer.invoke('file:getCurrentTransfer'),
  getLastTransfer: () => ipcRenderer.invoke('file:getLastTransfer'),
  getHistory: () => ipcRenderer.invoke('history:list'),
}

contextBridge.exposeInMainWorld('flova', api)