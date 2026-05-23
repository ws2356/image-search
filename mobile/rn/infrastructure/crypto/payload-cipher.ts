export interface PayloadCipher {
  encrypt_json_payload(payload: object): Promise<object>;
  decrypt_json_payload(payload: object): Promise<object>;
}

export class NoopPayloadCipher implements PayloadCipher {
  async encrypt_json_payload(payload: object): Promise<object> {
    return payload;
  }

  async decrypt_json_payload(payload: object): Promise<object> {
    return payload;
  }
}
