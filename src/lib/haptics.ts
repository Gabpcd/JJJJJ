import { isNative } from './platform';

type ImpactStyle = 'light' | 'medium' | 'heavy';

/**
 * Trigger haptic feedback on native platforms.
 * No-op on web.
 */
export async function hapticImpact(style: ImpactStyle = 'light'): Promise<void> {
  if (!isNative()) return;
  try {
    const { Haptics, ImpactStyle } = await import('@capacitor/haptics');
    const styleMap: Record<string, any> = {
      light: ImpactStyle.Light,
      medium: ImpactStyle.Medium,
      heavy: ImpactStyle.Heavy,
    };
    await Haptics.impact({ style: styleMap[style] });
  } catch {
    // Plugin not available
  }
}

export async function hapticNotification(type: 'success' | 'warning' | 'error' = 'success'): Promise<void> {
  if (!isNative()) return;
  try {
    const { Haptics, NotificationType } = await import('@capacitor/haptics');
    const typeMap: Record<string, any> = {
      success: NotificationType.Success,
      warning: NotificationType.Warning,
      error: NotificationType.Error,
    };
    await Haptics.notification({ type: typeMap[type] });
  } catch {
    // Plugin not available
  }
}
