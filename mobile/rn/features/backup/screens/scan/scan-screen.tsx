import { Stack } from 'expo-router';
import { CameraView, type BarcodeScanningResult } from 'expo-camera';
import { useEffect, useMemo, useRef, type ReactNode } from 'react';
import { ActivityIndicator, Linking, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useScanScreenController } from '@/features/backup/hooks/use-scan-screen-controller';
import { Pressable, Text, View } from '@/src/tw';

const SCAN_FRAME_MAX_SIZE = 240;
const SCAN_FRAME_WIDTH_RATIO = 0.62;

export function ScanScreen() {
  const controller = useScanScreenController();
  const scanned_ref = useRef(false);
  const { width, height } = useWindowDimensions();
  const insets = useSafeAreaInsets();

  const scan_frame = useMemo(() => {
    const size = Math.min(width * SCAN_FRAME_WIDTH_RATIO, SCAN_FRAME_MAX_SIZE);
    const left = (width - size) / 2;
    const top = Math.max(insets.top + 120, height * 0.24);
    return {
      size,
      left,
      top,
      right: left + size,
      bottom: top + size,
    };
  }, [height, insets.top, width]);

  useEffect(() => {
    scanned_ref.current = false;
  }, []);

  const on_barcode_scanned = async ({ data }: BarcodeScanningResult) => {
    if (scanned_ref.current || controller.is_claiming) {
      return;
    }
    scanned_ref.current = true;
    await controller.handle_barcode_scanned(data);
    // Do not reset scanned_ref here — keep guard up after attempt.
    // It is reset when the user explicitly retries (via retry_scan below).
  };

  const retry_scan = () => {
    scanned_ref.current = false;
    controller.clear_scan_error?.();
  };

  const open_settings = () => {
    void Linking.openSettings();
  };

  const show_camera = controller.camera_permission_granted;
  const show_permission_panel = !show_camera && !controller.scan_error && !controller.is_claiming;

  return (
    <View className="flex-1 bg-black">
      <Stack.Screen options={{ headerShown: false }} />

      {show_camera ? (
        <CameraView
          style={{ flex: 1 }}
          facing="back"
          onBarcodeScanned={on_barcode_scanned}
          barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
        />
      ) : (
        <View className="absolute inset-0 bg-black" />
      )}

      <View
        className="absolute left-0 right-0 bg-black/45"
        style={{ top: 0, height: scan_frame.top }}
      />
      <View
        className="absolute bg-black/45"
        style={{
          top: scan_frame.top,
          left: 0,
          width: scan_frame.left,
          height: scan_frame.size,
        }}
      />
      <View
        className="absolute bg-black/45"
        style={{
          top: scan_frame.top,
          left: scan_frame.right,
          right: 0,
          height: scan_frame.size,
        }}
      />
      <View
        className="absolute left-0 right-0 bg-black/45"
        style={{ top: scan_frame.bottom, bottom: 0 }}
      />

      <View
        className="absolute"
        style={{
          left: scan_frame.left,
          top: scan_frame.top,
          width: scan_frame.size,
          height: scan_frame.size,
        }}>
        <View
          style={{
            borderRadius: 16,
            borderCurve: 'continuous',
            borderWidth: 1,
            borderColor: 'rgba(255,255,255,0.25)',
            width: '100%',
            height: '100%',
          }}
        />
        <CornerMarker position="top-left" />
        <CornerMarker position="top-right" />
        <CornerMarker position="bottom-right" />
        <CornerMarker position="bottom-left" />
      </View>

      <View
        className="absolute left-0 right-0 px-5 pb-3.5"
        style={{
          paddingTop: insets.top + 8,
          backgroundColor: 'rgba(0,0,0,0.55)',
        }}>
        <View className="flex-row items-center">
          <Pressable onPress={controller.return_home} className="py-1 pr-4">
            <Text selectable className="text-body text-white">Cancel</Text>
          </Pressable>
          <View className="flex-1 items-center">
            <Text selectable className="text-body font-semibold text-white">Scan QR Code</Text>
          </View>
          <View style={{ width: 56 }} />
        </View>
      </View>

      <View
        className="absolute left-6 right-6 rounded-banner px-5 py-3"
        style={{
          bottom: Math.max(insets.bottom + 24, 32),
          backgroundColor: 'rgba(0,0,0,0.6)',
        }}>
        <View className="gap-1">
          <Text selectable className="text-subhead font-semibold text-white">
            Start a QR code based backup session on your pc:
          </Text>
          <Text selectable className="text-footnote text-white/95 leading-5">
            1. Open https://aurora.boldman.net on your PC browser then install and launch AuSearch.
          </Text>
          <Text selectable className="text-footnote text-white/95 leading-5">
            2. Click &apos;Add Folder&apos;.
          </Text>
          <Text selectable className="text-footnote text-white/95 leading-5">
            3. Select &apos;Mobile Device&apos;.
          </Text>
        </View>
      </View>

      {show_permission_panel ? (
        <StatusPanel>
          <Text selectable className="text-footnote text-white text-center leading-5">
            Camera access is turned off. Enable it in Settings to scan desktop QR codes.
          </Text>
          <Pressable
            onPress={
              controller.camera_permission_can_ask_again
                ? () => {
                    void controller.request_camera_permission();
                  }
                : open_settings
            }
            className="rounded-[14px] px-4 py-3 bg-app-brand items-center">
            <Text selectable className="text-app-brand-text font-semibold text-subhead">
              {controller.camera_permission_can_ask_again ? 'Grant Camera Access' : 'Open Settings'}
            </Text>
          </Pressable>
        </StatusPanel>
      ) : null}

      {controller.is_claiming ? (
        <StatusPanel>
          <ActivityIndicator color="#FFFFFF" />
          <Text selectable className="text-subhead font-semibold text-white text-center">
            Claiming pairing session…
          </Text>
        </StatusPanel>
      ) : null}

      {controller.scan_error ? (
        <StatusPanel>
          <Text selectable className="text-footnote text-white text-center leading-5">
            {controller.scan_error}
          </Text>
          <Pressable
            onPress={retry_scan}
            className="rounded-[14px] px-4 py-3 bg-app-brand items-center">
            <Text selectable className="text-app-brand-text font-semibold text-subhead">
              Try Again
            </Text>
          </Pressable>
        </StatusPanel>
      ) : null}
    </View>
  );
}

