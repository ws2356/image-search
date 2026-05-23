import { useRouter } from 'expo-router';
import { Pressable, ScrollView } from 'react-native';

import { Text } from '@/components/Themed';
import { createBackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import { TransferPipelineStage, TransferTransport } from '@/features/backup/transfer/enums';

const orchestrator = createBackupFlowOrchestrator();

async function push_snapshot(stage: TransferPipelineStage, transferred: number, failed: number) {
  await orchestrator.execute({
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
          router.push('/transfer');
        }}
        style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable>Simulate Enumerating</Text>
      </Pressable>
      <Pressable
        onPress={() => {
          void push_snapshot(TransferPipelineStage.ExistingCheck, 5, 0);
          router.push('/transfer');
        }}
        style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable>Simulate Existing Check</Text>
      </Pressable>
      <Pressable
        onPress={() => {
          void push_snapshot(TransferPipelineStage.Transferring, 24, 1);
          router.push('/transfer');
        }}
        style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable>Simulate Transferring</Text>
      </Pressable>
      <Pressable
        onPress={() => {
          void push_snapshot(TransferPipelineStage.Completing, 50, 1);
          router.push('/transfer');
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
