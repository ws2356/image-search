- Minumum trust model
    - PC and mobile app exchange a unique device identity during pairing, and the desktop app uses successful exchange and verification of this identity as the minimum trust signal to authorize backup and restore operations. This is similar to the trust model used by services like Apple's iCloud, where possession of the device (and its associated credentials) is used as a key factor in granting access to data and services.
    - The device identity can be safely exchanged by symmetrically encrypting it with a short-lived key derived from the QR code, which is only valid for a single pairing session. This approach ensures that even if the QR code is intercepted, it cannot be reused for unauthorized access.

- Improvement opportunities
    - End-to-end encryption
    - Key rotation
       - Each time reconnecting
       - Each time existing valid keys are used in transport, extend their validity to now + 28 days
       - Consecutive 28 days of inactivity should require a new QR code and key exchange to re-establish trust and derive fresh keys
