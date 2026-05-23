import { Link } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';

export default function BackupTransferRoute() {
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Transfer
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Transfer service, batched existence checks, and pipelined upload are implemented in later
        phases.
      </Text>
      <Link href="/completed">
        <Text selectable>Go to Completed placeholder</Text>
      </Link>
      <Link href="/error">
        <Text selectable>Go to Error placeholder</Text>
      </Link>
      <Link href="/incoming-link-replacement">
        <Text selectable>Open incoming-link replacement modal placeholder</Text>
      </Link>
    </ScrollView>
  );
}
