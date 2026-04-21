from __future__ import annotations

import base64
import hashlib
import hmac
import json
from typing import Mapping

TRUST_PROOF_FIELD = "trust_proof"
TRUST_PROOF_CONTEXT = "dtis.mobile-trust-proof.v1"


def derive_trust_proof_b64(
    *,
    trust_key_b64: str,
    payload: Mapping[str, object],
) -> str:
    payload_digest_b64 = _payload_digest_b64(payload)
    material = f"{TRUST_PROOF_CONTEXT}\n{payload_digest_b64}".encode("utf-8")
    digest = hmac.new(
        trust_key_b64.encode("utf-8"),
        material,
        hashlib.sha256,
    ).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


def is_valid_trust_proof(
    *,
    trust_key_b64: str,
    payload: Mapping[str, object],
    trust_proof_b64: str,
) -> bool:
    expected_proof = derive_trust_proof_b64(
        trust_key_b64=trust_key_b64,
        payload=payload,
    )
    return hmac.compare_digest(expected_proof, trust_proof_b64)


def _payload_digest_b64(payload: Mapping[str, object]) -> str:
    payload_without_proof = dict(payload)
    payload_without_proof.pop(TRUST_PROOF_FIELD, None)
    canonical_payload = json.dumps(
        payload_without_proof,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    digest = hashlib.sha256(canonical_payload).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")
