import { useFonts } from 'expo-font';
import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import * as Linking from 'expo-linking';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect } from 'react';
import 'react-native-reanimated';

import { useColorScheme } from '@/components/useColorScheme';
import { IncomingLinkReplacementDialog } from '@/features/backup/components/incoming-link-replacement-dialog';
import { UpdatePromptDialog } from '@/features/backup/components/update-prompt-dialog';
import { useBackupUiStore } from '@/features/backup/store/backup-ui-store';
import { AppServicesProvider } from '@/infrastructure/di/app-services-provider';

export {
  // Catch any errors thrown by the Layout component.
  ErrorBoundary,
} from 'expo-router';

export const unstable_settings = {
  initialRouteName: '(backup)',
};

// Prevent the splash screen from auto-hiding before asset loading is complete.
SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [loaded, error] = useFonts({
    SpaceMono: require('../assets/fonts/SpaceMono-Regular.ttf'),
  });

  // Expo Router uses Error Boundaries to catch errors in the navigation tree.
  useEffect(() => {
    if (error) throw error;
  }, [error]);

  useEffect(() => {
    if (loaded) {
      SplashScreen.hideAsync();
    }
  }, [loaded]);

  if (!loaded) {
    return null;
  }

  return <RootLayoutNav />;
}

function RootLayoutNav() {
  const colorScheme = useColorScheme();
  const incomingLinkReplacement = useBackupUiStore((state) => state.incomingLinkReplacement);
  const updatePrompt = useBackupUiStore((state) => state.updatePrompt);
  const hideIncomingLinkReplacement = useBackupUiStore((state) => state.hideIncomingLinkReplacement);
  const hideUpdatePrompt = useBackupUiStore((state) => state.hideUpdatePrompt);

  const openUpdateLink = () => {
    if (updatePrompt.upgradeUrl) {
      void Linking.openURL(updatePrompt.upgradeUrl);
    }
  };

  return (
    <AppServicesProvider>
      <ThemeProvider value={colorScheme === 'dark' ? DarkTheme : DefaultTheme}>
        <Stack>
          <Stack.Screen name="(backup)" options={{ headerShown: false }} />
          <Stack.Screen name="(modals)" options={{ headerShown: false }} />
        </Stack>
        <IncomingLinkReplacementDialog
          state={incomingLinkReplacement}
          on_keep_current={hideIncomingLinkReplacement}
          on_replace_incoming={hideIncomingLinkReplacement}
        />
        <UpdatePromptDialog state={updatePrompt} on_dismiss={hideUpdatePrompt} on_upgrade={openUpdateLink} />
      </ThemeProvider>
    </AppServicesProvider>
  );
}
