import { Alert, Pressable, ScrollView, View } from 'react-native';

import { Text } from '@/components/Themed';
import { useTransferScreenController } from '@/features/backup/hooks/use-transfer-screen-controller';
import { TransferPipelineStage } from '@/features/backup/transfer/enums';

const STAGE_LABELS: Record<TransferPipelineStage, string> = {
  [TransferPipelineStage.Enumerating]: 'Scanning library…',
  [TransferPipelineStage.ExistingCheck]: 'Checking existing files…',
  [TransferPipelineStage.Transferring]: 'Transferring…',
  [TransferPipelineStage.Completing]: 'Finishing up…',
};

export function TransferScreen() {
  const controller = useTransferScreenController();
  const snap = controller.transfer_snapshot;

  function handle_stop_pressed() {
    Alert.alert(
      'Stop backup?',
      'The desktop may continue indexing items that already transferred before the stop request.',
      [
        { text: 'Keep Backing Up', style: 'cancel' },
        {
          text: 'Stop Sending More Items',
          style: 'destructive',
          onPress: () => void controller.confirm_stop(),
        },
      ]
    );
  }

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ padding: 20, gap: 16 }}>
      <Text selectable style={{ fontSize: 28, fontWeight: '700', color: '#1C1C1E' }}>
        {controller.transfer_running ? 'Backing Up…' : 'Transfer'}
      </Text>

      {snap ? (
        <View
          style={{
            backgroundColor: '#F2F2F7',
            borderRadius: 14,
            padding: 16,
            gap: 12,
          }}>
          <Text selectable style={{ fontSize: 15, fontWeight: '600', color: '#1C1C1E' }}>
            {STAGE_LABELS[snap.pipelineStage] ?? snap.pipelineStage}
          </Text>
          <View style={{ flexDirection: 'row', gap: 20 }}>
            <StatCell label="Transferred" value={String(snap.counts.transferredAssets)} />
            <StatCell label="Total" value={String(snap.counts.totalAssets)} />
            <StatCell label="Failed" value={String(snap.counts.failedAssets)} />
          </View>
          {snap.estimatedSecondsRemaining != null && (
            <Text selectable style={{ fontSize: 13, color: '#6E6E73' }}>
              ETA: {formatETA(snap.estimatedSecondsRemaining)}
            </Text>
          )}
          {snap.bytesPerSecond != null && (
            <Text selectable style={{ fontSize: 13, color: '#6E6E73' }}>
              {formatSpeed(snap.bytesPerSecond)}
            </Text>
          )}
        </View>
      ) : (
        <View style={{ backgroundColor: '#F2F2F7', borderRadius: 12, padding: 14 }}>
          <Text selectable style={{ fontSize: 14, color: '#6E6E73' }}>
            Waiting for transfer to start…
          </Text>
        </View>
      )}

      {controller.transfer_error ? (
        <View style={{ backgroundColor: '#FFE5E5', borderRadius: 10, padding: 12 }}>
          <Text selectable style={{ fontSize: 14, color: '#CC0000', lineHeight: 20 }}>
            {controller.transfer_error}
          </Text>
          <Pressable
            onPress={() => void controller.recover_transfer()}
            style={{ marginTop: 10, alignSelf: 'flex-start' }}>
            <Text selectable style={{ color: '#0A84FF', fontWeight: '600', fontSize: 14 }}>
              Recover →
            </Text>
          </Pressable>
        </View>
      ) : null}

      <Pressable
        onPress={handle_stop_pressed}
        style={{
          borderRadius: 14,
          paddingHorizontal: 16,
          paddingVertical: 16,
          backgroundColor: '#F2F2F7',
          alignItems: 'center',
        }}>
        <Text selectable style={{ color: '#FF3B30', fontWeight: '600', fontSize: 17 }}>
          Stop Backup
        </Text>
      </Pressable>

      <Pressable
        onPress={() => void controller.complete_transfer()}
        style={{
          borderRadius: 14,
          paddingHorizontal: 16,
          paddingVertical: 16,
          backgroundColor: '#34C759',
          alignItems: 'center',
        }}>
        <Text selectable style={{ color: '#fff', fontWeight: '600', fontSize: 17 }}>
          Complete Transfer
        </Text>
      </Pressable>
    </ScrollView>
  );
}

function StatCell({ label, value }: { label: string; value: string }) {
  return (
    <View style={{ gap: 2 }}>
      <Text selectable style={{ fontSize: 20, fontWeight: '600', color: '#1C1C1E' }}>
        {value}
      </Text>
      <Text selectable style={{ fontSize: 12, color: '#6E6E73' }}>
        {label}
      </Text>
    </View>
  );
}

function formatETA(seconds: number): string {
  const mins = Math.ceil(seconds / 60);
  if (mins < 60) return `${mins} min`;
  const hrs = Math.floor(mins / 60);
  const rem = mins % 60;
  return rem === 0 ? `${hrs} hr` : `${hrs} hr ${rem} min`;
}

function formatSpeed(bytesPerSecond: number): string {
  if (bytesPerSecond < 1024) return `${bytesPerSecond.toFixed(0)} B/s`;
  if (bytesPerSecond < 1024 * 1024) return `${(bytesPerSecond / 1024).toFixed(1)} KB/s`;
  return `${(bytesPerSecond / (1024 * 1024)).toFixed(1)} MB/s`;
}
