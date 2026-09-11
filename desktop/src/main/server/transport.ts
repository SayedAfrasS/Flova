/**
 * WORKFLOW OF THIS FILE:
 * 1. Manages the WebSocket server and the active peer connection.
 * 2. Handles the handshake protocol: offer -> accept -> stream -> end.
 * 3. Tracks the "currentTransfer" state so the UI can read the real file name and size.
 * 4. offerFile() sends metadata to the peer and waits for them to say "accept".
 * 5. When "file-accept" is received, it opens the file stream and sends chunks.
 * 6. Handles incoming files from the peer by writing binary chunks to disk.
 */
import { WebSocketServer, WebSocket } from 'ws'
import { app } from 'electron'
import * as fs from 'fs'
import * as path from 'path'

export type Peer = { name: string; platform: string }

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

  // File receiving state
  private writeStream: fs.WriteStream | null = null
  private currentFileName: string | null = null
  private currentFileSize: number = 0
  private receivedBytes: number = 0

  // File sending state (handshake)
  private pendingFilePath: string | null = null

  // Shared state for the UI
  private currentTransfer: { name: string; size: number; isSending: boolean } | null = null

  onPeerConnected?: (peer: Peer) => void
  onPeerDisconnected?: () => void
  onFileTransferStart?: (name: string, size: number, isSending: boolean) => void
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
    if (this.peerWs) { ws.close(1013, 'already connected'); return; }

    ws.on('message', (data, isBinary) => {
      if (isBinary) {
        if (this.writeStream) {
          this.writeStream.write(data);
          this.receivedBytes += data.length;
          this.onFileProgress?.(data.length, false);
        }
      } else {
        try {
          const msg = JSON.parse(data.toString());
          if (msg?.type === 'hello') {
            this.peerWs = ws;
            this.peer = { name: String(msg.name ?? 'Phone'), platform: String(msg.platform ?? 'mobile') };
            this.lastPong = Date.now();
            ws.send(JSON.stringify({ type: 'hello-ack', name: this.selfName, platform: 'desktop' }));
            this.startHb();
            this.onPeerConnected?.(this.peer);
          } else if (msg?.type === 'ping') { ws.send(JSON.stringify({ type: 'pong' })); } 
          else if (msg?.type === 'pong') { this.lastPong = Date.now(); } 
          else if (msg?.type === 'file-accept') {
            if (this.pendingFilePath) {
              this.startFileStream(this.pendingFilePath);
              this.pendingFilePath = null;
            }
          } else if (msg?.type === 'file-start') {
            this.handleIncomingFile(msg.name, msg.size);
          } else if (msg?.type === 'file-end') {
            this.finishIncomingFile();
          }
        } catch (err) { console.warn('[transport] bad json frame', err); }
      }
    })

    ws.on('close', () => {
      if (this.peerWs === ws) {
        this.stopHb(); this.peerWs = null; this.peer = null;
        if (this.writeStream) this.writeStream.close();
        this.writeStream = null;
        this.currentTransfer = null;
        this.onPeerDisconnected?.();
      }
    })
    ws.on('error', (err) => console.warn('[transport] peer error', err));
  }

  // Step 1: Send offer to peer
  offerFile(filePath: string): void {
    if (!this.peerWs) return;
    this.pendingFilePath = filePath;
    const stats = fs.statSync(filePath);
    const name = path.basename(filePath);
    const size = stats.size;
    
    this.currentTransfer = { name, size, isSending: true };
    this.peerWs.send(JSON.stringify({ type: 'file-offer', name, size }));
    this.onFileTransferStart?.(name, size, true);
  }

  // Step 3: Stream chunks after peer accepts
  private async startFileStream(filePath: string): Promise<void> {
    if (!this.peerWs) return;
    const stats = fs.statSync(filePath);
    const name = path.basename(filePath);
    const size = stats.size;
    
    this.peerWs.send(JSON.stringify({ type: 'file-start', name, size }));
    const rs = fs.createReadStream(filePath, { highWaterMark: CHUNK_SIZE });
    
    for await (const chunk of rs) {
      while (this.peerWs.bufferedAmount > 1024 * 1024) {
        await new Promise(resolve => setTimeout(resolve, 10));
      }
      this.peerWs.send(chunk);
      this.onFileProgress?.(chunk.length, true);
    }
    
    this.peerWs.send(JSON.stringify({ type: 'file-end' }));
    this.onFileDone?.(name, true);
    this.currentTransfer = null;
  }

  private handleIncomingFile(name: string, size: number): void {
    const safeName = path.basename(name);
    const saveDir = path.join(app.getPath('downloads'), 'Flova');
    if (!fs.existsSync(saveDir)) fs.mkdirSync(saveDir, { recursive: true });
    const savePath = path.join(saveDir, safeName);
    
    this.currentFileName = safeName;
    this.currentFileSize = size;
    this.receivedBytes = 0;
    this.writeStream = fs.createWriteStream(savePath);
    
    this.currentTransfer = { name: safeName, size, isSending: false };
    this.onFileTransferStart?.(safeName, size, false);
  }

  private finishIncomingFile(): void {
    if (this.writeStream) {
      this.writeStream.end(() => {
        if (this.currentFileName) this.onFileDone?.(this.currentFileName, false);
        this.writeStream = null;
        this.currentFileName = null;
        this.currentTransfer = null;
      });
    }
  }

  getCurrentTransfer() { return this.currentTransfer; }

  private startHb(): void {
    this.stopHb();
    this.pingTimer = setInterval(() => {
      if (!this.peerWs) return;
      try { this.peerWs.send(JSON.stringify({ type: 'ping' })); } catch {}
      if (Date.now() - this.lastPong > PONG_TIMEOUT_MS) {
        try { this.peerWs?.close(1001, 'pong timeout'); } catch {}
      }
    }, PING_INTERVAL_MS);
  }

  private stopHb(): void { if (this.pingTimer) { clearInterval(this.pingTimer); this.pingTimer = null; } }
  getPort(): number { const addr = this.wss.address(); return typeof addr === 'object' && addr ? addr.port : 0; }
}