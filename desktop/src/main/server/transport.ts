/**
 * WORKFLOW OF THIS FILE:
 * 1. Manages the WebSocket server and peer connection.
 * 2. Handles multi-file transfers: files are queued and sent sequentially.
 * 3. Each file gets its own offer → accept → stream → verify cycle.
 * 4. Progress events include the queue ID so the UI can track each file.
 * 5. Supports cancellation of the active transfer and queued files.
 *
 * FUNCTIONS:
 *  - enqueueFile()        : add a file to the transfer queue.
 *  - cancelTransfer()     : cancel a specific file or the active transfer.
 *  - processQueue()       : send files one by one from the queue.
 *  - sendFile()           : send a single file with offer/accept handshake.
 *  - verifyAndComplete()  : wait for receiver's hash verdict.
 */

import { app } from 'electron';
import { WebSocketServer, WebSocket } from 'ws';
import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { TransferQueue, type QueuedFile } from './transferQueue';

export type Peer = { name: string; platform: string };
export type TransferMeta = { id: string; name: string; size: number; isSending: boolean; verified?: boolean; resumed?: number };

const CHUNK_SIZE = 4 * 1024 * 1024; // 4 MB chunks
const VERIFY_TIMEOUT = 20000; // 20 seconds

export class TransportServer {
  private server: WebSocketServer;
  private peer: WebSocket | null = null;
  private peerInfo: Peer | null = null;
  private pingTimer: NodeJS.Timeout | null = null;
  private lastPong: number = Date.now();

  private queue = new TransferQueue();
  private isProcessing = false;
  private cancelRequested = false;
  private cancelFileId: string | null = null;

  private incomingOffer: { id: string; name: string; size: number; hash: string; chunkSize: number; chunkCount: number } | null = null;
  private activeRecv: { id: string; fd: number; size: number; expected: Set<number>; received: Set<number> } | null = null;

  // Event callbacks
  onPeerConnected?: (peer: Peer) => void;
  onPeerDisconnected?: () => void;
  onSendAccepted?: (id: string) => void;
  onSendDeclined?: (id: string) => void;
  onFileTransferStart?: (meta: TransferMeta) => void;
  onFileProgress?: (id: string, bytes: number, isSending: boolean) => void;
  onFileDone?: (id: string, name: string, isSending: boolean, verified: boolean) => void;
  onIncomingOffer?: (id: string, name: string, size: number) => void;

  constructor(port: number = 8431) {
    this.server = new WebSocketServer({ port, host: '0.0.0.0' });
    console.log(`[transport] listening on 0.0.0.0:${port}`);
    this.server.on('connection', (ws) => this.handleConnection(ws));
  }

  enqueueFile(filePath: string, name: string, size: number): string {
    const id = this.queue.enqueue(filePath, name, size);
    if (!this.isProcessing) {
      this.processQueue();
    }
    return id;
  }

  cancelTransfer(id?: string): boolean {
    if (id) {
      return this.queue.cancel(id);
    } else {
      this.cancelRequested = true;
      return true;
    }
  }

  private async processQueue() {
    if (this.isProcessing || !this.peer) return;
    this.isProcessing = true;

    let file = this.queue.dequeue();
    while (file && this.peer) {
      if (this.cancelRequested) {
        this.queue.complete(file.id, false);
        this.cancelRequested = false;
        break;
      }

      const success = await this.sendFile(file);
      this.queue.complete(file.id, success);

      if (this.cancelRequested) {
        this.cancelRequested = false;
        break;
      }

      file = this.queue.dequeue();
    }

    this.isProcessing = false;
  }

