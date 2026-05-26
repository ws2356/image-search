import { Pressable, ScrollView, View } from 'react-native';

import { Text } from '@/components/Themed';
import { useHomeScreenController } from '@/features/backup/hooks/use-home-screen-controller';
import { PermissionScope } from '@/features/backup/preflight/enums';

const SETUP_STEPS = [
  {
    id: 'open-desktop',
    number: 1,
    title: 'Open AuSearch on your PC',
    detailPrefix: 'Open ',
    detailLink: 'https://aurora.boldman.net',
    detailSuffix: ' in your desktop browser. Then install and launch AuSearch.',
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
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={{ paddingVertical: 16 }}>
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
    <View style={{ gap: 24, paddingHorizontal: 20 }}>
      <HomeHeroSection />
      <HomeSetupSection />
      <HomePrimaryActionButton onPress={controller.start_backup} />
      {controller.permission_scope !== PermissionScope.Full && (
        <HomeWarningBanner title="Backup may be incomplete" message={permission_warning_detail(controller.permission_scope)} />
      )}
    </View>
  );
}

function ReturningHomeContent({ controller }: { controller: ReturnType<typeof useHomeScreenController> }) {
  return (
    <View>
      <Text
        selectable
        style={{
          fontSize: 34,
          fontWeight: '700',
          color: '#1C1C1E',
          letterSpacing: -0.5,
          paddingHorizontal: 20,
          paddingTop: 4,
        }}>
        {controller.desktop_name ?? ''}
      </Text>
      <View style={{ gap: 12, paddingHorizontal: 20, paddingTop: 16 }}>
        {controller.interruption_warning ? <HomeInterruptionBanner message={controller.interruption_warning} /> : null}
        {controller.last_backup_description ? <HomeStatsCard last_backup_description={controller.last_backup_description} /> : null}
        <HomePrimaryActionButton onPress={controller.start_backup} />
        <HomeUSBHintBanner />
        {controller.permission_scope !== PermissionScope.Full && (
          <HomeWarningBanner
            title="Backup may be incomplete"
            message={permission_warning_detail(controller.permission_scope)}
          />
        )}
      </View>
    </View>
  );
}

function HomeHeroSection() {
  return (
    <View style={{ alignItems: 'center', gap: 12, paddingTop: 8 }}>
      <View
        style={{
          width: 88,
          height: 88,
          borderRadius: 22,
          backgroundColor: '#0A84FF',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
        <Text selectable style={{ color: '#fff', fontSize: 40 }}>
          🖼️
        </Text>
      </View>
      <Text selectable style={{ fontSize: 26, fontWeight: '700', color: '#1C1C1E' }}>
        AuBackup
      </Text>
      <Text selectable style={{ fontSize: 14, color: '#6E6E73', textAlign: 'center', lineHeight: 20 }}>
        Back up your photos & videos to your PC securely over Wi-Fi or USB or both
      </Text>
    </View>
  );
}

function HomeSetupSection() {
  return (
    <View style={{ gap: 6 }}>
      <Text selectable style={{ fontSize: 13, fontWeight: '600', color: '#6E6E73', letterSpacing: 0.5 }}>
        START ON YOUR PC FIRST
      </Text>
      <View style={{ backgroundColor: '#fff', borderRadius: 14, overflow: 'hidden' }}>
        {SETUP_STEPS.map((step, index) => (
          <View key={step.id}>
            <View style={{ flexDirection: 'row', gap: 12, paddingHorizontal: 16, paddingVertical: 13 }}>
              <View
                style={{
                  width: 28,
                  height: 28,
                  borderRadius: 14,
                  backgroundColor: '#007AFF',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}>
                <Text selectable style={{ color: '#fff', fontSize: 14, fontWeight: '700' }}>
                  {step.number}
                </Text>
              </View>
              <View style={{ flex: 1, gap: 3 }}>
                <Text selectable style={{ fontSize: 15, fontWeight: '600', color: '#1C1C1E' }}>
                  {step.title}
                </Text>
                {'detailLink' in step ? (
                  <Text selectable style={{ fontSize: 13, color: '#6E6E73', lineHeight: 18 }}>
                    <Text style={{ color: '#6E6E73' }}>{step.detailPrefix}</Text>
                    <Text style={{ color: '#007AFF' }}>{step.detailLink}</Text>
                    <Text style={{ color: '#6E6E73' }}>{step.detailSuffix}</Text>
                  </Text>
                ) : (
                  <Text selectable style={{ fontSize: 13, color: '#6E6E73', lineHeight: 18 }}>
                    {step.detail}
                  </Text>
                )}
              </View>
            </View>
            {index < SETUP_STEPS.length - 1 ? <View style={{ marginLeft: 56, height: 1, backgroundColor: '#E5E5EA' }} /> : null}
          </View>
        ))}
      </View>
    </View>
  );
}

function HomeStatsCard({ last_backup_description }: { last_backup_description: string }) {
  return (
    <View style={{ backgroundColor: '#fff', borderRadius: 14, paddingHorizontal: 16, paddingVertical: 14, gap: 2 }}>
      <Text selectable style={{ fontSize: 17, color: '#1C1C1E' }}>
        Last backup
      </Text>
      <Text selectable style={{ fontSize: 14, color: '#6E6E73' }}>
        {last_backup_description}
      </Text>
    </View>
  );
}

function HomeInterruptionBanner({ message }: { message: string }) {
  return (
    <View style={{ backgroundColor: '#FFF3CD', borderRadius: 12, padding: 12, gap: 3 }}>
      <Text selectable style={{ fontSize: 14, fontWeight: '600', color: '#1C1C1E' }}>
        ⚠️ Backup was interrupted
      </Text>
      <Text selectable style={{ fontSize: 13, color: '#555555', lineHeight: 18 }}>
        {message}
      </Text>
    </View>
  );
}

function HomeUSBHintBanner() {
  return (
    <View style={{ backgroundColor: '#EEF2FF', borderRadius: 10, paddingHorizontal: 14, paddingVertical: 10 }}>
      <Text selectable style={{ fontSize: 13, color: '#3B5FC0', lineHeight: 18 }}>
        USB backups can be up to 5× faster than Wi-Fi. Plug in anytime—AuBackup will switch to USB automatically.
      </Text>
    </View>
  );
}

function HomeWarningBanner({ title, message }: { title: string; message: string }) {
  return (
    <View style={{ backgroundColor: '#FFF3CD', borderRadius: 12, padding: 14, gap: 4 }}>
      <Text selectable style={{ fontSize: 14, fontWeight: '600', color: '#1C1C1E' }}>
        ⚠️ {title}
      </Text>
      <Text selectable style={{ fontSize: 13, color: '#6E6E73', lineHeight: 18 }}>
        {message}
      </Text>
    </View>
  );
}

function HomePrimaryActionButton({ onPress }: { onPress: () => void }) {
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
      <Text selectable style={{ color: '#fff', fontWeight: '600', fontSize: 17 }}>
        Scan QR Code
      </Text>
    </Pressable>
  );
}

function permission_warning_detail(scope: PermissionScope): string {
  if (scope === PermissionScope.Limited) {
    return 'Only selected photos will be backed up. Grant full access for a complete backup.';
  }
  return 'Photo library access is denied. Grant access in Settings to enable backup.';
}
