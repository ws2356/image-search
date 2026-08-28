import { useNavigation } from 'expo-router';
import { useCallback, useEffect, useRef } from 'react';

export function useBackupExitGuard(on_exit_requested: () => void, enabled = true): (navigate: () => void) => void {
  const navigation = useNavigation();
  const allow_remove_ref = useRef(false);

  useEffect(() => {
    if (!enabled) {
      return;
    }
    return navigation.addListener('beforeRemove', (event) => {
      if (allow_remove_ref.current) {
        allow_remove_ref.current = false;
        return;
      }
      event.preventDefault();
      on_exit_requested();
    });
  }, [enabled, navigation, on_exit_requested]);

  return useCallback((navigate: () => void) => {
    allow_remove_ref.current = true;
    navigate();
  }, []);
}
