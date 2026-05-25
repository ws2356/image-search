import { assert_transfer_not_live_in_phase4 } from '@/features/backup/services/phase-scope';
import { TransferService } from '@/features/backup/services/transfer-service';
import type { CapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import { HttpCapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import {
  TransferFailureReason,
  TransferTransport,
  TransferPipelineStage,
} from '@/features/backup/transfer/enums';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { DefaultTrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import type { TrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import {
  begin_transfer_runtime_session,
  get_default_transfer_runtime_wiring,
  type TransferRuntimeWiring,
} from '@/infrastructure/platform/transfer-runtime-wiring';

export interface StartTransferDeps {
  apply_command: typeof apply_backup_command;
  trust_proof_signer: TrustProofSigner;
  capability_exchange_service: CapabilityExchangeService;
  transfer_runtime_wiring: TransferRuntimeWiring;
}

function build_initial_snapshot(now: Date): TransferProgressSnapshot {
  return {
    pipelineStage: TransferPipelineStage.Enumerating,
    transport: TransferTransport.Lan,
    counts: {
      totalAssets: 0,
      matchedAssets: 0,
      transferredAssets: 0,
      failedAssets: 0,
    },
    activeAssetId: null,
    activeRequestId: null,
    bytesUploaded: 0,
    bytesPerSecond: null,
    estimatedSecondsRemaining: null,
    lastUpdatedAt: now.toISOString(),
  };
}

export async function startTransfer(
  deps: StartTransferDeps = {
    apply_command: apply_backup_command,
    trust_proof_signer: new DefaultTrustProofSigner(),
    capability_exchange_service: new HttpCapabilityExchangeService(),
    transfer_runtime_wiring: get_default_transfer_runtime_wiring(),
  }
): Promise<void> {
  assert_transfer_not_live_in_phase4('startTransfer');
  const session = useBackupSessionStore.getState().session;
  if (!session.pairingSession?.sessionId || !session.pairingSession.endpointBaseUrl) {
    await deps.apply_command({
      type: 'transferResolved',
      result: {
        kind: 'failure',
        reason: TransferFailureReason.Unknown,
        error: {
          title: 'Transfer unavailable',
          message: 'Pairing session is missing. Pair a desktop first.',
        },
      },
    });
    return;
  }
  const device_uuid = session.localDeviceIdentity?.deviceUuid;
  const trust_key_b64 = session.pairingSession.trustKeyB64;
  if (!device_uuid || !trust_key_b64) {
    await deps.apply_command({
      type: 'transferResolved',
      result: {
        kind: 'failure',
        reason: TransferFailureReason.Unknown,
        error: {
          title: 'Transfer unavailable',
          message: 'Pairing data is incomplete. Pair this desktop again before starting transfer.',
        },
      },
    });
    return;
  }
  const trust_proof = await deps.trust_proof_signer.derive_trust_proof({
    purpose: 'capabilities.exchange',
    schema: 'dtis.mobile-capabilities.v1',
    session_id: session.pairingSession.sessionId,
    device_uuid,
    trust_key_b64,
  });
  const exchange = await deps.capability_exchange_service.exchange({
    endpoint_base_url: session.pairingSession.endpointBaseUrl,
    session_id: session.pairingSession.sessionId,
    device_uuid,
    trust_proof,
    capabilities: {
      encrypted_payload_v1: 1,
    },
  });
  if (exchange.status !== 'accepted') {
    await deps.apply_command({
      type: 'transferResolved',
      result: {
        kind: 'failure',
        reason: TransferFailureReason.Unknown,
        error: {
          title: 'Capability exchange rejected',
          message: exchange.message,
        },
      },
    });
    return;
  }
  const transfer_service = new TransferService({
    endpoint_base_url: session.pairingSession.endpointBaseUrl,
    session_id: session.pairingSession.sessionId,
    device_uuid,
    trust_key_b64,
  });
  await transfer_service.start(0);
  await begin_transfer_runtime_session(deps.transfer_runtime_wiring);
  await deps.apply_command({ type: 'startTransfer' });
  await deps.apply_command({
    type: 'transferSnapshotUpdated',
    snapshot: build_initial_snapshot(new Date()),
  });
}
