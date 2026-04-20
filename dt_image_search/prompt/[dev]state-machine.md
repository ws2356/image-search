Backup State Machine
The backup process can be modeled as a state machine with the following states:
1. Pending_Pairing: PC is waiting for mobile initiate pairing, e.g. via QR scan.
2. Pairing_Completed: PC/Mobile pair is set up correctly. PC is now waiting for mobile to start the transferring process. Mobile can do permissions check and show warnings before allowing user before starting the transfer.
3. Transfer_In_Progress: Transfer process has started and is ongoing.
4. Transfer_Stopped: User has stopped the transfer mid-way through, or transfer was interrupted due to connectivity issues. PC should show option to resume transfer when mobile is back online.
5. Transfer_Completed: Transfer process has completed successfully.
6. Transfer_Failed: Transfer process has failed due to an error.
7. Pairing_Mismatched: In 'Back Up Again' flow, mobile device id does not match the folder. PC should show error and recovery options (e.g. retry pairing, start new backup, etc.)

Transitions between states:
```mermaid
stateDiagram
    [*] --> Pending_Pairing
    Pending_Pairing --> Pairing_Completed: Mobile initiates pairing (e.g. QR scan)

    Pending_Pairing --> Pairing_Mismatched: Pairing and Backup again but device mismatch occurs
    Pairing_Mismatched --> Pairing_Completed: PC resolves mismatch (e.g. user confirms it's the same device, or starts new backup)

    Pairing_Completed --> Transfer_In_Progress: Mobile starts transfer
    Transfer_In_Progress --> Transfer_Stopped: User stops transfer or connectivity issues
    Transfer_In_Progress --> Transfer_Completed: Transfer completes successfully
    Transfer_In_Progress --> Transfer_Failed: Transfer fails due to error
```

Sequence diagram for backup process:
```mermaid
sequenceDiagram
    participant User
    participant Mobile
    participant PC
    User->>PC: Initiate Pairing and Backup, PC shows QR code

    alt Pairing Completed Directly
        User->>Mobile: Scan QR code to pair with PC
        Mobile->>PC: Claim QR code
        PC-->>Mobile: Pairing completed, waiting for transfer to start
    else Pairing Mismatch in Backup Again Flow
        User->>Mobile: Scan QR code to pair with PC
        Mobile->>PC: Claim QR code
        PC-->>Mobile: Pairing mismatch
        Mobile->>Mobile: Polling for Pairing mismatch resolution
        User->>PC: Confirm it's the same device or start new backup
        PC-->>Mobile: Pairing completed, waiting for transfer to start
    end

    Mobile->>Mobile: Check permissions, show warnings if needed
    User->>Mobile: Start Transfer

    Mobile->>PC: Transfer started
    PC-->>Mobile: Transfer_In_Progress

    Mobile->>PC: Upload data in chunks, update progress
    PC-->>Mobile: Acknowledge received chunks, update progress UI

    alt User stops transfer or connectivity issues
        User->>Mobile: Stop Transfer
        Mobile->>PC: Transfer stopped by user
        PC-->>Mobile: Transfer_Stopped
    else Transfer completes successfully
        Mobile->>PC: Transfer completed
        PC-->>Mobile: Transfer_Completed
    end
```