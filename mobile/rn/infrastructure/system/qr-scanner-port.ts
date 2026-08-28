import { Camera } from 'expo-camera';

export interface QrScannerPermissionSnapshot {
  granted: boolean;
  canAskAgain: boolean;
}

export interface QrScannerPort {
  get_permission_snapshot(): Promise<QrScannerPermissionSnapshot>;
  request_permission(): Promise<QrScannerPermissionSnapshot>;
}

function to_permission_snapshot(permission: {
  granted: boolean;
  canAskAgain: boolean;
}): QrScannerPermissionSnapshot {
  return {
    granted: permission.granted,
    canAskAgain: permission.canAskAgain,
  };
}

export class ExpoCameraQrScannerPort implements QrScannerPort {
  async get_permission_snapshot(): Promise<QrScannerPermissionSnapshot> {
    const permission = await Camera.getCameraPermissionsAsync();
    return to_permission_snapshot(permission);
  }

  async request_permission(): Promise<QrScannerPermissionSnapshot> {
    const permission = await Camera.requestCameraPermissionsAsync();
    return to_permission_snapshot(permission);
  }
}

