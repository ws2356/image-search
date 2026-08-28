import { ActivityIndicator } from 'react-native';

import { usePairingScreenController } from '@/features/backup/hooks/use-pairing-screen-controller';
import { Pressable, ScrollView, Text, View } from '@/src/tw';

export function PairingScreen() {
  const controller = usePairingScreenController();
  const pairing_message = controller.pairing_status_label

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerClassName="px-5 py-4 gap-5">
      <PairingHero message={pairing_message} />
      <PairingStepStatus />

      <Pressable
        onPress={controller.return_home}
        className="rounded-[14px] px-4 py-4 items-center"
        style={{ backgroundColor: '#FFF1F0' }}>
        <Text selectable className="text-body font-semibold" style={{ color: '#FF453A' }}>
          ✕ Cancel
        </Text>
      </Pressable>
    </ScrollView>
  );
}

function PairingHero({ message }: { message: string }) {
  return (
    <View className="items-center gap-3">
      <View className="items-center justify-center" style={{ width: 168, height: 168 }}>
        <View style={ring_style(168, 'rgba(0,122,255,0.25)')} />
        <View style={ring_style(144, 'rgba(0,122,255,0.2)')} />
        <View style={ring_style(120, 'rgba(0,122,255,0.15)')} />
        <View
          className="items-center justify-center rounded-circle"
          style={{
            width: 96,
            height: 96,
            backgroundColor: '#007AFF',
          }}>
          <Text selectable style={{ fontSize: 42, color: '#FFFFFF' }}>
            🔐
          </Text>
        </View>
      </View>

      <Text selectable className="text-[26px] font-bold text-app-text">
        Connecting…
      </Text>
      <Text selectable className="text-subhead text-app-text-2 text-center leading-5">
        {message}
      </Text>
    </View>
  );
}

function PairingStepStatus() {
  return (
    <View
      className="bg-app-surface-card rounded-[14px] overflow-hidden"
      style={{
        boxShadow: '0 1px 3px rgba(0, 0, 0, 0.06)',
      }}>
      <StepStatusRow icon="✓" text="QR code scanned" />
      <View className="ml-10 h-px bg-app-separator" />
      <StepStatusRow icon="✓" text="Desktop reached" />
      <View className="ml-10 h-px bg-app-separator" />
      <View className="flex-row items-center gap-3 px-4 py-3">
        <ActivityIndicator color="#007AFF" />
        <Text selectable className="text-subhead text-app-text flex-1">
          Verifying trust material…
        </Text>
      </View>
    </View>
  );
}

function StepStatusRow({ icon, text }: { icon: string; text: string }) {
  return (
    <View className="flex-row items-center gap-3 px-4 py-3">
      <Text selectable style={{ width: 20, fontSize: 16, color: '#30D158' }}>
        {icon}
      </Text>
      <Text selectable className="text-subhead text-app-text flex-1">
        {text}
      </Text>
    </View>
  );
}

function ring_style(size: number, border_color: string) {
  return {
    position: 'absolute' as const,
    width: size,
    height: size,
    borderRadius: size / 2,
    borderCurve: 'continuous' as const,
    borderWidth: 2,
    borderColor: border_color,
  };
}
