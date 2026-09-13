/**
 * WORKFLOW OF THIS FILE:
 * 1. Manages a queue of files waiting to be sent.
 * 2. Files are added via enqueue() with their path and metadata.
 * 3. The queue processes files one at a time: dequeue → send → next.
 * 4. Each transfer emits progress events for its specific file.
 * 5. Supports cancellation of individual queued files.
 * 6. Tracks total bytes across all queued files for aggregate progress.
 *
 * FUNCTIONS:
 *  - enqueue()          : add a file to the queue.
 *  - dequeue()          : remove and return the next file to send.
 *  - peek()             : see the next file without removing it.
 *  - cancel()           : remove a specific file from the queue.
 *  - clear()            : empty the entire queue.
 *  - getStats()         : total files, bytes, and active transfer ID.
 */

export interface QueuedFile {
  id: string;
  path: string;
  name: string;
  size: number;
  status: 'pending' | 'active' | 'completed' | 'failed';
  progress: number;
}

export class TransferQueue {
  private queue: QueuedFile[] = [];
  private activeId: string | null = null;

  enqueue(path: string, name: string, size: number): string {
    const id = `q_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    this.queue.push({
      id,
      path,
      name,
      size,
      status: 'pending',
      progress: 0,
    });
    return id;
  }

  dequeue(): QueuedFile | null {
    if (this.queue.length === 0) return null;
    const next = this.queue.find((f) => f.status === 'pending');
    if (next) {
      next.status = 'active';
      this.activeId = next.id;
    }
    return next || null;
  }

  peek(): QueuedFile | null {
    return this.queue.find((f) => f.status === 'pending') || null;
  }

  cancel(id: string): boolean {
    const idx = this.queue.findIndex((f) => f.id === id);
    if (idx === -1) return false;
    if (this.queue[idx].status === 'active') {
      this.activeId = null;
    }
    this.queue.splice(idx, 1);
    return true;
  }

  complete(id: string, success: boolean): void {
    const file = this.queue.find((f) => f.id === id);
    if (file) {
      file.status = success ? 'completed' : 'failed';
      file.progress = 100;
      if (this.activeId === id) {
        this.activeId = null;
      }
    }
  }

  updateProgress(id: string, progress: number): void {
    const file = this.queue.find((f) => f.id === id);
    if (file) {
      file.progress = progress;
    }
  }

  clear(): void {
    this.queue = [];
    this.activeId = null;
  }

  getStats(): { total: number; bytes: number; activeId: string | null } {
    const bytes = this.queue.reduce((sum, f) => sum + f.size, 0);
    return {
      total: this.queue.length,
      bytes,
      activeId: this.activeId,
    };
  }

  getAll(): QueuedFile[] {
    return [...this.queue];
  }
}