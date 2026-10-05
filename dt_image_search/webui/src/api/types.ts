// Wire types — mirrors dt_image_search/index_server/serializers.py contract.
// Every id is a string on the wire.
export interface FolderDto {
  id: string
  path: string
  status: number
  added_at: string
}

export interface FileDto {
  id: string
  path: string
  folder_id: string
  status: number
}

export interface SearchResultDto {
  id: string
  path: string
  folder_id: string
  score: number
}

export interface FoldersResponse {
  folders: FolderDto[]
}

export interface SearchResponse {
  results: SearchResultDto[]
}

export interface BrowseResponse {
  folder: FolderDto
  subfolders: FolderDto[]
  files: FileDto[]
}

export interface StatusResponse {
  model_state: string
  folders: FolderDto[]
}
