const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const config = getDefaultConfig(__dirname);
// Only pure business helpers and generated database types are shared with web.
config.watchFolders = [path.resolve(__dirname, '..')];
// Resolve React and native packages from this client, never web's React 18.
config.resolver.nodeModulesPaths = [path.resolve(__dirname, 'node_modules')];
// Keep nested Expo dependencies resolvable, while excluding the web install.
const webModules = path.resolve(__dirname, '../node_modules').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
config.resolver.blockList = [new RegExp(`^${webModules}/.*`)];
config.resolver.extraNodeModules = {
  react: path.resolve(__dirname, 'node_modules/react'),
  'react-native': path.resolve(__dirname, 'node_modules/react-native'),
};
module.exports = config;
