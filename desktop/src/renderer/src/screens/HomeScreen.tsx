/**
 * WORKFLOW OF THIS FILE:
 * 1. Main connected dashboard of the desktop app.
 * 2. Subscribes to peer-connected / peer-disconnected events from the main process.
 * 3. When the phone drops the connection, a red "Connection lost" banner slides in
 *    from the top of the page.
 * 4. When the phone reconnects, the banner disappears automatically.
 * 5. The device name in the connected card updates to the live peer name.
 * 6. Send / Receive cards and Recent transfers keep working the same way.
 *
 * FUNCTIONS:
 *  - HomeScreen() : owns the peer state + subscriptions.
 */
import { useEffect, useState } from "react";
import { useNav } from "../state/nav";

export function HomeScreen() {
  const go = useNav((s) => s.go);
  const [peerName, setPeerName] = useState<string | null>(null);
  const [connected, setConnected] = useState(true);

  // subscribe to peer events + load initial name
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!window.flova) return;
      const name = await window.flova.getPeerName();
      if (!cancelled) setPeerName(name);
    })();

    const off1 = window.flova?.onPeerConnected((name) => {
      setPeerName(name);
      setConnected(true);
    });
    const off2 = window.flova?.onPeerDisconnected(() => {
      setConnected(false);
    });
    return () => {
      cancelled = true;
      off1?.();
      off2?.();
    };
  }, []);

  return (
    <div className="w-full max-w-4xl mx-auto relative">
      {/* Connection-lost banner */}
      <div
        className={`transition-all duration-300 ease-out overflow-hidden ${
          connected ? "max-h-0 opacity-0" : "max-h-24 opacity-100"
        }`}
      >
        <div className="mx-8 mt-4 flex items-center justify-between rounded-control border border-error/30 bg-error/5 px-4 py-3">
          <div className="flex items-center gap-3">
            <span className="size-2 rounded-full bg-error" />
            <div>
              <p className="text-[13px] font-medium text-ink">Connection lost</p>
              <p className="text-[12px] text-ink-2">Waiting for {peerName ?? "your phone"} to return…</p>
            </div>
          </div>
          <button
            onClick={() => go("connect")}
            className="text-[12px] text-error hover:text-error/80 transition-colors"
          >
            Reconnect
          </button>
        </div>
      </div>

      <div className={`p-8 transition-opacity duration-300 ${connected ? "opacity-100" : "opacity-60"}`}>
        <header className="mb-10">
          <h1 className="text-[34px] font-semibold tracking-tight text-ink">
            {connected ? "Your phone is connected" : "Connection interrupted"}
          </h1>
          <p className="mt-2 text-[15px] text-ink-2">
            {connected ? "Ready to transfer files." : "File transfers are paused until the connection returns."}
          </p>
        </header>

        <div className="flex items-center gap-4 mb-10 p-4 border border-line rounded-card bg-surface">
          <div className="size-10 rounded-full bg-section flex items-center justify-center">
            <svg viewBox="0 0 24 24" className="size-5 text-ink-2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="5" y="2" width="14" height="20" rx="2" ry="2" /><line x1="12" y1="18" x2="12.01" y2="18" /></svg>
          </div>
          <div className="flex-1">
            <p className="text-[15px] font-medium text-ink">{peerName ?? "Phone"}</p>
            <p className="text-[13px] text-ink-2 flex items-center gap-1.5">
              <span className={`size-1.5 rounded-full ${connected ? "bg-success" : "bg-error"}`} />
              {connected ? "Connected" : "Disconnected"}
            </p>
          </div>
          <button onClick={() => go("connect")} className="text-[13px] text-ink-2 hover:text-ink transition-colors">
            Disconnect
          </button>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-12">
          <button
            onClick={() => go("send")}
            disabled={!connected}
            className="group text-left p-6 border border-line rounded-card bg-canvas hover:bg-surface transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <div className="size-10 rounded-full bg-accent-soft flex items-center justify-center mb-4 group-hover:bg-accent transition-colors">
              <svg viewBox="0 0 24 24" className="size-5 text-accent group-hover:text-white transition-colors" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="22" y1="2" x2="11" y2="13" /><polygon points="22 2 15 22 11 13 2 9 22 2" /></svg>
            </div>
            <h3 className="text-[18px] font-semibold text-ink mb-1">Send a file</h3>
            <p className="text-[14px] text-ink-2">Choose a file from your laptop and send it to your phone.</p>
          </button>

          <button
            onClick={() => go("receive")}
            disabled={!connected}
            className="group text-left p-6 border border-line rounded-card bg-canvas hover:bg-surface transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <div className="size-10 rounded-full bg-section flex items-center justify-center mb-4">
              <svg viewBox="0 0 24 24" className="size-5 text-ink-2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="22 12 16 12 14 15 10 15 8 12 2 12" /><path d="M5.45 5.11L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z" /></svg>
            </div>
            <h3 className="text-[18px] font-semibold text-ink mb-1">Receive a file</h3>
            <p className="text-[14px] text-ink-2">Receive a file from your phone.</p>
          </button>
        </div>

        <section>
          <h2 className="text-[16px] font-semibold text-ink mb-4">Recent transfers</h2>
          <div className="space-y-0">
            {[
              { name: "document.pdf", size: "2.4 MB", time: "Today, 10:42 AM" },
              { name: "presentation.key", size: "14.1 MB", time: "Yesterday" },
              { name: "vacation_video.mp4", size: "1.8 GB", time: "Sep 5" },
            ].map((item) => (
              <div key={item.name} className="flex items-center gap-4 py-3 border-b border-line last:border-0">
                <div className="size-9 rounded-control bg-section flex items-center justify-center">
                  <svg viewBox="0 0 24 24" className="size-4 text-ink-2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><polyline points="14 2 14 8 20 8" /></svg>
                </div>
                <div className="flex-1">
                  <p className="text-[14px] font-medium text-ink">{item.name}</p>
                  <p className="text-[12px] text-ink-3">{item.size}</p>
                </div>
                <span className="text-[13px] text-ink-3">{item.time}</span>
                <span className="text-[13px] text-success font-medium">Completed</span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}