import { Pressable, ScrollView } from 'react-native';

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
      <Text selectable style={{ lineHeight: 22 }}>
        {controller.transfer_snapshot_label}
      </Text>
      {controller.transfer_error ? (
        <Text selectable style={{ color: '#cc0000' }}>
          {controller.transfer_error}
        </Text>
      ) : null}
      <Pressable
        onPress={() => {
          void controller.start_live_transfer();
        }}
        style={{ borderRadius: 10, backgroundColor: '#0a84ff', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable style={{ color: '#fff', fontWeight: '600' }}>
          {controller.transfer_running ? 'Transfer Running...' : 'Start Live Transfer'}
        </Text>
      </Pressable>
      <Pressable
        onPress={() => {
          void controller.stop_live_transfer();
        }}
        style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable>Stop Transfer</Text>
      </Pressable>
      <Pressable
        onPress={() => {
          void controller.recover_transfer();
        }}
        style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable>Recover from Error</Text>
      </Pressable>
      <Pressable
        onPress={() => {
          void controller.complete_transfer();
        }}
        style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable>Complete Transfer</Text>
      </Pressable>
      <Text selectable onPress={controller.go_completed}>
        Go to Completed placeholder
      </Text>
      <Text selectable onPress={controller.go_error}>
        Go to Error placeholder
      </Text>
      <Text selectable onPress={controller.open_incoming_link_replacement}>
        Open incoming-link replacement modal placeholder
      </Text>
      <Text selectable onPress={controller.open_transfer_simulator}>
        Open transfer snapshot simulator
      </Text>
    </ScrollView>
  );
}
