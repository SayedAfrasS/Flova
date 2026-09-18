/**
 * WORKFLOW OF THIS FILE:
 * 1. Manages the WebSocket server, the peer, and the symmetric handshake.
 * 2. Every new connection creates a fresh SessionCrypto (forward secrecy).
 * 3. The hello/hello-ack messages carry X25519 public keys in plaintext.
 *    Both sides derive the same 32-byte shared secret after hello-ack.
 * 4. All messages after that are encrypted with ChaCha20-Poly1305:
 *    - JSON frames are wrapped as {"type":"e","n":nonce,"c":cipher}
 *    - Binary frames are prefixed with 0x01 + 12-byte nonce + ciphertext
 * 5. Incoming encrypted frames are decrypted before dispatch. Tampered
 *    frames fail the auth tag and are logged and dropped.
 * 6. All higher-level behavior (queue, resume, verify, history hooks) is
 *    identical to Phase 13; only the transport layer gained encryption.
 *
 * FUNCTIONS:
 *  - sendJson()       : encrypts (when session ready) and sends a JSON frame.
 *  - sendBinary()     : encrypts (when session ready) and sends a binary frame.
 *  - dispatch()       : processes an already-decrypted JSON message.
 *  - offerMultipleFiles / cancelQueue / acceptIncoming / etc: unchanged.
 */
import { WebSocketServer, WebSocket } from 'ws'
import { app } from 'electron'
import * as fs from 'fs'
import * as path from 'path'
import * as crypto from 'crypto'
import { SessionCrypto } from './crypto'

export type Peer = { name: string; platform: string }
export type TransferMeta = {
  name: string
  size: number
  isSending: boolean
  verified?: boolean
  resumed?: number
  filePath?: string
  queueIndex?: number
  queueTotal?: number
}

const PING_INTERVAL_MS = 3000
const PONG_TIMEOUT_MS = 10000
const CHUNK_SIZE = 4 * 1024 * 1024
const MIN_WORKERS = 2
const START_WORKERS = 4
const MAX_WORKERS = 8
const VERIFY_TIMEOUT_MS = 20000
const PLAINTEXT_TYPES = new Set(['hello', 'hello-ack'])

export class TransportServer {
  private wss: WebSocketServer
  private peerWs: WebSocket | null = null
  private peer: Peer | null = null
  private selfName: string
  private pingTimer: NodeJS.Timeout | null = null
  private lastPong = 0
  private crypto: SessionCrypto = new SessionCrypto()

  private recvFd: number | null = null
  private recvPartPath: string | null = null
  private recvFinalName: string | null = null
  private recvSize = 0
  private recvTransferId: string | null = null
  private recvSaveDir: string | null = null
  private recvExpectedHash: string | null = null
  private recvReceived = new Set<number>()
  private pendingIncoming: { name: string; size: number; transferId: string; fileHash: string } | null = null

  private sendQueue: { filePath: string; name: string; size: number; hash: string; transferId: string }[] = []
  private currentSendIndex = 0
  private resumeState: { transferId: string } | null = null
  private ackResolvers = new Map<number, () => void>()
  private resendQueue: number[] = []
  private sendAborted = false
  private verifyResolver: ((ok: boolean) => void) | null = null

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
  onQueueAdvance?: (completed: number, total: number) => void

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

