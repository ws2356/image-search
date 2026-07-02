## 1. Verify spec-implementation alignment

- [x] 1.1 Review `dt_image_search/instant_sharing/mdns.py:_build_txt_properties()` confirms TXT records are `ver`, `tls_port`, `device_name` only
- [x] 1.2 Review `mobile/ios/Sources/ISFromMobile/Services/InstantShareMDNSBrowser.swift:resolveWithEndpoint()` confirms `id = "\(host):\(port)"` with no device_id dependency
- [x] 1.3 Review `dt_image_search/instant_sharing/qr_trigger_mini_window.py:build_qr_url()` confirms no device_id in QR URL params

## 2. Archive and promote

- [x] 2.1 Archive this change to promote the reconciled `instant-share-secure-discovery-trust` spec to `openspec/specs/`
