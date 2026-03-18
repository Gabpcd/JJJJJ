import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.jolene.app',
  appName: 'Jolene',
  webDir: 'dist',
  server: {
    androidScheme: 'https',
  },
  plugins: {
    StatusBar: {
      style: 'dark',
      backgroundColor: '#0F172A',
    },
  },
};

export default config;
