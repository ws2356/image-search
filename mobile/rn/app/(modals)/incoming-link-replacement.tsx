import { Link } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';

export default function IncomingLinkReplacementModalRoute() {
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Incoming Link Replacement
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Modal flow placeholder for replacing the active backup session with a new incoming link.
      </Text>
      <Link href="/transfer">
        <Text selectable>Back to transfer</Text>
      </Link>
    </ScrollView>
  );
}
