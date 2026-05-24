import { useEffect, useRef } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { CameraView } from 'expo-camera';

import { Text } from '@/components/Themed';
import { useScanScreenController } from '@/features/backup/hooks/use-scan-screen-controller';

export function ScanScreen() {
  const controller = useScanScreenController();
  const scanned_ref = useRef(false);

  useEffect(() => {
    scanned_ref.current = false;
  }, []);

  const onBarcodeScanned = async ({ data }: { data: string }) => {
    if (scanned_ref.current || controller.is_claiming) {
      return;
    }
    scanned_ref.current = true;
    await controller.handle_barcode_scanned(data);
    scanned_ref.current = false;
  };

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ padding: 20, gap: 12 }}>
      <Text selectable style={{ fontSize: 24, fontWeight: '700' }}>
        Scan QR
      </Text>
      <Text selectable style={{ lineHeight: 22 }}>
        Point the physical Android device at the desktop QR code to start pairing.
      </Text>
      {controller.camera_permission_granted ? (
        <View style={{ height: 360, borderRadius: 16, overflow: 'hidden', backgroundColor: '#111' }}>
          <CameraView
            style={{ flex: 1 }}
            facing="back"
            onBarcodeScanned={onBarcodeScanned}
            barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
          />
        </View>
      ) : (
        <Pressable
          onPress={() => {
            void controller.request_camera_permission();
          }}
          style={{ borderRadius: 10, backgroundColor: '#0a84ff', paddingVertical: 12, paddingHorizontal: 14 }}>
          <Text selectable style={{ color: '#fff', fontWeight: '600' }}>
            Grant Camera Permission
          </Text>
        </Pressable>
      )}
      {controller.scan_error ? (
        <Text selectable style={{ color: '#cc0000' }}>
          {controller.scan_error}
        </Text>
      ) : null}
      {controller.is_claiming ? <Text selectable>Claiming pairing session...</Text> : null}
      <Text selectable onPress={controller.return_home}>
        Return Home
      </Text>
    </ScrollView>
  );
}
