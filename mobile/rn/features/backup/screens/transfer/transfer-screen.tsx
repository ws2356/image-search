import { useTransferScreenController } from '@/features/backup/hooks/use-transfer-screen-controller';
import { TransferPipelineStage } from '@/features/backup/transfer/enums';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';
import { Platform } from 'react-native';
import { Pressable, ScrollView, Text, View } from '@/src/tw';

export function TransferScreen() {
  const controller = useTransferScreenController();
  const snapshot = controller.transfer_snapshot;

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerClassName="px-5 py-4 gap-5">
      <TransferTransportBadge snapshot={snapshot} />
      <TransferProgressRing snapshot={snapshot} />
      <TransferStatsCard snapshot={snapshot} />
      <TransferMetaCard snapshot={snapshot} />
      <TransferGuidanceBanner snapshot={snapshot} />

      {controller.is_incomplete_library ? (
        <View className="bg-app-warning-bg rounded-banner p-3 flex-row gap-2">
          <Text selectable className="text-footnote">⚠️</Text>
          <Text selectable className="text-footnote text-app-warning-text leading-[18px] flex-1">
            Only the subset currently granted by device media permissions is being transferred.
          </Text>
        </View>
      ) : null}

      {controller.transfer_error ? (
        <View className="bg-app-warning-bg rounded-banner p-3 gap-2">
          <Text selectable className="text-footnote text-app-warning-text leading-5">
            {controller.transfer_error}
          </Text>
          <Pressable
            onPress={() => void controller.recover_transfer()}
            className="self-start rounded-[12px] px-3 py-2 bg-app-brand">
            <Text selectable className="text-app-brand-text font-semibold text-footnote">
              Recover →
            </Text>
          </Pressable>
        </View>
      ) : null}

      <Pressable
        onPress={controller.confirm_stop}
        className="rounded-[14px] px-4 py-4 items-center bg-app-surface-2">
        <Text selectable className="text-body font-semibold" style={{ color: '#FF453A' }}>
          Stop Backup
        </Text>
      </Pressable>
    </ScrollView>
  );
}

function TransferTransportBadge({ snapshot }: { snapshot: TransferProgressSnapshot | null }) {
  const transport_title = snapshot?.transport === 'usb' ? 'USB Active' : 'Wi-Fi Active';
  const icon = snapshot?.transport === 'usb' ? '🔌' : '📶';
  const bg_color = snapshot?.transport === 'usb' ? '#E6F9ED' : '#E8F4FD';
  const fg_color = snapshot?.transport === 'usb' ? '#30D158' : '#007AFF';

  return (
    <View
      className="self-start rounded-circle px-3.5 py-2 flex-row items-center gap-1.5"
      style={{ backgroundColor: bg_color }}>
      <Text selectable style={{ color: fg_color }}>{icon}</Text>
      <Text selectable className="text-footnote font-semibold" style={{ color: fg_color }}>
        {transport_title}
      </Text>
    </View>
  );
}

function TransferProgressRing({ snapshot }: { snapshot: TransferProgressSnapshot | null }) {
  const total = snapshot?.counts.totalAssets ?? 0;
  const sent = snapshot?.counts.transferredAssets ?? 0;
  const progress = total > 0 ? Math.min(1, sent / total) : 0;
  const progress_percent = Math.round(progress * 100);
  const speed_text = format_speed(snapshot?.bytesPerSecond ?? 0);

  return (
    <View className="items-center gap-3">
      <View
        className="rounded-circle items-center justify-center"
        style={{
          width: 180,
          height: 180,
          borderWidth: 12,
          borderColor: '#E5E5EA',
          borderCurve: 'continuous',
        }}>
        <View
          className="rounded-circle items-center justify-center"
          style={{
            width: 140,
            height: 140,
            borderWidth: 12,
            borderColor: snapshot?.transport === 'usb' ? '#30D158' : '#007AFF',
            borderCurve: 'continuous',
          }}>
          <Text selectable className="text-[40px] font-bold text-app-text">
            {progress_percent}%
          </Text>
          <Text selectable className="text-footnote text-app-text-2">
            {speed_text}
          </Text>
        </View>
      </View>
    </View>
  );
}

