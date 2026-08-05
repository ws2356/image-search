import {
  type PairingClaimRequest,
  type PairingResponse,
  type PairingStateRequest,
} from '@/features/backup/protocols/pairing';
import type {
  CapabilityExchangeResponse,
  CapabilityExchangeServiceInput,
} from '@/features/backup/services/capability-exchange-service';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { TransferServiceContext } from '@/features/backup/services/transfer-service';
import { TransportKind } from '@/infrastructure/transport/transport-kind';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

export type PreferredTransport = 'lan' | 'usb';

const DEFAULT_TRANSPORT_TIMEOUT_MS = 3000;
const AOA_CONNECT_POLL_INTERVAL_MS = 100;

export interface AdaptiveTransportStrategyOptions {
  transport_timeout_ms?: number;
  initial_preferred_transport?: PreferredTransport;
}

function sleep(duration_ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, duration_ms);
  });
}

export class AdaptiveTransportStrategy implements TransportStrategy {
  readonly kind = TransportKind.Usb;

  private preferred_transport: PreferredTransport | null;
  private readonly transport_timeout_ms: number;

  constructor(
    private readonly aoa_strategy: TransportStrategy,
    private readonly lan_strategy: TransportStrategy,
    private readonly is_aoa_connected: () => boolean,
    options: AdaptiveTransportStrategyOptions = {}
  ) {
    this.preferred_transport = options.initial_preferred_transport ?? null;
    this.transport_timeout_ms = options.transport_timeout_ms ?? DEFAULT_TRANSPORT_TIMEOUT_MS;
  }

  get last_working_transport(): PreferredTransport | null {
    return this.preferred_transport;
  }

  async claim_pairing(request: PairingClaimRequest): Promise<PairingResponse> {
    return this.run_candidates(['lan', 'usb'], (strategy) => strategy.claim_pairing(request));
  }

  async get_pairing_state(request: PairingStateRequest): Promise<PairingResponse> {
    return this.run_candidates(this.ordered_candidates(), (strategy) => strategy.get_pairing_state(request));
  }

  async exchange_capabilities(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse> {
    return this.run_candidates(this.ordered_candidates(), (strategy) => strategy.exchange_capabilities(input));
  }

  create_transfer_client(context: TransferServiceContext): TransferClient {
    const preferred = this.preferred_transport ?? (this.is_aoa_connected() ? 'usb' : 'lan');
    if (preferred === 'usb' && this.is_aoa_connected()) {
      return this.aoa_strategy.create_transfer_client(context);
    }
    return this.lan_strategy.create_transfer_client(context);
  }

  private ordered_candidates(): PreferredTransport[] {
    if (this.preferred_transport === 'usb') {
      return ['usb', 'lan'];
    }
    return ['lan', 'usb'];
  }

  private async run_candidates<T>(
    candidates: PreferredTransport[],
    operation: (strategy: TransportStrategy) => Promise<T>
  ): Promise<T> {
    let last_error: Error | null = null;
    for (const kind of candidates) {
      try {
        const value = await this.attempt(kind, operation);
        this.preferred_transport = kind;
        return value;
      } catch (error) {
        last_error = error instanceof Error ? error : new Error(String(error));
      }
    }
    throw last_error ?? new Error('Both transports failed.');
  }

  private async attempt<T>(
    kind: PreferredTransport,
    operation: (strategy: TransportStrategy) => Promise<T>
  ): Promise<T> {
    if (kind === 'usb') {
      await this.wait_for_aoa_connection(this.transport_timeout_ms);
      return operation(this.aoa_strategy);
    }
    return this.with_timeout(operation(this.lan_strategy), this.transport_timeout_ms);
  }

  private async wait_for_aoa_connection(timeout_ms: number): Promise<void> {
    const deadline = Date.now() + timeout_ms;
    while (true) {
      if (this.is_aoa_connected()) {
        return;
      }
      const remaining = deadline - Date.now();
      if (remaining <= 0) {
        throw new Error('AOA connection could not be established in time.');
      }
      await sleep(Math.min(AOA_CONNECT_POLL_INTERVAL_MS, remaining));
    }
  }

  private async with_timeout<T>(promise: Promise<T>, timeout_ms: number): Promise<T> {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        promise,
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error(`Transport attempt timed out after ${timeout_ms}ms.`)),
            timeout_ms
          );
        }),
      ]);
    } finally {
      if (timer !== undefined) {
        clearTimeout(timer);
      }
    }
  }
}
