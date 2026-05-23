import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';
import { useScanScreenController } from '@/features/backup/hooks/use-scan-screen-controller';

export function ScanScreen() {
  const controller = useScanScreenController();

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Scan QR
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Scanner integration lands in a later phase. This route keeps the flow structure stable.
      </Text>
      <Text selectable onPress={controller.continue_to_pairing}>
        Continue to Pairing placeholder
      </Text>
      <Text selectable onPress={controller.open_manual_payload_entry}>
        Enter payload manually
      </Text>
      <Text selectable onPress={controller.return_home}>
        Return Home
      </Text>
    </ScrollView>
  );
}
