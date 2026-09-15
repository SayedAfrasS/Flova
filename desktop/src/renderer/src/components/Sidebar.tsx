/**
 * WORKFLOW OF THIS FILE:
 * 1. Left navigation rail for the desktop app.
 * 2. Three destinations only: Home, Transfers (active + history merged),
 *    and Settings. The old separate History entry is removed.
 * 3. Highlights whichever screen is active in the nav store.
 */
import type { ReactNode } from 'react'
import { FlovaMark } from './primitives'
import { useNav, type Screen } from '../state/nav'

const ITEMS: { id: Screen; label: string; icon: ReactNode }[] = [
  {
    id: 'home',
    label: 'Home',
    icon: (
      <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 10.5 12 3l9 7.5" />
        <path d="M5 9.5V21h14V9.5" />
      </svg>
    ),
  },
  {
    id: 'transfers',
    label: 'Transfers',
    icon: (
      <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M7 16V4" />
        <path d="M3 8l4-4 4 4" />
        <path d="M17 8v12" />
        <path d="M21 16l-4 4-4-4" />
      </svg>
    ),
  },
  {
    id: 'settings',
    label: 'Settings',
    icon: (
      <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
        <circle cx="12" cy="12" r="3" />
        <path d="M12 2v2.5M12 19.5V22M22 12h-2.5M4.5 12H2M19.1 4.9l-1.8 1.8M6.7 17.3l-1.8 1.8M19.1 19.1l-1.8-1.8M6.7 6.7 4.9 4.9" />
      </svg>
    ),
  },
]

export function Sidebar() {
  const screen = useNav((s) => s.screen)
  const go = useNav((s) => s.go)

  return (
    <aside className="w-60 border-r border-line bg-canvas flex flex-col p-4">
      <div className="flex items-center gap-2 px-3 mb-8 mt-2">
        <FlovaMark />
        <span className="text-[15px] font-semibold tracking-tight text-ink">flova</span>
      </div>
      <nav className="flex flex-col gap-1">
        {ITEMS.map((item) => {
          const isActive = screen === item.id
          return (
            <button
              key={item.id}
              onClick={() => go(item.id)}
              className={`flex items-center gap-3 px-3 py-2 rounded-control text-[14px] font-medium transition-colors ${
                isActive ? 'bg-accent-soft text-accent' : 'text-ink-2 hover:bg-section hover:text-ink'
              }`}
            >
              {item.icon}
              {item.label}
            </button>
          )
        })}
      </nav>
    </aside>
  )
}