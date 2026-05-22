import { StatusBar } from 'expo-status-bar';
import { Stack } from 'expo-router';
import { Platform, ScrollView } from 'react-native';

import { Text, View } from '@/components/Themed';

export default function ModalScreen() {
  return (
    <>
      <Stack.Screen options={{ title: 'About AuBackup' }} />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ padding: 20, gap: 16 }}>
        <View style={{ gap: 8, borderRadius: 16, padding: 20 }}>
          <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
            About this starter
          </Text>
          <Text selectable style={{ lineHeight: 22 }}>
            This Expo project was initialized inside the repository pnpm workspace and prepared for
            Android-first AuBackup development with future iOS support.
          </Text>
        </View>

        <View
          style={{ gap: 10, borderRadius: 16, padding: 20 }}
          lightColor="rgba(0,0,0,0.04)"
          darkColor="rgba(255,255,255,0.06)">
          <Text selectable style={{ fontSize: 18, fontWeight: '600' }}>
            Current stack
          </Text>
          <Text selectable>Expo SDK 56</Text>
          <Text selectable>Expo Router</Text>
          <Text selectable>TypeScript</Text>
          <Text selectable>pnpm workspace</Text>
        </View>

        <StatusBar style={Platform.OS === 'ios' ? 'light' : 'auto'} />
      </ScrollView>
    </>
  );
}
