/**
 * WORKFLOW OF THIS FILE:
 * 1. Owns the WebSocket server, the peer, and the offer/accept handshake.
 * 2. RESUME (Phase 11):
 *    - offerFile() also saves a send-side sidecar (userData folder) recording
 *      transferId, file path, size and whole-file hash.
 *    - When a peer reconnects (hello), each side checks for unfinished work:
 *      sender sends "resume-offer"; receiver matches its .part sidecar by
 *      transferId and replies "resume-accept" with the indices already on disk.
 *    - The sender then streams ONLY missing indices; progress is seeded with
 *      the bytes the receiver already has, so the UI continues from e.g. 61%.
 *    - Sidecars are deleted on success, on decline, or when they go stale.
 * 3. Integrity: per-segment SHA-256 in frame headers (nack + resend on
 *    mismatch) and a whole-file hash re-checked after file-end.
 * 4. Sending: adaptive worker pool (2-8) pulling from a missing-index queue.
 * 5. Receiving: offset writes into a pre-allocated .part file; recv sidecar
 *    updated every 25 segments so a crash never loses the bitmap.
 *
 * FUNCTIONS:
 *  - hashFile()           : streaming SHA-256 of a whole file.
 *  - offerFile()          : hash + save send sidecar + send offer.
 *  - maybeOfferResume()   : after hello, propose resuming an interrupted send.
 *  - startFileStream()    : worker pool over the missing-index queue.
 *  - acceptIncoming()     : fresh receive: pre-allocate .part, reply accept.
 *  - handleResumeOffer()  : match recv sidecar, reopen .part, reply accept.
 *  - handleBinaryFrame()  : verify hash -> write at offset -> ack or nack.
 *  - finishIncomingFile() : whole-file verify, rename or delete, notify UI.
 */
import { WebSocketServer, WebSocket } from 'ws'
import { app } from 'electron'
import * as fs from 'fs'
import * as path from 'path'
import * as crypto from 'crypto'

