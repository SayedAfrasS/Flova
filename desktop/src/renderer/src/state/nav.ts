/**
 * WORKFLOW OF THIS FILE:
 * 1. Single zustand store holding the current screen id.
 * 2. History is no longer a screen: it lives inside the Transfers page.
 */
import { create } from 'zustand'

export type Screen =
  | 'connect'
  | 'home'
  | 'send'
  | 'receive'
  | 'progress'
  | 'complete'
  | 'transfers'
  | 'settings'

type NavState = {
  screen: Screen
  go: (s: Screen) => void
}

export const useNav = create<NavState>((set) => ({
  screen: 'connect',
  go: (screen) => set({ screen }),
}))