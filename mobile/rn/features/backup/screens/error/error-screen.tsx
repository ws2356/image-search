import { useErrorScreenController } from '@/features/backup/hooks/use-error-screen-controller';
import { Pressable, ScrollView, Text, View } from '@/src/tw';

export function ErrorScreen() {
  const controller = useErrorScreenController();

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerClassName="px-5 py-4 gap-6">
      <View className="items-center gap-3.5">
        <View
          className="w-22 h-22 rounded-[22px] items-center justify-center"
          style={{ backgroundColor: '#FF453A' }}>
          <Text selectable style={{ fontSize: 34, color: '#FFFFFF' }}>
            ⚠
          </Text>
        </View>
        <Text selectable className="text-[28px] font-bold text-app-text text-center">
          {controller.error_title}
        </Text>
        <Text selectable className="text-subhead text-app-text-2 text-center leading-[22px]">
          {controller.error_message}
        </Text>
      </View>

      <Pressable
        onPress={controller.retry_scan}
        className="rounded-[14px] px-4 py-4 bg-app-brand items-center flex-row justify-center gap-1.5">
        <Text selectable className="text-app-brand-text text-body font-semibold">
          ↺
        </Text>
        <Text selectable className="text-app-brand-text text-body font-semibold">
          Try Again
        </Text>
      </Pressable>

      <Pressable
        onPress={controller.return_home}
        className="rounded-[14px] px-4 py-4 bg-app-surface-2 items-center flex-row justify-center gap-1.5">
        <Text selectable className="text-body font-semibold text-app-text">
          🏠
        </Text>
        <Text selectable className="text-body font-semibold text-app-text">
          Back to Home
        </Text>
      </Pressable>
    </ScrollView>
  );
}
