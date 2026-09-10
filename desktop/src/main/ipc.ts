/**
 * WORKFLOW OF THIS FILE:
 * 1. Registers IPC handlers the renderer can call via contextBridge.
 * 2. "net:getServer" returns the current host + port.
 * 3. "net:getState" returns "waiting" or "paired".
 * 4. "net:getPeerName" returns the phone's name if paired.
 * 5. Forwards peer events to the renderer via webContents.send.
 *
 * FUNCTIONS:
 *  - registerIpc() : called once at startup, wires handlers and event forwarders.
 */
import { ipcMain, BrowserWindow } from 'electron'
import { TransportServer, type Peer } from './server/transport'

export function registerIpc(server: TransportServer, getInfo: () => { host: string; port: number }): void {
  let peer: Peer | null = null

  server.onPeerConnected = (p) => {
    peer = p
    for (const win of BrowserWindow.getAllWindows()) {
      win.webContents.send('net:peer-connected', p.name)
    }
  }
  server.onPeerDisconnected = () => {
    peer = null
    for (const win of BrowserWindow.getAllWindows()) {
      win.webContents.send('net:peer-disconnected')
    }
  }

  ipcMain.handle('net:getServer', () => getInfo())
  ipcMain.handle('net:getState', () => (peer ? 'paired' : 'waiting'))
  ipcMain.handle('net:getPeerName', () => peer?.name ?? null)
}