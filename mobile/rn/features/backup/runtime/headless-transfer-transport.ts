import type { PairingSessionSummary } from '@/features/backup/pairing/models';
import { AdaptiveTransportStrategy } from '@/infrastructure/transport/adaptive-transport-strategy';
import { NativeAoaBridge } from '@/infrastructure/transport/aoa/aoa-bridge';
import { AoaTransportStrategy } from '@/infrastructure/transport/aoa/aoa-transport-strategy';
import { LanTransportStrategy } from '@/infrastructure/transport/lan/lan-transport-strategy';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

export function build_transfer_transport_strategy(
  pairing_session: PairingSessionSummary
): TransportStrategy {
  const aoa_bridge = new NativeAoaBridge();
  return new AdaptiveTransportStrategy(
    new AoaTransportStrategy(aoa_bridge, {
      sessionId: pairing_session.sessionId ?? '',
      oneTimePasscode: '',
    }),
    new LanTransportStrategy(pairing_session.endpointBaseUrl ?? ''),
    () => aoa_bridge.isConnected(),
    { initial_preferred_transport: pairing_session.transport }
  );
}
