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

const AOA_RETRY_COOLDOWN_MS = 500;

export class AdaptiveTransportStrategy implements TransportStrategy {
  readonly kind = TransportKind.Usb;

  private aoa_unavailable_until = 0;
  private last_pairing_strategy: TransportStrategy | null = null;

  constructor(
    private readonly aoa_strategy: TransportStrategy,
    private readonly lan_strategy: TransportStrategy,
    private readonly is_aoa_connected: () => boolean
  ) {}

  async claim_pairing(request: PairingClaimRequest): Promise<PairingResponse> {
    return this.execute_with_fallback(
      (s) => s.claim_pairing(request),
      (result) => {
        this.last_pairing_strategy = result.strategy;
      }
    );
  }

  async get_pairing_state(request: PairingStateRequest): Promise<PairingResponse> {
    return this.execute_with_fallback((s) => s.get_pairing_state(request), () => {});
  }

  async exchange_capabilities(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse> {
    return this.execute_with_fallback((s) => s.exchange_capabilities(input), () => {});
  }

  create_transfer_client(context: TransferServiceContext): TransferClient {
    if (this.can_try_aoa()) {
      try {
        return this.aoa_strategy.create_transfer_client(context);
      } catch {
        this.mark_aoa_unavailable();
      }
    }
    return this.lan_strategy.create_transfer_client(context);
  }

  private async execute_with_fallback<T>(
    operation: (strategy: TransportStrategy) => Promise<T>,
    on_success: (result: { strategy: TransportStrategy; value: T }) => void
  ): Promise<T> {
    const try_aoa = this.can_try_aoa();
    if (try_aoa) {
      try {
        const value = await operation(this.aoa_strategy);
        on_success({ strategy: this.aoa_strategy, value });
        return value;
      } catch (error) {
        this.mark_aoa_unavailable();
      }
    }
    const value = await operation(this.lan_strategy);
    on_success({ strategy: this.lan_strategy, value });
    return value;
  }

  private can_try_aoa(): boolean {
    return this.is_aoa_connected() && Date.now() >= this.aoa_unavailable_until;
  }

  private mark_aoa_unavailable(): void {
    this.aoa_unavailable_until = Date.now() + AOA_RETRY_COOLDOWN_MS;
  }
}
