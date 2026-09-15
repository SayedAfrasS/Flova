/**
 * WORKFLOW OF THIS FILE:
 * 1. Main process entry point for the Electron app.
 * 2. Detects the local IP on the active Wi-Fi/Ethernet interface.
 * 3. Starts the TransportServer on port 8431 and registers IPC handlers.
 * 4. Creates the main window and loads the React renderer.
 * 5. DevTools do NOT open automatically; press F12 manually if needed.
 */
import { app, BrowserWindow } from 'electron'
import * as os from 'os'
import * as path from 'path'
import { TransportServer } from './server/transport'
import { registerIpc } from './ipc'

let mainWindow: BrowserWindow | null = null

function getLocalIP(): string {
  const interfaces = os.networkInterfaces()

  // preferred interface names first
  const priority = ['Wi-Fi', 'Ethernet', 'en0', 'wlan0', 'eth0']
  for (const name of priority) {
    for (const iface of interfaces[name] || []) {
      if (iface.family === 'IPv4' && !iface.internal) return iface.address
    }
  }

  // fallback: any non-internal IPv4 address
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name] || []) {
      if (iface.family === 'IPv4' && !iface.internal) return iface.address
    }
  }

  return '127.0.0.1'
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    title: 'Flova',
    webPreferences: {
      preload: path.join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  if (process.env.NODE_ENV === 'development' || process.env['ELECTRON_RENDERER_URL']) {
    // dev: load from the vite dev server (no DevTools auto-open)
    const url = process.env['ELECTRON_RENDERER_URL'] || 'http://localhost:5173'
    mainWindow.loadURL(url)
  } else {
    // production: load the built renderer files
    mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'))
  }

  mainWindow.on('closed', () => {
    mainWindow = null
  })
}

app.whenReady().then(() => {
  const port = 8431
  const host = getLocalIP()
  const server = new TransportServer(port, 'Desktop')
  registerIpc(server, () => ({ host, port }))

  console.log(`[main] server listening on ${host}:${port}`)

  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})