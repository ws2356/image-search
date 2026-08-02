1. [x] Instant share support for multiple selected images 
2. [x] UI Polish
3. [ ] Instant share p2m BLE flow
4. [ ] Instant share session management refactor - only pass sessionID or opt in encrypted payload. pc-to-mobile additional: remove sessionID from QR payload (pc search for sessionID using opt).
5. [ ] Bug: mobile/instant-share splash screen. Content layout too high
6. [ ] Security risk: in instant-share trust handshake process, the data accessor should be authenticated to the data holder; e.g. in pc-to-mobile flow, mobile should send an auth field to pc for authn; in mobile-to-pc flow, mobile should send a challenge to pc and pc should reply the challenge with a hash value of the challenge combined with shared secret and dh pub key of both sides.
7. [ ] Update AuBackup authentication flow to reuse the protocol of instant-share (mobile sends a challenge for pc to respond after QR scan).
8. [ ] 有的时候,share extension点击之后,提交文件给agent的请求失败,与此同时is.sock文件不存在.似乎是agent进行没有管理好is.sock?