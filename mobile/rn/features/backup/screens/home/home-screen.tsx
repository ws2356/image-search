import { Pressable, ScrollView, View } from 'react-native';

import { Text } from '@/components/Themed';
import { useHomeScreenController } from '@/features/backup/hooks/use-home-screen-controller';
import { PermissionScope } from '@/features/backup/preflight/enums';

const SETUP_STEPS = [
  {
    id: 'open-desktop',
    number: 1,
    title: 'Open AuSearch on your PC',
    detail: 'Open in your desktop browser. Then install and launch AuSearch.',
  },
  {
    id: 'add-mobile-folder',
    number: 2,
    title: 'Add a Mobile Folder',
    detail: 'Click Add Folder → Mobile Device in the PC app',
  },
  {
    id: 'scan-qr',
    number: 3,
    title: 'Scan the QR code',
    detail: 'A QR code appears on screen — scan it below to pair',
  },
];

export function HomeScreen() {
  const controller = useHomeScreenController();

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={{ padding: 20, gap: 16 }}>
      {controller.has_session_history ? (
        <ReturningHomeContent controller={controller} />
      ) : (
        <FirstTimeHomeContent controller={controller} />
      )}
    </ScrollView>
  );
}

function FirstTimeHomeContent({ controller }: { controller: ReturnType<typeof useHomeScreenController> }) {
  return (
    <>
      <Text selectable style={{ fontSize: 28, fontWeight: '700', color: '#1C1C1E' }}>
        AuBackup
      </Text>
      <Text selectable style={{ fontSize: 15, color: '#6E6E73', lineHeight: 22 }}>
        Back up your photos and videos to your desktop automatically.
      </Text>
      <View style={{ gap: 12 }}>
        {SETUP_STEPS.map((step) => (
          <View
            key={step.id}
            style={{
              flexDirection: 'row',
              gap: 12,
              backgroundColor: '#F2F2F7',
              borderRadius: 12,
              padding: 14,
            }}>
            <View
              style={{
                width: 28,
                height: 28,
                borderRadius: 14,
                backgroundColor: '#0A84FF',
                alignItems: 'center',
                justifyContent: 'center',
              }}>
              <Text selectable style={{ color: '#fff', fontWeight: '700', fontSize: 14 }}>
                {step.number}
              </Text>
            </View>
            <View style={{ flex: 1, gap: 2 }}>
              <Text selectable style={{ fontWeight: '600', fontSize: 15, color: '#1C1C1E' }}>
                {step.title}
              </Text>
              <Text selectable style={{ fontSize: 13, color: '#6E6E73', lineHeight: 18 }}>
                {step.detail}
              </Text>
            </View>
          </View>
        ))}
      </View>
      {controller.permission_scope !== PermissionScope.Full && (
        <PermissionWarningBanner scope={controller.permission_scope} />
      )}
      <ScanButton onPress={controller.start_backup} />
    </>
  );
}

function ReturningHomeContent({ controller }: { controller: ReturnType<typeof useHomeScreenController> }) {
  return (
    <>
      {controller.desktop_name ? (
        <Text selectable style={{ fontSize: 34, fontWeight: '700', color: '#1C1C1E', letterSpacing: -0.5 }}>
          {controller.desktop_name}
        </Text>
      ) : null}
      {controller.interruption_warning ? (
        <View
          style={{
            backgroundColor: '#FFF3CD',
            borderRadius: 10,
            padding: 12,
            flexDirection: 'row',
            gap: 8,
          }}>
          <Text selectable style={{ fontSize: 13, color: '#856404', lineHeight: 18, flex: 1 }}>
            ⚠️ {controller.interruption_warning}
          </Text>
        </View>
      ) : null}
      {controller.last_backup_description ? (
        <View
          style={{
            backgroundColor: '#F2F2F7',
            borderRadius: 12,
            padding: 14,
          }}>
          <Text selectable style={{ fontSize: 13, color: '#6E6E73', lineHeight: 18 }}>
            {controller.last_backup_description}
          </Text>
        </View>
      ) : null}
      {controller.permission_scope !== PermissionScope.Full && (
        <PermissionWarningBanner scope={controller.permission_scope} />
      )}
      <ScanButton onPress={controller.start_backup} />
    </>
  );
}

function PermissionWarningBanner({ scope }: { scope: PermissionScope }) {
  const detail =
    scope === PermissionScope.Limited
      ? 'Only selected photos will be backed up. Grant full access for a complete backup.'
      : 'Photo library access is denied. Grant access in Settings to enable backup.';
  return (
    <View
      style={{
        backgroundColor: '#FFF3CD',
        borderRadius: 10,
        padding: 12,
      }}>
      <Text selectable style={{ fontWeight: '600', fontSize: 14, color: '#856404', marginBottom: 4 }}>
        Backup may be incomplete
      </Text>
      <Text selectable style={{ fontSize: 13, color: '#856404', lineHeight: 18 }}>
        {detail}
      </Text>
    </View>
  );
}

function ScanButton({ onPress }: { onPress: () => void }) {
  return (
    <Pressable
      onPress={onPress}
      style={{
        borderRadius: 14,
        paddingHorizontal: 16,
        paddingVertical: 16,
        backgroundColor: '#0A84FF',
        alignItems: 'center',
      }}>
      <Text selectable style={{ color: '#ffffff', fontWeight: '600', fontSize: 17 }}>
        Scan QR Code
      </Text>
    </Pressable>
  );
}
