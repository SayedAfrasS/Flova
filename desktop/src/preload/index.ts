/**
 * WORKFLOW OF THIS FILE:
 * 1. Exposes safe IPC APIs to the renderer process.
 * 2. Provides methods for file picking, queuing, and transfer control.
 * 3. Provides event listeners for transfer lifecycle events.
 * 4. Uses contextBridge to prevent direct access to Node.js APIs.
 *
 * FUNCTIONS:
 *  - pickFiles()      : open file picker dialog.
 *  - enqueueFiles()   : add files to transfer queue.
 *  - cancelTransfer() : cancel a specific or active transfer.
 *  - getQueue()       : get queue state and file list.
 *  - acceptFile()     : accept an incoming file offer.
 *  - declineFile()    : decline an incoming file offer.
 *  - on*()            : subscribe to transfer events.
 */

import { contextBridge, ipcRenderer } from 'electron';

export interface QueuedFile {
  id: string;
  path: string;
  name: string;
  size: number;
  status: 'pending' | 'active' | 'completed' | 'failed';
  progress: number;
}

export interface TransferMeta {
  id: string;
  name: string;
  size: number;
  isSending: boolean;
  verified?: boolean;
  resumed?: number;
}

contextBridge.exposeInMainWorld('flova', {
  // File operations
  pickFiles: () => ipcRenderer.invoke('file:pick'),
  enqueueFiles: (files: { path: string; name: string; size: number }[]) =>
    ipcRenderer.invoke('file:enqueue', files),
  cancelTransfer: (id?: string) => ipcRenderer.invoke('file:cancel', id),
  getQueue: () => ipcRenderer.invoke('file:getQueue'),

  // Incoming file handling
  acceptFile: (id: string) => ipcRenderer.invoke('file:accept', id),
  declineFile: (id: string) => ipcRenderer.invoke('file:decline', id),

  // Event listeners
  onSendAccepted: (callback: (id: string) => void) => {
    ipcRenderer.on('file:send-accepted', (_, id) => callback(id));
    return () => ipcRenderer.removeAllListeners('file:send-accepted');
  },

  onSendDeclined: (callback: (id: string) => void) => {
    ipcRenderer.on('file:send-declined', (_, id) => callback(id));
    return () => ipcRenderer.removeAllListeners('file:send-declined');
  },

  onFileTransferStart: (callback: (meta: TransferMeta) => void) => {
    ipcRenderer.on('file:transfer-start', (_, meta) => callback(meta));
    return () => ipcRenderer.removeAllListeners('file:transfer-start');
  },

  onFileProgress: (callback: (id: string, bytes: number, isSending: boolean) => void) => {
    ipcRenderer.on('file:progress', (_, id, bytes, isSending) => callback(id, bytes, isSending));
    return () => ipcRenderer.removeAllListeners('file:progress');
  },

  onFileDone: (callback: (id: string, name: string, isSending: boolean, verified: boolean) => void) => {
    ipcRenderer.on('file:done', (_, id, name, isSending, verified) => callback(id, name, isSending, verified));
    return () => ipcRenderer.removeAllListeners('file:done');
  },

  onIncomingOffer: (callback: (id: string, name: string, size: number) => void) => {
    ipcRenderer.on('file:incoming-offer', (_, id, name, size) => callback(id, name, size));
    return () => ipcRenderer.removeAllListeners('file:incoming-offer');
  },
});