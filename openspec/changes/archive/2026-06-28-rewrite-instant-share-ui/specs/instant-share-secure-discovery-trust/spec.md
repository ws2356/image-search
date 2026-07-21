## MODIFIED Requirements

### Requirement: mDNS candidate PC discovery before send
The mobile system SHALL discover PCs via mDNS (Bonjour) on the local network and SHALL maintain a user-selectable list of candidate PCs in the iOS Share Extension. No AuBackup handoff — extension handles the full flow natively.

#### Scenario: Candidate list population
- **WHEN** the sender opens instant-share target selection
- **THEN** the Share Extension presents a production device selector card populated with discovered candidate PCs from mDNS `_instantshare._tcp` service advertisements
- **AND** device cards SHALL follow the new design system styling with dark theme and proper typography