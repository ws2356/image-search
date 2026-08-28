import type { TrustProofInput } from '@/features/backup/protocols/trust';
import { hmac } from '@noble/hashes/hmac.js';
import { sha256 } from '@noble/hashes/sha2.js';
import { utf8ToBytes } from '@noble/hashes/utils.js';

export interface TrustProofSigner {
  derive_trust_proof(input: TrustProofInput): Promise<string>;
}

function to_base64_url(input: string): string {
  if (typeof globalThis.btoa === 'function') {
    return globalThis.btoa(input).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  }
  return encodeURIComponent(input).replace(/%/g, '_');
}

function bytes_to_binary(bytes: Uint8Array): string {
  let binary = '';
  for (let index = 0; index < bytes.length; index += 1) {
    binary += String.fromCharCode(bytes[index]);
  }
  return binary;
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
    const digest = hmac(sha256, utf8ToBytes(input.trust_key_b64), utf8ToBytes(material));
    return to_base64_url(bytes_to_binary(digest));
  }
}
