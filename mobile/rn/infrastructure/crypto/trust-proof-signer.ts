import type { TrustProofInput } from '@/features/backup/protocols/trust';

export interface TrustProofSigner {
  derive_trust_proof(input: TrustProofInput): Promise<string>;
}

export class StubTrustProofSigner implements TrustProofSigner {
  async derive_trust_proof(input: TrustProofInput): Promise<string> {
    return `stub_trust_proof:${input.purpose}:${input.schema}:${input.session_id}:${input.device_uuid}`;
  }
}
