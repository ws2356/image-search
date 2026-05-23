import { Link } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';

export default function BackupPermissionsRoute() {
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Permissions
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Preflight policy and permission adapters are added in later phases.
      </Text>
      <Link href="/transfer">
        <Text selectable>Continue to Transfer placeholder</Text>
      </Link>
    </ScrollView>
  );
}
