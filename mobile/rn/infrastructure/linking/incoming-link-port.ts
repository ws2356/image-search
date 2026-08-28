import * as Linking from 'expo-linking';

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

export class ExpoIncomingLinkPort implements IncomingLinkPort {
  async get_initial_url(): Promise<string | null> {
    return Linking.getInitialURL();
  }

  subscribe(handler: (url: string) => void): () => void {
    const subscription = Linking.addEventListener('url', (event) => {
      handler(event.url);
    });
    return () => {
      subscription.remove();
    };
  }
}
