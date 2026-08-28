import { useRouter } from 'expo-router';
import { Pressable, ScrollView } from 'react-native';

import { Text } from '@/components/Themed';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { TransferPipelineStage, TransferTransport } from '@/features/backup/transfer/enums';

async function push_snapshot(stage: TransferPipelineStage, transferred: number, failed: number) {
  await apply_backup_command({
    type: 'transferSnapshotUpdated',
    snapshot: {
      pipelineStage: stage,
      transport: TransferTransport.Lan,
      counts: {
        totalAssets: 50,
        matchedAssets: 10,
        transferredAssets: transferred,
        failedAssets: failed,
      },
      activeAssetId: transferred < 50 ? `asset-${transferred + 1}` : null,
      activeRequestId: `req-${stage}-${transferred}-${failed}`,
      bytesUploaded: transferred * 1024 * 1024,
      bytesPerSecond: 512 * 1024,
      estimatedSecondsRemaining: Math.max(0, 50 - transferred),
      startedAt: new Date(Date.now() - transferred * 1000).toISOString(),
      lastUpdatedAt: new Date().toISOString(),
    },
  });
}

export default function TransferSimulatorRoute() {
  const router = useRouter();

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Transfer Snapshot Simulator
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Placeholder route for simulating transfer progress before live transfer integration.
      </Text>
      <Pressable
        onPress={() => {
          void push_snapshot(TransferPipelineStage.Enumerating, 0, 0);
          router.replace('/transfer');
        }}
        style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable>Simulate Enumerating</Text>
      </Pressable>
      <Pressable
        onPress={() => {
          void push_snapshot(TransferPipelineStage.ExistingCheck, 5, 0);
          router.replace('/transfer');
        }}
        style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable>Simulate Existing Check</Text>
      </Pressable>
      <Pressable
        onPress={() => {
          void push_snapshot(TransferPipelineStage.Transferring, 24, 1);
          router.replace('/transfer');
        }}
        style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable>Simulate Transferring</Text>
      </Pressable>
      <Pressable
        onPress={() => {
          void push_snapshot(TransferPipelineStage.Completing, 50, 1);
          router.replace('/transfer');
        }}
        style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable>Simulate Completing</Text>
      </Pressable>
      <Text selectable onPress={() => router.back()}>
        Back
      </Text>
    </ScrollView>
  );
}
