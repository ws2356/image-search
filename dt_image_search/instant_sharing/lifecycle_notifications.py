from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class InstantShareLifecycleNotification:
    title: str
    message: str
    severity: str = "info"


def build_instant_share_lifecycle_notification(
    *,
    state: str,
    payload_class: str,
    error_message: str | None = None,
) -> InstantShareLifecycleNotification | None:
    payload_label = _payload_label(payload_class)

    if state == "queued":
        return InstantShareLifecycleNotification(
            title="SnapGet Incoming",
            message=f"Preparing to receive {payload_label} from iPhone.",
        )
    if state == "transferring":
        return InstantShareLifecycleNotification(
            title="SnapGet Receiving",
            message=f"Receiving {payload_label} from iPhone.",
        )
    if state == "delivering":
        return InstantShareLifecycleNotification(
            title="SnapGet Delivering",
            message=_delivery_message(payload_class),
        )
    if state == "done":
        return InstantShareLifecycleNotification(
            title="SnapGet Complete",
            message=_completion_message(payload_class),
        )
    if state == "timed_out":
        return InstantShareLifecycleNotification(
            title="SnapGet Timed Out",
            message=error_message or f"The {payload_label} did not finish in time. Retry from iPhone.",
            severity="warning",
        )
    if state == "aborted":
        return InstantShareLifecycleNotification(
            title="SnapGet Canceled",
            message=error_message or f"The {payload_label} was canceled before completion.",
            severity="warning",
        )
    if state == "failed":
        return InstantShareLifecycleNotification(
            title="SnapGet Failed",
            message=error_message or f"The {payload_label} could not be completed.",
            severity="error",
        )
    return None


def _payload_label(payload_class: str) -> str:
    if payload_class == "text":
        return "shared text"
    if payload_class == "image":
        return "shared image"
    return "shared item"


def _delivery_message(payload_class: str) -> str:
    if payload_class == "text":
        return "Copying shared text to the clipboard."
    if payload_class == "image":
        return "Saving the shared image on this Mac."
    return "Delivering the shared item."


def _completion_message(payload_class: str) -> str:
    if payload_class == "text":
        return "Shared text is ready in the clipboard."
    if payload_class == "image":
        return "Shared image was received on this Mac."
    return "The shared item was received successfully."