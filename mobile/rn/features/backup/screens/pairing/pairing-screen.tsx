import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';
import { usePairingScreenController } from '@/features/backup/hooks/use-pairing-screen-controller';

export function PairingScreen() {
  const controller = usePairingScreenController();

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Pairing
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        {controller.live_pairing_enabled
          ? controller.pairing_status_label
          : 'Live pairing params are missing. Use manual payload entry from Scan as fallback.'}
      </Text>
      <Text selectable onPress={controller.continue_to_permissions}>
        Continue to Permissions placeholder
      </Text>
      <Text selectable onPress={controller.return_home}>
        Return Home
      </Text>
    </ScrollView>
  );
}
