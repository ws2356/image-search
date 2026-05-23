import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, TextInput } from 'react-native';

import { Text } from '@/components/Themed';
import { parse_pairing_link_payload } from '@/features/backup/use-cases/process-incoming-link';
import { submitScannedPayload } from '@/features/backup/use-cases/submit-scanned-payload';

export default function ManualPayloadRoute() {
  const router = useRouter();
  const [payloadUrl, setPayloadUrl] = useState('');
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    const payload = parse_pairing_link_payload(payloadUrl);
    if (!payload) {
      setError('Invalid payload. Expected query params: v,ept,sid,opt,usp.');
      return;
    }
    setError(null);
    await submitScannedPayload(payload);
    router.push('/pair');
  };

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Manual Pairing Payload
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Placeholder route for manual QR payload entry before scanner integration lands.
      </Text>
      <TextInput
        value={payloadUrl}
        onChangeText={setPayloadUrl}
        autoCapitalize="none"
        autoCorrect={false}
        placeholder="https://dl.boldman.net/?v=2&ept=127.0.0.1:38080&sid=...&opt=...&usp=47001"
        style={{
          borderRadius: 10,
          borderWidth: 1,
          borderColor: '#d0d0d0',
          paddingHorizontal: 12,
          paddingVertical: 10,
        }}
      />
      {error ? (
        <Text selectable style={{ color: '#cc0000' }}>
          {error}
        </Text>
      ) : null}
      <Pressable
        onPress={() => {
          void submit();
        }}
        style={{ borderRadius: 10, backgroundColor: '#0a84ff', paddingVertical: 12, paddingHorizontal: 14 }}>
        <Text selectable style={{ color: '#fff', fontWeight: '600' }}>
          Submit Payload
        </Text>
      </Pressable>
      <Text selectable onPress={() => router.back()}>
        Back
      </Text>
    </ScrollView>
  );
}
