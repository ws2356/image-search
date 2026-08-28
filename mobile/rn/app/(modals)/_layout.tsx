import { Stack } from 'expo-router';

export default function ModalLayout() {
  return (
    <Stack>
      <Stack.Screen
        name="incoming-link-replacement"
        options={{ presentation: 'modal', title: 'Replace Incoming Link' }}
      />
      <Stack.Screen name="update-prompt" options={{ presentation: 'modal', title: 'Update App' }} />
    </Stack>
  );
}
