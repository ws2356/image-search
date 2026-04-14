# Refactor dt_image_search/mobile/*
## Overall design
This refactor plan aims to abstract the transport layer and add a new transport for USB communication. The existing transport for Wi-Fi LAN will be refactored to fit into the new architecture.

The new transport layer logically work as a server that handles incoming requests (like pairing claiming, transfer start, transfer upload, transfer complete), routing them to upper layers like pairing_service and transfer_service, and sending responses back to the client.

The new transport physically work as an http server for Wi-Fi LAN and as a websocket client for USB. The transport layer defines a common message schema which will be used by mobile side and desktop side to communicate. For development speed, let's use JSON as the message format for now, and we can switch to protobuf later if needed.