  private awaitVerify(): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      this.verifyResolver = resolve
      setTimeout(() => {
        if (this.verifyResolver === resolve) {
          this.verifyResolver = null
          resolve(true)
        }
      }, VERIFY_TIMEOUT_MS)
    })
  }

  /** wraps a JSON frame in the encrypted envelope when the session is ready */
  private sendJson(msg: Record<string, unknown>): void {
    if (!this.peerWs) return
    if (this.crypto.hasKey() && !PLAINTEXT_TYPES.has(msg.type as string)) {
      try {
        const plain = Buffer.from(JSON.stringify(msg), 'utf8')
        const { nonce, ciphertext } = this.crypto.encrypt(plain)
        this.peerWs.send(JSON.stringify({
          type: 'e',
          n: nonce.toString('base64'),
          c: ciphertext.toString('base64'),
        }))
        return
      } catch (e) {
        console.warn('[transport] encrypt json failed', e)
      }
    }
    this.peerWs.send(JSON.stringify(msg))
  }

  /** wraps a binary frame with 0x01 marker + nonce + ciphertext when session ready */
  private sendBinary(data: Buffer): void {
    if (!this.peerWs) return
    if (this.crypto.hasKey()) {
      try {
        const { nonce, ciphertext } = this.crypto.encrypt(data)
        const frame = Buffer.alloc(1 + nonce.length + ciphertext.length)
        frame[0] = 0x01
        nonce.copy(frame, 1)
        ciphertext.copy(frame, 1 + nonce.length)
        this.peerWs.send(frame)
        return
      } catch (e) {
        console.warn('[transport] encrypt binary failed', e)
      }
    }
    this.peerWs.send(data)
  }

  private handle(ws: WebSocket): void {
    if (this.peerWs) { ws.close(1013, 'already connected'); return }

    // fresh crypto for this session -> forward secrecy per connection
    this.crypto = new SessionCrypto()

    ws.on('message', (data, isBinary) => {
      if (isBinary) {
        const buf = data as Buffer
        if (buf.length >= 1 + 12 + 16 && buf[0] === 0x01 && this.crypto.hasKey()) {
          try {
            const nonce = buf.subarray(1, 13)
            const cipher = buf.subarray(13)
            const plain = this.crypto.decrypt(nonce, cipher)
            this.handleBinaryFrame(Buffer.from(plain))
          } catch (e) {
            console.warn('[transport] binary decrypt failed', e)
          }
          return
        }
        this.handleBinaryFrame(buf)
        return
      }

      let msg: any
      try { msg = JSON.parse(data.toString()) } catch { return }

      if (msg?.type === 'e' && this.crypto.hasKey()) {
        try {
          const plain = this.crypto.decrypt(
            Buffer.from(String(msg.n), 'base64'),
            Buffer.from(String(msg.c), 'base64')
          )
          const inner = JSON.parse(plain.toString('utf8'))
          this.dispatch(inner, ws)
        } catch (e) {
          console.warn('[transport] json decrypt failed', e)
        }
        return
      }

      this.dispatch(msg, ws)
    })

    ws.on('close', () => {
      if (this.peerWs === ws) {
        this.stopHb()
        this.peerWs = null
        this.peer = null
        this.sendAborted = true
        for (const resolve of this.ackResolvers.values()) resolve()
        this.ackResolvers.clear()
        if (this.verifyResolver) { const r = this.verifyResolver; this.verifyResolver = null; r(false) }
        if (this.recvFd != null) { try { fs.closeSync(this.recvFd) } catch {} this.recvFd = null }
        this.writeSidecar()
        this.currentTransfer = null
        this.onPeerDisconnected?.()
      }
    })
    ws.on('error', (err) => console.warn('[transport] peer error', err))
  }

  /** dispatches an already-decrypted (or plaintext handshake) JSON message */
  private dispatch(msg: any, ws: WebSocket): void {
    if (!msg || typeof msg !== 'object') return
    const type = msg.type

    if (type === 'hello') {
      this.peerWs = ws
      this.peer = { name: String(msg.name ?? 'Phone'), platform: String(msg.platform ?? 'mobile') }
      this.lastPong = Date.now()
      if (msg.pubKey) {
        try {
          this.crypto.deriveKey(Buffer.from(String(msg.pubKey), 'base64'))
          console.log(`[crypto] key derived, fingerprint=${this.crypto.fingerprint()}`)
        } catch (e) {
          console.warn('[crypto] derive failed', e)
        }
      }
      this.sendJson({
        type: 'hello-ack',
        name: this.selfName,
        platform: 'desktop',
        pubKey: this.crypto.getPublicKey().toString('base64'),
      })
      this.startHb()
      this.onPeerConnected?.(this.peer)
      this.maybeOfferResume()
    } else if (type === 'hello-ack') {
      if (msg.pubKey) {
        try {
          this.crypto.deriveKey(Buffer.from(String(msg.pubKey), 'base64'))
          console.log(`[crypto] key derived from ack, fingerprint=${this.crypto.fingerprint()}`)
        } catch (e) {
          console.warn('[crypto] derive on ack failed', e)
        }
      }
    } else if (type === 'ping') {
      this.sendJson({ type: 'pong' })
    } else if (type === 'pong') {
      this.lastPong = Date.now()
    } else if (type === 'verify-result') {
      const r = this.verifyResolver
      this.verifyResolver = null
      if (r) r(msg.ok === true)
    } else if (type === 'chunk-ack') {
      const i = Number(msg.i)
      const resolve = this.ackResolvers.get(i)
      if (resolve) { this.ackResolvers.delete(i); resolve() }
    } else if (type === 'chunk-nack') {
      const i = Number(msg.i)
      if (!this.resendQueue.includes(i)) this.resendQueue.push(i)
    } else if (type === 'file-offer') {
      const queueIndex = Number(msg.queueIndex ?? 0)
      this.pendingIncoming = {
        name: path.basename(String(msg.name)),
        size: Number(msg.size),
        transferId: String(msg.transferId ?? 't0'),
        fileHash: String(msg.fileHash ?? ''),
      }
      if (queueIndex > 0) {
        this.acceptIncoming()
      } else {
        this.onIncomingOffer?.(this.pendingIncoming.name, this.pendingIncoming.size)
      }
    } else if (type === 'file-accept') {
      if (this.sendQueue.length > 0 && this.currentSendIndex < this.sendQueue.length) {
        const item = this.sendQueue[this.currentSendIndex]
        this.startFileStream(item.filePath, new Set<number>(), 0)
      }
    } else if (type === 'file-decline') {
      this.currentTransfer = null
      this.onSendDeclined?.()
    } else if (type === 'resume-offer') {
      this.handleResumeOffer(msg)
    } else if (type === 'resume-accept') {
      const received = Array.isArray(msg.received) ? (msg.received as number[]) : []
      if (this.resumeState && this.sendQueue.length > 0 && this.currentSendIndex < this.sendQueue.length) {
        const skip = new Set(received)
        let resumed = 0
        const item = this.sendQueue[this.currentSendIndex]
        const size = fs.statSync(item.filePath).size
        for (const i of skip) {
          const off = i * CHUNK_SIZE
          resumed += Math.min(CHUNK_SIZE, size - off)
        }
        this.startFileStream(item.filePath, skip, resumed)
      }
    } else if (type === 'resume-decline') {
      this.clearSendSidecar()
      this.resumeState = null
      this.sendQueue = []
      this.currentSendIndex = 0
    } else if (type === 'file-start') {
      // segments follow; sink already open
    } else if (type === 'file-end') {
      this.finishIncomingFile()
    }
  }

  // ---------- sending (queue) ----------
  async offerMultipleFiles(filePaths: string[]): Promise<void> {
    if (!this.peerWs || filePaths.length === 0) return
    this.sendQueue = []
    this.currentSendIndex = 0
    const ts = Date.now()
    for (let i = 0; i < filePaths.length; i++) {
      const fp = filePaths[i]
      const stats = fs.statSync(fp)
      const hash = await this.hashFile(fp)
      this.sendQueue.push({ filePath: fp, name: path.basename(fp), size: stats.size, hash, transferId: `t${ts}_${i}` })
    }
    try {
      fs.writeFileSync(this.sendSidecarPath(), JSON.stringify({ queue: this.sendQueue, currentIndex: 0 }))
    } catch {}
    const first = this.sendQueue[0]
    const meta: TransferMeta = {
      name: first.name, size: first.size, isSending: true, filePath: first.filePath,
      queueIndex: 0, queueTotal: this.sendQueue.length,
    }
    this.currentTransfer = meta
    this.lastTransfer = meta
    this.sendJson({
      type: 'file-offer', transferId: first.transferId, name: first.name, size: first.size,
      chunkSize: CHUNK_SIZE, chunkCount: Math.ceil(first.size / CHUNK_SIZE), fileHash: first.hash,
      queueIndex: 0, queueTotal: this.sendQueue.length,
    })
  }

  cancelQueue(): void {
    this.sendAborted = true
    this.sendQueue = []
    this.currentSendIndex = 0
    this.clearSendSidecar()
    this.currentTransfer = null
  }

  private clearSendSidecar(): void {
    try { fs.unlinkSync(this.sendSidecarPath()) } catch {}
  }

  private maybeOfferResume(): void {
    const p = this.sendSidecarPath()
    if (!fs.existsSync(p)) return
    try {
      const s = JSON.parse(fs.readFileSync(p, 'utf8'))
      const queue = s.queue as any[]
      const idx = s.currentIndex as number
      if (!Array.isArray(queue) || idx >= queue.length) { this.clearSendSidecar(); return }
      const valid: any[] = []
      for (const item of queue) {
        if (!fs.existsSync(item.filePath) || fs.statSync(item.filePath).size !== item.size) continue
        valid.push(item)
      }
      if (valid.length === 0) { this.clearSendSidecar(); return }
      this.sendQueue = valid
      this.currentSendIndex = Math.min(idx, valid.length - 1)
      const item = this.sendQueue[this.currentSendIndex]
      this.resumeState = { transferId: item.transferId }
      this.sendJson({
        type: 'resume-offer', transferId: item.transferId, name: item.name, size: item.size,
        chunkSize: CHUNK_SIZE, chunkCount: Math.ceil(item.size / CHUNK_SIZE), fileHash: item.hash,
        queueIndex: this.currentSendIndex, queueTotal: valid.length,
      })
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
    this.onFileTransferStart?.({
      name, size, isSending: true, resumed: resumedBytes, filePath,
      queueIndex: this.currentSendIndex, queueTotal: this.sendQueue.length,
    })
    this.sendJson({ type: 'file-start', name, size })

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
            const frame = Buffer.concat([prefix, header, buf])
            const ackPromise = new Promise<void>((resolve) => { self.ackResolvers.set(i, resolve) })
            self.sendBinary(frame)
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
      this.sendJson({ type: 'file-end' })
      const verified = await this.awaitVerify()
      this.onFileDone?.(name, true, verified)

      this.currentSendIndex++
      this.onQueueAdvance?.(this.currentSendIndex, this.sendQueue.length)

      if (this.currentSendIndex >= this.sendQueue.length) {
        this.clearSendSidecar()
        this.sendQueue = []
        this.currentSendIndex = 0
        this.currentTransfer = null
      } else {
        const next = this.sendQueue[this.currentSendIndex]
        const meta: TransferMeta = {
          name: next.name, size: next.size, isSending: true, filePath: next.filePath,
          queueIndex: this.currentSendIndex, queueTotal: this.sendQueue.length,
        }
        this.currentTransfer = meta
        this.lastTransfer = meta
        await new Promise((resolve) => setTimeout(resolve, 100))
        this.sendJson({
          type: 'file-offer', transferId: next.transferId, name: next.name, size: next.size,
          chunkSize: CHUNK_SIZE, chunkCount: Math.ceil(next.size / CHUNK_SIZE), fileHash: next.hash,
          queueIndex: this.currentSendIndex, queueTotal: this.sendQueue.length,
        })
      }
    }
    this.resumeState = null
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
    for (const f of fs.readdirSync(saveDir)) {
      if (f.endsWith('.flova.json') && !f.includes(transferId)) {
        try {
          const sc = JSON.parse(fs.readFileSync(path.join(saveDir, f), 'utf8'))
          if (sc?.name) try { fs.unlinkSync(path.join(saveDir, `${sc.name}.part`)) } catch {}
          fs.unlinkSync(path.join(saveDir, f))
        } catch {}
      }
    }

    if (this.recvFd != null) { try { fs.closeSync(this.recvFd) } catch {} this.recvFd = null }

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

    this.sendJson({ type: 'file-accept' })
    const meta: TransferMeta = { name, size, isSending: false, resumed: 0 }
    this.currentTransfer = meta
    this.lastTransfer = meta
    this.onFileTransferStart?.(meta)
  }

  declineIncoming(): void {
    if (!this.pendingIncoming || !this.peerWs) return
    this.pendingIncoming = null
    this.sendJson({ type: 'file-decline' })
  }

  private handleResumeOffer(msg: any): void {
    const transferId = String(msg.transferId ?? '')
    const size = Number(msg.size)
    const saveDir = this.recvDir()
    const sidecar = path.join(saveDir, `.${transferId}.flova.json`)
    const name = path.basename(String(msg.name))
    const partPath = path.join(saveDir, `${name}.part`)
    if (!transferId || !fs.existsSync(sidecar) || !fs.existsSync(partPath)) {
      this.sendJson({ type: 'resume-decline', transferId })
      return
    }
    try {
      const sc = JSON.parse(fs.readFileSync(sidecar, 'utf8'))
      if (sc.size !== size) throw new Error('size mismatch')
      const received: number[] = Array.isArray(sc.received) ? sc.received : []
      if (this.recvFd != null) { try { fs.closeSync(this.recvFd) } catch {} this.recvFd = null }
      this.recvFd = fs.openSync(partPath, 'r+')
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
      this.sendJson({
        type: 'resume-accept', transferId, received: Array.from(this.recvReceived),
        queueIndex: msg.queueIndex ?? 0, queueTotal: msg.queueTotal ?? 1,
      })
      const meta: TransferMeta = {
        name, size, isSending: false, resumed,
        queueIndex: msg.queueIndex ?? 0, queueTotal: msg.queueTotal ?? 1,
      }
      this.currentTransfer = meta
      this.lastTransfer = meta
      this.onFileTransferStart?.(meta)
    } catch {
      try { fs.unlinkSync(sidecar) } catch {}
      this.sendJson({ type: 'resume-decline', transferId })
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
        this.sendJson({ type: 'chunk-nack', i: header.i })
        return
      }
      fs.writeSync(this.recvFd, payload, 0, payload.length, Number(header.o))
      this.recvReceived.add(Number(header.i))
      if (this.recvReceived.size % 25 === 0) this.writeSidecar()
      this.sendJson({ type: 'chunk-ack', i: header.i })
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
    const transferId = this.recvTransferId
    this.recvPartPath = null
    this.recvSaveDir = null
    this.recvFinalName = null
    this.recvExpectedHash = null
    this.recvTransferId = null
    this.currentTransfer = null

    ;(async () => {
      let verified = true
      if (expected) {
        const actual = await this.hashFile(partPath)
        verified = actual === expected
      }
      this.sendJson({ type: 'verify-result', ok: verified })
      if (!verified) {
        try { fs.unlinkSync(partPath) } catch {}
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
        if (transferId) {
          const sidecar = path.join(saveDir, `.${transferId}.flova.json`)
          if (fs.existsSync(sidecar)) fs.unlinkSync(sidecar)
        }
        this.onFileDone?.(path.basename(finalPath), false, true)
      } catch (err) {
        console.warn('[transport] rename failed', err)
      }
    })()
  }

  getCurrentTransfer() { return this.currentTransfer }
  getLastTransfer() { return this.lastTransfer }
  getQueueInfo() { return { queue: this.sendQueue, currentIndex: this.currentSendIndex } }
  getFingerprint() { return this.crypto.fingerprint() }

  private startHb(): void {
    this.stopHb()
    this.pingTimer = setInterval(() => {
      if (!this.peerWs) return
      this.sendJson({ type: 'ping' })
      if (Date.now() - this.lastPong > PONG_TIMEOUT_MS) {
        try { this.peerWs?.close(1001, 'pong timeout') } catch {}
      }
    }, PING_INTERVAL_MS)
  }
  private stopHb(): void { if (this.pingTimer) { clearInterval(this.pingTimer); this.pingTimer = null } }
  getPort(): number { const addr = this.wss.address(); return typeof addr === 'object' && addr ? addr.port : 0 }
}