import { Pressable, ScrollView, View } from 'react-native';

import { Text } from '@/components/Themed';
import { useCompletionScreenController } from '@/features/backup/hooks/use-completion-screen-controller';

export function CompletionScreen() {
  const controller = useCompletionScreenController();

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ padding: 20, gap: 20 }}>
      <View style={{ alignItems: 'center', gap: 14, paddingTop: 8 }}>
        <View
          style={{
            width: 72,
            height: 72,
            borderRadius: 36,
            backgroundColor: '#34C759',
            alignItems: 'center',
            justifyContent: 'center',
          }}>
          <Text selectable style={{ fontSize: 32, color: '#fff' }}>
            ✓
          </Text>
        </View>
        <Text selectable style={{ fontSize: 28, fontWeight: '700', color: '#1C1C1E', textAlign: 'center' }}>
          Backup Complete!
        </Text>
        <Text selectable style={{ fontSize: 15, color: '#6E6E73', textAlign: 'center', lineHeight: 22 }}>
          Desktop confirmed this mobile backup session is complete. Already transferred items may still
          be finishing desktop indexing.
        </Text>
      </View>

      <View
        style={{
          backgroundColor: '#fff',
          borderRadius: 14,
          shadowColor: '#000',
          shadowOpacity: 0.06,
          shadowRadius: 3,
          shadowOffset: { width: 0, height: 1 },
          elevation: 2,
          overflow: 'hidden',
        }}>
        <Text
          selectable
          style={{
            fontSize: 13,
            fontWeight: '600',
            color: '#6E6E73',
            textTransform: 'uppercase',
            letterSpacing: 0.5,
            paddingHorizontal: 16,
            paddingTop: 14,
            paddingBottom: 8,
          }}>
          Session Summary
        </Text>
        <View style={{ flexDirection: 'row' }}>
          <SummaryCell
            label="Items backed up"
            value={controller.items_backed_up != null ? String(controller.items_backed_up) : '—'}
          />
          <SummaryCell
            label="Completed at"
            value={controller.completed_at_description ?? '—'}
          />
        </View>
      </View>

      <View
        style={{
          backgroundColor: '#E6F9ED',
          borderRadius: 12,
          padding: 14,
          flexDirection: 'row',
          gap: 10,
          alignItems: 'flex-start',
        }}>
        <Text selectable style={{ fontSize: 16 }}>
          ℹ️
        </Text>
        <Text selectable style={{ flex: 1, fontSize: 13, color: '#166534', lineHeight: 18 }}>
          The desktop is now indexing your backed-up photos and videos. They'll appear in search
          results shortly.
        </Text>
      </View>

      <Pressable
        onPress={controller.return_home}
        style={{
          borderRadius: 14,
          paddingHorizontal: 16,
          paddingVertical: 16,
          backgroundColor: '#0A84FF',
          alignItems: 'center',
        }}>
        <Text selectable style={{ color: '#ffffff', fontWeight: '600', fontSize: 17 }}>
          OK
        </Text>
      </Pressable>
    </ScrollView>
  );
}

function SummaryCell({ label, value }: { label: string; value: string }) {
  return (
    <View
      style={{
        flex: 1,
        paddingHorizontal: 16,
        paddingVertical: 12,
        gap: 4,
      }}>
      <Text selectable style={{ fontSize: 17, fontWeight: '600', color: '#1C1C1E' }}>
        {value}
      </Text>
      <Text selectable style={{ fontSize: 12, color: '#6E6E73' }}>
        {label}
      </Text>
    </View>
  );
}
