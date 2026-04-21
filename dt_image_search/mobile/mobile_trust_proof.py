from __future__ import annotations

import base64
import hashlib
import hmac

TRUST_PROOF_CONTEXT = "dtis.mobile-trust-proof.v1"


def derive_trust_proof_b64(
    *,
    trust_key_b64: str,
    purpose: str,
    schema: str,
    session_id: str,
    device_uuid: str,
) -> str:
    material = "\n".join(
        [
            TRUST_PROOF_CONTEXT,
            purpose,
            schema,
            session_id,
            device_uuid,
        ]
    ).encode("utf-8")
    digest = hmac.new(
        trust_key_b64.encode("utf-8"),
        material,
        hashlib.sha256,
    ).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


def is_valid_trust_proof(
    *,
    trust_key_b64: str,
    purpose: str,
    schema: str,
    session_id: str,
    device_uuid: str,
    trust_proof_b64: str,
) -> bool:
    expected_proof = derive_trust_proof_b64(
        trust_key_b64=trust_key_b64,
        purpose=purpose,
        schema=schema,
        session_id=session_id,
        device_uuid=device_uuid,
    )
    return hmac.compare_digest(expected_proof, trust_proof_b64)
