import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';
import { useErrorScreenController } from '@/features/backup/hooks/use-error-screen-controller';

export function ErrorScreen() {
  const controller = useErrorScreenController();

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Error
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Error-page actions will be driven by orchestration commands in later tasks.
      </Text>
      <Text selectable onPress={controller.retry_scan}>
        Try again placeholder
      </Text>
      <Text selectable onPress={controller.return_home}>
        Return Home
      </Text>
    </ScrollView>
  );
}
