import { useEffect, useRef } from 'react';
import { ActivityIndicator, Alert } from 'react-native';

import { usePreflightScreenController, type PreflightPromptPhase } from '@/features/backup/hooks/use-preflight-screen-controller';
import { Pressable, ScrollView, Text, View } from '@/src/tw';

export function PreflightScreen() {
  const controller = usePreflightScreenController();
  const prompted_phase_ref = useRef<PreflightPromptPhase | null>(null);

  useEffect(() => {
    if (controller.phase === 'loading' || controller.phase === 'failed') {
      prompted_phase_ref.current = null;
      return;
    }
    if (prompted_phase_ref.current === controller.phase) {
      return;
    }
    prompted_phase_ref.current = controller.phase;

    if (controller.phase === 'media') {
      Alert.alert(
        'Full media access recommended',
        'Do you want to expand access permission to back up more or all media files in your photo library?',
        [
          {
            text: 'Update',
            onPress: () => {
              void controller.request_media_access();
            },
          },
          {
            text: 'Not now',
            style: 'cancel',
            onPress: () => {
              void controller.continue_without_media_update();
            },
          },
        ]
      );
      return;
    }

    if (controller.phase === 'low-battery') {
      Alert.alert(
        'Low battery detected',
        'Long transfers are more likely to pause when battery is low. Connect the device to a charger or desktop if you can.',
        [
          {
            text: 'Continue Anyway',
            onPress: () => {
              void controller.continue_past_low_battery();
            },
          },
          {
            text: 'Not Now',
            style: 'cancel',
            onPress: () => {
              void controller.cancel_from_low_battery();
            },
          },
        ]
      );
      return;
    }

    Alert.alert(
      'After backup, remove transferred media?',
      'Choose whether successfully transferred photos and videos should be moved to Recently Removed on this device after backup completes.',
      [
        {
          text: 'Remove',
          style: 'destructive',
          onPress: () => {
            void controller.choose_remove_after_backup(true);
          },
        },
        {
          text: 'Do not remove',
          style: 'cancel',
          onPress: () => {
            void controller.choose_remove_after_backup(false);
          },
        },
      ]
    );
  }, [controller]);

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerClassName="px-5 py-4 gap-5">
      <View className="items-center gap-3">
        <View
          className="items-center justify-center rounded-circle"
          style={{
            width: 120,
            height: 120,
            backgroundColor: '#007AFF',
          }}>
          <Text selectable style={{ fontSize: 52, color: '#FFFFFF' }}>
            🛡️
          </Text>
        </View>
        <Text selectable className="text-[26px] font-bold text-app-text">
          Backup preflight
        </Text>
        <Text selectable className="text-subhead text-app-text-2">
          Preparing backup...
        </Text>
      </View>

      <View
        className="bg-app-surface-card rounded-[14px] px-4 py-4 gap-3 items-center"
        style={{ boxShadow: '0 1px 3px rgba(0, 0, 0, 0.06)' }}>
        <ActivityIndicator size="large" color="#007AFF" />
        <Text selectable className="text-footnote text-app-text-2 text-center leading-5">
          Checking media access, battery status, and backup cleanup preference. Continue in each
          prompt to begin transfer automatically.
        </Text>
      </View>

      {controller.phase === 'failed' ? (
        <View className="gap-3">
          <View className="bg-app-warning-bg rounded-banner p-3 gap-1">
            <Text selectable className="text-footnote font-semibold text-app-warning-text">
              Preflight failed
            </Text>
            <Text selectable className="text-footnote text-app-warning-text leading-[18px]">
              {controller.error_message ?? 'Unable to continue backup preflight.'}
            </Text>
          </View>
          <Pressable
            onPress={controller.return_home}
            className="rounded-[14px] px-4 py-4 bg-app-surface-2 items-center">
            <Text selectable className="text-body font-semibold text-app-text">
              Return Home
            </Text>
          </Pressable>
        </View>
      ) : (
        <View className="bg-app-info-bg rounded-chip px-3.5 py-2.5">
          <Text selectable className="text-footnote text-app-info-text leading-[18px]">
            Prompts are shown automatically as checks complete.
          </Text>
        </View>
      )}
    </ScrollView>
  );
}
