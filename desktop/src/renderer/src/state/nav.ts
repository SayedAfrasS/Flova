import { create } from "zustand";

export type Screen =
  | "connect" | "home" | "send" | "progress"
  | "complete" | "queue" | "history" | "settings";

type NavState = { screen: Screen; go: (s: Screen) => void };

export const useNav = create<NavState>((set) => ({
  screen: "connect",
  go: (screen) => set({ screen }),
}));