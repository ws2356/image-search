import { Pressable, ScrollView, View } from 'react-native';

import { Text } from '@/components/Themed';
import { usePreflightScreenController } from '@/features/backup/hooks/use-preflight-screen-controller';

export function PreflightScreen() {
  const controller = usePreflightScreenController();

  const summary = controller.summary;

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Backup preflight
      </Text>

      {controller.phase === 'loading' ? <Text selectable>Checking media access, battery, and backup cleanup preference…</Text> : null}

      {summary ? (
        <View style={{ gap: 4 }}>
          <Text selectable>Media access: {summary.mediaScope}</Text>
          <Text selectable>Battery: {summary.batteryPercentage ?? 'unknown'}%</Text>
          <Text selectable>Charging: {summary.isCharging ? 'yes' : 'no'}</Text>
          <Text selectable>Remove after backup: {summary.removeAfterBackupEnabled ? 'enabled' : 'disabled'}</Text>
        </View>
      ) : null}

      {controller.phase === 'media' ? (
        <View style={{ gap: 8 }}>
          <Text selectable style={{ lineHeight: 22 }}>
            Full media access is recommended so backup can include your whole library.
          </Text>
          <Pressable
            onPress={() => {
              void controller.request_media_access();
            }}
            style={{ borderRadius: 10, backgroundColor: '#0a84ff', paddingVertical: 12, paddingHorizontal: 14 }}>
            <Text selectable style={{ color: '#fff', fontWeight: '600' }}>
              Update Media Access
            </Text>
          </Pressable>
          <Text selectable onPress={() => void controller.continue_without_media_update()}>
            Not now
          </Text>
        </View>
      ) : null}

      {controller.phase === 'low-battery' ? (
        <View style={{ gap: 8 }}>
          <Text selectable style={{ lineHeight: 22 }}>
            Battery is low. Long transfers are more likely to pause. Connect a charger if possible.
          </Text>
          <Text selectable onPress={() => void controller.continue_past_low_battery()}>
            Continue anyway
          </Text>
          <Text selectable onPress={() => void controller.cancel_from_low_battery()}>Not now</Text>
        </View>
      ) : null}

      {controller.phase === 'remove-after-backup' ? (
        <View style={{ gap: 8 }}>
          <Text selectable style={{ lineHeight: 22 }}>
            After transfer completes, should copied media be moved to Recently Removed on this device?
          </Text>
          <Text selectable onPress={() => void controller.choose_remove_after_backup(true)}>
            Remove after backup
          </Text>
          <Text selectable onPress={() => void controller.choose_remove_after_backup(false)}>
            Keep originals
          </Text>
        </View>
      ) : null}

      {controller.error_message ? <Text selectable style={{ color: '#cc0000' }}>{controller.error_message}</Text> : null}

      <Text selectable onPress={controller.return_home}>
        Return Home
      </Text>
    </ScrollView>
  );
}