export type Peer = { name: string; platform: string }
export type TransferMeta = { name: string; size: number; isSending: boolean; verified?: boolean; resumed?: number }

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
  private resumeState: { transferId: string } | null = null
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

  private sendSidecarPath(): string {
    return path.join(app.getPath('userData'), 'flova-pending-send.json')
  }

  private recvDir(): string {
    const d = path.join(app.getPath('downloads'), 'Flova')
    if (!fs.existsSync(d)) fs.mkdirSync(d, { recursive: true })
    return d
  }

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
          this.maybeOfferResume()
        } else if (msg?.type === 'ping') {
          ws.send(JSON.stringify({ type: 'pong' }))
        } else if (msg?.type === 'pong') {
          this.lastPong = Date.now()
        } else if (msg?.type === 'chunk-ack') {
          const i = Number(msg.i)
          const resolve = this.ackResolvers.get(i)
          if (resolve) { this.ackResolvers.delete(i); resolve() }
        } else if (msg?.type === 'chunk-nack') {
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
            this.startFileStream(fp, new Set<number>(), 0)
          }
        } else if (msg?.type === 'file-decline') {
          this.pendingFilePath = null
          this.currentTransfer = null
          this.onSendDeclined?.()
        } else if (msg?.type === 'resume-offer') {
          this.handleResumeOffer(msg)
        } else if (msg?.type === 'resume-accept') {
          const received = Array.isArray(msg.received) ? (msg.received as number[]) : []
          if (this.resumeState && this.pendingFilePath) {
            const skip = new Set(received)
            let resumed = 0
            const size = fs.statSync(this.pendingFilePath).size
            for (const i of skip) {
              const off = i * CHUNK_SIZE
              resumed += Math.min(CHUNK_SIZE, size - off)
            }
            const fp = this.pendingFilePath
            this.pendingFilePath = null
            this.startFileStream(fp, skip, resumed)
          }
        } else if (msg?.type === 'resume-decline') {
          this.clearSendSidecar()
          this.resumeState = null
          this.pendingFilePath = null
        } else if (msg?.type === 'file-start') {
          // segments follow; write sink already open
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
        this.writeSidecar() // bitmap survives for resume
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
    const fileHash = await this.hashFile(filePath)
    const transferId = `t${Date.now()}`
    const meta: TransferMeta = { name: path.basename(filePath), size: stats.size, isSending: true }
    this.currentTransfer = meta
    this.lastTransfer = meta
    // remember what we are shipping so a reconnect can resume it
    fs.writeFileSync(this.sendSidecarPath(), JSON.stringify({
      transferId, filePath, name: meta.name, size: stats.size,
      chunkSize: CHUNK_SIZE, chunkCount: Math.ceil(stats.size / CHUNK_SIZE), fileHash,
    }))
    this.peerWs.send(JSON.stringify({
      type: 'file-offer', transferId, name: meta.name, size: stats.size,
      chunkSize: CHUNK_SIZE, chunkCount: Math.ceil(stats.size / CHUNK_SIZE), fileHash,
    }))
  }

  private clearSendSidecar(): void {
    try { fs.unlinkSync(this.sendSidecarPath()) } catch {}
  }

  // after hello: propose resuming an interrupted send, if any
  private maybeOfferResume(): void {
    const p = this.sendSidecarPath()
    if (!fs.existsSync(p)) return
    try {
      const s = JSON.parse(fs.readFileSync(p, 'utf8'))
      if (!fs.existsSync(s.filePath) || fs.statSync(s.filePath).size !== s.size) {
        this.clearSendSidecar(); return
      }
      this.pendingFilePath = s.filePath
      this.resumeState = { transferId: s.transferId }
      this.peerWs?.send(JSON.stringify({
        type: 'resume-offer', transferId: s.transferId, name: s.name, size: s.size,
        chunkSize: s.chunkSize, chunkCount: s.chunkCount, fileHash: s.fileHash,
      }))
    } catch {
      this.clearSendSidecar()
    }
  }

  private async startFileStream(filePath: string, skip: Set<number>, resumedBytes: number): Promise<void> {
    if (!this.peerWs) return
    const size = fs.statSync(filePath).size
    const name = path.basename(filePath)
    const count = size === 0 ? 0 : Math.ceil(size / CHUNK_SIZE)
    this.sendAborted = false
    this.resendQueue = []
    this.onSendAccepted?.()
    this.onFileTransferStart?.({ name, size, isSending: true, resumed: resumedBytes })
    this.peerWs.send(JSON.stringify({ type: 'file-start', name, size }))

    // queue only the indices the receiver does not have yet
    const missing: number[] = []
    for (let i = 0; i < count; i++) if (!skip.has(i)) missing.push(i)
    let queuePos = 0

    const fd = fs.openSync(filePath, 'r')
    const self = this
    let activeWorkers = 0
    let targetWorkers = missing.length === 0 ? 1 : Math.min(START_WORKERS, missing.length)
    let ackedBytes = resumedBytes
    let lastSampleBytes = resumedBytes
    let lastSampleTime = Date.now()
    let lastRate = 0
    const workers: Promise<void>[] = []

    function workerLoop(): Promise<void> {
      activeWorkers++
      return (async () => {
        try {
          while (!self.sendAborted && self.peerWs) {
            const i = self.resendQueue.length > 0
              ? self.resendQueue.shift()!
              : (queuePos < missing.length ? missing[queuePos++] : -1)
            if (i === -1) break
            if (activeWorkers > targetWorkers && self.resendQueue.length === 0) break
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
      this.clearSendSidecar() // finished: nothing left to resume
      this.onFileDone?.(name, true, true)
    }
    this.resumeState = null
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

    const saveDir = this.recvDir()
    // sweep orphaned sidecars/.part files from dead transfers
    for (const f of fs.readdirSync(saveDir)) {
      if (f.endsWith('.flova.json') && !f.includes(transferId)) {
        try {
          const sc = JSON.parse(fs.readFileSync(path.join(saveDir, f), 'utf8'))
          if (sc?.name) try { fs.unlinkSync(path.join(saveDir, `${sc.name}.part`)) } catch {}
          fs.unlinkSync(path.join(saveDir, f))
        } catch {}
      }
    }

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
    const meta: TransferMeta = { name, size, isSending: false, resumed: 0 }
    this.currentTransfer = meta
    this.lastTransfer = meta
    this.onFileTransferStart?.(meta)
  }

  declineIncoming(): void {
    if (!this.pendingIncoming || !this.peerWs) return
    this.pendingIncoming = null
    this.peerWs.send(JSON.stringify({ type: 'file-decline' }))
  }

  // receiver side of resume: match sidecar, reopen .part, report what we have
  private handleResumeOffer(msg: any): void {
    const transferId = String(msg.transferId ?? '')
    const size = Number(msg.size)
    const saveDir = this.recvDir()
    const sidecar = path.join(saveDir, `.${transferId}.flova.json`)
    const name = path.basename(String(msg.name))
    const partPath = path.join(saveDir, `${name}.part`)
    if (!transferId || !fs.existsSync(sidecar) || !fs.existsSync(partPath)) {
      this.peerWs?.send(JSON.stringify({ type: 'resume-decline', transferId }))
      return
    }
    try {
      const sc = JSON.parse(fs.readFileSync(sidecar, 'utf8'))
      if (sc.size !== size) throw new Error('size mismatch')
      const received: number[] = Array.isArray(sc.received) ? sc.received : []
      this.recvFd = fs.openSync(partPath, 'r+') // keep existing bytes
      this.recvPartPath = partPath
      this.recvFinalName = name
      this.recvSize = size
      this.recvTransferId = transferId
      this.recvSaveDir = saveDir
      this.recvExpectedHash = String(msg.fileHash ?? '') || null
      this.recvReceived = new Set(received)
      let resumed = 0
      for (const i of this.recvReceived) {
        const off = i * CHUNK_SIZE
        resumed += Math.min(CHUNK_SIZE, size - off)
      }
      this.peerWs?.send(JSON.stringify({ type: 'resume-accept', transferId, received: Array.from(this.recvReceived) }))
      const meta: TransferMeta = { name, size, isSending: false, resumed }
      this.currentTransfer = meta
      this.lastTransfer = meta
      this.onFileTransferStart?.(meta)
    } catch {
      try { fs.unlinkSync(sidecar) } catch {}
      this.peerWs?.send(JSON.stringify({ type: 'resume-decline', transferId }))
    }
  }

  private handleBinaryFrame(data: Buffer): void {
    if (this.recvFd == null) return
    try {
      const headerLen = data.readUInt32BE(0)
      const header = JSON.parse(data.subarray(4, 4 + headerLen).toString('utf8'))
      const payload = data.subarray(4 + headerLen)

      const actual = crypto.createHash('sha256').update(payload).digest('hex')
      if (header.h && actual !== header.h) {
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

    ;(async () => {
      let verified = true
      if (expected) {
        const actual = await this.hashFile(partPath)
        verified = actual === expected
      }
      if (!verified) {
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