/**
 * WORKFLOW OF THIS FILE:
 * 1. Bridges TransportServer events to the renderer via IPC.
 * 2. file:pickMultiple opens the native dialog with multi-select enabled.
 * 3. file:sendMultiple queues the files and starts the first offer.
 * 4. file:cancelQueue aborts the entire queue.
 * 5. file:getQueueInfo returns the current queue state for the UI.
 * 6. Forwards all transfer events including queue advancement.
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
  server.onQueueAdvance = (completed, total) => broadcast('file:queue-advance', { completed, total })

  ipcMain.handle('net:getServer', () => getInfo())
  ipcMain.handle('net:getState', () => (peer ? 'paired' : 'waiting'))
  ipcMain.handle('net:getPeerName', () => peer?.name ?? null)

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
    try { await server.offerMultipleFiles([filePath]); return true } catch (err) { console.error('[ipc] offer failed', err); return false }
  })

  ipcMain.handle('file:sendMultiple', async (_, filePaths: string[]) => {
    try { await server.offerMultipleFiles(filePaths); return true } catch (err) { console.error('[ipc] offer failed', err); return false }
  })

  ipcMain.handle('file:cancelQueue', () => { server.cancelQueue(); return true })
  ipcMain.handle('file:getQueueInfo', () => server.getQueueInfo())

  ipcMain.handle('file:getIncomingOffer', () => server.getIncomingOffer())
  ipcMain.handle('file:acceptIncoming', () => { server.acceptIncoming(); return true })
  ipcMain.handle('file:declineIncoming', () => { server.declineIncoming(); return true })
  ipcMain.handle('file:getCurrentTransfer', () => server.getCurrentTransfer())
  ipcMain.handle('file:getLastTransfer', () => server.getLastTransfer())
}