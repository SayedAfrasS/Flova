/**
 * WORKFLOW OF THIS FILE:
 * 1. Shows a drag-and-drop zone for sending files.
 * 2. User can drag files from Explorer onto the screen, or click to browse.
 * 3. Once files are selected, shows their names and sizes.
 * 4. "Send files" queues them via sendMultipleFiles IPC and navigates to Progress.
 */
import { useState, useCallback, DragEvent } from 'react'
import { useNav } from '../state/nav'
import { FlovaMark } from '../components/primitives'

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`
  return `${Math.round(bytes / 1024)} KB`
}

interface SelectedFile {
  path: string
  name: string
  size: number
}

export function SendScreen() {
  const go = useNav((s) => s.go)
  const [files, setFiles] = useState<SelectedFile[]>([])
  const [isDragging, setIsDragging] = useState(false)
  const [isSending, setIsSending] = useState(false)

  const handleFiles = useCallback(async (paths: string[]) => {
    if (!window.flova || paths.length === 0) return
    const selected: SelectedFile[] = []
    for (const p of paths) {
      const stats = await window.flova.getFileStats(p)
      if (stats) selected.push({ path: p, name: stats.name, size: stats.size })
    }
    if (selected.length > 0) setFiles(selected)
  }, [])

  const handleDrop = useCallback((e: DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
    const paths = Array.from(e.dataTransfer.files).map(f => (f as any).path as string)
    handleFiles(paths)
  }, [handleFiles])

  const handleDragOver = useCallback((e: DragEvent) => {
    e.preventDefault()
    setIsDragging(true)
  }, [])

  const handleDragLeave = useCallback(() => {
    setIsDragging(false)
  }, [])

  const handleBrowse = useCallback(async () => {
    if (!window.flova) return
    const paths = await window.flova.pickMultipleFiles()
    if (paths && paths.length > 0) handleFiles(paths)
  }, [handleFiles])

  const handleSend = useCallback(async () => {
    if (files.length === 0 || !window.flova) return
    setIsSending(true)
    await window.flova.sendMultipleFiles(files.map(f => f.path))
    go('progress')
  }, [files, go])

  return (
    <div className="w-full max-w-sm mx-auto flex flex-col items-center justify-center gap-6 p-8 text-center">
      <div className="flex items-center gap-2">
        <FlovaMark />
        <span className="text-[20px] font-semibold tracking-tight text-ink">flova</span>
      </div>

      <div
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onClick={handleBrowse}
        className={`
          w-full rounded-card border-2 border-dashed p-8 flex flex-col items-center gap-4
          cursor-pointer transition-all duration-200
          ${isDragging
            ? 'border-accent bg-accent-soft scale-[1.02]'
            : 'border-line bg-surface hover:border-accent hover:bg-accent-soft'
          }
        `}
      >
        <svg viewBox="0 0 24 24" className="size-12 text-accent" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
          <polyline points="17 8 12 3 7 8" />
          <line x1="12" y1="3" x2="12" y2="15" />
        </svg>
        <div>
          <p className="text-[15px] font-medium text-ink">
            {isDragging ? 'Release to select files' : 'Drag files here'}
          </p>
          <p className="text-[13px] text-ink-2 mt-1">or click to browse</p>
        </div>
      </div>

      {files.length > 0 && (
        <>
          <div className="w-full rounded-card border border-line bg-surface divide-y divide-line">
            {files.map((f, i) => (
              <div key={i} className="flex items-center gap-3 px-4 py-3">
                <svg viewBox="0 0 24 24" className="size-5 text-ink-2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                  <polyline points="14 2 14 8 20 8" />
                </svg>
                <div className="flex-1 min-w-0 text-left">
                  <p className="text-[13px] font-medium text-ink truncate">{f.name}</p>
                  <p className="text-[12px] text-ink-2">{formatBytes(f.size)}</p>
                </div>
              </div>
            ))}
          </div>

          <div className="flex w-full flex-col gap-3">
            <button
              onClick={handleSend}
              disabled={isSending}
              className="w-full rounded-control bg-accent py-3 text-[14px] font-medium text-white shadow-sm hover:bg-accent-hover disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              {isSending ? 'Starting...' : `Send ${files.length} file${files.length > 1 ? 's' : ''}`}
            </button>
            <button
              onClick={() => setFiles([])}
              className="w-full rounded-control border border-line bg-surface py-3 text-[14px] font-medium text-ink hover:bg-section transition-colors"
            >
              Clear selection
            </button>
          </div>
        </>
      )}
    </div>
  )
}