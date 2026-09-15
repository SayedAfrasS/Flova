/**
 * WORKFLOW OF THIS FILE:
 * 1. Root of the desktop UI: picks the screen from the nav store.
 * 2. Global watchers: incoming offer jumps to Receive; transfer start (including
 *    resume) jumps to Progress while on Home.
 */
import { useEffect, type ComponentType } from "react";
import { useNav, type Screen } from "./state/nav";
import { ConnectScreen } from "./screens/ConnectScreen";
import { HomeScreen } from "./screens/HomeScreen";
import { SendScreen } from "./screens/SendScreen";
import { ReceiveScreen } from "./screens/ReceiveScreen";
import { ProgressScreen } from "./screens/ProgressScreen";
import { CompleteScreen } from "./screens/CompleteScreen";
import { QueueScreen } from "./screens/QueueScreen";
import { HistoryScreen } from "./screens/HistoryScreen";
import { SettingsScreen } from "./screens/SettingsScreen";
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
  settings: SettingsScreen,
};

export default function App() {
  const screen = useNav((s) => s.screen);
  const CurrentScreen = SCREENS[screen];

  useEffect(() => {
    const offOffer = window.flova?.onIncomingOffer(() => {
      const nav = useNav.getState();
      if (nav.screen === "home") nav.go("receive");
    });
    const offStart = window.flova?.onFileTransferStart(() => {
      const nav = useNav.getState();
      if (nav.screen === "home") nav.go("progress");
    });
    return () => { offOffer?.(); offStart?.(); };
  }, []);

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