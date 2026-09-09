import { useNav, type Screen } from "./state/nav";
import { ConnectScreen } from "./screens/ConnectScreen";
import { HomeScreen } from "./screens/HomeScreen";
import { Sidebar } from "./components/Sidebar";
import { Button } from "./components/primitives";

const SCREENS: Record<Screen, React.ComponentType> = {
  connect: ConnectScreen,
  home: HomeScreen,
  send: () => <div className="p-8 text-ink text-center">Send Screen (Next Increment)</div>,
  progress: () => <div className="p-8 text-ink text-center">Progress Screen</div>,
  complete: () => <div className="p-8 text-ink text-center">Complete Screen</div>,
  queue: () => <div className="p-8 text-ink text-center">Transfers Queue</div>,
  history: () => <div className="p-8 text-ink text-center">History Screen</div>,
  settings: () => <div className="p-8 text-ink text-center">Settings Screen</div>,
};

export default function App() {
  const screen = useNav((s) => s.screen);
  const go = useNav((s) => s.go);
  const CurrentScreen = SCREENS[screen];

  if (screen === "connect") {
    return <ConnectScreen />;
  }

  return (
    <div className="flex h-full">
      <Sidebar />
      <main className="flex-1 overflow-auto flex justify-center bg-canvas">
        <CurrentScreen />
      </main>
    </div>
  );
}