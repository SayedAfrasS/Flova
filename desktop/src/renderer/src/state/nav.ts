import { create } from "zustand";

export type Screen =
  | "connect" | "home" | "send" | "receive" | "progress"
  | "complete" | "queue" | "history" | "settings";

export type Direction = "send" | "receive";

export interface FileInfo {
  name: string;
  size: string;
  bytes: number;
}

type NavState = {
  screen: Screen;
  direction: Direction;
  file: FileInfo;
  go: (screen: Screen) => void;
  startTransfer: (direction: Direction, file: FileInfo) => void;
};

export const useNav = create<NavState>((set) => ({
  screen: "connect",
  direction: "send",
  file: { name: "Vacation Video.mp4", size: "1.8 GB", bytes: 1.8 * 1024 ** 3 },
  go: (screen) => set({ screen }),
  startTransfer: (direction, file) => set({ direction, file, screen: "progress" }),
}));