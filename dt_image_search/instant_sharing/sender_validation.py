from __future__ import annotations

from pathlib import Path

from dt_image_search.instant_sharing.contracts import ErrorCode
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.security import PersistentEd25519SessionSigner


_DEFAULT_KEY_FILENAME = "instant_share_ed25519.pem"


class SenderIdentity:
    def __init__(self, *, key_path: Path, device_id: str) -> None:
        if not isinstance(device_id, str) or not device_id.strip():
            raise ValueError("device_id must not be empty.")
        self._device_id = device_id
        self._signer = PersistentEd25519SessionSigner(key_path)

    @classmethod
    def from_config_dir(cls, config_dir: Path, *, device_id: str) -> "SenderIdentity":
        config_dir.mkdir(parents=True, exist_ok=True)
        return cls(key_path=config_dir / _DEFAULT_KEY_FILENAME, device_id=device_id)

    @property
    def device_id(self) -> str:
        return self._device_id

    @property
    def session_signer(self) -> PersistentEd25519SessionSigner:
        return self._signer

    def sign_session_id(self, session_id: str) -> tuple[str, str]:
        if not isinstance(session_id, str) or not session_id.strip():
            raise InstantShareError(
                ErrorCode.SESSION_SIGNATURE_INVALID,
                "Cannot sign an empty session id.",
            )
        try:
            return self._signer.sign(session_id)
        except Exception as exc:
            raise InstantShareError(
                ErrorCode.SESSION_SIGNATURE_INVALID,
                f"Failed to sign session id: {exc}",
            ) from exc

    def public_key_pem(self) -> str:
        return self._signer.public_key_pem()
