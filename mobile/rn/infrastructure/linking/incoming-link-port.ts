export interface IncomingLinkPort {
  get_initial_url(): Promise<string | null>;
  subscribe(handler: (url: string) => void): () => void;
}

export class NoopIncomingLinkPort implements IncomingLinkPort {
  async get_initial_url(): Promise<string | null> {
    return null;
  }

  subscribe(_handler: (url: string) => void): () => void {
    return () => undefined;
  }
}
