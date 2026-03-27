import { isNative, isIOS } from './platform';
import { logger } from './logger';

const BIOMETRIC_TOKEN_KEY = 'jolene_bio_refresh_token';
const BIOMETRIC_ENABLED_KEY = 'jolene_bio_enabled';

/**
 * Check if biometric authentication is available on the device.
 */
export async function isBiometricAvailable(): Promise<boolean> {
  if (!isNative()) return false;
  try {
    const { NativeBiometric } = await import('@capgo/capacitor-native-biometric');
    const result = await NativeBiometric.isAvailable();
    return result.isAvailable;
  } catch {
    return false;
  }
}

/**
 * Get biometric type label in French.
 */
export function getBiometricLabel(): string {
  if (isIOS()) return 'Face ID / Touch ID';
  return "l'empreinte digitale";
}

/**
 * Check if the user has enabled biometric login.
 */
export function isBiometricEnabled(): boolean {
  return localStorage.getItem(BIOMETRIC_ENABLED_KEY) === 'true';
}

/**
 * Save credentials securely for biometric login.
 */
export async function enableBiometric(refreshToken: string): Promise<boolean> {
  if (!isNative()) return false;
  try {
    const { NativeBiometric } = await import('@capgo/capacitor-native-biometric');
    await NativeBiometric.setCredentials({
      username: 'jolene-session',
      password: refreshToken,
      server: 'app.jolene.app',
    });
    localStorage.setItem(BIOMETRIC_ENABLED_KEY, 'true');
    return true;
  } catch (e) {
    logger.error('[BIOMETRIC] Failed to save credentials:', e);
    return false;
  }
}

/**
 * Disable biometric login and clear stored credentials.
 */
export async function disableBiometric(): Promise<void> {
  localStorage.removeItem(BIOMETRIC_ENABLED_KEY);
  if (!isNative()) return;
  try {
    const { NativeBiometric } = await import('@capgo/capacitor-native-biometric');
    await NativeBiometric.deleteCredentials({ server: 'app.jolene.app' });
  } catch {
    // Ignore
  }
}

/**
 * Attempt biometric login: verify identity then return stored refresh token.
 */
export async function authenticateWithBiometric(): Promise<string | null> {
  if (!isNative()) return null;
  try {
    const { NativeBiometric } = await import('@capgo/capacitor-native-biometric');

    // Verify identity
    await NativeBiometric.verifyIdentity({
      reason: 'Connexion à Jolene',
      title: 'Authentification biométrique',
      subtitle: 'Connectez-vous avec votre empreinte ou visage',
    });

    // Get stored credentials
    const credentials = await NativeBiometric.getCredentials({
      server: 'app.jolene.app',
    });

    return credentials.password || null;
  } catch (e) {
    logger.error('[BIOMETRIC] Auth failed:', e);
    return null;
  }
}
