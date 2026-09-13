/**
 * WORKFLOW OF THIS FILE:
 * 1. Bridges IPC calls from renderer to TransportServer.
 * 2. Enqueues files for transfer and returns queue IDs.
 * 3. Forwards transfer events (start, progress, done) to renderer.
 * 4. Handles accept/decline for incoming files.
 * 5. Supports queue queries and cancellation.
 *
 * FUNCTIONS:
 *  - file:enqueue       : add a file to the transfer queue.
 *  - file:cancel        : cancel a specific transfer or the active one.
 *  - file:getQueue      : get all queued files and stats.
 *  - file:accept        : accept an incoming file offer.
 *  - file:decline       : decline an incoming file offer.
 */

import { ipcMain, dialog } from 'electron';
import { TransportServer } from './server/transport';

export function setupIPC(server: TransportServer) {
  // File picker
  ipcMain.handle('file:pick', async () => {
    const result = await dialog.showOpenDialog({
      properties: ['openFile', 'multiSelections'],
    });
    if (result.canceled) return null;
    
    const files = await Promise.all(result.filePaths.map(async (path) => {
      const stats = await import('fs').then(fs => fs.promises.stat(path));
      const name = path.split(/[\\/]/).pop() || path;
      return { path, name, size: stats.size };
    }));
    
    return files;
  });

  // Enqueue files for transfer
  ipcMain.handle('file:enqueue', async (_, files: { path: string; name: string; size: number }[]) => {
    const ids = files.map((f) => server.enqueueFile(f.path, f.name, f.size));
    return ids;
  });

  // Cancel a transfer
  ipcMain.handle('file:cancel', (_, id?: string) => {
    return server.cancelTransfer(id);
  });

  // Get queue state
  ipcMain.handle('file:getQueue', () => {
    return {
      stats: server.getQueueStats(),
      files: server.getQueueFiles(),
    };
  });

  // Accept incoming file
  ipcMain.handle('file:accept', (_, id: string) => {
    return server.acceptIncoming(id);
  });

  // Decline incoming file
  ipcMain.handle('file:decline', (_, id: string) => {
    server.declineIncoming(id);
    return true;
  });
}