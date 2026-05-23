export interface PairingKeyDeriveInput {
  session_id: string;
  one_time_passcode: string;
  client_nonce: string;
}

export interface PairingKeyDeriver {
  derive_pairing_key_b64(input: PairingKeyDeriveInput): Promise<string>;
}

function to_base64_url(input: string): string {
  if (typeof globalThis.btoa === 'function') {
    return globalThis.btoa(input).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  }
  return encodeURIComponent(input).replace(/%/g, '_');
}

function hash_seed(seed: string): string {
  let hash = 5381;
  for (let index = 0; index < seed.length; index += 1) {
    hash = (hash * 33) ^ seed.charCodeAt(index);
  }
  return Math.abs(hash).toString(16);
}

export class DefaultPairingKeyDeriver implements PairingKeyDeriver {
  async derive_pairing_key_b64(input: PairingKeyDeriveInput): Promise<string> {
    const seed = `${input.session_id}:${input.one_time_passcode}:${input.client_nonce}`;
    return to_base64_url(`pairing_key:${hash_seed(seed)}`);
  }
}
