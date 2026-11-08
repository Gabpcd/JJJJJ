import JoleneCore
import JoleneSupabase

/// Magasin des reçus d'envoi des justificatifs (`ReceiptJournal<RecuDocument>`, domaine `document`, décision 14).
///
/// Point d'extension (lot 2 T7) : `AppContainer` n'expose pas encore `Appareil` (posé par T4b avec le GPS, le réseau et
/// l'identifiant terminal). D'ici là, le monde démo partage un magasin en mémoire pour tout le processus (un envoi en vol
/// survit à la fermeture de l'écran, comme le registre `EssaisDocumentsEnVol`) ; Staging et Production lisent le trousseau
/// (`KeychainReceiptStore`, service `app.jolene.receipts`, sans état propre). À l'intégration de T4b, cette propriété
/// devient `appareil.recus`, sans autre changement d'appelant.
extension AppContainer {
    private static let recusDemo = MagasinRecusEnMemoire()

    var recusJustificatifs: any ReceiptStorePort {
        isDemo ? Self.recusDemo : KeychainReceiptStore()
    }
}