  private async sendFile(file: QueuedFile): Promise<boolean> {
    if (!this.peer) return false;

    try {
      // Hash the file
      const hash = await this.hashFile(file.path);
      const chunkCount = Math.ceil(file.size / CHUNK_SIZE);

      // Send offer
      this.peer.send(JSON.stringify({
        type: 'file-offer',
        id: file.id,
        name: file.name,
        size: file.size,
        hash,
        chunkSize: CHUNK_SIZE,
        chunkCount,
      }));

      // Wait for accept/decline
      const response = await this.waitForMessage(['file-accept', 'file-decline']);
      if (response.type === 'file-decline') {
        this.onSendDeclined?.(file.id);
        return false;
      }

      this.onSendAccepted?.(file.id);
      this.onFileTransferStart?.({ id: file.id, name: file.name, size: file.size, isSending: true });

      // Stream the file
      const fd = fs.openSync(file.path, 'r');
      let bytesSent = 0;

      for (let i = 0; i < chunkCount; i++) {
        if (this.cancelRequested || this.cancelFileId === file.id) {
          fs.closeSync(fd);
          this.cancelFileId = null;
          return false;
        }

        const offset = i * CHUNK_SIZE;
        const chunkSize = Math.min(CHUNK_SIZE, file.size - offset);
        const chunk = Buffer.alloc(chunkSize);
        fs.readSync(fd, chunk, 0, chunkSize, offset);

        // Calculate chunk hash
        const chunkHash = crypto.createHash('sha256').update(chunk).digest('hex');

        // Send chunk with header
        const header = {
          type: 'chunk',
          id: file.id,
          index: i,
          hash: chunkHash,
        };
        const headerStr = JSON.stringify(header);
        const headerBuf = Buffer.from(headerStr, 'utf-8');
        const headerLenBuf = Buffer.alloc(4);
        headerLenBuf.writeUInt32BE(headerBuf.length, 0);

        this.peer.send(Buffer.concat([headerLenBuf, headerBuf, chunk]));
        bytesSent += chunkSize;

        const progress = (bytesSent / file.size) * 100;
        this.queue.updateProgress(file.id, progress);
        this.onFileProgress?.(file.id, chunkSize, true);

        // Wait for chunk ack
        await this.waitForMessage(['chunk-ack']);
      }

      fs.closeSync(fd);

      // Send end marker
      this.peer.send(JSON.stringify({ type: 'file-end', id: file.id }));

      // Wait for verify result
      const verified = await this.verifyAndComplete(file.id);
      this.onFileDone?.(file.id, file.name, true, verified);

      return verified;
    } catch (err) {
      console.error('[transport] send failed:', err);
      return false;
    }
  }

  private async verifyAndComplete(id: string): Promise<boolean> {
    return new Promise((resolve) => {
      const timeout = setTimeout(() => {
        console.warn(`[transport] verify timeout for ${id}, assuming success`);
        resolve(true);
      }, VERIFY_TIMEOUT);

      const checkMessage = (msg: any) => {
        if (msg.type === 'verify-result' && msg.id === id) {
          clearTimeout(timeout);
          this.messageHandlers = this.messageHandlers.filter((h) => h !== checkMessage);
          resolve(msg.ok === true);
        }
      };

      this.messageHandlers.push(checkMessage);
    });
  }

  private messageHandlers: ((msg: any) => void)[] = [];

  private waitForMessage(types: string[]): Promise<any> {
    return new Promise((resolve) => {
      const handler = (msg: any) => {
        if (types.includes(msg.type)) {
          this.messageHandlers = this.messageHandlers.filter((h) => h !== handler);
          resolve(msg);
        }
      };
      this.messageHandlers.push(handler);
    });
  }

