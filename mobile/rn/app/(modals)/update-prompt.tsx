import { Link } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';

export default function UpdatePromptModalRoute() {
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Update Prompt
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Modal flow placeholder for recommended or required app updates.
      </Text>
      <Link href="/">
        <Text selectable>Return home</Text>
      </Link>
    </ScrollView>
  );
}
