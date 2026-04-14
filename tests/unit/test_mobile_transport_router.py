import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.transport.contracts import (
    MobileTransportContext,
    MobileTransportKind,
    MobileTransportResponse,
)
from dt_image_search.mobile.transport.router import (
    MobileTransportRouteNotFoundError,
    MobileTransportRouter,
)


class TestMobileTransportRouter(unittest.TestCase):
    def test_dispatches_registered_operation(self):
        router = MobileTransportRouter()
        captured_requests = []

        def handler(request):
            captured_requests.append(request)
            return MobileTransportResponse(status_code=200, payload={"status": "ok"})

        router.register("pairing.claim", handler)
        context = MobileTransportContext(
            transport=MobileTransportKind.LAN_HTTP,
            operation="pairing.claim",
            remote_address="127.0.0.1:5000",
        )

        response = router.dispatch(
            operation="pairing.claim",
            payload={"schema": "dtis.mobile-pairing.v1"},
            context=context,
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.payload["status"], "ok")
        self.assertEqual(len(captured_requests), 1)
        self.assertEqual(captured_requests[0].operation, "pairing.claim")
        self.assertEqual(captured_requests[0].context.remote_address, "127.0.0.1:5000")

    def test_dispatch_raises_when_operation_not_registered(self):
        router = MobileTransportRouter()
        context = MobileTransportContext(
            transport=MobileTransportKind.LAN_HTTP,
            operation="transfer.start",
        )

        with self.assertRaises(MobileTransportRouteNotFoundError):
            router.dispatch(
                operation="transfer.start",
                payload={},
                context=context,
            )


if __name__ == "__main__":
    unittest.main()
