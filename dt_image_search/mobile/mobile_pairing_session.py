from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from enum import Enum
from pathlib import Path
import secrets
from urllib.parse import urlencode, urlsplit, urlunsplit
import uuid

from dt_image_search.mobile.mobile_pairing_discovery import PAIRING_ADVERTISED_HOST_LIMIT

PAIRING_TOKEN_TTL = timedelta(minutes=15)
PAIRING_QR_SCHEMA_VERSION = 2
PAIRING_QR_HOST = "dl.boldman.net"
USB_SUGGESTED_PORT_MIN = 47000
USB_SUGGESTED_PORT_MAX = 57000


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
    one_time_passcode: str
    suggested_usb_port: int
    payload: str
    endpoint_targets: tuple[str, ...]
    strict_security_enabled: bool
    expires_at: datetime
    refresh_generation: int
    deep_link_url: str
    store_url: str

    @property
    def endpoint_target(self) -> str:
        return self.endpoint_targets[0]

    def seconds_remaining(self, now: datetime | None = None) -> int:
        remaining = int((self.expires_at - _utc_now(now)).total_seconds())
        return max(0, remaining)

    def is_expired(self, now: datetime | None = None) -> bool:
        return self.seconds_remaining(now) == 0


@dataclass
class MobilePairingSessionDraft:
    destination_parent: str
    desktop_endpoint_urls: tuple[str, ...]
    session_id: str
    created_at: datetime
    tokens: dict[MobilePlatform, MobilePairingToken] = field(default_factory=dict)

    @property
    def desktop_endpoint_url(self) -> str:
        return self.desktop_endpoint_urls[0]

    @classmethod
    def create(
        cls,
        destination_parent: str,
        desktop_endpoint_url: str | None = None,
        desktop_endpoint_urls: list[str] | tuple[str, ...] | None = None,
        strict_security_enabled: bool = False,
        now: datetime | None = None,
    ) -> "MobilePairingSessionDraft":
        current_time = _utc_now(now)
        normalized_endpoint_urls = _normalize_endpoint_urls(
            desktop_endpoint_url=desktop_endpoint_url,
            desktop_endpoint_urls=desktop_endpoint_urls,
        )
        session = cls(
            destination_parent=_normalize_directory_path(destination_parent),
            desktop_endpoint_urls=normalized_endpoint_urls,
            session_id=uuid.uuid4().hex,
            created_at=current_time,
        )
        for platform in MobilePlatform:
            session.tokens[platform] = _new_pairing_token(
                session_id=session.session_id,
                desktop_endpoint_urls=session.desktop_endpoint_urls,
                platform=platform,
                strict_security_enabled=strict_security_enabled,
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
            desktop_endpoint_urls=self.desktop_endpoint_urls,
            platform=platform,
            strict_security_enabled=current_token.strict_security_enabled,
            refresh_generation=current_token.refresh_generation + 1,
            now=now,
        )
        self.tokens[platform] = refreshed_token
        return refreshed_token

    def set_destination_parent(self, destination_parent: str) -> None:
        self.destination_parent = _normalize_directory_path(destination_parent)


def _new_pairing_token(
    session_id: str,
    desktop_endpoint_urls: tuple[str, ...],
    platform: MobilePlatform,
    strict_security_enabled: bool,
    refresh_generation: int,
    now: datetime | None = None,
) -> MobilePairingToken:
    current_time = _utc_now(now)
    metadata = _PLATFORM_METADATA[platform]
    endpoint_targets = tuple(_endpoint_target_from_url(endpoint_url) for endpoint_url in desktop_endpoint_urls)
    one_time_passcode = f"{secrets.randbelow(1_000_000):06d}"
    suggested_usb_port = USB_SUGGESTED_PORT_MIN + secrets.randbelow(
        USB_SUGGESTED_PORT_MAX - USB_SUGGESTED_PORT_MIN + 1
    )
    expires_at = current_time + PAIRING_TOKEN_TTL
    payload_fields = {
        "v": str(PAIRING_QR_SCHEMA_VERSION),
        "ept": ",".join(endpoint_targets),
        "sid": session_id,
        "opt": one_time_passcode,
        "usp": str(suggested_usb_port),
    }
    if strict_security_enabled:
        payload_fields["sec"] = "1"
    payload_query = urlencode(payload_fields)
    payload = urlunsplit(("https", PAIRING_QR_HOST, "", payload_query, ""))
    return MobilePairingToken(
        platform=platform,
        one_time_passcode=one_time_passcode,
        suggested_usb_port=suggested_usb_port,
        payload=payload,
        endpoint_targets=endpoint_targets,
        strict_security_enabled=strict_security_enabled,
        expires_at=expires_at,
        refresh_generation=refresh_generation,
        deep_link_url=metadata["deep_link_url"],
        store_url=metadata["store_url"],
    )


def _normalize_endpoint_urls(
    *,
    desktop_endpoint_url: str | None,
    desktop_endpoint_urls: list[str] | tuple[str, ...] | None,
) -> tuple[str, ...]:
    raw_endpoint_urls: list[str] = []
    if desktop_endpoint_urls is not None:
        raw_endpoint_urls.extend(desktop_endpoint_urls)
    elif desktop_endpoint_url is not None:
        raw_endpoint_urls.append(desktop_endpoint_url)

    normalized_endpoint_urls: list[str] = []
    seen_endpoint_urls: set[str] = set()
    for endpoint_url in raw_endpoint_urls:
        if not isinstance(endpoint_url, str) or not endpoint_url:
            raise ValueError("Desktop pairing endpoint URLs must be non-empty strings.")
        if endpoint_url in seen_endpoint_urls:
            continue
        seen_endpoint_urls.add(endpoint_url)
        normalized_endpoint_urls.append(endpoint_url)

    if not normalized_endpoint_urls:
        raise ValueError("Desktop pairing requires at least one endpoint URL.")

    return tuple(normalized_endpoint_urls[:PAIRING_ADVERTISED_HOST_LIMIT])


def _endpoint_target_from_url(desktop_endpoint_url: str) -> str:
    parsed_endpoint = urlsplit(desktop_endpoint_url)
    if not parsed_endpoint.hostname or parsed_endpoint.port is None:
        raise ValueError(f"Desktop endpoint URL must include host and port: {desktop_endpoint_url}")

    hostname = parsed_endpoint.hostname
    if ":" in hostname and not hostname.startswith("["):
        hostname = f"[{hostname}]"
    return f"{hostname}:{parsed_endpoint.port}"


def platform_display_name(platform: MobilePlatform) -> str:
    return _PLATFORM_METADATA[platform]["display_name"]
