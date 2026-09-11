/**
 * WORKFLOW OF THIS FILE:
 * 1. Owns the WebSocket server and the single active peer.
 * 2. Symmetric handshake for BOTH directions:
 *    sender -> "file-offer" -> receiver shows Accept/Decline UI ->
 *    receiver -> "file-accept" (opens disk sink first) or "file-decline" ->
 *    sender streams "file-start" + binary chunks + "file-end".
 * 3. As receiver: acceptIncoming() opens the write stream BEFORE replying accept,
 *    so no chunk can ever arrive before the sink exists.
 * 4. As sender: offerFile() waits for file-accept before reading the file.
 * 5. Keeps currentTransfer (live) and lastTransfer (finished) for the UI.
 */
import { WebSocketServer, WebSocket } from 'ws'
import { app } from 'electron'
import * as fs from 'fs'
import * as path from 'path'

export type Peer = { name: string; platform: string }
export type TransferMeta = { name: string; size: number; isSending: boolean }

const PING_INTERVAL_MS = 3000
const PONG_TIMEOUT_MS = 10000
const CHUNK_SIZE = 64 * 1024

export class TransportServer {
  private wss: WebSocketServer
  private peerWs: WebSocket | null = null
  private peer: Peer | null = null
  private selfName: string
  private pingTimer: NodeJS.Timeout | null = null
  private lastPong: number = 0

  // receiving state
  private writeStream: fs.WriteStream | null = null
  private currentFileName: string | null = null
  private pendingIncoming: { name: string; size: number } | null = null

  // sending state
  private pendingFilePath: string | null = null

  // UI state
  private currentTransfer: TransferMeta | null = null
  private lastTransfer: TransferMeta | null = null

  onPeerConnected?: (peer: Peer) => void
  onPeerDisconnected?: () => void
  onIncomingOffer?: (name: string, size: number) => void
  onSendAccepted?: () => void
  onSendDeclined?: () => void
  onFileTransferStart?: (meta: TransferMeta) => void
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
    if (this.peerWs) { ws.close(1013, 'already connected'); return }

    ws.on('message', (data, isBinary) => {
      if (isBinary) {
        if (this.writeStream) {
          this.writeStream.write(data)
          this.onFileProgress?.(data.length, false)
        }
        return
      }
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
        } else if (msg?.type === 'file-offer') {
          // phone wants to send us a file: show Accept/Decline UI
          this.pendingIncoming = { name: path.basename(String(msg.name)), size: Number(msg.size) }
          this.onIncomingOffer?.(this.pendingIncoming.name, this.pendingIncoming.size)
        } else if (msg?.type === 'file-accept') {
          // phone accepted our offer: stream now
          if (this.pendingFilePath) {
            const fp = this.pendingFilePath
            this.pendingFilePath = null
            this.startFileStream(fp)
          }
        } else if (msg?.type === 'file-decline') {
          this.pendingFilePath = null
          this.currentTransfer = null
          this.onSendDeclined?.()
        } else if (msg?.type === 'file-start') {
          // safety net: if a sender streams without accept, open the sink now
          if (!this.writeStream && this.pendingIncoming) {
            this.openIncomingSink(this.pendingIncoming.name, this.pendingIncoming.size)
            this.pendingIncoming = null
          }
        } else if (msg?.type === 'file-end') {
          this.finishIncomingFile()
        }
      } catch (err) {
        console.warn('[transport] bad json frame', err)
      }
    })

    ws.on('close', () => {
      if (this.peerWs === ws) {
        this.stopHb(); this.peerWs = null; this.peer = null
        if (this.writeStream) this.writeStream.close()
        this.writeStream = null
        this.currentTransfer = null
        this.onPeerDisconnected?.()
      }
    })
    ws.on('error', (err) => console.warn('[transport] peer error', err))
  }

  // ---- sending side ----
  offerFile(filePath: string): void {
    if (!this.peerWs) return
    this.pendingFilePath = filePath
    const stats = fs.statSync(filePath)
    const meta: TransferMeta = { name: path.basename(filePath), size: stats.size, isSending: true }
    this.currentTransfer = meta
    this.lastTransfer = meta
    this.peerWs.send(JSON.stringify({ type: 'file-offer', name: meta.name, size: meta.size }))
  }

  private async startFileStream(filePath: string): Promise<void> {
    if (!this.peerWs) return
    const stats = fs.statSync(filePath)
    const meta: TransferMeta = { name: path.basename(filePath), size: stats.size, isSending: true }
    this.onSendAccepted?.()
    this.onFileTransferStart?.(meta)
    this.peerWs.send(JSON.stringify({ type: 'file-start', name: meta.name, size: meta.size }))

    const rs = fs.createReadStream(filePath, { highWaterMark: CHUNK_SIZE })
    for await (const chunk of rs) {
      while (this.peerWs.bufferedAmount > 1024 * 1024) {
        await new Promise((r) => setTimeout(r, 10))
      }
      this.peerWs.send(chunk)
      this.onFileProgress?.(chunk.length, true)
    }
    this.peerWs.send(JSON.stringify({ type: 'file-end' }))
    this.onFileDone?.(meta.name, true)
    this.currentTransfer = null
  }

  // ---- receiving side ----
  getIncomingOffer() { return this.pendingIncoming }

  acceptIncoming(): void {
    if (!this.pendingIncoming || !this.peerWs) return
    const { name, size } = this.pendingIncoming
    this.pendingIncoming = null
    this.openIncomingSink(name, size) // sink ready BEFORE we tell the phone to stream
    this.peerWs.send(JSON.stringify({ type: 'file-accept' }))
    const meta: TransferMeta = { name, size, isSending: false }
    this.currentTransfer = meta
    this.lastTransfer = meta
    this.onFileTransferStart?.(meta)
  }

  declineIncoming(): void {
    if (!this.pendingIncoming || !this.peerWs) return
    this.pendingIncoming = null
    this.peerWs.send(JSON.stringify({ type: 'file-decline' }))
  }

  private openIncomingSink(name: string, size: number): void {
    const saveDir = path.join(app.getPath('downloads'), 'Flova')
    if (!fs.existsSync(saveDir)) fs.mkdirSync(saveDir, { recursive: true })
    let savePath = path.join(saveDir, name)
    let counter = 1
    while (fs.existsSync(savePath)) {
      const ext = path.extname(name)
      const base = path.basename(name, ext)
      savePath = path.join(saveDir, `${base}_(${counter})${ext}`)
      counter++
    }
    this.currentFileName = path.basename(savePath)
    this.writeStream = fs.createWriteStream(savePath)
  }

  private finishIncomingFile(): void {
    if (this.writeStream) {
      this.writeStream.end(() => {
        if (this.currentFileName) this.onFileDone?.(this.currentFileName, false)
        this.writeStream = null
        this.currentFileName = null
        this.currentTransfer = null
      })
    }
  }

  getCurrentTransfer() { return this.currentTransfer }
  getLastTransfer() { return this.lastTransfer }

  private startHb(): void {
    this.stopHb()
    this.pingTimer = setInterval(() => {
      if (!this.peerWs) return
      try { this.peerWs.send(JSON.stringify({ type: 'ping' })) } catch {}
      if (Date.now() - this.lastPong > PONG_TIMEOUT_MS) {
        try { this.peerWs?.close(1001, 'pong timeout') } catch {}
      }
    }, PING_INTERVAL_MS)
  }
  private stopHb(): void { if (this.pingTimer) { clearInterval(this.pingTimer); this.pingTimer = null } }
  getPort(): number { const addr = this.wss.address(); return typeof addr === 'object' && addr ? addr.port : 0 }
}