/**
 * WORKFLOW OF THIS FILE:
 * 1. Owns the WebSocket server, the peer, and the offer/accept handshake.
 * 2. INTEGRITY (Phase 10):
 *    - offerFile() hashes the whole file first and puts that hash in the offer.
 *    - Every segment frame header carries the SHA-256 of its own payload.
 *    - The receiver hashes each incoming segment BEFORE writing it. On a
 *      mismatch it replies chunk-nack and the sender re-queues that index.
 *    - After file-end the receiver re-hashes the finished .part file and
 *      compares with the offer hash: match -> rename + verified done event,
 *      mismatch -> delete the .part and report a failed transfer.
 * 3. SENDING: adaptive worker pool (2-8) pulls segment indices from a shared
 *    queue; nacked indices jump the queue via the resend list.
 * 4. RECEIVING: segments are written at byte offset in a pre-allocated .part
 *    file; a manifest sidecar is saved every 25 segments for future resume.
 *
 * FUNCTIONS:
 *  - hashFile()          : streaming SHA-256 of a whole file.
 *  - offerFile()         : hashes file, sends offer, waits for accept.
 *  - startFileStream()   : adaptive parallel segment workers.
 *  - acceptIncoming()    : pre-allocates .part, replies file-accept.
 *  - handleBinaryFrame() : verify segment hash -> write at offset -> ack/nack.
 *  - finishIncomingFile(): whole-file verify, rename or delete, notify UI.
 */
import { WebSocketServer, WebSocket } from 'ws'
import { app } from 'electron'
import * as fs from 'fs'
import * as path from 'path'
import * as crypto from 'crypto'

export type Peer = { name: string; platform: string }
export type TransferMeta = { name: string; size: number; isSending: boolean; verified?: boolean }

const PING_INTERVAL_MS = 3000
const PONG_TIMEOUT_MS = 10000
const CHUNK_SIZE = 4 * 1024 * 1024
const MIN_WORKERS = 2
const START_WORKERS = 4
const MAX_WORKERS = 8

export class TransportServer {
  private wss: WebSocketServer
  private peerWs: WebSocket | null = null
  private peer: Peer | null = null
  private selfName: string
  private pingTimer: NodeJS.Timeout | null = null
  private lastPong = 0

  // receiving state
  private recvFd: number | null = null
  private recvPartPath: string | null = null
  private recvFinalName: string | null = null
  private recvSize = 0
  private recvTransferId: string | null = null
  private recvSaveDir: string | null = null
  private recvExpectedHash: string | null = null
  private recvReceived = new Set<number>()
  private pendingIncoming: { name: string; size: number; transferId: string; fileHash: string } | null = null

  // sending state
  private pendingFilePath: string | null = null
  private ackResolvers = new Map<number, () => void>()
  private resendQueue: number[] = []
  private sendAborted = false

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
  onFileDone?: (name: string, isSending: boolean, verified: boolean) => void

  constructor(port: number, selfName: string) {
    this.selfName = selfName
    this.wss = new WebSocketServer({ host: '0.0.0.0', port })
    this.wss.on('connection', (ws) => this.handle(ws))
    this.wss.on('error', (err) => console.error('[transport] server error', err))
    console.log(`[transport] listening on 0.0.0.0:${port}`)
  }

  // streaming SHA-256 of an entire file
  private async hashFile(p: string): Promise<string> {
    const h = crypto.createHash('sha256')
    const fd = fs.openSync(p, 'r')
    const buf = Buffer.alloc(4 * 1024 * 1024)
    try {
      let n = fs.readSync(fd, buf, 0, buf.length, null)
      while (n > 0) {
        h.update(buf.subarray(0, n))
        n = fs.readSync(fd, buf, 0, buf.length, null)
      }
    } finally {
      fs.closeSync(fd)
    }
    return h.digest('hex')
  }

