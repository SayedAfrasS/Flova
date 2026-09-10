/**
 * WORKFLOW OF THIS FILE:
 * 1. This screen lists app preferences in calm grouped rows.
 * 2. "Device name" is an editable input kept in component state.
 *    Later it will be saved in the local database (Phase 13).
 * 3. "Notifications" is a working on/off switch (state only for now).
 * 4. Other rows are quiet placeholders for later phases.
 *
 * FUNCTIONS:
 *  - SettingsScreen() : main screen, owns name + notifications state.
 *  - Group()          : rounded panel that stacks rows with hairlines.
 *  - Row()            : one row: label left, value or control right.
 *  - Toggle()         : small accessible on/off switch.
 *  - Chevron()        : right-pointing arrow used by placeholder rows.
 */
import { useState, type ReactNode } from "react";

function Group({ children }: { children: ReactNode }) {
  return <div className="divide-y divide-line rounded-card border border-line bg-canvas">{children}</div>;
}

function Row({ label, right }: { label: string; right: ReactNode }) {
  return (
    <div className="flex items-center justify-between px-4 py-3">
      <span className="text-[14px] text-ink">{label}</span>
      {right}
    </div>
  );
}

function Chevron() {
  return (
    <svg viewBox="0 0 24 24" className="size-4 text-ink-3" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="9 18 15 12 9 6" /></svg>
  );
}

function Toggle({ on, onChange }: { on: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      role="switch"
      aria-checked={on}
      aria-label="Notifications"
      onClick={() => onChange(!on)}
      className={`relative h-6 w-10 rounded-full transition-colors duration-200 ${on ? "bg-accent" : "bg-line"}`}
    >
      <span className={`absolute top-0.5 size-5 rounded-full bg-white shadow-sm transition-all duration-200 ${on ? "left-[18px]" : "left-0.5"}`} />
    </button>
  );
}

export function SettingsScreen() {
  const [deviceName, setDeviceName] = useState("Afras's Laptop");
  const [notifications, setNotifications] = useState(true);

  return (
    <div className="w-full max-w-lg mx-auto p-8">
      <h1 className="text-[24px] font-semibold tracking-tight text-ink mb-6">Settings</h1>

      <div className="flex flex-col gap-6">
        <Group>
          <Row
            label="Device name"
            right={
              <input
                value={deviceName}
                onChange={(e) => setDeviceName(e.target.value)}
                aria-label="Device name"
                className="w-44 bg-transparent text-right text-[13px] text-ink-2 transition-colors focus:text-ink focus:outline-none"
              />
            }
          />
        </Group>

        <Group>
          <Row label="Save files to" right={<span className="flex items-center gap-2 text-[13px] text-ink-2">Downloads <Chevron /></span>} />
          <Row label="Notifications" right={<Toggle on={notifications} onChange={setNotifications} />} />
          <Row label="Privacy" right={<Chevron />} />
        </Group>

        <Group>
          <Row label="About" right={<span className="text-[13px] text-ink-3">Flova 1.0</span>} />
        </Group>
      </div>
    </div>
  );
}