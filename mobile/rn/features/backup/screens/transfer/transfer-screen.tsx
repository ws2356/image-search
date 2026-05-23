import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';
import { useTransferScreenController } from '@/features/backup/hooks/use-transfer-screen-controller';

export function TransferScreen() {
  const controller = useTransferScreenController();

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Transfer
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Transfer service, batched existence checks, and pipelined upload are implemented in later phases.
      </Text>
      <Text selectable onPress={controller.go_completed}>
        Go to Completed placeholder
      </Text>
      <Text selectable onPress={controller.go_error}>
        Go to Error placeholder
      </Text>
      <Text selectable onPress={controller.open_incoming_link_replacement}>
        Open incoming-link replacement modal placeholder
      </Text>
    </ScrollView>
  );
}
