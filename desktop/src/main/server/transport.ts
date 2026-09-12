/**
 * WORKFLOW OF THIS FILE:
 * 1. Owns the WebSocket server, the peer, and the offer/accept handshake.
 * 2. SENDING (Phase 9): after accept, a pool of workers streams segments.
 *    - A shared counter hands out the next segment index to any free worker.
 *    - Each worker: read segment -> send binary frame -> await its chunk-ack.
 *    - Several segments are in flight at once, so the link never waits idle.
 *    - Every 2s a monitor measures the ack rate: if speed climbs it spawns
 *      one more worker (max 8); if speed collapses it halves the pool (min 2).
 * 3. RECEIVING: unchanged from Phase 8 - segments are written at their byte
 *    offset in a pre-allocated .part file and acked per index, so out-of-order
 *    arrival is perfectly fine.
 * 4. A manifest sidecar is saved every 25 segments for future resume support.
 * 5. On "file-end" the .part file is renamed to its final name and the UI
 *    is notified.
 *
 * FUNCTIONS:
 *  - offerFile()         : sends metadata + segment plan, waits for accept.
 *  - startFileStream()   : spawns the adaptive worker pool and awaits it.
 *  - acceptIncoming()    : pre-allocates .part file, then replies file-accept.
 *  - handleBinaryFrame() : parses header, writes segment at offset, sends ack.
 *  - finishIncomingFile(): closes, renames, cleans sidecar, notifies UI.
 */
import { WebSocketServer, WebSocket } from 'ws'
import { app } from 'electron'
import * as fs from 'fs'
import * as path from 'path'

export type Peer = { name: string; platform: string }
export type TransferMeta = { name: string; size: number; isSending: boolean }

const PING_INTERVAL_MS = 3000
const PONG_TIMEOUT_MS = 10000
const CHUNK_SIZE = 4 * 1024 * 1024 // 4 MB segments
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
  private recvReceived = new Set<number>()
  private pendingIncoming: { name: string; size: number; transferId: string } | null = null

  // sending state
  private pendingFilePath: string | null = null
  private ackResolvers = new Map<number, () => void>()
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
        } else if (msg?.type === 'file-offer') {
          this.pendingIncoming = {
            name: path.basename(String(msg.name)),
            size: Number(msg.size),
            transferId: String(msg.transferId ?? 't0'),
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
          // segments follow; the write sink is already open from accept
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

  // ---------- sending: adaptive parallel workers ----------
  offerFile(filePath: string): void {
    if (!this.peerWs) return
    this.pendingFilePath = filePath
    const stats = fs.statSync(filePath)
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
    }))
  }

  private async startFileStream(filePath: string): Promise<void> {
    if (!this.peerWs) return
    const size = fs.statSync(filePath).size
    const name = path.basename(filePath)
    const count = size === 0 ? 0 : Math.ceil(size / CHUNK_SIZE)
    this.sendAborted = false
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

    // one worker: grab indices from the shared queue until done or shed
    function workerLoop(): Promise<void> {
      activeWorkers++
      return (async () => {
        try {
          while (nextIndex < count && !self.sendAborted && self.peerWs) {
            if (activeWorkers > targetWorkers) break // pool shrank: shed this worker
            const i = nextIndex++
            const offset = i * CHUNK_SIZE
            const len = Math.min(CHUNK_SIZE, size - offset)
            const buf = Buffer.alloc(len)
            fs.readSync(fd, buf, 0, len, offset) // positional read: safe to share fd

            const header = Buffer.from(JSON.stringify({ i, o: offset, l: len }), 'utf8')
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

    // AIMD monitor: grow while speed climbs, halve when it collapses
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
          console.log(`[transport] speed up, workers -> ${targetWorkers}`)
        } else if (rate < lastRate * 0.7 && targetWorkers > MIN_WORKERS) {
          targetWorkers = Math.max(MIN_WORKERS, Math.floor(targetWorkers / 2))
          console.log(`[transport] speed down, workers -> ${targetWorkers}`)
        }
      }
      lastRate = rate
    }, 2000)

    // spawn the initial pool
    for (let w = 0; w < targetWorkers; w++) workers.push(workerLoop())

    // drain: keep awaiting until no new workers exist (monitor may add some)
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
      this.onFileDone?.(name, true)
    }
    this.currentTransfer = null
  }

  // ---------- receiving ----------
  getIncomingOffer() {
    return this.pendingIncoming ? { name: this.pendingIncoming.name, size: this.pendingIncoming.size } : null
  }

  acceptIncoming(): void {
    if (!this.pendingIncoming || !this.peerWs) return
    const { name, size, transferId } = this.pendingIncoming
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

    let finalPath = path.join(this.recvSaveDir, this.recvFinalName)
    let counter = 1
    while (fs.existsSync(finalPath)) {
      const ext = path.extname(this.recvFinalName)
      const base = path.basename(this.recvFinalName, ext)
      finalPath = path.join(this.recvSaveDir, `${base}_(${counter})${ext}`)
      counter++
    }
    try {
      fs.renameSync(this.recvPartPath, finalPath)
      if (this.recvSaveDir && this.recvTransferId) {
        const sidecar = path.join(this.recvSaveDir, `.${this.recvTransferId}.flova.json`)
        if (fs.existsSync(sidecar)) fs.unlinkSync(sidecar)
      }
      this.onFileDone?.(path.basename(finalPath), false)
    } catch (err) {
      console.warn('[transport] rename failed', err)
    }
    this.recvPartPath = null; this.recvFinalName = null; this.recvTransferId = null
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