import { Stack } from 'expo-router';
import { Pressable, Text } from 'react-native';

export default function BackupLayout() {
  const close_button = ({ tintColor, onPress }: { tintColor?: string; onPress: () => void }) => (
    <Pressable
      onPress={onPress}
      hitSlop={10}
      style={{
        width: 28,
        height: 28,
        borderRadius: 14,
        alignItems: 'center',
        justifyContent: 'center',
      }}>
      <Text
        style={{
          color: tintColor ?? '#1C1C1E',
          fontSize: 18,
          fontWeight: '600',
          lineHeight: 20,
        }}>
        ✕
      </Text>
    </Pressable>
  );

  return (
    <Stack
      screenOptions={{
        headerBackButtonDisplayMode: 'minimal',
      }}>
      <Stack.Screen name="index" options={{ title: 'AuBackup' }} />
      <Stack.Screen
        name="scan"
        options={({ navigation }) => ({
          title: 'Scan QR',
          headerBackVisible: false,
          headerLeft: (props) => close_button({ tintColor: props.tintColor, onPress: () => navigation.replace('index') }),
        })}
      />
      <Stack.Screen
        name="pair"
        options={({ navigation }) => ({
          title: 'Pairing',
          headerBackVisible: false,
          headerLeft: (props) => close_button({ tintColor: props.tintColor, onPress: () => navigation.replace('index') }),
        })}
      />
      <Stack.Screen
        name="permissions"
        options={({ navigation }) => ({
          title: 'Permissions',
          headerBackVisible: false,
          headerLeft: (props) => close_button({ tintColor: props.tintColor, onPress: () => navigation.replace('index') }),
        })}
      />
      <Stack.Screen
        name="transfer"
        options={({ navigation }) => ({
          title: 'Backup in Progress',
          headerBackVisible: false,
          headerLeft: (props) => close_button({ tintColor: props.tintColor, onPress: () => navigation.replace('index') }),
        })}
      />
      <Stack.Screen
        name="transfer-simulator"
        options={({ navigation }) => ({
          title: 'Transfer Simulator',
          headerBackVisible: false,
          headerLeft: (props) => close_button({ tintColor: props.tintColor, onPress: () => navigation.replace('index') }),
        })}
      />
      <Stack.Screen
        name="completed"
        options={({ navigation }) => ({
          title: 'Backup Complete',
          headerBackVisible: false,
          headerLeft: (props) => close_button({ tintColor: props.tintColor, onPress: () => navigation.replace('index') }),
        })}
      />
      <Stack.Screen
        name="error"
        options={({ navigation }) => ({
          title: 'Backup Error',
          headerBackVisible: false,
          headerLeft: (props) => close_button({ tintColor: props.tintColor, onPress: () => navigation.replace('index') }),
        })}
      />
    </Stack>
  );
}
