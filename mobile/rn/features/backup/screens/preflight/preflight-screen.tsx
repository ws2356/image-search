import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';
import { usePreflightScreenController } from '@/features/backup/hooks/use-preflight-screen-controller';

export function PreflightScreen() {
  const controller = usePreflightScreenController();

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Permissions
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Preflight policy and permission adapters are added in later phases.
      </Text>
      <Text selectable onPress={controller.continue_to_transfer}>
        Continue to Transfer placeholder
      </Text>
      <Text selectable onPress={controller.return_home}>
        Return Home
      </Text>
    </ScrollView>
  );
}
