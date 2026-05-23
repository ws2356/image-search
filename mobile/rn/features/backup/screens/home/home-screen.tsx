import { Link } from 'expo-router';
import { Pressable, ScrollView, View } from 'react-native';

import { Text } from '@/components/Themed';

export function HomeScreen() {
  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 28, fontWeight: '700' }}>
        AuBackup
      </Text>
      <Text selectable style={{ fontSize: 16, lineHeight: 22 }}>
        Backup flow shell wired to dedicated screen components.
      </Text>
      <Link href="/scan" asChild>
        <Pressable
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
      </Link>
      <View style={{ gap: 8 }}>
        <Link href="/pair">
          <Text selectable>Pair route placeholder</Text>
        </Link>
        <Link href="/permissions">
          <Text selectable>Permissions route placeholder</Text>
        </Link>
        <Link href="/transfer">
          <Text selectable>Transfer route placeholder</Text>
        </Link>
      </View>
    </ScrollView>
  );
}
