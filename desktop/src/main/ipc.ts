/**
 * WORKFLOW OF THIS FILE:
 * 1. Bridges TransportServer events to the renderer via IPC.
 * 2. file:send awaits offerFile so the whole-file hash is ready first.
 * 3. file:done now carries the verified flag for the Complete screen.
 */
import { ipcMain, BrowserWindow, dialog } from 'electron'
import * as fs from 'fs'
import * as path from 'path'
import { TransportServer, type Peer, type TransferMeta } from './server/transport'

export function registerIpc(server: TransportServer, getInfo: () => { host: string; port: number }): void {
  let peer: Peer | null = null
  const broadcast = (channel: string, payload?: unknown) => {
    for (const win of BrowserWindow.getAllWindows()) win.webContents.send(channel, payload)
  }

  server.onPeerConnected = (p) => { peer = p; broadcast('net:peer-connected', p.name) }
  server.onPeerDisconnected = () => { peer = null; broadcast('net:peer-disconnected') }
  server.onIncomingOffer = (name, size) => broadcast('file:incoming-offer', { name, size })
  server.onSendAccepted = () => broadcast('file:send-accepted')
  server.onSendDeclined = () => broadcast('file:send-declined')
  server.onFileTransferStart = (meta) => broadcast('file:transfer-start', meta)
  server.onFileProgress = (bytes, isSending) => broadcast('file:progress', { bytes, isSending })
  server.onFileDone = (name, isSending, verified) => broadcast('file:done', { name, isSending, verified })

  ipcMain.handle('net:getServer', () => getInfo())
  ipcMain.handle('net:getState', () => (peer ? 'paired' : 'waiting'))
  ipcMain.handle('net:getPeerName', () => peer?.name ?? null)

  ipcMain.handle('file:pick', async () => {
    const result = await dialog.showOpenDialog({ properties: ['openFile'] })
    if (result.canceled || result.filePaths.length === 0) return null
    return result.filePaths[0]
  })
  ipcMain.handle('file:getStats', (_, filePath: string) => {
    try {
      const stats = fs.statSync(filePath)
      return { name: path.basename(filePath), size: stats.size }
    } catch { return null }
  })
  ipcMain.handle('file:send', async (_, filePath: string) => {
    try { await server.offerFile(filePath); return true } catch (err) { console.error('[ipc] offer failed', err); return false }
  })
  ipcMain.handle('file:getIncomingOffer', () => server.getIncomingOffer())
  ipcMain.handle('file:acceptIncoming', () => { server.acceptIncoming(); return true })
  ipcMain.handle('file:declineIncoming', () => { server.declineIncoming(); return true })
  ipcMain.handle('file:getCurrentTransfer', () => server.getCurrentTransfer())
  ipcMain.handle('file:getLastTransfer', () => server.getLastTransfer())
}