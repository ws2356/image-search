import { Link } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';

export function ErrorScreen() {
  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Error
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Error-page actions will be driven by orchestration commands in later tasks.
      </Text>
      <Link href="/scan">
        <Text selectable>Try again placeholder</Text>
      </Link>
      <Link href="/">
        <Text selectable>Return Home</Text>
      </Link>
    </ScrollView>
  );
}
