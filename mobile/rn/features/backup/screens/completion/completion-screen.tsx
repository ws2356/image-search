import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';
import { useCompletionScreenController } from '@/features/backup/hooks/use-completion-screen-controller';

export function CompletionScreen() {
  const controller = useCompletionScreenController();

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Completed
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Completion summary wiring arrives after orchestration and store layers are added.
      </Text>
      <Text selectable onPress={controller.return_home}>
        Return Home
      </Text>
    </ScrollView>
  );
}
