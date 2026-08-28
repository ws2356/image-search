Device discovery is needed for auto resume interrupted backup session from mobile side
- USB:
  - Android: leverage AOA to detect USB connection and trigger device discovery. Almost zero-conf discovery.
  - iOS: leverage libimobiledevice or usbmuxd to detect USB connection and trigger device discovery. Mobile side should use a hardcoded port to listen for incoming connections from the desktop side, and desktop side should connect to that port after detecting the device through usbmuxd. This approach is needed because iOS does not support acting as a USB host and cannot reliably initiate connections over USB on its own.
- Wi-Fi LAN:
  - Both platforms: mDNS and dns-sd based service discovery for pc and mobile device to discover each other.
- Manual fallback:
  - PC ip/port can be encoded in the QR code during onboarding, and mobile can connect to that ip/port to circumvent the need for automatic discovery. This should actually be preferred over automatic discovery.
  - When automatic discovery fails or interrupted, we can prompt the user to manually enter the IP address of the pc to establish the connection. This is a common fallback mechanism used by many applications that support local network connectivity, and can be implemented with a simple UI for entering the connection details.