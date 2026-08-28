import type { ReactNode } from 'react';
import React from 'react';

import type { PairingQRCodePayload } from '@/features/backup/pairing/models';
import { AdaptiveTransportStrategy } from '@/infrastructure/transport/adaptive-transport-strategy';
import { AoaTransportStrategy } from '@/infrastructure/transport/aoa/aoa-transport-strategy';
import { NativeAoaBridge } from '@/infrastructure/transport/aoa/aoa-bridge';
import { LanTransportStrategy } from '@/infrastructure/transport/lan/lan-transport-strategy';

export type AppRuntimeMode = 'native-capable';

export interface AppServices {
  runtimeMode: AppRuntimeMode;
  aoa_bridge: NativeAoaBridge;
  transport_strategy: AdaptiveTransportStrategy;
}

const AppServicesContext = React.createContext<AppServices | null>(null);

function createAppServices(): AppServices {
  const aoa_bridge = new NativeAoaBridge();
  return {
    runtimeMode: 'native-capable',
    aoa_bridge,
    transport_strategy: new AdaptiveTransportStrategy(
      new AoaTransportStrategy(aoa_bridge, { sessionId: '', oneTimePasscode: '' }),
      new LanTransportStrategy(''),
      () => aoa_bridge.isConnected()
    ),
  };
}

export function createAoaTransportStrategyForQr(
  aoa_bridge: NativeAoaBridge,
  payload: PairingQRCodePayload
): AoaTransportStrategy {
  return new AoaTransportStrategy(aoa_bridge, {
    sessionId: payload.sessionId,
    oneTimePasscode: payload.oneTimePasscode,
    suggestedUsbPort: payload.suggestedUsbPort,
  });
}

export function AppServicesProvider({ children }: { children: ReactNode }) {
  const servicesRef = React.useRef<AppServices | null>(null);
  if (!servicesRef.current) {
    servicesRef.current = createAppServices();
  }
  return <AppServicesContext.Provider value={servicesRef.current}>{children}</AppServicesContext.Provider>;
}

export function useAppServices(): AppServices {
  const services = React.use(AppServicesContext);
  if (!services) {
    throw new Error('useAppServices must be used inside AppServicesProvider');
  }
  return services;
}
