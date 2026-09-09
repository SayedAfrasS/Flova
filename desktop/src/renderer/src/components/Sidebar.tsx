import { FlovaMark } from "./primitives";
import { useNav, type Screen } from "../state/nav";

const NAV_ITEMS: { id: Screen; label: string }[] = [
  { id: "home", label: "Home" },
  { id: "queue", label: "Transfers" },
  { id: "history", label: "History" },
  { id: "settings", label: "Settings" },
];

export function Sidebar() {
  const screen = useNav((s) => s.screen);
  const go = useNav((s) => s.go);

  return (
    <aside className="w-60 border-r border-line bg-canvas flex flex-col p-4">
      <div className="flex items-center gap-2 px-3 mb-8 mt-2">
        <FlovaMark />
        <span className="text-[15px] font-semibold tracking-tight text-ink">flova</span>
      </div>
      <nav className="flex flex-col gap-1">
        {NAV_ITEMS.map((item) => {
          const isActive = screen === item.id;
          return (
            <button
              key={item.id}
              onClick={() => go(item.id)}
              className={`flex items-center gap-3 px-3 py-2 rounded-control text-[14px] font-medium transition-colors ${
                isActive
                  ? "bg-accent-soft text-accent"
                  : "text-ink-2 hover:bg-section hover:text-ink"
              }`}
            >
              {item.label}
            </button>
          );
        })}
      </nav>
    </aside>
  );
}