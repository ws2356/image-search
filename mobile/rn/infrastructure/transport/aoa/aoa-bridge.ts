import { NativeEventEmitter, NativeModules } from 'react-native';

export interface AoaBridgeStateEvent {
  state: 'IDLE' | 'PREPARING' | 'AUTHENTICATING' | 'CONNECTED' | 'DISCONNECTED' | 'FAILED';
  errorMessage?: string | null;
}

export interface AoaBridge {
  prepareBootstrap(session_id: string, one_time_passcode: string, suggested_port: number): Promise<void>;
  reset(): Promise<void>;
  isConnected(): boolean;
  sendRequest(envelopeJson: string): Promise<string>;
  beginStreamingRequest(envelopeJson: string): Promise<string>;
  sendBinaryChunk(request_id: string, chunk: Uint8Array): Promise<void>;
  finishStreamingRequest(request_id: string): Promise<string>;
  addStateListener(listener: (event: AoaBridgeStateEvent) => void): () => void;
}

const AOA_TRANSPORT_STATE_EVENT = 'AoaTransportStateChanged';

export class NativeAoaBridge implements AoaBridge {
  private readonly nativeModule = NativeModules.AoaTransportModule as {
    prepareBootstrap(sessionId: string, oneTimePasscode: string, suggestedPort: number): Promise<void>;
    reset(): Promise<void>;
    isConnected(): boolean;
    sendRequest(envelopeJson: string): Promise<string>;
    beginStreamingRequest(envelopeJson: string): Promise<string>;
    sendBinaryChunk(requestId: string, chunk: number[]): Promise<void>;
    finishStreamingRequest(requestId: string): Promise<string>;
  };
  private readonly eventEmitter = new NativeEventEmitter(NativeModules.AoaTransportModule);

  async prepareBootstrap(session_id: string, one_time_passcode: string, suggested_port: number): Promise<void> {
    return this.nativeModule.prepareBootstrap(session_id, one_time_passcode, suggested_port);
  }

  async reset(): Promise<void> {
    return this.nativeModule.reset();
  }

  isConnected(): boolean {
    return this.nativeModule.isConnected();
  }

  async sendRequest(envelopeJson: string): Promise<string> {
    return this.nativeModule.sendRequest(envelopeJson);
  }

  async beginStreamingRequest(envelopeJson: string): Promise<string> {
    return this.nativeModule.beginStreamingRequest(envelopeJson);
  }

  async sendBinaryChunk(request_id: string, chunk: Uint8Array): Promise<void> {
    const array = Array.from(chunk);
    return this.nativeModule.sendBinaryChunk(request_id, array);
  }

  async finishStreamingRequest(request_id: string): Promise<string> {
    return this.nativeModule.finishStreamingRequest(request_id);
  }

  addStateListener(listener: (event: AoaBridgeStateEvent) => void): () => void {
    const subscription = this.eventEmitter.addListener(AOA_TRANSPORT_STATE_EVENT, listener);
    return () => subscription.remove();
  }
}
