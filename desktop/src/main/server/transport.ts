/**
 * WORKFLOW OF THIS FILE:
 * 1. Starts a WebSocket server on 0.0.0.0:8431.
 * 2. When a phone connects, it expects a "hello" JSON message.
 * 3. We reply with "hello-ack" containing the laptop's name.
 * 4. While a peer is paired, we send "ping" every 3 seconds and expect "pong".
 * 5. If no pong is received within 10 seconds, the peer is declared dead
 *    and the socket is closed, firing the onPeerDisconnected event.
 * 6. Incoming "ping" from the phone is answered with "pong" right away.
 * 7. Only one peer is allowed at a time in this phase.
 *
 * CLASSES / FUNCTIONS:
 *  - TransportServer           : owns the WS server, the active peer, and the ping timer.
 *  - TransportServer.handle    : wires message parsing and close handling.
 *  - TransportServer.startHb   : starts the ping/pong timer.
 *  - TransportServer.stopHb    : clears the timer when peer disconnects.
 */
import { WebSocketServer, WebSocket } from 'ws'

export type Peer = { name: string; platform: string }

const PING_INTERVAL_MS = 3000
const PONG_TIMEOUT_MS = 10000

export class TransportServer {
  private wss: WebSocketServer
  private peerWs: WebSocket | null = null
  private peer: Peer | null = null
  private selfName: string
  private pingTimer: NodeJS.Timeout | null = null
  private lastPong: number = 0

  onPeerConnected?: (peer: Peer) => void
  onPeerDisconnected?: () => void

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

    ws.on('message', (raw) => {
      try {
        const msg = JSON.parse(raw.toString())
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
        }
      } catch (err) {
        console.warn('[transport] bad frame', err)
      }
    })

    ws.on('close', () => {
      if (this.peerWs === ws) {
        this.stopHb()
        this.peerWs = null
        this.peer = null
        this.onPeerDisconnected?.()
      }
    })

    ws.on('error', (err) => console.warn('[transport] peer error', err))
  }

  private startHb(): void {
    this.stopHb()
    this.pingTimer = setInterval(() => {
      if (!this.peerWs) return
      try {
        this.peerWs.send(JSON.stringify({ type: 'ping' }))
      } catch {
        // swallow
      }
      if (Date.now() - this.lastPong > PONG_TIMEOUT_MS) {
        console.warn('[transport] peer unresponsive, closing')
        try {
          this.peerWs?.close(1001, 'pong timeout')
        } catch {
          // swallow
        }
      }
    }, PING_INTERVAL_MS)
  }

  private stopHb(): void {
    if (this.pingTimer) {
      clearInterval(this.pingTimer)
      this.pingTimer = null
    }
  }

  getPort(): number {
    const addr = this.wss.address()
    return typeof addr === 'object' && addr ? addr.port : 0
  }
}