import 'dart:js_interop';

@JS()
external void eval(String code);

@JS('setupNostrExtensionAsync')
external JSPromise<JSAny?> _setupNostrExtensionAsync();

Future<void> setupNostrExtension() async {
  await _setupNostrExtensionAsync().toDart;
}

const extensionPrivateKey =
    '0a47414ecfcdda1fe8374ec28629883cdd95287e353b3fd1a536c03d953f6cc2';

void injectSetupCode() {
  eval('''
    window.setupNostrExtensionAsync = async function() {
      const nostrTools = await import('https://esm.sh/nostr-tools@2.23.0');
      const { nip04, nip44, getPublicKey, finalizeEvent } = nostrTools;

      const privateKeyHex = '$extensionPrivateKey';

      function hexToBytes(hex) {
        const bytes = new Uint8Array(hex.length / 2);
        for (let i = 0; i < hex.length; i += 2) {
          bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
        }
        return bytes;
      }

      const privateKeyBytes = hexToBytes(privateKeyHex);
      const publicKeyHex = getPublicKey(privateKeyBytes);

      window.nostr = {
        _privkey: privateKeyBytes,
        _privkeyHex: privateKeyHex,
        _pubkey: publicKeyHex,
        _hang: false,
        _held: [],
        _stripClientTag: false,

        setHang: function(hang) {
          this._hang = hang;
        },

        release: function() {
          const held = this._held;
          this._held = [];
          held.forEach(function(answer) { answer(); });
        },

        _wait: function() {
          if (!this._hang) {
            return Promise.resolve();
          }
          const held = this._held;
          return new Promise(function(answer) { held.push(answer); });
        },

        setStripClientTag: function(strip) {
          this._stripClientTag = strip;
        },

        setAccount: function(privkeyHex) {
          this._privkeyHex = privkeyHex;
          this._privkey = hexToBytes(privkeyHex);
          this._pubkey = getPublicKey(this._privkey);
        },

        getPublicKey: async function() {
          await this._wait();
          return this._pubkey;
        },

        signEvent: async function(event) {
          await this._wait();
          const tags = this._stripClientTag
            ? event.tags.filter(function(tag) { return tag[0] !== 'client'; })
            : event.tags;
          const eventToSign = {
            kind: event.kind,
            created_at: event.created_at,
            tags: tags,
            content: event.content,
            pubkey: event.pubkey,
          };
          return finalizeEvent(eventToSign, this._privkey);
        },

        nip04: {
          encrypt: async function(recipientPubkey, plaintext) {
            return nip04.encrypt(window.nostr._privkeyHex, recipientPubkey, plaintext);
          },

          decrypt: async function(senderPubkey, ciphertext) {
            return nip04.decrypt(window.nostr._privkeyHex, senderPubkey, ciphertext);
          }
        },

        nip44: {
          encrypt: async function(recipientPubkey, plaintext) {
            const conversationKey = nip44.v2.utils.getConversationKey(window.nostr._privkey, recipientPubkey);
            return nip44.v2.encrypt(plaintext, conversationKey);
          },

          decrypt: async function(senderPubkey, ciphertext) {
            const conversationKey = nip44.v2.utils.getConversationKey(window.nostr._privkey, senderPubkey);
            return nip44.v2.decrypt(ciphertext, conversationKey);
          }
        }
      };
    };
  ''');
}
