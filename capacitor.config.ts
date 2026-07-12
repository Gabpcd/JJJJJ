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
      launchShowDuration: 1800,
      // Filet natif si le bundle JS ne démarre pas ; le code masque aussi le
      // splash plus tôt dès que la session locale est prête.
      launchAutoHide: true,
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
    PushNotifications: {
      // Affichage cohérent au premier plan sur iOS ; Android s'appuie sur
      // les NotificationChannel déclarés dans MainActivity.
      presentationOptions: ['badge', 'sound', 'banner', 'list'],
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
