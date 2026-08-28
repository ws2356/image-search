import { Platform } from 'react-native';

export interface PlatformCapabilities {
  platform: 'android' | 'ios' | 'web' | 'unknown';
  supports_usb_transport: boolean;
  supports_background_transfer_policy: boolean;
}

export function get_platform_capabilities(): PlatformCapabilities {
  if (Platform.OS === 'android') {
    return {
      platform: 'android',
      supports_usb_transport: false,
      supports_background_transfer_policy: true,
    };
  }

  if (Platform.OS === 'ios') {
    return {
      platform: 'ios',
      supports_usb_transport: false,
      supports_background_transfer_policy: false,
    };
  }

  if (Platform.OS === 'web') {
    return {
      platform: 'web',
      supports_usb_transport: false,
      supports_background_transfer_policy: false,
    };
  }

  return {
    platform: 'unknown',
    supports_usb_transport: false,
    supports_background_transfer_policy: false,
  };
}
