import type { ComponentType } from "react";
import { useNav, type Screen } from "./state/nav";
import { ConnectScreen } from "./screens/ConnectScreen";
import { HomeScreen } from "./screens/HomeScreen";
import { ProgressScreen } from "./screens/ProgressScreen";
import { CompleteScreen } from "./screens/CompleteScreen";
import { Sidebar } from "./components/Sidebar";

const SCREENS: Record<Screen, ComponentType> = {
  connect: ConnectScreen,
  home: HomeScreen,
  send: () => <div className="p-8 text-center text-ink-2">File selection screen (next increment)</div>,
  progress: ProgressScreen,
  complete: CompleteScreen,
  queue: () => <div className="p-8 text-center text-ink-2">Transfer queue (coming soon)</div>,
  history: () => <div className="p-8 text-center text-ink-2">History (coming soon)</div>,
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