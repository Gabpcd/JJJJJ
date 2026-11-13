import JoleneCore

/// Magasin des reçus d'envoi des justificatifs (`ReceiptJournal<RecuDocument>`, domaine `document`, décision 14).
///
/// Point d'extension de T7, câblé par T4b : le magasin de l'`Appareil` d'`AppContainer` (un seul par processus, partagé
/// par le pointage et les justificatifs, une clé par domaine) : en démo un magasin en mémoire pour tout le processus (un
/// envoi en vol survit à la fermeture de l'écran, comme le registre `EssaisDocumentsEnVol`), sinon le trousseau
/// (`KeychainReceiptStore`, service `app.jolene.receipts`). Aucun autre changement d'appelant.
extension AppContainer {
    var recusJustificatifs: any ReceiptStorePort {
        appareil.recus
    }
}
