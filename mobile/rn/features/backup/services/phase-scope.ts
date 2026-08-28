export const PHASE4_PAIRING_ONLY_SCOPE = false;

export function assert_transfer_not_live_in_phase4(operation: string): void {
  if (PHASE4_PAIRING_ONLY_SCOPE) {
    throw new Error(`${operation} is intentionally deferred until Phase 5 live transfer work.`);
  }
}