function StatusPanel({ children }: { children: ReactNode }) {
  return (
    <View className="absolute inset-0 items-center justify-center px-7">
      <View
        className="w-full rounded-[14px] px-4 py-3.5 gap-3"
        style={{
          backgroundColor: 'rgba(0,0,0,0.72)',
          borderWidth: 1,
          borderColor: 'rgba(255,255,255,0.2)',
        }}>
        {children}
      </View>
    </View>
  );
}

function CornerMarker({
  position,
}: {
  position: 'top-left' | 'top-right' | 'bottom-right' | 'bottom-left';
}) {
  const base_style = {
    position: 'absolute' as const,
    width: 26,
    height: 26,
    borderColor: '#FFFFFF',
    borderCurve: 'continuous' as const,
  };

  if (position === 'top-left') {
    return (
      <View
        style={{
          ...base_style,
          left: 14,
          top: 14,
          borderLeftWidth: 3,
          borderTopWidth: 3,
          borderTopLeftRadius: 4,
        }}
      />
    );
  }
  if (position === 'top-right') {
    return (
      <View
        style={{
          ...base_style,
          right: 14,
          top: 14,
          borderRightWidth: 3,
          borderTopWidth: 3,
          borderTopRightRadius: 4,
        }}
      />
    );
  }
  if (position === 'bottom-right') {
    return (
      <View
        style={{
          ...base_style,
          right: 14,
          bottom: 14,
          borderRightWidth: 3,
          borderBottomWidth: 3,
          borderBottomRightRadius: 4,
        }}
      />
    );
  }
  return (
    <View
      style={{
        ...base_style,
        left: 14,
        bottom: 14,
        borderLeftWidth: 3,
        borderBottomWidth: 3,
        borderBottomLeftRadius: 4,
      }}
    />
  );
}
