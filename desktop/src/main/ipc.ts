/**
 * WORKFLOW OF THIS FILE:
 * 1. Bridges TransportServer events to the renderer via IPC.
 * 2. Records every finished transfer into SQLite history (recordTransfer).
 * 3. Exposes history:list so the Transfers page can read real rows.
 * 4. Exposes net:getFingerprint so the Home screen can show the session
 *    fingerprint and let the user visually verify the encrypted session.
 */
import { ipcMain, BrowserWindow, dialog } from 'electron'
import * as fs from 'fs'
import * as path from 'path'
import { TransportServer, type Peer } from './server/transport'
import { recordTransfer, listTransfers } from './server/history'

export function registerIpc(server: TransportServer, getInfo: () => { host: string; port: number }): void {
  let peer: Peer | null = null
  const sizes = new Map<string, number>()
  const broadcast = (channel: string, payload?: unknown) => {
    for (const win of BrowserWindow.getAllWindows()) win.webContents.send(channel, payload)
  }

  server.onPeerConnected = (p) => { peer = p; broadcast('net:peer-connected', p.name) }
  server.onPeerDisconnected = () => { peer = null; broadcast('net:peer-disconnected') }
  server.onIncomingOffer = (name, size) => broadcast('file:incoming-offer', { name, size })
  server.onSendAccepted = () => broadcast('file:send-accepted')
  server.onSendDeclined = () => broadcast('file:send-declined')
  server.onFileTransferStart = (meta) => {
    sizes.set(meta.name, meta.size)
    broadcast('file:transfer-start', meta)
  }
  server.onFileProgress = (bytes, isSending) => broadcast('file:progress', { bytes, isSending })
  server.onFileDone = (name, isSending, verified) => {
    recordTransfer(name, sizes.get(name) ?? 0, isSending ? 'sent' : 'received', verified)
    broadcast('file:done', { name, isSending, verified })
  }
  server.onQueueAdvance = (completed, total) => broadcast('file:queue-advance', { completed, total })

  ipcMain.handle('net:getServer', () => getInfo())
  ipcMain.handle('net:getState', () => (peer ? 'paired' : 'waiting'))
  ipcMain.handle('net:getPeerName', () => peer?.name ?? null)
  ipcMain.handle('net:getFingerprint', () => server.getFingerprint())

  ipcMain.handle('file:pick', async () => {
    const result = await dialog.showOpenDialog({ properties: ['openFile'] })
    if (result.canceled || result.filePaths.length === 0) return null
    return result.filePaths[0]
  })
  ipcMain.handle('file:pickMultiple', async () => {
    const result = await dialog.showOpenDialog({ properties: ['openFile', 'multiSelections'] })
    if (result.canceled || result.filePaths.length === 0) return []
    return result.filePaths
  })
  ipcMain.handle('file:getStats', (_, filePath: string) => {
    try {
      const stats = fs.statSync(filePath)
      return { name: path.basename(filePath), size: stats.size }
    } catch { return null }
  })
  ipcMain.handle('file:send', async (_, filePath: string) => {
    try { await server.offerMultipleFiles([filePath]); return true } catch { return false }
  })
  ipcMain.handle('file:sendMultiple', async (_, filePaths: string[]) => {
    try { await server.offerMultipleFiles(filePaths); return true } catch { return false }
  })
  ipcMain.handle('file:cancelQueue', () => { server.cancelQueue(); return true })
  ipcMain.handle('file:getQueueInfo', () => server.getQueueInfo())
  ipcMain.handle('file:getIncomingOffer', () => server.getIncomingOffer())
  ipcMain.handle('file:acceptIncoming', () => { server.acceptIncoming(); return true })
  ipcMain.handle('file:declineIncoming', () => { server.declineIncoming(); return true })
  ipcMain.handle('file:getCurrentTransfer', () => server.getCurrentTransfer())
  ipcMain.handle('file:getLastTransfer', () => server.getLastTransfer())
  ipcMain.handle('history:list', () => listTransfers())
}