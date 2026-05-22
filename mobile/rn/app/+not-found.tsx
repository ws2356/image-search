import { Link, Stack } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text, View } from '@/components/Themed';

export default function NotFoundScreen() {
  return (
    <>
      <Stack.Screen options={{ title: 'Not found' }} />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ padding: 20 }}>
        <View style={{ gap: 12, alignItems: 'flex-start', borderRadius: 16, padding: 20 }}>
          <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
            This route does not exist.
          </Text>
          <Link href="/">
            <Text selectable style={{ fontSize: 16 }}>
              Return to AuBackup home
            </Text>
          </Link>
        </View>
      </ScrollView>
    </>
  );
}
