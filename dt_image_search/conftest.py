"""Conftest to mock heavy dependencies for unit tests."""

import sys
import types

# Mock aiortc before any imports trigger it
mock_aiortc = types.ModuleType('aiortc')
mock_aiortc.RTCDataChannel = type('RTCDataChannel', (), {})
mock_aiortc.RTCPeerConnection = type('RTCPeerConnection', (), {})
mock_aiortc.RTCSessionDescription = type('RTCSessionDescription', (), {})
sys.modules['aiortc'] = mock_aiortc
