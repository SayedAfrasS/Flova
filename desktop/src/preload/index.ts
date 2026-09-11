/**
 * WORKFLOW OF THIS FILE:
 * 1. Exposes the typed flova API to the renderer through contextBridge.
 * 2. Includes the receive-handshake methods: incoming offer, accept, decline.
 * 3. Includes the send-handshake events: accepted, declined.
 */
import { contextBridge, ipcRenderer, type IpcRendererEvent } from 'electron'

type Meta = { name: string; size: number; isSending: boolean }

const api = {
  getServer: () => ipcRenderer.invoke('net:getServer') as Promise<{ host: string; port: number }>,
  getState: () => ipcRenderer.invoke('net:getState') as Promise<'waiting' | 'paired'>,
  getPeerName: () => ipcRenderer.invoke('net:getPeerName') as Promise<string | null>,
  onPeerConnected: (cb: (name: string) => void) => {
    const l = (_e: IpcRendererEvent, n: string) => cb(n)
    ipcRenderer.on('net:peer-connected', l)
    return () => ipcRenderer.removeListener('net:peer-connected', l)
  },
  onPeerDisconnected: (cb: () => void) => {
    const l = () => cb()
    ipcRenderer.on('net:peer-disconnected', l)
    return () => ipcRenderer.removeListener('net:peer-disconnected', l)
  },

  pickFile: () => ipcRenderer.invoke('file:pick') as Promise<string | null>,
  getFileStats: (p: string) => ipcRenderer.invoke('file:getStats', p) as Promise<{ name: string; size: number } | null>,
  sendFile: (p: string) => ipcRenderer.invoke('file:send', p) as Promise<boolean>,
  onSendAccepted: (cb: () => void) => {
    const l = () => cb()
    ipcRenderer.on('file:send-accepted', l)
    return () => ipcRenderer.removeListener('file:send-accepted', l)
  },
  onSendDeclined: (cb: () => void) => {
    const l = () => cb()
    ipcRenderer.on('file:send-declined', l)
    return () => ipcRenderer.removeListener('file:send-declined', l)
  },

  getIncomingOffer: () => ipcRenderer.invoke('file:getIncomingOffer') as Promise<{ name: string; size: number } | null>,
  acceptIncoming: () => ipcRenderer.invoke('file:acceptIncoming') as Promise<boolean>,
  declineIncoming: () => ipcRenderer.invoke('file:declineIncoming') as Promise<boolean>,
  onIncomingOffer: (cb: (d: { name: string; size: number }) => void) => {
    const l = (_e: IpcRendererEvent, d: { name: string; size: number }) => cb(d)
    ipcRenderer.on('file:incoming-offer', l)
    return () => ipcRenderer.removeListener('file:incoming-offer', l)
  },

  getCurrentTransfer: () => ipcRenderer.invoke('file:getCurrentTransfer') as Promise<Meta | null>,
  getLastTransfer: () => ipcRenderer.invoke('file:getLastTransfer') as Promise<Meta | null>,
  onFileTransferStart: (cb: (m: Meta) => void) => {
    const l = (_e: IpcRendererEvent, m: Meta) => cb(m)
    ipcRenderer.on('file:transfer-start', l)
    return () => ipcRenderer.removeListener('file:transfer-start', l)
  },
  onFileProgress: (cb: (d: { bytes: number; isSending: boolean }) => void) => {
    const l = (_e: IpcRendererEvent, d: { bytes: number; isSending: boolean }) => cb(d)
    ipcRenderer.on('file:progress', l)
    return () => ipcRenderer.removeListener('file:progress', l)
  },
  onFileDone: (cb: (d: { name: string; isSending: boolean }) => void) => {
    const l = (_e: IpcRendererEvent, d: { name: string; isSending: boolean }) => cb(d)
    ipcRenderer.on('file:done', l)
    return () => ipcRenderer.removeListener('file:done', l)
  },
}

contextBridge.exposeInMainWorld('flova', api)