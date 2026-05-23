import { create } from 'zustand';

import type { PairingQRCodePayload } from '@/features/backup/pairing/models';

export interface IncomingLinkReplacementState {
  isVisible: boolean;
  currentSessionId: string | null;
  incomingPayload: PairingQRCodePayload | null;
}

export interface UpdatePromptState {
  isVisible: boolean;
  isRequired: boolean;
  title: string;
  message: string;
  upgradeUrl: string | null;
}

interface BackupUiStoreState {
  incomingLinkReplacement: IncomingLinkReplacementState;
  updatePrompt: UpdatePromptState;
  showIncomingLinkReplacement: (
    params: Omit<IncomingLinkReplacementState, 'isVisible'> & { isVisible?: boolean }
  ) => void;
  hideIncomingLinkReplacement: () => void;
  showUpdatePrompt: (params: Omit<UpdatePromptState, 'isVisible'> & { isVisible?: boolean }) => void;
  hideUpdatePrompt: () => void;
}

const INITIAL_INCOMING_LINK_REPLACEMENT: IncomingLinkReplacementState = {
  isVisible: false,
  currentSessionId: null,
  incomingPayload: null,
};

const INITIAL_UPDATE_PROMPT: UpdatePromptState = {
  isVisible: false,
  isRequired: false,
  title: '',
  message: '',
  upgradeUrl: null,
};

export const useBackupUiStore = create<BackupUiStoreState>((set) => ({
  incomingLinkReplacement: INITIAL_INCOMING_LINK_REPLACEMENT,
  updatePrompt: INITIAL_UPDATE_PROMPT,
  showIncomingLinkReplacement: ({ isVisible = true, ...payload }) =>
    set({
      incomingLinkReplacement: {
        isVisible,
        ...payload,
      },
    }),
  hideIncomingLinkReplacement: () =>
    set({
      incomingLinkReplacement: INITIAL_INCOMING_LINK_REPLACEMENT,
    }),
  showUpdatePrompt: ({ isVisible = true, ...payload }) =>
    set({
      updatePrompt: {
        isVisible,
        ...payload,
      },
    }),
  hideUpdatePrompt: () =>
    set({
      updatePrompt: INITIAL_UPDATE_PROMPT,
    }),
}));
