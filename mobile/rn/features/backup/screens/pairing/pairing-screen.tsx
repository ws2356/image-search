import { Link } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text } from '@/components/Themed';

export function PairingScreen() {
  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Pairing
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Pairing service wiring is introduced after Phase 3 shell implementation.
      </Text>
      <Link href="/permissions">
        <Text selectable>Continue to Permissions placeholder</Text>
      </Link>
    </ScrollView>
  );
}
