## MODIFIED Requirements

### Requirement: X509 public certificate exchange for HTTPS trust
After successful PIN confirmation, both sides SHALL exchange X509 public certificates. The mobile SHALL store the PC's certificate keyed by public key hash. The PC SHALL store the mobile's certificate using its existing API. The mobile SHALL also include `peer_device_name` in the `/trust/confirm` encrypted request body. Batch image transfer metadata (image count) SHALL be communicated via HTTP headers on `/transfer/image` requests, not in the trust confirm body.

#### Scenario: Trust material persisted after first sharing (batch)
- **WHEN** first-share trust establishment completes successfully with a batch of images
- **THEN** the certificate exchange SHALL proceed identically to single-image flow
- **AND** the batch metadata SHALL be communicated via `X-Image-Count` header on subsequent `/transfer/image` requests
