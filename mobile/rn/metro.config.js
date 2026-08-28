const { getDefaultConfig } = require("expo/metro-config");
const { withNativewind } = require("nativewind/metro");

/** @type {import('expo/metro-config').MetroConfig} */
const config = getDefaultConfig(__dirname);

const nativewindConfig = withNativewind(config, {
  // We add className support manually via useCssElement wrappers
  globalClassNamePolyfill: false,
});

module.exports = nativewindConfig;
