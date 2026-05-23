import { Link } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';

export default function BackupScanRoute() {
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Scan QR
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Scanner integration lands in a later phase. This route keeps the flow structure stable.
      </Text>
      <Link href="/pair">
        <Text selectable>Continue to Pairing placeholder</Text>
      </Link>
    </ScrollView>
  );
}
