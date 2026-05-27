import QuickCrypto from 'react-native-quick-crypto';
const { Buffer } = QuickCrypto;

const MOBILE_ENCRYPTION_SCHEMA = 'dtis.mobile-encryption.v1' as const;
const MOBILE_ENCRYPTION_KEY_DERIVATION_CONTEXT = 'dtis.mobile-encryption.key.v1' as const;
const MOBILE_ENCRYPTION_BINARY_CHUNK_VERSION = 1;
const MOBILE_ENCRYPTION_NONCE_BYTES = 12;
const MOBILE_ENCRYPTION_TAG_BYTES = 16;

function to_base64_url(value: Uint8Array): string {
  return Buffer.from(value).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function from_base64_url(raw_value: string): Uint8Array {
  const normalized = raw_value.trim();
  if (normalized.length === 0) {
    throw new Error('Encrypted payload contains an empty base64url field.');
  }
  const base64_value = normalized.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64_value + '='.repeat((4 - (base64_value.length % 4)) % 4);
  return Buffer.from(padded, 'base64');
}

function assert_json_object(value: unknown, error_message: string): asserts value is Record<string, unknown> {
  if (typeof value !== 'object' || value == null || Array.isArray(value)) {
    throw new Error(error_message);
  }
}

function optional_locator_field(payload: Record<string, unknown>, field_name: string): string | null {
  const value = payload[field_name];
  if (typeof value !== 'string') {
    return null;
  }
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

function derive_encryption_key(trust_key_b64: string): Uint8Array {
  const normalized_trust_key = trust_key_b64.trim();
  if (normalized_trust_key.length === 0) {
    throw new Error('Transfer encryption key is missing.');
  }
  const material = `${MOBILE_ENCRYPTION_KEY_DERIVATION_CONTEXT}\n${normalized_trust_key}`;
  return QuickCrypto.createHash('sha256').update(material).digest();
}

export interface PayloadCipher {
  encrypt_json_payload(payload: object): Promise<object>;
  decrypt_json_payload(payload: object): Promise<object>;
  encrypt_binary_chunk(chunk: Blob | Uint8Array): Promise<Uint8Array>;
}

export class NoopPayloadCipher implements PayloadCipher {
  async encrypt_json_payload(payload: object): Promise<object> {
    return payload;
  }

  async decrypt_json_payload(payload: object): Promise<object> {
    return payload;
  }

  async encrypt_binary_chunk(chunk: Blob | Uint8Array): Promise<Uint8Array> {
    if (chunk instanceof Uint8Array) {
      return chunk;
    }
    return new Uint8Array(await chunk.arrayBuffer());
  }
}

export class TransferPayloadCipher implements PayloadCipher {
  private readonly trust_key_b64: string;

  constructor(trust_key_b64: string) {
    this.trust_key_b64 = trust_key_b64;
  }

  async encrypt_json_payload(payload: object): Promise<object> {
    assert_json_object(payload, 'Transfer request payload must be a JSON object.');
    const session_id = optional_locator_field(payload, 'session_id');
    if (session_id == null) {
      throw new Error("Encrypted transfer request is missing locator field 'session_id'.");
    }
    const plaintext = Buffer.from(JSON.stringify(payload), 'utf-8');
    const key = derive_encryption_key(this.trust_key_b64);
    const nonce = QuickCrypto.randomBytes(MOBILE_ENCRYPTION_NONCE_BYTES);
    const cipher = QuickCrypto.createCipheriv('aes-256-gcm', key, nonce);
    const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const tag = cipher.getAuthTag() as Uint8Array;
    const encrypted_payload: Record<string, string> = {
      schema: MOBILE_ENCRYPTION_SCHEMA,
      nonce: to_base64_url(nonce),
      ciphertext: to_base64_url(Buffer.concat([ciphertext, tag])),
      session_id,
    };
    const device_uuid = optional_locator_field(payload, 'device_uuid');
    if (device_uuid != null) {
      encrypted_payload.device_uuid = device_uuid;
    }
    const platform = optional_locator_field(payload, 'platform');
    if (platform != null) {
      encrypted_payload.platform = platform;
    }
    return encrypted_payload;
  }

  async decrypt_json_payload(payload: object): Promise<object> {
    assert_json_object(payload, 'Transfer response payload must be a JSON object.');
    if (payload.schema !== MOBILE_ENCRYPTION_SCHEMA) {
      throw new Error('Desktop transfer response must be encrypted.');
    }
    const raw_nonce = payload.nonce;
    if (typeof raw_nonce !== 'string' || raw_nonce.trim().length === 0) {
      throw new Error("Encrypted transfer response is missing field 'nonce'.");
    }
    const raw_ciphertext = payload.ciphertext;
    if (typeof raw_ciphertext !== 'string' || raw_ciphertext.trim().length === 0) {
      throw new Error("Encrypted transfer response is missing field 'ciphertext'.");
    }
    const nonce = from_base64_url(raw_nonce);
    if (nonce.length !== MOBILE_ENCRYPTION_NONCE_BYTES) {
      throw new Error('Encrypted transfer response nonce length is invalid.');
    }
    const ciphertext_with_tag = from_base64_url(raw_ciphertext);
    if (ciphertext_with_tag.length <= MOBILE_ENCRYPTION_TAG_BYTES) {
      throw new Error('Encrypted transfer response ciphertext is invalid.');
    }
    const ciphertext = ciphertext_with_tag.subarray(0, ciphertext_with_tag.length - MOBILE_ENCRYPTION_TAG_BYTES);
    const tag = ciphertext_with_tag.subarray(ciphertext_with_tag.length - MOBILE_ENCRYPTION_TAG_BYTES);
    try {
      const decipher = QuickCrypto.createDecipheriv('aes-256-gcm', derive_encryption_key(this.trust_key_b64), nonce);
      decipher.setAuthTag(Buffer.from(tag));
      const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      const decoded = JSON.parse(plaintext.toString('utf-8'));
      assert_json_object(decoded, 'Decrypted transfer response payload is not a JSON object.');
      return decoded;
    } catch {
      throw new Error('Desktop transfer response decryption failed.');
    }
  }

  async encrypt_binary_chunk(chunk: Blob | Uint8Array): Promise<Uint8Array> {
    const raw_chunk = chunk instanceof Uint8Array ? chunk : new Uint8Array(await chunk.arrayBuffer());
    const key = derive_encryption_key(this.trust_key_b64);
    const nonce = QuickCrypto.randomBytes(MOBILE_ENCRYPTION_NONCE_BYTES);
    const cipher = QuickCrypto.createCipheriv('aes-256-gcm', key, nonce);
    const ciphertext = Buffer.concat([cipher.update(Buffer.from(raw_chunk)), cipher.final()]);
    const tag = cipher.getAuthTag() as Uint8Array;
    return Buffer.concat([
      Buffer.from([MOBILE_ENCRYPTION_BINARY_CHUNK_VERSION]),
      nonce,
      ciphertext,
      tag,
    ]);
  }
}
