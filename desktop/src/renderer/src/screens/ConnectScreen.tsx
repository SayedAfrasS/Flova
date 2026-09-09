import { QRCodeSVG } from "qrcode.react";
import { Button, FlovaMark } from "../components/primitives";
import { useNav } from "../state/nav";

// Prototype only: real schema, dummy values. Real payload arrives in Phase 4.
const DEMO_QR = JSON.stringify({
  v: 1, app: "flova", host: "192.168.43.100", port: 8431, sid: "demo-session", pk: "demo-key",
});

export function ConnectScreen() {
  const go = useNav((s) => s.go);

  return (
    <div className="flex h-full flex-col">
      <header className="flex h-14 items-center justify-between border-b border-line/70 px-6">
        <div className="flex items-center gap-2">
          <FlovaMark />
          <span className="text-[15px] font-semibold tracking-tight">flova</span>
        </div>
        <Button variant="ghost" aria-label="Settings" className="px-2" onClick={() => go("settings")}>
          <svg viewBox="0 0 20 20" className="size-5" fill="none" stroke="currentColor" strokeWidth="1.5">
            <circle cx="10" cy="10" r="3" />
            <path d="M10 2v2.2M10 15.8V18M18 10h-2.2M4.2 10H2M15.7 4.3l-1.6 1.6M5.9 14.1l-1.6 1.6M15.7 15.7l-1.6-1.6M5.9 5.9 4.3 4.3" />
          </svg>
        </Button>
      </header>

      <main className="flex flex-1 flex-col items-center justify-center gap-6 px-8">
        <div className="text-center">
          <h1 className="text-[34px] font-semibold tracking-tight text-ink">Connect your phone</h1>
          <p className="mt-2 text-[15px] text-ink-2">Open the app on your phone and scan this code.</p>
        </div>

        <div className="relative">
          <div aria-hidden="true" className="absolute -inset-3 rounded-panel bg-accent-soft animate-halo" />
          <div className="relative rounded-panel border border-line bg-canvas p-6 shadow-soft">
            <QRCodeSVG value={DEMO_QR} size={192} fgColor="#111827" bgColor="#FFFFFF" level="M" />
          </div>
        </div>

        <div className="flex items-center gap-2 text-[13px] text-ink-2">
          <span className="size-2 rounded-full bg-ink-3 animate-pulse-dot" />
          Waiting for your phone
        </div>

        {/* dev-only, removed in Phase 4 */}
        <button
          onClick={() => go("home")}
          className="text-[12px] text-ink-3 underline decoration-line underline-offset-4 transition-colors hover:text-ink-2"
        >
          Simulate phone scan (dev)
        </button>
      </main>

      <footer className="pb-8 text-center text-[13px] text-ink-3">
        Make sure your laptop is connected to your phone&apos;s hotspot.
      </footer>
    </div>
  );
}