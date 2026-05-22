import { Stack } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text, View } from '@/components/Themed';

export default function TabOneScreen() {
  return (
    <>
      <Stack.Screen options={{ title: 'AuBackup' }} />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ padding: 20, gap: 16 }}>
        <View style={{ gap: 8, borderRadius: 16, padding: 20 }}>
          <Text selectable style={{ fontSize: 28, fontWeight: '700' }}>
            AuBackup mobile app
          </Text>
          <Text selectable style={{ fontSize: 16, lineHeight: 24 }}>
            Expo Router + TypeScript has been bootstrapped for the Android-first AuBackup client,
            while keeping the project ready to expand to iOS later.
          </Text>
        </View>

        <View
          style={{ gap: 10, borderRadius: 16, padding: 20 }}
          lightColor="rgba(0,0,0,0.04)"
          darkColor="rgba(255,255,255,0.06)">
          <Text selectable style={{ fontSize: 18, fontWeight: '600' }}>
            Workspace commands
          </Text>
          <Text selectable style={{ fontVariant: ['tabular-nums'] }}>
            pnpm --filter aubackup start
          </Text>
          <Text selectable style={{ fontVariant: ['tabular-nums'] }}>
            pnpm --filter aubackup android
          </Text>
          <Text selectable style={{ fontVariant: ['tabular-nums'] }}>
            pnpm --filter aubackup ios
          </Text>
        </View>

        <View style={{ gap: 10, borderRadius: 16, padding: 20 }}>
          <Text selectable style={{ fontSize: 18, fontWeight: '600' }}>
            Initial direction
          </Text>
          <Text selectable style={{ lineHeight: 22 }}>
            1. Build the pairing and backup UX as route-based screens under the Expo Router app.
          </Text>
          <Text selectable style={{ lineHeight: 22 }}>
            2. Keep shared logic cross-platform until native backup integrations force a custom
            build.
          </Text>
          <Text selectable style={{ lineHeight: 22 }}>
            3. Start in Expo Go where possible, then add dev-client/native modules only when the
            backup feature set truly requires them.
          </Text>
        </View>
      </ScrollView>
    </>
  );
}