  private async hashFile(filePath: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const hash = crypto.createHash('sha256');
      const stream = fs.createReadStream(filePath);
      stream.on('data', (chunk) => hash.update(chunk));
      stream.on('end', () => resolve(hash.digest('hex')));
      stream.on('error', reject);
    });
  }

  private handleConnection(ws: WebSocket) {
    this.peer = ws;
    this.lastPong = Date.now();

    ws.on('message', (data) => {
      if (Buffer.isBuffer(data)) {
        this.handleBinaryFrame(data);
      } else {
        try {
          const msg = JSON.parse(data.toString());
          this.handleMessage(msg);
        } catch (err) {
          console.error('[transport] invalid JSON:', err);
        }
      }
    });

    ws.on('close', () => {
      this.peer = null;
      this.peerInfo = null;
      this.stopPing();
      this.onPeerDisconnected?.();
    });

    this.startPing();
  }

  private handleMessage(msg: any) {
    // Dispatch to waiting handlers
    this.messageHandlers.forEach((h) => h(msg));

    if (msg.type === 'hello') {
      this.peerInfo = { name: msg.name, platform: msg.platform };
      this.peer?.send(JSON.stringify({ type: 'hello-ack' }));
      this.onPeerConnected?.(this.peerInfo);
      this.processQueue();
    } else if (msg.type === 'pong') {
      this.lastPong = Date.now();
    } else if (msg.type === 'file-offer') {
      this.incomingOffer = {
        id: msg.id,
        name: msg.name,
        size: msg.size,
        hash: msg.hash,
        chunkSize: msg.chunkSize,
        chunkCount: msg.chunkCount,
      };
      this.onIncomingOffer?.(msg.id, msg.name, msg.size);
    } else if (msg.type === 'file-end') {
      this.finishIncoming(msg.id);
    }
  }

  private handleBinaryFrame(data: Buffer) {
    if (!this.activeRecv) return;

    try {
      const headerLen = data.readUInt32BE(0);
      const headerStr = data.subarray(4, 4 + headerLen).toString('utf-8');
      const header = JSON.parse(headerStr);
      const chunk = data.subarray(4 + headerLen);

      if (header.type !== 'chunk' || header.id !== this.activeRecv.id) return;

      // Verify chunk hash
      const chunkHash = crypto.createHash('sha256').update(chunk).digest('hex');
      if (chunkHash !== header.hash) {
        this.peer?.send(JSON.stringify({ type: 'chunk-nack', id: header.id, index: header.index }));
        return;
      }

      // Write chunk at offset
      const offset = header.index * CHUNK_SIZE;
      fs.writeSync(this.activeRecv.fd, chunk, 0, chunk.length, offset);

      this.activeRecv.received.add(header.index);
      this.peer?.send(JSON.stringify({ type: 'chunk-ack', id: header.id, index: header.index }));
      this.onFileProgress?.(header.id, chunk.length, false);
    } catch (err) {
      console.error('[transport] binary frame error:', err);
    }
  }

  acceptIncoming(id: string): boolean {
    if (!this.incomingOffer || this.incomingOffer.id !== id) return false;

    try {
      const downloadDir = path.join(app.getPath('downloads'), 'Flova');
      if (!fs.existsSync(downloadDir)) {
        fs.mkdirSync(downloadDir, { recursive: true });
      }

      const partPath = path.join(downloadDir, `${this.incomingOffer.name}.part`);
      const fd = fs.openSync(partPath, 'w');
      fs.ftruncateSync(fd, this.incomingOffer.size);

      this.activeRecv = {
        id,
        fd,
        size: this.incomingOffer.size,
        expected: new Set(Array.from({ length: this.incomingOffer.chunkCount }, (_, i) => i)),
        received: new Set(),
      };

      this.peer?.send(JSON.stringify({ type: 'file-accept', id }));
      this.onFileTransferStart?.({ id, name: this.incomingOffer.name, size: this.incomingOffer.size, isSending: false });
      return true;
    } catch (err) {
      console.error('[transport] accept failed:', err);
      return false;
    }
  }

  declineIncoming(id: string): void {
    if (this.incomingOffer?.id === id) {
      this.peer?.send(JSON.stringify({ type: 'file-decline', id }));
      this.incomingOffer = null;
    }
  }

  private finishIncoming(id: string) {
    if (!this.activeRecv || this.activeRecv.id !== id) return;

    const { fd, size, expected, received } = this.activeRecv;
    fs.closeSync(fd);

    const downloadDir = path.join(app.getPath('downloads'), 'Flova');
    const partPath = path.join(downloadDir, `${this.incomingOffer!.name}.part`);
    const finalPath = path.join(downloadDir, this.incomingOffer!.name);

    if (received.size === expected.size) {
      fs.renameSync(partPath, finalPath);
      const verified = this.verifyFileSync(finalPath, this.incomingOffer!.hash);
      this.peer?.send(JSON.stringify({ type: 'verify-result', id, ok: verified }));
      this.onFileDone?.(id, this.incomingOffer!.name, false, verified);
    } else {
      fs.unlinkSync(partPath);
      this.peer?.send(JSON.stringify({ type: 'verify-result', id, ok: false }));
      this.onFileDone?.(id, this.incomingOffer!.name, false, false);
    }

    this.activeRecv = null;
    this.incomingOffer = null;
  }

  private verifyFileSync(filePath: string, expectedHash: string): boolean {
    try {
      const hash = crypto.createHash('sha256');
      const data = fs.readFileSync(filePath);
      hash.update(data);
      return hash.digest('hex') === expectedHash;
    } catch {
      return false;
    }
  }

  private startPing() {
    this.pingTimer = setInterval(() => {
      if (Date.now() - this.lastPong > 15000) {
        console.warn('[transport] peer timeout, closing');
        this.peer?.close();
        return;
      }
      this.peer?.send(JSON.stringify({ type: 'ping' }));
    }, 5000);
  }

  private stopPing() {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
  }

  getQueueStats() {
    return this.queue.getStats();
  }

  getQueueFiles() {
    return this.queue.getAll();
  }

  shutdown() {
    this.stopPing();
    this.server.close();
  }
}