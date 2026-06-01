from __future__ import annotations

from dataclasses import dataclass, field
from typing import Mapping

from dt_image_search.instant_sharing.contracts import ErrorCode


@dataclass(eq=False)
class InstantShareError(Exception):
    error_code: ErrorCode
    message: str
    correlation_id: str | None = None
    retryable: bool = False
    details: Mapping[str, object] = field(default_factory=dict)

    def __post_init__(self) -> None:
        super().__init__(self.message)

    def to_payload(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "error_code": self.error_code.value,
            "message": self.message,
            "retryable": self.retryable,
        }
        if self.correlation_id is not None:
            payload["correlation_id"] = self.correlation_id
        if self.details:
            payload["details"] = dict(self.details)
        return payload