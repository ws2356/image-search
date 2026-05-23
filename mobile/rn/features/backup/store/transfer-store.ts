import { create } from 'zustand';

export interface TransferStoreState {
  is_running: boolean;
  last_error: string | null;
  set_running: (is_running: boolean) => void;
  set_last_error: (message: string | null) => void;
  reset: () => void;
}

export const useTransferStore = create<TransferStoreState>((set) => ({
  is_running: false,
  last_error: null,
  set_running: (is_running) => set({ is_running }),
  set_last_error: (message) => set({ last_error: message }),
  reset: () =>
    set({
      is_running: false,
      last_error: null,
    }),
}));
