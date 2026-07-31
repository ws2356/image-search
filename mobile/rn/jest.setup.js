jest.mock('react-native-quick-crypto', () => {
  const { Buffer } = require('node:buffer');
  const { webcrypto } = require('node:crypto');
  const crypto = require('node:crypto');
  return {
    default: {
      Buffer,
      randomBytes: crypto.randomBytes,
      createHash: crypto.createHash,
      createCipheriv: crypto.createCipheriv,
      createDecipheriv: crypto.createDecipheriv,
      getRandomValues: webcrypto.getRandomValues.bind(webcrypto),
    },
  };
});
