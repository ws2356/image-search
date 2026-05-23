import { Stack } from 'expo-router';

export default function BackupLayout() {
  return (
    <Stack
      screenOptions={{
        headerBackButtonDisplayMode: 'minimal',
      }}>
      <Stack.Screen name="index" options={{ title: 'AuBackup' }} />
      <Stack.Screen name="scan" options={{ title: 'Scan QR' }} />
      <Stack.Screen name="manual-payload" options={{ title: 'Manual Payload Entry' }} />
      <Stack.Screen name="pair" options={{ title: 'Pairing' }} />
      <Stack.Screen name="permissions" options={{ title: 'Permissions' }} />
      <Stack.Screen name="transfer" options={{ title: 'Backup in Progress' }} />
      <Stack.Screen name="transfer-simulator" options={{ title: 'Transfer Simulator' }} />
      <Stack.Screen name="completed" options={{ title: 'Backup Complete' }} />
      <Stack.Screen name="error" options={{ title: 'Backup Error' }} />
    </Stack>
  );
}
