from __future__ import annotations

from typing import Callable

from dt_image_search.mobile.transport.contracts import (
    MobileTransportContext,
    MobileTransportRequest,
    MobileTransportResponse,
)

MobileTransportHandler = Callable[[MobileTransportRequest], MobileTransportResponse]


class MobileTransportRouteNotFoundError(RuntimeError):
    def __init__(self, operation: str):
        super().__init__(f"No transport route is registered for operation '{operation}'.")
        self.operation = operation


class MobileTransportRouter:
    def __init__(self):
        self._handlers: dict[str, MobileTransportHandler] = {}

    def register(self, operation: str, handler: MobileTransportHandler) -> None:
        existing_handler = self._handlers.get(operation)
        if existing_handler is not None and existing_handler is not handler:
            raise ValueError(f"Transport route '{operation}' is already registered.")
        self._handlers[operation] = handler

    def dispatch(
        self,
        *,
        operation: str,
        payload: object,
        context: MobileTransportContext,
    ) -> MobileTransportResponse:
        handler = self._handlers.get(operation)
        if handler is None:
            raise MobileTransportRouteNotFoundError(operation)
        request = MobileTransportRequest(operation=operation, payload=payload, context=context)
        return handler(request)
