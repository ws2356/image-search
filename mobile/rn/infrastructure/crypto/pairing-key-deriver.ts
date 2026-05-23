export interface PairingKeyDeriveInput {
  session_id: string;
  one_time_passcode: string;
  client_nonce: string;
}

export interface PairingKeyDeriver {
  derive_pairing_key_b64(input: PairingKeyDeriveInput): Promise<string>;
}

export class StubPairingKeyDeriver implements PairingKeyDeriver {
  async derive_pairing_key_b64(input: PairingKeyDeriveInput): Promise<string> {
    const seed = `${input.session_id}:${input.one_time_passcode}:${input.client_nonce}`;
    return `stub_pairing_key:${seed}`;
  }
}
