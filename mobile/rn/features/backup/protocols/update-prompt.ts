export const MOBILE_UPDATE_PROMPT_SCHEMA = 'dtis.mobile-update.v1' as const;
export const MOBILE_UPDATE_PROMPT_PATH = '/api/mobile/update/prompt' as const;
export const MOBILE_UPDATE_PROMPT_PROOF_PURPOSE = 'update.prompt' as const;

export interface UpdatePromptRequest {
  schema: typeof MOBILE_UPDATE_PROMPT_SCHEMA;
  session_id: string;
  device_uuid: string;
  trust_proof: string;
  required: boolean;
  body_text?: string;
  update_destination?: string;
}

export interface UpdatePromptResponse {
  schema: typeof MOBILE_UPDATE_PROMPT_SCHEMA;
  status: 'accepted' | 'rejected';
  message: string;
  session_id?: string;
  device_uuid?: string;
  required?: boolean;
}
