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
      // Le splash ne doit jamais rester au-dessus d'une interface déjà prête.
      // Le scénario précédent créait un carré rose semi-transparent sur iOS.
      launchShowDuration: 0,
      launchAutoHide: false,
      launchFadeOutDuration: 120,
      backgroundColor: '#FFFFFF',
      showSpinner: false,
    },
    StatusBar: {
      // Capacitor nomme le style d'après le fond : LIGHT = texte sombre.
      style: 'LIGHT',
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
