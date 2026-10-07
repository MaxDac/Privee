/* tslint:disable */
/* eslint-disable */

export class EncryptedMessage {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    body: Uint8Array;
    /**
     * 2 for a regular (Whisper) message, 3 for a PreKey (session-initiating) message.
     */
    messageType: number;
}

/**
 * A public key to upload, plus its signature (empty for one-time prekeys).
 */
export class PublicPreKey {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    keyId: number;
    publicKey: Uint8Array;
    signature: Uint8Array;
}

export class SignalStore {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    decrypt(name: string, device_id: number, message_type: number, body: Uint8Array): Uint8Array;
    encrypt(name: string, device_id: number, plaintext: Uint8Array, now_ms: number): EncryptedMessage;
    fingerprint(local_id: string, remote_id: string, remote_identity_key: Uint8Array): string;
    generateKyberPreKey(id: number, now_ms: number): PublicPreKey;
    generatePreKey(id: number): PublicPreKey;
    generateSignedPreKey(id: number, now_ms: number): PublicPreKey;
    /**
     * Creates a new identity with a fresh registration id and empty stores.
     */
    static generate(): SignalStore;
    hasSession(name: string, device_id: number, now_ms: number): boolean;
    identityKey(): Uint8Array;
    isTrusted(name: string, device_id: number, identity_key: Uint8Array): boolean;
    kyberPreKeyIds(): Uint32Array;
    peerIdentity(name: string, device_id: number): Uint8Array | undefined;
    preKeyIds(): Uint32Array;
    /**
     * Starts a PQXDH session with `name` from the peer's published bundle.
     */
    processPreKeyBundle(name: string, device_id: number, registration_id: number, prekey_id: number | null | undefined, prekey: Uint8Array | null | undefined, signed_prekey_id: number, signed_prekey: Uint8Array, signed_prekey_signature: Uint8Array, kyber_prekey_id: number, kyber_prekey: Uint8Array, kyber_prekey_signature: Uint8Array, identity_key: Uint8Array, now_ms: number): void;
    registrationId(): number;
    removeKyberPreKey(id: number): void;
    removePreKey(id: number): void;
    removeSession(name: string, device_id: number): void;
    removeSignedPreKey(id: number): void;
    static restore(bytes: Uint8Array): SignalStore;
    serialize(): Uint8Array;
    signedPreKeyIds(): Uint32Array;
    trustIdentity(name: string, device_id: number, identity_key: Uint8Array): boolean;
}

/**
 * The sender identity key carried by a PreKey (type 3) message, without decrypting it.
 */
export function preKeyMessageIdentity(body: Uint8Array): Uint8Array;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly __wbg_encryptedmessage_free: (a: number, b: number) => void;
    readonly __wbg_get_encryptedmessage_body: (a: number) => [number, number];
    readonly __wbg_get_encryptedmessage_messageType: (a: number) => number;
    readonly __wbg_get_publicprekey_keyId: (a: number) => number;
    readonly __wbg_get_publicprekey_publicKey: (a: number) => [number, number];
    readonly __wbg_get_publicprekey_signature: (a: number) => [number, number];
    readonly __wbg_publicprekey_free: (a: number, b: number) => void;
    readonly __wbg_set_encryptedmessage_body: (a: number, b: number, c: number) => void;
    readonly __wbg_set_encryptedmessage_messageType: (a: number, b: number) => void;
    readonly __wbg_set_publicprekey_keyId: (a: number, b: number) => void;
    readonly __wbg_set_publicprekey_publicKey: (a: number, b: number, c: number) => void;
    readonly __wbg_set_publicprekey_signature: (a: number, b: number, c: number) => void;
    readonly __wbg_signalstore_free: (a: number, b: number) => void;
    readonly preKeyMessageIdentity: (a: number, b: number) => [number, number, number, number];
    readonly signalstore_decrypt: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => [number, number, number, number];
    readonly signalstore_encrypt: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => [number, number, number];
    readonly signalstore_fingerprint: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => [number, number, number, number];
    readonly signalstore_generate: () => number;
    readonly signalstore_generateKyberPreKey: (a: number, b: number, c: number) => [number, number, number];
    readonly signalstore_generatePreKey: (a: number, b: number) => [number, number, number];
    readonly signalstore_generateSignedPreKey: (a: number, b: number, c: number) => [number, number, number];
    readonly signalstore_hasSession: (a: number, b: number, c: number, d: number, e: number) => [number, number, number];
    readonly signalstore_identityKey: (a: number) => [number, number, number, number];
    readonly signalstore_isTrusted: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number, number];
    readonly signalstore_kyberPreKeyIds: (a: number) => [number, number];
    readonly signalstore_peerIdentity: (a: number, b: number, c: number, d: number) => [number, number, number, number];
    readonly signalstore_preKeyIds: (a: number) => [number, number];
    readonly signalstore_processPreKeyBundle: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number, l: number, m: number, n: number, o: number, p: number, q: number, r: number, s: number, t: number, u: number) => [number, number];
    readonly signalstore_registrationId: (a: number) => number;
    readonly signalstore_removeKyberPreKey: (a: number, b: number) => void;
    readonly signalstore_removePreKey: (a: number, b: number) => void;
    readonly signalstore_removeSession: (a: number, b: number, c: number, d: number) => [number, number];
    readonly signalstore_removeSignedPreKey: (a: number, b: number) => void;
    readonly signalstore_restore: (a: number, b: number) => [number, number, number];
    readonly signalstore_serialize: (a: number) => [number, number];
    readonly signalstore_signedPreKeyIds: (a: number) => [number, number];
    readonly signalstore_trustIdentity: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number, number];
    readonly __wbindgen_exn_store: (a: number) => void;
    readonly __externref_table_alloc: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
