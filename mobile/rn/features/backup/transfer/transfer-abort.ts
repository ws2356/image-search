export const TRANSFER_ABORT_ERROR_MESSAGE = 'Transfer stopped by user.';

export function create_transfer_abort_error(): Error {
  const error = new Error(TRANSFER_ABORT_ERROR_MESSAGE);
  error.name = 'AbortError';
  return error;
}

export function is_transfer_abort_error(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }
  return error.name === 'AbortError' || error.message === TRANSFER_ABORT_ERROR_MESSAGE;
}
