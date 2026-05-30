import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'app.jolene',
  appName: 'Jolene',
  webDir: 'dist',
  server: {
    androidScheme: 'https',
    // Pour le dev local, décommenter la ligne suivante :
    // url: 'http://localhost:8080',
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1500,
      launchAutoHide: false, // We hide manually after session check
      backgroundColor: '#FFFFFF',
      showSpinner: false,
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#FFFFFF',
    },
    Keyboard: {
      resize: 'native',
      scrollAssist: true,
    },
  },
  ios: {
    contentInset: 'automatic',
  },
  android: {
    backgroundColor: '#FFFFFF',
  },
};

export default config;
