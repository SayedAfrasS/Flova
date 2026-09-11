/**
 * WORKFLOW OF THIS FILE:
 * 1. Manages the WebSocket server and the active peer connection.
 * 2. Handles the basic control protocol: hello, ping/pong, and file metadata.
 * 3. When a file transfer starts, it opens a write stream to the Downloads folder.
 * 4. Incoming binary frames are piped directly into the write stream.
 * 5. Provides a sendFile method that reads a local file in 64KB chunks and 
 *    sends them as binary frames to the peer.
 *
 * CLASSES / FUNCTIONS:
 *  - TransportServer           : owns the WS server, peer, and file streams.
 *  - TransportServer.handle    : wires message parsing, binary handling, and close events.
 *  - TransportServer.sendFile  : reads a local file and streams it to the peer.
 *  - TransportServer.startHb   : starts the ping/pong heartbeat timer.
 */
import { WebSocketServer, WebSocket } from 'ws'
import { app } from 'electron'
import * as fs from 'fs'
import * as path from 'path'

export type Peer = { name: string; platform: string }

const PING_INTERVAL_MS = 3000
const PONG_TIMEOUT_MS = 10000
const CHUNK_SIZE = 64 * 1024 // 64 KB

export class TransportServer {
  private wss: WebSocketServer
  private peerWs: WebSocket | null = null
  private peer: Peer | null = null
  private selfName: string
  private pingTimer: NodeJS.Timeout | null = null
  private lastPong: number = 0

  // File receiving state
  private writeStream: fs.WriteStream | null = null
  private currentFileName: string | null = null
  private currentFileSize: number = 0
  private receivedBytes: number = 0

  onPeerConnected?: (peer: Peer) => void
  onPeerDisconnected?: () => void
  onFileIncoming?: (name: string, size: number) => void
  onFileProgress?: (bytes: number, isSending: boolean) => void
  onFileDone?: (name: string, isSending: boolean) => void

  constructor(port: number, selfName: string) {
    this.selfName = selfName
    this.wss = new WebSocketServer({ host: '0.0.0.0', port })
    this.wss.on('connection', (ws) => this.handle(ws))
    this.wss.on('error', (err) => console.error('[transport] server error', err))
    console.log(`[transport] listening on 0.0.0.0:${port}`)
  }

  private handle(ws: WebSocket): void {
    if (this.peerWs) {
      ws.close(1013, 'already connected')
      return
    }

    ws.on('message', (data, isBinary) => {
      if (isBinary) {
        // Incoming file chunk
        if (this.writeStream) {
          this.writeStream.write(data)
          this.receivedBytes += data.length
          this.onFileProgress?.(data.length, false)
        }
      } else {
        try {
          const msg = JSON.parse(data.toString())
          if (msg?.type === 'hello') {
            this.peerWs = ws
            this.peer = { name: String(msg.name ?? 'Phone'), platform: String(msg.platform ?? 'mobile') }
            this.lastPong = Date.now()
            ws.send(JSON.stringify({ type: 'hello-ack', name: this.selfName, platform: 'desktop' }))
            this.startHb()
            this.onPeerConnected?.(this.peer)
          } else if (msg?.type === 'ping') {
            ws.send(JSON.stringify({ type: 'pong' }))
          } else if (msg?.type === 'pong') {
            this.lastPong = Date.now()
          } else if (msg?.type === 'file-start') {
            this.handleIncomingFile(msg.name, msg.size)
          } else if (msg?.type === 'file-end') {
            this.finishIncomingFile()
          }
        } catch (err) {
          console.warn('[transport] bad json frame', err)
        }
      }
    })

    ws.on('close', () => {
      if (this.peerWs === ws) {
        this.stopHb()
        this.peerWs = null
        this.peer = null
        if (this.writeStream) this.writeStream.close()
        this.writeStream = null
        this.onPeerDisconnected?.()
      }
    })

    ws.on('error', (err) => console.warn('[transport] peer error', err))
  }

  private handleIncomingFile(name: string, size: number): void {
    const safeName = path.basename(name)
    const saveDir = path.join(app.getPath('downloads'), 'Flova')
    if (!fs.existsSync(saveDir)) fs.mkdirSync(saveDir, { recursive: true })
    
    const savePath = path.join(saveDir, safeName)
    this.currentFileName = safeName
    this.currentFileSize = size
    this.receivedBytes = 0
    this.writeStream = fs.createWriteStream(savePath)
    this.onFileIncoming?.(safeName, size)
  }

  private finishIncomingFile(): void {
    if (this.writeStream) {
      this.writeStream.end(() => {
        if (this.currentFileName) {
          this.onFileDone?.(this.currentFileName, false)
        }
        this.writeStream = null
        this.currentFileName = null
      })
    }
  }

  async sendFile(filePath: string): Promise<void> {
    if (!this.peerWs) throw new Error('No peer connected')
    
    const stats = fs.statSync(filePath)
    const name = path.basename(filePath)
    
    // Tell peer a file is coming
    this.peerWs.send(JSON.stringify({ type: 'file-start', name, size: stats.size }))
    
    // Stream the file in chunks
    const rs = fs.createReadStream(filePath, { highWaterMark: CHUNK_SIZE })
    
    for await (const chunk of rs) {
      // Wait for the socket buffer to drain if it's full (backpressure)
      while (this.peerWs.bufferedAmount > 1024 * 1024) {
        await new Promise(resolve => setTimeout(resolve, 10))
      }
      this.peerWs.send(chunk)
      this.onFileProgress?.(chunk.length, true)
    }
    
    // Tell peer the file is done
    this.peerWs.send(JSON.stringify({ type: 'file-end' }))
    this.onFileDone?.(name, true)
  }

  private startHb(): void {
    this.stopHb()
    this.pingTimer = setInterval(() => {
      if (!this.peerWs) return
      try { this.peerWs.send(JSON.stringify({ type: 'ping' })) } catch {}
      if (Date.now() - this.lastPong > PONG_TIMEOUT_MS) {
        console.warn('[transport] peer unresponsive, closing')
        try { this.peerWs?.close(1001, 'pong timeout') } catch {}
      }
    }, PING_INTERVAL_MS)
  }

  private stopHb(): void {
    if (this.pingTimer) { clearInterval(this.pingTimer); this.pingTimer = null }
  }

  getPort(): number {
    const addr = this.wss.address()
    return typeof addr === 'object' && addr ? addr.port : 0
  }
}