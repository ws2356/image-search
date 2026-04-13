```mermaid
sequenceDiagram
    participant PC as PC (PySide6 App)
    participant US as usbmuxd / pymobiledevice3
    participant iOS as iPhone (Swift App)

    Note over PC, iOS: 1. Discovery & Physical Connection
    PC->>US: Monitor USB events (device_list)
    PC->>PC: Generate QR Code (Nonce + Suggested Port)
    iOS->>PC: Scan QR Code
    Note right of iOS: Store Nonce & Start TCP Server on Suggested Port

    Note over PC, iOS: 2. Tunnel Establishment
    US-->>PC: For each Device Detected (UDID)
    loop Port Probing
        PC->>US: usbmuxd_connect(UDID, port)
        US-->>iOS: Internal USB-to-TCP Bridge
        alt Port matches
            iOS-->>PC: Connection Accepted
        else Port Busy/Closed
            iOS-->>PC: Connection Refused
        end
    end

    Note over PC, iOS: 3. Identity Verification (Security)
    PC->>iOS: Auth Request: SHA256(Nonce + RandomString)
    iOS->>iOS: Validate using local Nonce
    iOS-->>PC: Auth Success (Encrypted Session Key)

    Note over PC, iOS: 4. Data Transmission (Request/Reply)
    rect rgb(240, 240, 240)
    Note right of iOS: User clicks "Backup"
    iOS->>PC: Command: PUSH_FILE (Metadata: name, size, hash)
    PC-->>iOS: Reply: READY / OFFSET
    
    loop Chunked Transfer
        iOS->>PC: Data Frame: Binary Chunk (encrypted)
        PC->>PC: Write to Disk / Update Progress
        PC-->>iOS: Reply: ACK (Chunk Received)
    end

    iOS->>PC: Command: TRANSFER_COMPLETE
    PC-->>iOS: Reply: VERIFIED (Final MD5 Check)
    end
````