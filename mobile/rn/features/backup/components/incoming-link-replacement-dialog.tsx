import { Modal, Pressable, View } from 'react-native';

import { Text } from '@/components/Themed';
import type { IncomingLinkReplacementState } from '@/features/backup/store/backup-ui-store';

interface IncomingLinkReplacementDialogProps {
  state: IncomingLinkReplacementState;
  on_keep_current: () => void;
  on_replace_incoming: () => void;
}

export function IncomingLinkReplacementDialog({
  state,
  on_keep_current,
  on_replace_incoming,
}: IncomingLinkReplacementDialogProps) {
  return (
    <Modal animationType="fade" transparent visible={state.isVisible} onRequestClose={on_keep_current}>
      <View
        style={{
          flex: 1,
          backgroundColor: 'rgba(0,0,0,0.45)',
          justifyContent: 'center',
          padding: 20,
        }}>
        <View style={{ borderRadius: 14, backgroundColor: '#fff', padding: 18, gap: 12 }}>
          <Text selectable style={{ fontSize: 20, fontWeight: '700' }}>
            Replace Current Backup Session?
          </Text>
          <Text selectable style={{ lineHeight: 20 }}>
            A new incoming pairing payload was detected. Choose whether to keep the current session or replace it.
          </Text>
          {state.currentSessionId ? (
            <Text selectable style={{ lineHeight: 20 }}>
              Current session: {state.currentSessionId}
            </Text>
          ) : null}
          <Pressable
            onPress={on_replace_incoming}
            style={{ borderRadius: 10, backgroundColor: '#0a84ff', paddingVertical: 12, paddingHorizontal: 14 }}>
            <Text selectable style={{ color: '#fff', fontWeight: '600' }}>
              Replace with Incoming Link
            </Text>
          </Pressable>
          <Pressable
            onPress={on_keep_current}
            style={{ borderRadius: 10, backgroundColor: '#efefef', paddingVertical: 12, paddingHorizontal: 14 }}>
            <Text selectable style={{ fontWeight: '600' }}>Keep Current Session</Text>
          </Pressable>
        </View>
      </View>
    </Modal>
  );
}
