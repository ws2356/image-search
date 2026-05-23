export type MediaPermissionScope = 'full' | 'limited' | 'denied';

export interface PermissionGateway {
  get_media_permission_scope(): Promise<MediaPermissionScope>;
}

export class StubPermissionGateway implements PermissionGateway {
  async get_media_permission_scope(): Promise<MediaPermissionScope> {
    return 'full';
  }
}
