import { useFonts } from 'expo-font';
import { DarkTheme, DefaultTheme, Stack, ThemeProvider, useRouter } from 'expo-router';
import * as Linking from 'expo-linking';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect, useMemo } from 'react';
import 'react-native-reanimated';

import { useColorScheme } from '@/components/useColorScheme';
import { IncomingLinkReplacementDialog } from '@/features/backup/components/incoming-link-replacement-dialog';
import { UpdatePromptDialog } from '@/features/backup/components/update-prompt-dialog';
import { processIncomingLink } from '@/features/backup/use-cases/process-incoming-link';
import { useBackupUiStore } from '@/features/backup/store/backup-ui-store';
import { AppServicesProvider } from '@/infrastructure/di/app-services-provider';
import { ExpoIncomingLinkPort } from '@/infrastructure/linking/incoming-link-port';

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
  const router = useRouter();
  const incoming_link_port = useMemo(() => new ExpoIncomingLinkPort(), []);
  const colorScheme = useColorScheme();
  const incomingLinkReplacement = useBackupUiStore((state) => state.incomingLinkReplacement);
  const updatePrompt = useBackupUiStore((state) => state.updatePrompt);
  const hideIncomingLinkReplacement = useBackupUiStore((state) => state.hideIncomingLinkReplacement);
  const hideUpdatePrompt = useBackupUiStore((state) => state.hideUpdatePrompt);

  const openUpdateLink = () => {
    if (updatePrompt.upgradeUrl) {
      void Linking.openURL(updatePrompt.upgradeUrl);
    }
    if (!updatePrompt.isRequired) {
      hideUpdatePrompt();
    }
  };

  useEffect(() => {
    let cancelled = false;
    const handle_link = async (url: string) => {
      const result = await processIncomingLink(url);
      if (!cancelled && result.accepted) {
        router.replace('/scan');
      }
    };

    void incoming_link_port.get_initial_url().then((url) => {
      if (cancelled || !url) {
        return;
      }
      void handle_link(url);
    });
    const unsubscribe = incoming_link_port.subscribe((url) => {
      void handle_link(url);
    });
    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, [incoming_link_port, router]);

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
          on_replace_incoming={() => {
            hideIncomingLinkReplacement();
            router.replace('/scan');
          }}
        />
        <UpdatePromptDialog state={updatePrompt} on_dismiss={hideUpdatePrompt} on_upgrade={openUpdateLink} />
      </ThemeProvider>
    </AppServicesProvider>
  );
}
