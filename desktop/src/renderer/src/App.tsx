import { ConnectScreen } from "./screens/ConnectScreen";
import { Button } from "./components/primitives";
import { useNav, type Screen } from "./state/nav";

const TITLES: Partial<Record<Screen, string>> = {
  home: "Your phone is connected",
  settings: "Settings",
  history: "History",
};

export default function App() {
  const screen = useNav((s) => s.screen);
  const go = useNav((s) => s.go);

  if (screen === "connect") return <ConnectScreen />;

  return (
    <main className="flex h-full flex-col items-center justify-center gap-4">
      <h1 className="text-[28px] font-semibold tracking-tight">{TITLES[screen] ?? screen}</h1>
      <p className="text-[14px] text-ink-2">Screen lands in the next Phase 2 increment.</p>
      <Button variant="secondary" onClick={() => go("connect")}>Back</Button>
    </main>
  );
}