/**
 * WORKFLOW OF THIS FILE:
 * 1. Tiny SQLite helper for transfer history (better-sqlite3, synchronous).
 * 2. Opens flova-history.db inside the Electron userData folder.
 * 3. recordTransfer() inserts one row per finished file (sent or received).
 * 4. listTransfers() returns rows newest-first for the Transfers page.
 */
import Database from 'better-sqlite3'
import { app } from 'electron'
import * as path from 'path'

export type HistoryRow = {
  id: number
  name: string
  size: number
  direction: string
  ok: number
  ts: number
}

let db: Database.Database | null = null

function getDb(): Database.Database {
  if (db) return db
  const file = path.join(app.getPath('userData'), 'flova-history.db')
  db = new Database(file)
  db.exec(`CREATE TABLE IF NOT EXISTS transfers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    size INTEGER NOT NULL,
    direction TEXT NOT NULL,
    ok INTEGER NOT NULL,
    ts INTEGER NOT NULL
  )`)
  return db
}

export function recordTransfer(name: string, size: number, direction: 'sent' | 'received', ok: boolean): void {
  getDb()
    .prepare('INSERT INTO transfers (name, size, direction, ok, ts) VALUES (?, ?, ?, ?, ?)')
    .run(name, size, direction, ok ? 1 : 0, Date.now())
}

export function listTransfers(limit = 100): HistoryRow[] {
  return getDb()
    .prepare('SELECT * FROM transfers ORDER BY ts DESC LIMIT ?')
    .all(limit) as HistoryRow[]
}