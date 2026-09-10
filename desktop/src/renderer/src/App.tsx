/**
 * WORKFLOW OF THIS FILE:
 * 1. This is the root of the desktop UI.
 * 2. It reads the current screen name from the nav store (state/nav.ts).
 * 3. If not connected yet, it shows the QR connect screen alone.
 * 4. After connecting, it shows Sidebar + the current screen inside.
 * 5. The SCREENS map connects each screen name to its component.
 */
import type { ComponentType } from "react";
import { useNav, type Screen } from "./state/nav";
import { ConnectScreen } from "./screens/ConnectScreen";
import { HomeScreen } from "./screens/HomeScreen";
import { SendScreen } from "./screens/SendScreen";
import { ReceiveScreen } from "./screens/ReceiveScreen";
import { ProgressScreen } from "./screens/ProgressScreen";
import { CompleteScreen } from "./screens/CompleteScreen";
import { QueueScreen } from "./screens/QueueScreen";
import { HistoryScreen } from "./screens/HistoryScreen";
import { Sidebar } from "./components/Sidebar";

const SCREENS: Record<Screen, ComponentType> = {
  connect: ConnectScreen,
  home: HomeScreen,
  send: SendScreen,
  receive: ReceiveScreen,
  progress: ProgressScreen,
  complete: CompleteScreen,
  queue: QueueScreen,
  history: HistoryScreen,
  settings: () => <div className="p-8 text-center text-ink-2">Settings (coming soon)</div>,
};

export default function App() {
  const screen = useNav((s) => s.screen);
  const CurrentScreen = SCREENS[screen];

  if (screen === "connect") return <ConnectScreen />;

  return (
    <div className="flex h-full">
      <Sidebar />
      <main className="flex flex-1 justify-center overflow-auto bg-canvas">
        <CurrentScreen />
      </main>
    </div>
  );
}