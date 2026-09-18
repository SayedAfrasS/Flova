/**
 * WORKFLOW OF THIS FILE:
 * 1. SessionCrypto manages one secure session between the laptop and phone.
 * 2. On construction it generates an X25519 keypair using tweetnacl.
 * 3. The public key is exchanged in plaintext inside hello/hello-ack.
 * 4. deriveKey() performs X25519 Diffie-Hellman to produce a shared 32-byte
 *    secret that is identical on both devices.
 * 5. encrypt() wraps plaintext in ChaCha20-Poly1305, producing a 12-byte
 *    nonce plus ciphertext concatenated with a 16-byte auth tag.
 * 6. decrypt() reverses the process and throws when the auth tag fails,
 *    meaning the frame was tampered with or the session key is wrong.
 * 7. fingerprint() returns the first 4 bytes of the shared secret as an
 *    8-character uppercase hex string shown on both home screens so the
 *    user can visually verify the session matches on both devices.
 *
 * FUNCTIONS:
 *  - constructor()    : generates a fresh X25519 keypair.
 *  - getPublicKey()   : returns the 32-byte public key to share with the peer.
 *  - deriveKey()      : performs DH with the peer's public key, stores the
 *                       shared secret.
 *  - hasKey()         : true once deriveKey has run successfully.
 *  - encrypt()        : ChaCha20-Poly1305 AEAD encrypt.
 *  - decrypt()        : ChaCha20-Poly1305 AEAD decrypt with auth verification.
 *  - fingerprint()    : 8-char hex fingerprint of the shared secret.
 */
import * as nacl from 'tweetnacl'
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto'

export class SessionCrypto {
  private keyPair: nacl.BoxKeyPair
  private sessionKey: Buffer | null = null

  constructor() {
    this.keyPair = nacl.box.keyPair()
  }

  getPublicKey(): Buffer {
    return Buffer.from(this.keyPair.publicKey)
  }

  deriveKey(peerPublicKey: Buffer): void {
    const shared = nacl.scalarMult(
      this.keyPair.secretKey,
      new Uint8Array(peerPublicKey)
    )
    this.sessionKey = Buffer.from(shared)
  }

  hasKey(): boolean {
    return this.sessionKey !== null
  }

  encrypt(plaintext: Buffer): { nonce: Buffer; ciphertext: Buffer } {
    if (!this.sessionKey) throw new Error('session key not derived')
    const nonce = randomBytes(12)
    const cipher = createCipheriv(
      'chacha20-poly1305',
      this.sessionKey,
      nonce,
      { authTagLength: 16 }
    )
    const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()])
    const tag = cipher.getAuthTag()
    return { nonce, ciphertext: Buffer.concat([encrypted, tag]) }
  }

  decrypt(nonce: Buffer, ciphertextWithTag: Buffer): Buffer {
    if (!this.sessionKey) throw new Error('session key not derived')
    if (ciphertextWithTag.length < 16) throw new Error('ciphertext too short')
    const ciphertext = ciphertextWithTag.subarray(0, ciphertextWithTag.length - 16)
    const tag = ciphertextWithTag.subarray(ciphertextWithTag.length - 16)
    const decipher = createDecipheriv(
      'chacha20-poly1305',
      this.sessionKey,
      nonce,
      { authTagLength: 16 }
    )
    decipher.setAuthTag(tag)
    return Buffer.concat([decipher.update(ciphertext), decipher.final()])
  }

  fingerprint(): string {
    if (!this.sessionKey) return '----'
    return this.sessionKey.subarray(0, 4).toString('hex').toUpperCase()
  }
}