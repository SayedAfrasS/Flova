/**
 * WORKFLOW OF THIS FILE:
 * 1. Main process entry point for the Electron app.
 * 2. Detects the local IP address on the hotspot subnet (any non-internal IPv4).
 * 3. Starts the TransportServer on port 8431.
 * 4. Registers IPC handlers to bridge transport events to the renderer.
 * 5. Creates the main BrowserWindow and loads the React app.
 */
import { app, BrowserWindow } from 'electron'
import * as os from 'os'
import * as path from 'path'
import { TransportServer } from './server/transport'
import { registerIpc } from './ipc'

let mainWindow: BrowserWindow | null = null

function getLocalIP(): string {
  const interfaces = os.networkInterfaces()
  
  // Priority order for interface names
  const priority = ['Wi-Fi', 'Ethernet', 'en0', 'wlan0', 'eth0']
  
  // First try to find a hotspot-like interface
  for (const name of priority) {
    for (const iface of interfaces[name] || []) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address
      }
    }
  }
  
  // Fallback: any non-internal IPv4
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name] || []) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address
      }
    }
  }
  
  return '127.0.0.1'
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      preload: path.join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  if (process.env.NODE_ENV === 'development') {
    mainWindow.loadURL('http://localhost:5173')
    mainWindow.webContents.openDevTools()
  } else {
    mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'))
  }
}

app.whenReady().then(() => {
  const port = 8431
  const host = getLocalIP()
  const server = new TransportServer(port, 'Desktop')
  registerIpc(server, () => ({ host, port }))

  console.log(`Server listening on ${host}:${port}`)

  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})