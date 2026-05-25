import { Pressable, ScrollView, View } from 'react-native';

import { Text } from '@/components/Themed';
import { useErrorScreenController } from '@/features/backup/hooks/use-error-screen-controller';

export function ErrorScreen() {
  const controller = useErrorScreenController();

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
            backgroundColor: '#FF453A',
            alignItems: 'center',
            justifyContent: 'center',
          }}>
          <Text selectable style={{ fontSize: 32, color: '#fff' }}>
            ⚠
          </Text>
        </View>
        <Text selectable style={{ fontSize: 28, fontWeight: '700', color: '#1C1C1E', textAlign: 'center' }}>
          {controller.error_title}
        </Text>
        <Text selectable style={{ fontSize: 15, color: '#6E6E73', textAlign: 'center', lineHeight: 22 }}>
          {controller.error_message}
        </Text>
      </View>

      <Pressable
        onPress={controller.retry_scan}
        style={{
          borderRadius: 14,
          paddingHorizontal: 16,
          paddingVertical: 16,
          backgroundColor: '#0A84FF',
          alignItems: 'center',
        }}>
        <Text selectable style={{ color: '#ffffff', fontWeight: '600', fontSize: 17 }}>
          ↺  Try Again
        </Text>
      </Pressable>

      <Pressable
        onPress={controller.return_home}
        style={{
          borderRadius: 14,
          paddingHorizontal: 16,
          paddingVertical: 16,
          backgroundColor: '#F2F2F7',
          alignItems: 'center',
        }}>
        <Text selectable style={{ color: '#1C1C1E', fontWeight: '600', fontSize: 17 }}>
          Back to Home
        </Text>
      </Pressable>
    </ScrollView>
  );
}
