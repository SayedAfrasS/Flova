/**
 * WORKFLOW OF THIS FILE:
 * 1. Entry point of the desktop app (main process).
 * 2. On app ready: detects the local hotspot IP, starts the WS server,
 *    registers the IPC handlers, then creates the main window.
 * 3. On window close (macOS style), keeps the server alive.
 * 4. On activate (macOS dock click), recreates the window.
 *
 * FUNCTIONS:
 *  - createWindow() : creates the BrowserWindow and loads the renderer.
 */
import { app, shell, BrowserWindow } from 'electron'
import { join } from 'path'
import { electronApp, optimizer, is } from '@electron-toolkit/utils'
import icon from '../../resources/icon.png?asset'
import { detectLocalIp } from './server/network'
import { TransportServer } from './server/transport'
import { registerIpc } from './ipc'

const SELF_NAME = "Afras's Laptop"
const PORT = 8431

let server: TransportServer | null = null
let serverInfo = { host: '0.0.0.0', port: PORT }

function startServer(): void {
  const detected = detectLocalIp()
  if (detected) {
    serverInfo.host = detected.host
    console.log(`[main] using interface ${detected.iface} → ${detected.host}`)
  } else {
    console.warn('[main] no external IPv4 found, using 0.0.0.0')
  }
  server = new TransportServer(PORT, SELF_NAME)
  registerIpc(server, () => serverInfo)
}

function createWindow(): void {
  const mainWindow = new BrowserWindow({
    width: 1100,
    height: 780,
    minWidth: 800,
    minHeight: 600,
    show: false,
    title: 'Flova',
    autoHideMenuBar: true,
    ...(process.platform === 'linux' ? { icon } : {}),
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false,
    },
  })

  mainWindow.on('ready-to-show', () => mainWindow.show())
  mainWindow.webContents.setWindowOpenHandler((details) => {
    shell.openExternal(details.url)
    return { action: 'deny' }
  })

  if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
    mainWindow.loadURL(process.env['ELECTRON_RENDERER_URL'])
  } else {
    mainWindow.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

app.whenReady().then(() => {
  electronApp.setAppUserModelId('com.flova')
  app.on('browser-window-created', (_, window) => optimizer.watchWindowShortcuts(window))
  startServer()
  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})