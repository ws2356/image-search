import { useCompletionScreenController } from '@/features/backup/hooks/use-completion-screen-controller';
import { Pressable, ScrollView, Text, View } from '@/src/tw';

export function CompletionScreen() {
  const controller = useCompletionScreenController();

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerClassName="px-5 py-4 gap-6">
      <View className="items-center gap-3.5">
        <View
          className="w-22 h-22 rounded-[22px] items-center justify-center"
          style={{ backgroundColor: '#34C759' }}>
          <Text selectable style={{ fontSize: 36, color: '#FFFFFF' }}>✓</Text>
        </View>
        <Text selectable className="text-[28px] font-bold text-app-text text-center">
          Backup Complete!
        </Text>
        <Text selectable className="text-subhead text-app-text-2 text-center leading-[22px]">
          Desktop confirmed this mobile backup session is complete. Already transferred items may still
          be finishing desktop indexing.
        </Text>
      </View>

      <View
        className="bg-app-surface-card rounded-[14px] overflow-hidden"
        style={{ boxShadow: '0 1px 3px rgba(0,0,0,0.06)' }}>
        <Text
          selectable
          className="text-footnote font-semibold text-app-text-2 uppercase"
          style={{ letterSpacing: 0.5, paddingHorizontal: 16, paddingTop: 14, paddingBottom: 8 }}>
          Session Summary
        </Text>
        <View className="flex-row">
          <SummaryCell
            label="Items backed up"
            value={controller.items_backed_up != null ? String(controller.items_backed_up) : '—'}
            icon="📷"
          />
          <SummaryCell
            label="Duration"
            value={controller.duration_description ?? '—'}
            icon="⏱️"
          />
        </View>
      </View>

      <View
        className="rounded-banner px-3.5 py-3 flex-row gap-2.5 items-start"
        style={{ backgroundColor: '#E6F9ED' }}>
        <Text selectable className="text-subhead">
          ℹ️
        </Text>
        <Text selectable className="flex-1 text-footnote leading-[18px]" style={{ color: '#166534' }}>
          The desktop is now indexing your backed-up photos and videos. They'll appear in search
          results shortly.
        </Text>
      </View>

      <Pressable
        onPress={controller.return_home}
        className="rounded-[14px] px-4 py-4 bg-app-brand items-center">
        <Text selectable className="text-app-brand-text text-body font-semibold">
          OK
        </Text>
      </Pressable>
    </ScrollView>
  );
}

function SummaryCell({ label, value, icon }: { label: string; value: string; icon: string }) {
  return (
    <View className="flex-1 px-4 py-3 gap-1.5">
      <Text selectable className="text-footnote">{icon}</Text>
      <Text selectable className="text-body font-semibold text-app-text">
        {value}
      </Text>
      <Text selectable className="text-caption1 text-app-text-2">
        {label}
      </Text>
    </View>
  );
}
