export type MediaPermissionScope = 'full' | 'limited' | 'denied';

export interface PermissionGateway {
  get_media_permission_scope(): Promise<MediaPermissionScope>;
  request_media_permission_scope(): Promise<MediaPermissionScope>;
}

function map_media_library_scope(permission: {
  granted: boolean;
  accessPrivileges?: 'all' | 'limited' | 'none' | string;
}): MediaPermissionScope {
  if (!permission.granted) {
    return 'denied';
  }

  if (permission.accessPrivileges === 'limited') {
    return 'limited';
  }

  return 'full';
}

export class StubPermissionGateway implements PermissionGateway {
  async get_media_permission_scope(): Promise<MediaPermissionScope> {
    return 'full';
  }

  async request_media_permission_scope(): Promise<MediaPermissionScope> {
    return 'full';
  }
}

export class ExpoMediaLibraryPermissionGateway implements PermissionGateway {
  async get_media_permission_scope(): Promise<MediaPermissionScope> {
    const media_library = await import('expo-media-library');
    const permission = await media_library.getPermissionsAsync(false);
    return map_media_library_scope(permission);
  }

  async request_media_permission_scope(): Promise<MediaPermissionScope> {
    const media_library = await import('expo-media-library');
    const permission = await media_library.requestPermissionsAsync(false);
    return map_media_library_scope(permission);
  }
}