function TransferStatsCard({ snapshot }: { snapshot: TransferProgressSnapshot | null }) {
  const sent = snapshot?.counts.transferredAssets ?? 0;
  const failed = snapshot?.counts.failedAssets ?? 0;
  const total = snapshot?.counts.totalAssets ?? 0;
  const remaining = Math.max(0, total - sent - failed);

  return (
    <View
      className="bg-app-surface-card rounded-[12px] py-3.5 flex-row items-center"
      style={{ boxShadow: '0 1px 3px rgba(0, 0, 0, 0.06)' }}>
      <StatCell label="Sent" value={String(sent)} color="#30D158" />
      <View className="h-10 w-px bg-app-separator" />
      <StatCell label="Remaining" value={String(remaining)} color="#007AFF" />
      <View className="h-10 w-px bg-app-separator" />
      <StatCell label="Failed" value={String(failed)} color="#FF453A" />
    </View>
  );
}

function TransferMetaCard({ snapshot }: { snapshot: TransferProgressSnapshot | null }) {
  const eta = snapshot?.estimatedSecondsRemaining != null
    ? format_eta(snapshot.estimatedSecondsRemaining)
    : '--';
  const skipped_count = snapshot?.counts.matchedAssets ?? 0;

  return (
    <View
      className="bg-app-surface-card rounded-[12px] py-3.5 flex-row items-center"
      style={{ boxShadow: '0 1px 3px rgba(0, 0, 0, 0.06)' }}>
      <MetaCell label="ETA" value={eta} color="#007AFF" />
      <View className="h-10 w-px bg-app-separator" />
      <MetaCell label="Skipped" value={String(skipped_count)} color="#FF9F0A" />
    </View>
  );
}

function TransferGuidanceBanner({ snapshot }: { snapshot: TransferProgressSnapshot | null }) {
  const message = guidance_message(snapshot);
  const is_usb = snapshot?.transport === 'usb';
  return (
    <View
      className="rounded-banner px-3.5 py-3 flex-row gap-2"
      style={{ backgroundColor: is_usb ? '#E6F9ED' : '#EEF2FF' }}>
      <Text selectable>{is_usb ? '✅' : '⚡'}</Text>
      <Text selectable className="text-footnote text-app-text-2 leading-[18px] flex-1">
        {message}
      </Text>
    </View>
  );
}

function StatCell({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <View className="flex-1 items-center gap-1">
      <Text selectable style={{ color }} className="text-[22px] font-bold">
        {value}
      </Text>
      <Text selectable className="text-caption1 font-semibold text-app-text-2 uppercase">
        {label}
      </Text>
    </View>
  );
}

function MetaCell({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <View className="flex-1 items-center gap-1">
      <Text selectable style={{ color }} className="text-body font-semibold">
        {value}
      </Text>
      <Text selectable className="text-caption1 font-semibold text-app-text-2 uppercase">
        {label}
      </Text>
    </View>
  );
}

function format_eta(seconds: number): string {
  const mins = Math.ceil(seconds / 60);
  if (mins < 60) return `${mins} min`;
  const hrs = Math.floor(mins / 60);
  const rem = mins % 60;
  return rem === 0 ? `${hrs} hr` : `${hrs} hr ${rem} min`;
}

function format_speed(bytes_per_second: number): string {
  return `${(bytes_per_second / (1024 * 1024)).toFixed(2)} MB/s`;
}

function guidance_message(snapshot: TransferProgressSnapshot | null): string {
  if (!snapshot) {
    return Platform.OS === 'android'
      ? 'Backup can continue in the background on Android while the persistent notification stays visible.'
      : 'Keep the app in the foreground while backup prepares.';
  }
  if (snapshot.counts.failedAssets > 0) {
    return 'Some items failed so far. Let this run finish, then inspect desktop logs for per-item errors.';
  }
  if (snapshot.pipelineStage === TransferPipelineStage.Enumerating) {
    return Platform.OS === 'android'
      ? 'Backup is preparing. You can background the app on Android once the persistent notification appears.'
      : 'Keep the app in the foreground while the phone prepares the backup session.';
  }
  if (snapshot.transport === 'usb') {
    return 'USB is active for the fastest backup. Keep the phone unlocked and connected until transfer finishes.';
  }
  return Platform.OS === 'android'
    ? 'Backup can continue over Wi-Fi in the background on Android. Keep the persistent notification visible, or plug in USB anytime for faster backup.'
    : 'Keep the app in the foreground while items transfer over Wi-Fi. Plug in USB anytime for faster backup.';
}
