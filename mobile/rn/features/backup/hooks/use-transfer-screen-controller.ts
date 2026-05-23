import { useRouter } from 'expo-router';

export interface TransferScreenController {
  go_completed: () => void;
  go_error: () => void;
  open_incoming_link_replacement: () => void;
}

export function useTransferScreenController(): TransferScreenController {
  const router = useRouter();
  return {
    go_completed: () => router.push('/completed'),
    go_error: () => router.push('/error'),
    open_incoming_link_replacement: () => router.push('/incoming-link-replacement'),
  };
}
