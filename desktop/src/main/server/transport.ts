/**
 * WORKFLOW OF THIS FILE:
 * 1. Starts a WebSocket server on 0.0.0.0:8431.
 * 2. When a phone connects, it sends a "hello" JSON message.
 * 3. We reply with "hello-ack" containing the laptop's name.
 * 4. We emit onPeerConnected / onPeerDisconnected events to the main process.
 * 5. Only one peer is allowed at a time in this phase.
 *
 * CLASSES / FUNCTIONS:
 *  - TransportServer        : owns the WebSocket server and the active peer.
 *  - TransportServer.handle : wires message parsing and close handling.
 */
import { WebSocketServer, WebSocket } from 'ws'

export type Peer = { name: string; platform: string }

export class TransportServer {
  private wss: WebSocketServer
  private peerWs: WebSocket | null = null
  private selfName: string

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
    // reject second peer while first is still connected
    if (this.peerWs) {
      ws.close(1013, 'already connected')
      return
    }

    ws.on('message', (raw) => {
      try {
        const msg = JSON.parse(raw.toString())
        if (msg?.type === 'hello') {
          this.peerWs = ws
          const peer: Peer = { name: String(msg.name ?? 'Phone'), platform: String(msg.platform ?? 'mobile') }
          ws.send(JSON.stringify({ type: 'hello-ack', name: this.selfName, platform: 'desktop' }))
          this.onPeerConnected?.(peer)
        }
      } catch (err) {
        console.warn('[transport] bad frame', err)
      }
    })

    ws.on('close', () => {
      if (this.peerWs === ws) {
        this.peerWs = null
        this.onPeerDisconnected?.()
      }
    })

    ws.on('error', (err) => console.warn('[transport] peer error', err))
  }

  getPort(): number {
    const addr = this.wss.address()
    return typeof addr === 'object' && addr ? addr.port : 0
  }
}