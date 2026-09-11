/**
 * WORKFLOW OF THIS FILE:
 * 1. Registers IPC handlers for the renderer process.
 * 2. file:getStats reads the real file size of a picked file from the disk.
 * 3. file:getCurrentTransfer lets the UI read the active transfer state on mount.
 */
import { ipcMain, BrowserWindow, dialog } from 'electron'
import * as fs from 'fs'
import * as path from 'path'
import { TransportServer, type Peer } from './server/transport'

export function registerIpc(server: TransportServer, getInfo: () => { host: string; port: number }): void {
  let peer: Peer | null = null

  server.onPeerConnected = (p) => { peer = p; for (const win of BrowserWindow.getAllWindows()) win.webContents.send('net:peer-connected', p.name); }
  server.onPeerDisconnected = () => { peer = null; for (const win of BrowserWindow.getAllWindows()) win.webContents.send('net:peer-disconnected'); }
  
  server.onFileTransferStart = (name, size, isSending) => { 
    for (const win of BrowserWindow.getAllWindows()) win.webContents.send('file:transfer-start', { name, size, isSending }); 
  }
  server.onFileProgress = (bytes, isSending) => { 
    for (const win of BrowserWindow.getAllWindows()) win.webContents.send('file:progress', { bytes, isSending }); 
  }
  server.onFileDone = (name, isSending) => { 
    for (const win of BrowserWindow.getAllWindows()) win.webContents.send('file:done', { name, isSending }); 
  }

  ipcMain.handle('net:getServer', () => getInfo());
  ipcMain.handle('net:getState', () => (peer ? 'paired' : 'waiting'));
  ipcMain.handle('net:getPeerName', () => peer?.name ?? null);

  ipcMain.handle('file:pick', async () => {
    const result = await dialog.showOpenDialog({ properties: ['openFile'] });
    if (result.canceled || result.filePaths.length === 0) return null;
    return result.filePaths[0];
  });

  ipcMain.handle('file:getStats', (_, filePath: string) => {
    try {
      const stats = fs.statSync(filePath);
      return { name: path.basename(filePath), size: stats.size };
    } catch { return null; }
  });

  ipcMain.handle('file:getCurrentTransfer', () => server.getCurrentTransfer());

  ipcMain.handle('file:send', async (_, filePath: string) => {
    try {
      server.offerFile(filePath); 
      return true;
    } catch (err) {
      console.error('[ipc] file send failed', err);
      return false;
    }
  });
}