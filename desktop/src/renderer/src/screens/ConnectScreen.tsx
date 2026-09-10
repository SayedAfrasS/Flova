/**
 * WORKFLOW OF THIS FILE:
 * 1. Phase-4 connect screen: shows the live QR code and connection status.
 * 2. On mount it asks the main process for the laptop's hotspot IP + port.
 * 3. It generates a JSON payload matching the protocol and renders it as a QR code.
 * 4. It subscribes to peer-connected events from the main process.
 * 5. When a phone pairs, a "Continue to Home" button appears.
 *
 * FUNCTIONS:
 *  - ConnectScreen() : owns the live state, payload generation, and event subscriptions.
 */
import { useEffect, useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { Button, FlovaMark } from "../components/primitives";
import { useNav } from "../state/nav";

type NetState = { host: string; port: number; state: "waiting" | "paired"; peerName: string | null };

export function ConnectScreen() {
  const go = useNav((s) => s.go);
  const [net, setNet] = useState<NetState>({ host: "0.0.0.0", port: 8431, state: "waiting", peerName: null });

  // boot: read server info + current state + peer name from main process
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!window.flova) return;
      const info = await window.flova.getServer();
      const state = await window.flova.getState();
      const peerName = await window.flova.getPeerName();
      if (!cancelled) setNet({ host: info.host, port: info.port, state, peerName });
    })();

    // subscribe to live peer events
    const offConnected = window.flova?.onPeerConnected((name) =>
      setNet((prev) => ({ ...prev, state: "paired", peerName: name })),
    );
    const offDisconnected = window.flova?.onPeerDisconnected(() =>
      setNet((prev) => ({ ...prev, state: "waiting", peerName: null })),
    );
    return () => {
      cancelled = true;
      offConnected?.();
      offDisconnected?.();
    };
  }, []);

  // real protocol payload that the mobile app will scan
  const payload = JSON.stringify({
    v: 1,
    app: "flova",
    host: net.host,
    port: net.port,
    sid: `session-${Date.now()}`,
  });

  return (
    <div className="flex h-full flex-col">
      <header className="flex h-14 items-center justify-between border-b border-line/70 px-6">
        <div className="flex items-center gap-2">
          <FlovaMark />
          <span className="text-[15px] font-semibold tracking-tight">flova</span>
        </div>
      </header>

      <main className="flex flex-1 flex-col items-center justify-center gap-6 px-8">
        <div className="text-center">
          <h1 className="text-[34px] font-semibold tracking-tight text-ink">Connect your phone</h1>
          <p className="mt-2 text-[15px] text-ink-2">
            {net.state === "paired"
              ? `Connected to ${net.peerName ?? "your phone"}.`
              : "Open the app on your phone and scan this code."}
          </p>
        </div>

        <div className="relative">
          <div aria-hidden="true" className="absolute -inset-3 rounded-panel bg-accent-soft animate-halo" />
          <div className="relative rounded-panel border border-line bg-canvas p-6 shadow-soft">
            <QRCodeSVG value={payload} size={192} fgColor="#111827" bgColor="#FFFFFF" level="M" />
          </div>
        </div>

        {net.state === "paired" ? (
          <div className="flex flex-col items-center gap-3">
            <div className="flex items-center gap-2 text-[13px] text-success">
              <span className="size-2 rounded-full bg-success" />
              Connected
            </div>
            <Button onClick={() => go("home")}>Continue to Home</Button>
          </div>
        ) : (
          <div className="flex items-center gap-2 text-[13px] text-ink-2">
            <span className="size-2 rounded-full bg-ink-3 animate-pulse-dot" />
            Waiting for your phone
          </div>
        )}
      </main>

      <footer className="pb-8 text-center text-[13px] text-ink-3">
        Make sure your laptop is connected to your phone&apos;s hotspot.
      </footer>
    </div>
  );
}