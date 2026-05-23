export const TRUST_PROOF_CONTEXT = 'dtis.mobile-trust-proof.v1' as const;

export type TrustProofPurpose =
  | 'capabilities.exchange'
  | 'transfer.start'
  | 'transfer.existence'
  | 'transfer.asset'
  | 'transfer.complete'
  | 'update.prompt';

export interface TrustProofInput {
  purpose: TrustProofPurpose;
  schema: string;
  session_id: string;
  device_uuid: string;
}

export interface TrustProofDeriveInput extends TrustProofInput {
  trust_key_b64: string;
}
