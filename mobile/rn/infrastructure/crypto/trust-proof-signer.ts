import type { TrustProofInput } from '@/features/backup/protocols/trust';

export interface TrustProofSigner {
  derive_trust_proof(input: TrustProofInput): Promise<string>;
}

function to_base64_url(input: string): string {
  if (typeof globalThis.btoa === 'function') {
    return globalThis.btoa(input).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  }
  return encodeURIComponent(input).replace(/%/g, '_');
}

function hash_seed(seed: string): string {
  let hash = 2166136261;
  for (let index = 0; index < seed.length; index += 1) {
    hash ^= seed.charCodeAt(index);
    hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  return Math.abs(hash >>> 0).toString(16);
}

export class DefaultTrustProofSigner implements TrustProofSigner {
  async derive_trust_proof(input: TrustProofInput): Promise<string> {
    const material = [
      'dtis.mobile-trust-proof.v1',
      input.purpose,
      input.schema,
      input.session_id,
      input.device_uuid,
    ].join('\n');
    return to_base64_url(`trust_proof:${hash_seed(material)}`);
  }
}
