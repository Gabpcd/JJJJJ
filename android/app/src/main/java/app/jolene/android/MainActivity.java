package app.jolene.android;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.media.AudioAttributes;
import android.os.Bundle;
import android.provider.Settings;
import com.getcapacitor.BridgeActivity;

/**
 * MainActivity Jolene — Sprint 4 PR 7.
 *
 * Déclare les notification channels Android 8+ (requis depuis API 26).
 * Le FCM payload depuis send-push (PR 1 Sprint 4) cible ces channels via
 * le helper channelForType côté Deno.
 *
 * Sans cette déclaration, les notifications Android n'apparaîtraient
 * dans aucun groupe (default channel système) et l'utilisateur ne
 * pourrait pas configurer leur priorité dans Paramètres → Notifications.
 */
public class MainActivity extends BridgeActivity {

  private static final String CHANNEL_URGENCE = "jolene_urgence";
  private static final String CHANNEL_INFO = "jolene_info";
  private static final String CHANNEL_PAIEMENT = "jolene_paiement";
  private static final String CHANNEL_MESSAGERIE = "jolene_messagerie";
  private static final String CHANNEL_SIGNATURE = "jolene_signature";
  private static final String CHANNEL_POINTAGE = "jolene_pointage";

  @Override
  public void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    creerNotificationChannels();
  }

  private void creerNotificationChannels() {
    NotificationManager manager =
        (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
    if (manager == null) return;

    AudioAttributes audioAttrs = new AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build();

    // 1. Urgences — mission ASAP, pool urgence — IMPORTANCE_HIGH
    NotificationChannel urgence = new NotificationChannel(
        CHANNEL_URGENCE, "Urgences mission", NotificationManager.IMPORTANCE_HIGH);
    urgence.setDescription("Missions ASAP, pool urgence, demandes immédiates");
    urgence.enableVibration(true);
    urgence.setVibrationPattern(new long[]{0, 250, 250, 250});
    urgence.setShowBadge(true);
    urgence.setSound(
        Settings.System.DEFAULT_NOTIFICATION_URI,
        audioAttrs);
    manager.createNotificationChannel(urgence);

    // 2. Info — notifications générales — IMPORTANCE_DEFAULT
    NotificationChannel info = new NotificationChannel(
        CHANNEL_INFO, "Informations", NotificationManager.IMPORTANCE_DEFAULT);
    info.setDescription("Notifications générales (candidature, mission, etc.)");
    info.enableVibration(true);
    info.setShowBadge(true);
    manager.createNotificationChannel(info);

    // 3. Paiement — IMPORTANCE_DEFAULT avec badge
    NotificationChannel paiement = new NotificationChannel(
        CHANNEL_PAIEMENT, "Paiements & factures", NotificationManager.IMPORTANCE_DEFAULT);
    paiement.setDescription("Factures émises, paiements reçus, avoirs");
    paiement.setShowBadge(true);
    manager.createNotificationChannel(paiement);

    // 4. Messagerie — IMPORTANCE_HIGH son léger
    NotificationChannel messagerie = new NotificationChannel(
        CHANNEL_MESSAGERIE, "Messagerie & litiges", NotificationManager.IMPORTANCE_HIGH);
    messagerie.setDescription("Nouveaux messages, conversations litiges");
    messagerie.enableVibration(true);
    messagerie.setVibrationPattern(new long[]{0, 150});
    messagerie.setShowBadge(true);
    manager.createNotificationChannel(messagerie);

    // 5. Signature — contrats à signer, signature reçue — IMPORTANCE_HIGH
    NotificationChannel signature = new NotificationChannel(
        CHANNEL_SIGNATURE, "Signature contrats", NotificationManager.IMPORTANCE_HIGH);
    signature.setDescription("Contrats à signer, signatures reçues");
    signature.enableVibration(true);
    signature.setVibrationPattern(new long[]{0, 200, 100, 200});
    signature.setShowBadge(true);
    manager.createNotificationChannel(signature);

    // 6. Pointage & DPAE — rappels pointage, DPAE — IMPORTANCE_DEFAULT
    NotificationChannel pointage = new NotificationChannel(
        CHANNEL_POINTAGE, "Pointage & DPAE", NotificationManager.IMPORTANCE_DEFAULT);
    pointage.setDescription("Rappels pointage, déclarations DPAE");
    pointage.enableVibration(true);
    pointage.setShowBadge(false);
    manager.createNotificationChannel(pointage);
  }
}
