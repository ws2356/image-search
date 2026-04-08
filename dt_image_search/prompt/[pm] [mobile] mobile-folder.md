Create a PM spec for the new mobile companion app (tentatively named "Album Transporter") to be built that work with the desktop app to transfer photos and videos from mobile to desktop. Refer to the existing [PM spec - image search](../specs/%5Bpm%5D%20%5Bpc%5D%20image-search.md) and [PM spec - mobile folder](../specs/%5Bpm%5D%20%5Bpc%5D%20mobile-folder.md) for the desktop app for background and context.

## Entry Points
- PC first flow: The user initiate `Add Folder` or `Reconnect` flow from PC and shows the QR code page. Then user can scan the QR code with either system camera or the in-app camera in the Album Transporter app to kick off the backup and indexing process.
- Mobile first flow: User opens the Album Transporter app for the first time and is guided through a setup process to connect it with the desktop app. The setup process include installing and then launch the desktop app, click the `Add Folder` button, and then follow the instructions to show a QR code page on the desktop app and then scan the QR code to kick off the backup and indexing process.

## Work Flow
1. User kick off the connection process by scanning the QR code on the desktop app with the Album Transporter app.
2. Album Transporter app establishes a secure connection with the desktop app and starts the backup process.
3. Album Transporter app shows the backup progress and estimated time remaining.
4. User can stop the backup process by pressing the `Stop` button on the Album Transporter app, which will not stop desktop app from indexing the photos and videos that have already been transferred.
5. Once the backup process is complete, the Album Transporter app shows a confirmation message.

## UI Design
- The Album Transporter app should have a clean and modern design that is consistent with the desktop app.
- The main screen should contain precise instructions for mobile first flow defined above. It should also have a button to trigger the camera for scanning the QR code for PC first flow. The instructions should mention that currently only full album backup is supported, and user can backup incrementally by stop/resume the backup process multiple times, without retransmitting already transferred items.
- During the backup process, the app should show a spinner and message indicating that the backup is in progress, along with an estimated time remaining. There should also be a `Stop` button that allows users to stop the backup process at any time. There should be messages reminding the user that USB transfer is faster and more stable than Wi-Fi.
- After the backup process is complete, the app should show a confirmation pop up dialog with a message indicating that the backup is complete and a button to return to the main screen.

## Telemetry
- Usage telemetry should include page views (including dialogs and modals), button clicks (organized by each screen or dialog), app launch.
- Health telemetry should include async activities like device discovery, pairing, backup and also include any errors that occur in the app.