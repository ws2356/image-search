import * as Crypto from 'expo-crypto';

export interface PairingKeyDeriveInput {
  session_id: string;
  one_time_passcode: string;
  platform: 'android' | 'ios';
}

export interface PairingKeyDeriver {
  derive_pairing_key_b64(input: PairingKeyDeriveInput): Promise<string>;
}

function to_base64_url(base64_value: string): string {
  return base64_value.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export class DefaultPairingKeyDeriver implements PairingKeyDeriver {
  async derive_pairing_key_b64(input: PairingKeyDeriveInput): Promise<string> {
    const material = [
      'dtis.mobile-pairing.v1',
      input.session_id,
      input.one_time_passcode,
      input.platform,
    ].join('\n');
    const digest_b64 = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, material, {
      encoding: Crypto.CryptoEncoding.BASE64,
    });
    return to_base64_url(digest_b64);
  }
}
