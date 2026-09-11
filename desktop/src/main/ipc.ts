/**
 * WORKFLOW OF THIS FILE:
 * 1. Registers IPC handlers for the renderer process.
 * 2. Handles network state queries (getServer, getState, getPeerName).
 * 3. Opens the native OS file picker when the user wants to send a file.
 * 4. Triggers the actual file transfer via the TransportServer.
 * 5. Forwards real-time file progress and completion events to the renderer.
 *
 * FUNCTIONS:
 *  - registerIpc() : wires all handlers and event forwarders.
 */
import { ipcMain, BrowserWindow, dialog } from 'electron'
import { TransportServer, type Peer } from './server/transport'

export function registerIpc(server: TransportServer, getInfo: () => { host: string; port: number }): void {
  let peer: Peer | null = null

  server.onPeerConnected = (p) => {
    peer = p
    for (const win of BrowserWindow.getAllWindows()) win.webContents.send('net:peer-connected', p.name)
  }
  server.onPeerDisconnected = () => {
    peer = null
    for (const win of BrowserWindow.getAllWindows()) win.webContents.send('net:peer-disconnected')
  }

  server.onFileIncoming = (name, size) => {
    for (const win of BrowserWindow.getAllWindows()) win.webContents.send('file:incoming', { name, size })
  }
  server.onFileProgress = (bytes, isSending) => {
    for (const win of BrowserWindow.getAllWindows()) win.webContents.send('file:progress', { bytes, isSending })
  }
  server.onFileDone = (name, isSending) => {
    for (const win of BrowserWindow.getAllWindows()) win.webContents.send('file:done', { name, isSending })
  }

  ipcMain.handle('net:getServer', () => getInfo())
  ipcMain.handle('net:getState', () => (peer ? 'paired' : 'waiting'))
  ipcMain.handle('net:getPeerName', () => peer?.name ?? null)

  ipcMain.handle('file:pick', async () => {
    const result = await dialog.showOpenDialog({ properties: ['openFile'] })
    if (result.canceled || result.filePaths.length === 0) return null
    return result.filePaths[0]
  })

  ipcMain.handle('file:send', async (_, filePath: string) => {
    try {
      await server.sendFile(filePath)
      return true
    } catch (err) {
      console.error('[ipc] file send failed', err)
      return false
    }
  })
}