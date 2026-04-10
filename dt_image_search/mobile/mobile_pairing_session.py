from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from enum import Enum
from pathlib import Path
import secrets
from urllib.parse import urlencode, urlunsplit
import uuid

PAIRING_TOKEN_TTL = timedelta(minutes=15)
PAIRING_QR_SCHEMA_VERSION = 1
PAIRING_QR_HOST = "dl.boldman.net"


class MobileSourceType(str, Enum):
    LOCAL_DEVICE = "local_device"
    MOBILE_DEVICE = "mobile_device"


class MobilePlatform(str, Enum):
    ANDROID = "android"
    IOS = "ios"


_PLATFORM_METADATA = {
    MobilePlatform.ANDROID: {
        "display_name": "Android",
        "deep_link_url": "album-transporter://pair/android",
        "store_url": "https://play.google.com/store/apps/details?id=net.boldman.albumtransporter",
    },
    MobilePlatform.IOS: {
        "display_name": "iPhone / iPad",
        "deep_link_url": "album-transporter://pair/ios",
        "store_url": "https://apps.apple.com/app/album-transporter/id0000000000",
    },
}


def _utc_now(now: datetime | None = None) -> datetime:
    if now is None:
        return datetime.now(timezone.utc)
    if now.tzinfo is None:
        return now.replace(tzinfo=timezone.utc)
    return now.astimezone(timezone.utc)


def _normalize_directory_path(directory_path: str) -> str:
    return Path(directory_path).expanduser().resolve().as_posix()


@dataclass(frozen=True)
class MobilePairingToken:
    platform: MobilePlatform
    token_id: str
    bootstrap_secret: str
    payload: str
    endpoint_url: str
    expires_at: datetime
    refresh_generation: int
    deep_link_url: str
    store_url: str

    def seconds_remaining(self, now: datetime | None = None) -> int:
        remaining = int((self.expires_at - _utc_now(now)).total_seconds())
        return max(0, remaining)

    def is_expired(self, now: datetime | None = None) -> bool:
        return self.seconds_remaining(now) == 0


@dataclass
class MobilePairingSessionDraft:
    destination_parent: str
    desktop_endpoint_url: str
    session_id: str
    created_at: datetime
    tokens: dict[MobilePlatform, MobilePairingToken] = field(default_factory=dict)

    @classmethod
    def create(
        cls,
        destination_parent: str,
        desktop_endpoint_url: str,
        now: datetime | None = None,
    ) -> "MobilePairingSessionDraft":
        current_time = _utc_now(now)
        session = cls(
            destination_parent=_normalize_directory_path(destination_parent),
            desktop_endpoint_url=desktop_endpoint_url,
            session_id=uuid.uuid4().hex,
            created_at=current_time,
        )
        for platform in MobilePlatform:
            session.tokens[platform] = _new_pairing_token(
                session_id=session.session_id,
                desktop_endpoint_url=session.desktop_endpoint_url,
                platform=platform,
                refresh_generation=0,
                now=current_time,
            )
        return session

    def token_for(self, platform: MobilePlatform) -> MobilePairingToken:
        return self.tokens[platform]

    def refresh_token(self, platform: MobilePlatform, now: datetime | None = None) -> MobilePairingToken:
        current_token = self.tokens[platform]
        refreshed_token = _new_pairing_token(
            session_id=self.session_id,
            desktop_endpoint_url=self.desktop_endpoint_url,
            platform=platform,
            refresh_generation=current_token.refresh_generation + 1,
            now=now,
        )
        self.tokens[platform] = refreshed_token
        return refreshed_token

    def set_destination_parent(self, destination_parent: str) -> None:
        self.destination_parent = _normalize_directory_path(destination_parent)


def _new_pairing_token(
    session_id: str,
    desktop_endpoint_url: str,
    platform: MobilePlatform,
    refresh_generation: int,
    now: datetime | None = None,
) -> MobilePairingToken:
    current_time = _utc_now(now)
    metadata = _PLATFORM_METADATA[platform]
    token_id = uuid.uuid4().hex
    bootstrap_secret = secrets.token_urlsafe(24)
    expires_at = current_time + PAIRING_TOKEN_TTL
    payload_query = urlencode(
        {
            "v": str(PAIRING_QR_SCHEMA_VERSION),
            "endpoint": desktop_endpoint_url,
            "pairing_id": session_id,
            "token_id": token_id,
            "secret": bootstrap_secret,
            "expires_at": expires_at.isoformat(),
        }
    )
    payload = urlunsplit(("https", PAIRING_QR_HOST, "", payload_query, ""))
    return MobilePairingToken(
        platform=platform,
        token_id=token_id,
        bootstrap_secret=bootstrap_secret,
        payload=payload,
        endpoint_url=desktop_endpoint_url,
        expires_at=expires_at,
        refresh_generation=refresh_generation,
        deep_link_url=metadata["deep_link_url"],
        store_url=metadata["store_url"],
    )


def platform_display_name(platform: MobilePlatform) -> str:
    return _PLATFORM_METADATA[platform]["display_name"]
