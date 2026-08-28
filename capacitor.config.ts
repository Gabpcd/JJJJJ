import type { CapacitorConfig } from '@capacitor/cli';
import { KeyboardResize } from '@capacitor/keyboard';

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
      // Aucun écran de splash applicatif : iOS/Android montrent uniquement le
      // fond natif uni, puis l'interface dès qu'elle est prête.
      launchShowDuration: 0,
      launchAutoHide: true,
      launchFadeOutDuration: 0,
      backgroundColor: '#FFFFFF',
      showSpinner: false,
    },
    StatusBar: {
      // Capacitor nomme le style d'après le fond : LIGHT = texte sombre.
      style: 'LIGHT',
      backgroundColor: '#FFFFFF',
    },
    Keyboard: {
      // Une seule source de redimensionnement : le WebView natif. Le scroll
      // du champ actif reste géré par iOS, sans assistance JS concurrente.
      resize: KeyboardResize.Native,
    },
    PushNotifications: {
      // Affichage cohérent au premier plan sur iOS ; Android s'appuie sur
      // les NotificationChannel déclarés dans MainActivity.
      presentationOptions: ['badge', 'sound', 'banner', 'list'],
    },
  },
  ios: {
    // AuthLayout applique déjà env(safe-area-inset-*). Le réglage automatique
    // d'UIScrollView les ajoutait une seconde fois sur les iPhone Dynamic Island.
    contentInset: 'never',
  },
  android: {
    backgroundColor: '#FFFFFF',
  },
};

export default config;
