import { Pressable, ScrollView, View } from 'react-native';

import { Text } from '@/components/Themed';
import { useHomeScreenController } from '@/features/backup/hooks/use-home-screen-controller';

export function HomeScreen() {
  const controller = useHomeScreenController();

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 28, fontWeight: '700' }}>
        AuBackup
      </Text>
      <Text selectable style={{ fontSize: 16, lineHeight: 22 }}>
        Backup flow shell wired to dedicated screen components.
      </Text>
      <Pressable
        onPress={controller.start_backup}
        style={{
          borderRadius: 14,
          paddingHorizontal: 16,
          paddingVertical: 14,
          backgroundColor: '#0a84ff',
        }}>
        <Text selectable style={{ color: '#ffffff', fontWeight: '600' }}>
          Start Backup
        </Text>
      </Pressable>
      <View style={{ gap: 8 }}>
        <Text selectable onPress={controller.go_pair}>
          Pair route placeholder
        </Text>
        <Text selectable onPress={controller.go_permissions}>
          Permissions route placeholder
        </Text>
        <Text selectable onPress={controller.go_transfer}>
          Transfer route placeholder
        </Text>
      </View>
    </ScrollView>
  );
}
