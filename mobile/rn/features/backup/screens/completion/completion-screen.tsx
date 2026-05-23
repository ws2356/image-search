import { Link } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';

export function CompletionScreen() {
  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Completed
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Completion summary wiring arrives after orchestration and store layers are added.
      </Text>
      <Link href="/">
        <Text selectable>Return Home</Text>
      </Link>
    </ScrollView>
  );
}
