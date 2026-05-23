import { Modal, Pressable, View } from 'react-native';

import { Text } from '@/components/Themed';
import type { UpdatePromptState } from '@/features/backup/store/backup-ui-store';

interface UpdatePromptDialogProps {
  state: UpdatePromptState;
  on_dismiss: () => void;
  on_upgrade: () => void;
}

export function UpdatePromptDialog({ state, on_dismiss, on_upgrade }: UpdatePromptDialogProps) {
  return (
    <Modal animationType="fade" transparent visible={state.isVisible} onRequestClose={on_dismiss}>
      <View
        style={{
          flex: 1,
          backgroundColor: 'rgba(0,0,0,0.45)',
          justifyContent: 'center',
          padding: 20,
        }}>
        <View style={{ borderRadius: 14, backgroundColor: '#fff', padding: 18, gap: 12 }}>
          <Text selectable style={{ fontSize: 20, fontWeight: '700' }}>
            {state.title || 'Update Required'}
          </Text>
          <Text selectable style={{ lineHeight: 20 }}>{state.message || 'Please update the app to continue.'}</Text>
          <Pressable
            onPress={on_upgrade}
            style={{ borderRadius: 10, backgroundColor: '#0a84ff', paddingVertical: 12, paddingHorizontal: 14 }}>
            <Text selectable style={{ color: '#fff', fontWeight: '600' }}>
              Open Update Link
            </Text>
          </Pressable>
          {!state.isRequired ? (
            <Pressable
              onPress={on_dismiss}
              style={{
                borderRadius: 10,
                backgroundColor: '#efefef',
                paddingVertical: 12,
                paddingHorizontal: 14,
              }}>
              <Text selectable style={{ fontWeight: '600' }}>Later</Text>
            </Pressable>
          ) : null}
        </View>
      </View>
    </Modal>
  );
}