  private handle(ws: WebSocket): void {
    if (this.peerWs) { ws.close(1013, 'already connected'); return }

    ws.on('message', (data, isBinary) => {
      if (isBinary) { this.handleBinaryFrame(data as Buffer); return }
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
        } else if (msg?.type === 'chunk-ack') {
          const i = Number(msg.i)
          const resolve = this.ackResolvers.get(i)
          if (resolve) { this.ackResolvers.delete(i); resolve() }
        } else if (msg?.type === 'chunk-nack') {
          // damaged segment: put it back at the front of the work queue
          const i = Number(msg.i)
          if (!this.resendQueue.includes(i)) this.resendQueue.push(i)
        } else if (msg?.type === 'file-offer') {
          this.pendingIncoming = {
            name: path.basename(String(msg.name)),
            size: Number(msg.size),
            transferId: String(msg.transferId ?? 't0'),
            fileHash: String(msg.fileHash ?? ''),
          }
          this.onIncomingOffer?.(this.pendingIncoming.name, this.pendingIncoming.size)
        } else if (msg?.type === 'file-accept') {
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
          // segments follow; write sink already open from accept
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
        this.sendAborted = true
        for (const resolve of this.ackResolvers.values()) resolve()
        this.ackResolvers.clear()
        if (this.recvFd != null) { try { fs.closeSync(this.recvFd) } catch {} this.recvFd = null }
        this.writeSidecar()
        this.currentTransfer = null
        this.onPeerDisconnected?.()
      }
    })
    ws.on('error', (err) => console.warn('[transport] peer error', err))
  }

  // ---------- sending ----------
  async offerFile(filePath: string): Promise<void> {
    if (!this.peerWs) return
    this.pendingFilePath = filePath
    const stats = fs.statSync(filePath)
    const fileHash = await this.hashFile(filePath) // whole-file integrity stamp
    const meta: TransferMeta = { name: path.basename(filePath), size: stats.size, isSending: true }
    this.currentTransfer = meta
    this.lastTransfer = meta
    this.peerWs.send(JSON.stringify({
      type: 'file-offer',
      transferId: `t${Date.now()}`,
      name: meta.name,
      size: meta.size,
      chunkSize: CHUNK_SIZE,
      chunkCount: Math.ceil(meta.size / CHUNK_SIZE),
      fileHash,
    }))
  }

  private async startFileStream(filePath: string): Promise<void> {
    if (!this.peerWs) return
    const size = fs.statSync(filePath).size
    const name = path.basename(filePath)
    const count = size === 0 ? 0 : Math.ceil(size / CHUNK_SIZE)
    this.sendAborted = false
    this.resendQueue = []
    this.onSendAccepted?.()
    this.onFileTransferStart?.({ name, size, isSending: true })
    this.peerWs.send(JSON.stringify({ type: 'file-start', name, size }))

    const fd = fs.openSync(filePath, 'r')
    const self = this
    let nextIndex = 0
    let activeWorkers = 0
    let targetWorkers = count === 0 ? 1 : Math.min(START_WORKERS, count)
    let ackedBytes = 0
    let lastSampleBytes = 0
    let lastSampleTime = Date.now()
    let lastRate = 0
    const workers: Promise<void>[] = []

    function workerLoop(): Promise<void> {
      activeWorkers++
      return (async () => {
        try {
          while (!self.sendAborted && self.peerWs) {
            if (self.resendQueue.length === 0 && nextIndex >= count) break
            if (activeWorkers > targetWorkers && self.resendQueue.length === 0) break
            // nacked segments jump the queue, otherwise take the next index
            const i = self.resendQueue.length > 0 ? self.resendQueue.shift()! : nextIndex++
            const offset = i * CHUNK_SIZE
            const len = Math.min(CHUNK_SIZE, size - offset)
            const buf = Buffer.alloc(len)
            fs.readSync(fd, buf, 0, len, offset)
            const segHash = crypto.createHash('sha256').update(buf).digest('hex')

            const header = Buffer.from(JSON.stringify({ i, o: offset, l: len, h: segHash }), 'utf8')
            const prefix = Buffer.alloc(4)
            prefix.writeUInt32BE(header.length, 0)

            const ackPromise = new Promise<void>((resolve) => { self.ackResolvers.set(i, resolve) })
            self.peerWs.send(Buffer.concat([prefix, header, buf]))
            await ackPromise
            if (self.sendAborted || !self.peerWs) break
            ackedBytes += len
            self.onFileProgress?.(len, true)
          }
        } finally {
          activeWorkers--
        }
      })()
    }

    const monitor = setInterval(() => {
      const now = Date.now()
      const dt = (now - lastSampleTime) / 1000
      if (dt <= 0) return
      const rate = (ackedBytes - lastSampleBytes) / dt
      lastSampleBytes = ackedBytes
      lastSampleTime = now
      if (lastRate > 0 && rate > 0) {
        if (rate > lastRate * 1.05 && targetWorkers < MAX_WORKERS) {
          targetWorkers++
          workers.push(workerLoop())
        } else if (rate < lastRate * 0.7 && targetWorkers > MIN_WORKERS) {
          targetWorkers = Math.max(MIN_WORKERS, Math.floor(targetWorkers / 2))
        }
      }
      lastRate = rate
    }, 2000)

    for (let w = 0; w < targetWorkers; w++) workers.push(workerLoop())

    let awaited = 0
    while (awaited < workers.length) {
      const batch = workers.slice(awaited)
      awaited = workers.length
      await Promise.all(batch)
    }
    clearInterval(monitor)
    while (awaited < workers.length) {
      const batch = workers.slice(awaited)
      awaited = workers.length
      await Promise.all(batch)
    }

    fs.closeSync(fd)
    if (!this.sendAborted && this.peerWs) {
      this.peerWs.send(JSON.stringify({ type: 'file-end' }))
      this.onFileDone?.(name, true, true)
    }
    this.currentTransfer = null
  }

  // ---------- receiving ----------
  getIncomingOffer() {
    return this.pendingIncoming ? { name: this.pendingIncoming.name, size: this.pendingIncoming.size } : null
  }

  acceptIncoming(): void {
    if (!this.pendingIncoming || !this.peerWs) return
    const { name, size, transferId, fileHash } = this.pendingIncoming
    this.pendingIncoming = null

    const saveDir = path.join(app.getPath('downloads'), 'Flova')
    if (!fs.existsSync(saveDir)) fs.mkdirSync(saveDir, { recursive: true })

    const partPath = path.join(saveDir, `${name}.part`)
    this.recvFd = fs.openSync(partPath, 'w')
    fs.ftruncateSync(this.recvFd, size)
    this.recvPartPath = partPath
    this.recvFinalName = name
    this.recvSize = size
    this.recvTransferId = transferId
    this.recvSaveDir = saveDir
    this.recvExpectedHash = fileHash || null
    this.recvReceived = new Set<number>()

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

  private handleBinaryFrame(data: Buffer): void {
    if (this.recvFd == null) return
    try {
      const headerLen = data.readUInt32BE(0)
      const header = JSON.parse(data.subarray(4, 4 + headerLen).toString('utf8'))
      const payload = data.subarray(4 + headerLen)

      // verify segment integrity BEFORE touching the disk
      const actual = crypto.createHash('sha256').update(payload).digest('hex')
      if (header.h && actual !== header.h) {
        console.warn(`[transport] segment ${header.i} hash mismatch, requesting resend`)
        this.peerWs?.send(JSON.stringify({ type: 'chunk-nack', i: header.i }))
        return
      }

      fs.writeSync(this.recvFd, payload, 0, payload.length, Number(header.o))
      this.recvReceived.add(Number(header.i))
      if (this.recvReceived.size % 25 === 0) this.writeSidecar()
      this.peerWs?.send(JSON.stringify({ type: 'chunk-ack', i: header.i }))
      this.onFileProgress?.(payload.length, false)
    } catch (err) {
      console.warn('[transport] bad binary frame', err)
    }
  }

  private writeSidecar(): void {
    if (!this.recvSaveDir || !this.recvTransferId) return
    try {
      const sidecar = path.join(this.recvSaveDir, `.${this.recvTransferId}.flova.json`)
      fs.writeFileSync(sidecar, JSON.stringify({
        name: this.recvFinalName, size: this.recvSize,
        chunkSize: CHUNK_SIZE, received: Array.from(this.recvReceived),
      }))
    } catch {}
  }

  private finishIncomingFile(): void {
    if (this.recvFd != null) { try { fs.closeSync(this.recvFd) } catch {} this.recvFd = null }
    if (!this.recvPartPath || !this.recvSaveDir || !this.recvFinalName) return
    const partPath = this.recvPartPath
    const saveDir = this.recvSaveDir
    const finalName = this.recvFinalName
    const expected = this.recvExpectedHash

    // whole-file verdict runs async so the UI can show "Checking file..."
    ;(async () => {
      let verified = true
      if (expected) {
        const actual = await this.hashFile(partPath)
        verified = actual === expected
      }
      if (!verified) {
        console.warn('[transport] whole-file hash mismatch, discarding')
        try { fs.unlinkSync(partPath) } catch {}
        this.cleanupRecvState()
        this.onFileDone?.(finalName, false, false)
        return
      }
      let finalPath = path.join(saveDir, finalName)
      let counter = 1
      while (fs.existsSync(finalPath)) {
        const ext = path.extname(finalName)
        const base = path.basename(finalName, ext)
        finalPath = path.join(saveDir, `${base}_(${counter})${ext}`)
        counter++
      }
      try {
        fs.renameSync(partPath, finalPath)
        if (this.recvTransferId) {
          const sidecar = path.join(saveDir, `.${this.recvTransferId}.flova.json`)
          if (fs.existsSync(sidecar)) fs.unlinkSync(sidecar)
        }
        this.onFileDone?.(path.basename(finalPath), false, true)
      } catch (err) {
        console.warn('[transport] rename failed', err)
      }
      this.cleanupRecvState()
    })()
  }

  private cleanupRecvState(): void {
    this.recvPartPath = null; this.recvFinalName = null; this.recvTransferId = null
    this.recvExpectedHash = null
    this.currentTransfer = null
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