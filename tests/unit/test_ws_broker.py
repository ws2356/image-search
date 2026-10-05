# Unit tests for the index server WebSocket event broker.
import asyncio
import json
import unittest

from dt_image_search.index_server.ws import EventBroker


class FakeWebSocket:
    def __init__(self, auth=None):
        self._auth = auth
        self.sent = []
        self.closed = None
        self.accepted = False
        from starlette.datastructures import QueryParams
        self.query_params = QueryParams({"auth": auth} if auth else {})

    async def accept(self):
        self.accepted = True

    async def close(self, code=1000):
        self.closed = code

    async def send_text(self, data):
        self.sent.append(data)

    async def receive_text(self):
        await asyncio.Event().wait()  # blocks forever (client stays connected)


def run(coro):
    return asyncio.run(coro)


class TestEventBrokerTokenValidation(unittest.TestCase):
    def test_invalid_token_closes_with_1008_without_accept(self):
        async def scenario():
            broker = EventBroker(token="secret")
            ws = FakeWebSocket(auth="wrong")
            task = asyncio.create_task(broker.connect(ws))
            await asyncio.sleep(0.05)
            self.assertEqual(ws.closed, 1008)
            self.assertFalse(ws.accepted)
            task.cancel()
        run(scenario())

    def test_missing_token_closes_with_1008(self):
        async def scenario():
            broker = EventBroker(token="secret")
            ws = FakeWebSocket(auth=None)
            task = asyncio.create_task(broker.connect(ws))
            await asyncio.sleep(0.05)
            self.assertEqual(ws.closed, 1008)
            task.cancel()
        run(scenario())

    def test_valid_token_accepts_and_stays_connected(self):
        async def scenario():
            broker = EventBroker(token="secret")
            ws = FakeWebSocket(auth="secret")
            task = asyncio.create_task(broker.connect(ws))
            await asyncio.sleep(0.05)
            self.assertTrue(ws.accepted)
            self.assertIsNone(ws.closed)
            task.cancel()
        run(scenario())


class TestEventBrokerBroadcast(unittest.TestCase):
    def test_broadcast_reaches_all_clients(self):
        async def scenario():
            broker = EventBroker(token="secret")
            broker.attach_loop(asyncio.get_running_loop())
            ws1, ws2 = FakeWebSocket(auth="secret"), FakeWebSocket(auth="secret")
            tasks = [asyncio.create_task(broker.connect(w)) for w in (ws1, ws2)]
            await asyncio.sleep(0.05)

            broker.broadcast_threadsafe({"event": "status_message", "data": {"message": "hi"}})
            await asyncio.sleep(0.1)

            payload = json.dumps({"event": "status_message", "data": {"message": "hi"}})
            self.assertEqual(ws1.sent, [payload])
            self.assertEqual(ws2.sent, [payload])
            for t in tasks:
                t.cancel()
        run(scenario())

    def test_broadcast_without_loop_is_noop(self):
        broker = EventBroker(token="secret")
        broker.broadcast_threadsafe({"event": "x", "data": {}})  # must not raise

    def test_failing_client_is_dropped_without_breaking_others(self):
        async def scenario():
            broker = EventBroker(token="secret")
            broker.attach_loop(asyncio.get_running_loop())
            bad, good = FakeWebSocket(auth="secret"), FakeWebSocket(auth="secret")
            async def fail_send(data):
                raise RuntimeError("connection reset")
            bad.send_text = fail_send
            tasks = [asyncio.create_task(broker.connect(w)) for w in (bad, good)]
            await asyncio.sleep(0.05)

            broker.broadcast_threadsafe({"event": "x", "data": {}})
            await asyncio.sleep(0.1)

            self.assertEqual(good.sent, [json.dumps({"event": "x", "data": {}})])
            for t in tasks:
                t.cancel()
        run(scenario())


if __name__ == "__main__":
    unittest.main()
