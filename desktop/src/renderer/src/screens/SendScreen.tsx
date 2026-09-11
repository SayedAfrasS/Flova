/**
 * WORKFLOW OF THIS FILE:
 * 1. Allows the user to pick a file from their laptop using the native OS dialog.
 * 2. Uses the file:getStats IPC call to read the real file name and size from disk.
 * 3. When "Send file" is clicked, it triggers the offerFile() handshake.
 * 4. Navigates to the ProgressScreen to show real-time transfer stats.
 */
import { useState } from "react";
import { Button } from "../components/primitives";
import { useNav } from "../state/nav";

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${Math.round(bytes / 1024)} KB`;
}

export function SendScreen() {
  const go = useNav((s) => s.go);
  const [filePath, setFilePath] = useState<string | null>(null);
  const [fileName, setFileName] = useState("");
  const [fileSize, setFileSize] = useState(0);
  const [isSending, setIsSending] = useState(false);

  const handlePick = async () => {
    if (!window.flova) return;
    const picked = await window.flova.pickFile();
    if (picked) {
      setFilePath(picked);
      const stats = await window.flova.getFileStats(picked);
      if (stats) {
        setFileName(stats.name);
        setFileSize(stats.size);
      }
    }
  };

  const handleSend = async () => {
    if (!filePath || !window.flova) return;
    setIsSending(true);
    window.flova.sendFile(filePath);
    go("progress");
  };

  return (
    <div className="flex w-full max-w-sm mx-auto flex-col items-center justify-center gap-6 p-8">
      <div className="flex size-20 items-center justify-center rounded-card border border-line bg-surface">
        <svg viewBox="0 0 24 24" className="size-9 text-accent" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><polyline points="14 2 14 8 20 8" /></svg>
      </div>

      <div className="text-center">
        <h1 className="text-[20px] font-semibold tracking-tight text-ink">
          {fileName || "No file selected"}
        </h1>
        {fileName && <p className="mt-1 text-[13px] text-ink-2">{formatBytes(fileSize)}</p>}
      </div>

      {!fileName ? (
        <Button onClick={handlePick} className="w-full">Browse files</Button>
      ) : (
        <div className="flex w-full flex-col gap-2">
          <Button onClick={handleSend} disabled={isSending}>
            {isSending ? "Starting..." : "Send file"}
          </Button>
          <Button variant="secondary" onClick={() => go("home")}>Cancel</Button>
        </div>
      )}
    </div>
  );
}