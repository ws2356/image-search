import { Stack } from 'expo-router';
import { ScrollView } from 'react-native';

import { Text, View } from '@/components/Themed';

export default function TabTwoScreen() {
  return (
    <>
      <Stack.Screen options={{ title: 'Build plan' }} />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ padding: 20, gap: 16 }}>
        <View style={{ gap: 8, borderRadius: 16, padding: 20 }}>
          <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
            Near-term roadmap
          </Text>
          <Text selectable style={{ lineHeight: 22 }}>
            The starter app is intentionally simple so the first real implementation can focus on
            device discovery, pairing, transfer progress, and recovery states.
          </Text>
        </View>

        <View
          style={{ gap: 10, borderRadius: 16, padding: 20 }}
          lightColor="rgba(0,0,0,0.04)"
          darkColor="rgba(255,255,255,0.06)">
          <Text selectable style={{ fontSize: 18, fontWeight: '600' }}>
            Recommended next slices
          </Text>
          <Text selectable style={{ lineHeight: 22 }}>
            - Pairing screen with QR scan / manual code entry
          </Text>
          <Text selectable style={{ lineHeight: 22 }}>
            - Transfer session list and live progress
          </Text>
          <Text selectable style={{ lineHeight: 22 }}>
            - Settings for target device, logs, and troubleshooting
          </Text>
        </View>

        <View style={{ gap: 10, borderRadius: 16, padding: 20 }}>
          <Text selectable style={{ fontSize: 18, fontWeight: '600' }}>
            Key decision still open
          </Text>
          <Text selectable style={{ lineHeight: 22 }}>
            Stay managed as long as backup flows fit Expo APIs; move to a dev client only when
            Android backup or media capabilities need native modules that Expo Go cannot host.
          </Text>
        </View>
      </ScrollView>
    </>
  );
}
