import { useHomeScreenController } from '@/features/backup/hooks/use-home-screen-controller';
import { PermissionScope } from '@/features/backup/preflight/enums';
import { Pressable, ScrollView, Text, View } from '@/src/tw';

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
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerClassName="py-4">
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
    <View className="gap-6 px-5">
      <HomeHeroSection />
      <HomeSetupSection />
      <HomePrimaryActionButton onPress={controller.start_backup} />
      {controller.permission_scope !== PermissionScope.Full && (
        <HomeWarningBanner
          title="Backup may be incomplete"
          message={permission_warning_detail(controller.permission_scope)}
        />
      )}
    </View>
  );
}

function ReturningHomeContent({ controller }: { controller: ReturnType<typeof useHomeScreenController> }) {
  return (
    <View>
      <Text
        selectable
        className="text-largetitle font-bold text-app-text tracking-tight px-5 pt-1">
        {controller.desktop_name ?? ''}
      </Text>
      <View className="gap-3 px-5 pt-4">
        {controller.interruption_warning
          ? <HomeInterruptionBanner message={controller.interruption_warning} />
          : null}
        {controller.last_backup_description
          ? <HomeStatsCard last_backup_description={controller.last_backup_description} />
          : null}
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
    <View className="items-center gap-3 pt-2">
      {/* App icon */}
      <View className="w-22 h-22 rounded-[22px] bg-app-brand items-center justify-center">
        <Text selectable className="text-[40px]">🖼️</Text>
      </View>

      <Text selectable className="text-[26px] font-bold text-app-text">
        AuBackup
      </Text>

      <Text selectable className="text-footnote text-app-text-2 text-center leading-5">
        Back up your photos &amp; videos to your PC securely over Wi-Fi or USB or both
      </Text>
    </View>
  );
}

function HomeSetupSection() {
  return (
    <View className="gap-1.5">
      <Text selectable className="text-footnote font-semibold text-app-text-2 tracking-wide">
        START ON YOUR PC FIRST
      </Text>

      <View className="bg-app-surface-card rounded-[14px] overflow-hidden">
        {SETUP_STEPS.map((step, index) => (
          <View key={step.id}>
            <View className="flex-row gap-3 px-4 py-3.5">
              {/* Step badge */}
              <View className="w-7 h-7 rounded-full bg-app-brand items-center justify-center shrink-0">
                <Text selectable className="text-app-brand-text text-footnote font-bold">
                  {step.number}
                </Text>
              </View>

              <View className="flex-1 gap-[3px]">
                <Text selectable className="text-subhead font-semibold text-app-text">
                  {step.title}
                </Text>
                {'detailLink' in step ? (
                  <Text selectable className="text-footnote text-app-text-2 leading-[18px]">
                    <Text className="text-app-text-2">{step.detailPrefix}</Text>
                    <Text className="text-app-brand">{step.detailLink}</Text>
                    <Text className="text-app-text-2">{step.detailSuffix}</Text>
                  </Text>
                ) : (
                  <Text selectable className="text-footnote text-app-text-2 leading-[18px]">
                    {step.detail}
                  </Text>
                )}
              </View>
            </View>

            {index < SETUP_STEPS.length - 1
              ? <View className="ml-14 h-px bg-app-separator" />
              : null}
          </View>
        ))}
      </View>
    </View>
  );
}

function HomeStatsCard({ last_backup_description }: { last_backup_description: string }) {
  return (
    <View className="bg-app-surface-card rounded-[14px] px-4 py-3.5 gap-0.5">
      <Text selectable className="text-body text-app-text">
        Last backup
      </Text>
      <Text selectable className="text-footnote text-app-text-2">
        {last_backup_description}
      </Text>
    </View>
  );
}

function HomeInterruptionBanner({ message }: { message: string }) {
  return (
    <View className="bg-app-warning-bg rounded-banner p-3 gap-[3px]">
      <Text selectable className="text-footnote font-semibold text-app-warning-text">
        ⚠️ Backup was interrupted
      </Text>
      <Text selectable className="text-footnote text-app-warning-text leading-[18px]">
        {message}
      </Text>
    </View>
  );
}

function HomeUSBHintBanner() {
  return (
    <View className="bg-app-info-bg rounded-chip px-3.5 py-2.5">
      <Text selectable className="text-footnote text-app-info-text leading-[18px]">
        USB backups can be up to 5× faster than Wi-Fi. Plug in anytime—AuBackup will switch to USB automatically.
      </Text>
    </View>
  );
}

function HomeWarningBanner({ title, message }: { title: string; message: string }) {
  return (
    <View className="bg-app-warning-bg rounded-banner p-3.5 gap-1">
      <Text selectable className="text-footnote font-semibold text-app-warning-text">
        ⚠️ {title}
      </Text>
      <Text selectable className="text-footnote text-app-text-2 leading-[18px]">
        {message}
      </Text>
    </View>
  );
}

function HomePrimaryActionButton({ onPress }: { onPress: () => void }) {
  return (
    <Pressable
      onPress={onPress}
      className="rounded-[14px] px-4 py-4 bg-app-brand items-center">
      <Text selectable className="text-app-brand-text font-semibold text-body">
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
