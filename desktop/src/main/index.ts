/**
 * WORKFLOW OF THIS FILE:
 * 1. Creates the Electron main window and initializes the transport server.
 * 2. Sets up IPC bridges between main and renderer processes.
 * 3. Forwards transfer events from server to renderer via IPC.
 * 4. Handles app lifecycle events (ready, quit, etc.).
 *
 * FUNCTIONS:
 *  - createWindow()     : create the main browser window.
 *  - setupEventForwarding() : wire server events to IPC.
 */

import { app, BrowserWindow } from 'electron';
import * as path from 'path';
import { TransportServer } from './server/transport';
import { setupIPC } from './ipc';

let mainWindow: BrowserWindow | null = null;
let server: TransportServer | null = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    webPreferences: {
      preload: path.join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  if (process.env.NODE_ENV === 'development') {
    mainWindow.loadURL('http://localhost:5173');
    mainWindow.webContents.openDevTools();
  } else {
    mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

function setupEventForwarding() {
  if (!server || !mainWindow) return;

  server.onPeerConnected = (peer) => {
    mainWindow?.webContents.send('net:peer-connected', peer.name);
  };

  server.onPeerDisconnected = () => {
    mainWindow?.webContents.send('net:peer-disconnected');
  };

  server.onSendAccepted = (id) => {
    mainWindow?.webContents.send('file:send-accepted', id);
  };

  server.onSendDeclined = (id) => {
    mainWindow?.webContents.send('file:send-declined', id);
  };

  server.onFileTransferStart = (meta) => {
    mainWindow?.webContents.send('file:transfer-start', meta);
  };

  server.onFileProgress = (id, bytes, isSending) => {
    mainWindow?.webContents.send('file:progress', id, bytes, isSending);
  };

  server.onFileDone = (id, name, isSending, verified) => {
    mainWindow?.webContents.send('file:done', id, name, isSending, verified);
  };

  server.onIncomingOffer = (id, name, size) => {
    mainWindow?.webContents.send('file:incoming-offer', id, name, size);
  };
}

app.whenReady().then(() => {
  server = new TransportServer(8431);
  createWindow();
  setupEventForwarding();
  setupIPC(server);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    server?.shutdown();
    app.quit();
  }
});

app.on('before-quit', () => {
  server?.shutdown();
});