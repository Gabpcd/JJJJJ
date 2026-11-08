import XCTest
@testable import JoleneCore

/// Libellés non juridiques du lot 2 (`Libelles/LibellesWeb.swift`, LOT2_PLAN §3 TL, hors HARD STOP).
/// L'égalité de chaque constante avec le texte du web, l'absence de marque juridique et la zone web
/// de chaque assemblage sont prouvées par la garde Node `tests/node/textes-juridiques-ios.node.mjs` ;
/// ce test assert les rendus assemblés (chacun repris mot pour mot de
/// `scripts/mobile/textes-web-ios-rendus.json`, ce que la garde vérifie). La forme des textes
/// (vide, gabarit, tutoiement, délai de contestation) est testée avec ceux de TextesWeb
/// (`TextesWebTests.tousLesTextes`).
final class LibellesWebTests: XCTestCase {
    func testCatalogueCompletEtClesUniques() {
        let catalogue = LibellesWeb.catalogue
        XCTAssertGreaterThanOrEqual(catalogue.count, 40)
        XCTAssertEqual(Set(catalogue.map(\.cle)).count, catalogue.count, "clé dupliquée dans le catalogue")
        XCTAssertTrue(catalogue.contains(EntreeTexteWeb(cle: "SignatureOtp.renvoyerCode",
                                                        texte: LibellesWeb.SignatureOtp.renvoyerCode)))
    }

    /// Relance de l'établissement (`DetailPresencesMission.tsx` l.120-123) : message serveur s'il
    /// existe (`??` : seul un message absent est remplacé), sinon le repli du web.
    func testMessageDeRelanceCommeLeWeb() {
        let presences = LibellesWeb.Presences.self
        XCTAssertEqual(presences.messageRelance(succes: true, message: nil, erreur: nil), "Établissement relancé.")
        XCTAssertEqual(presences.messageRelance(succes: true, message: "Relance envoyée.", erreur: nil), "Relance envoyée.")
        XCTAssertEqual(presences.messageRelance(succes: false, message: nil, erreur: "Déjà relancé."), "Déjà relancé.")
        XCTAssertEqual(presences.messageRelance(succes: false, message: nil, erreur: nil), "Relance impossible.")
        XCTAssertEqual(presences.relancer, "Relancer l'établissement")
    }

    /// Envoi du code (`SignerContratOtp.tsx` l.149-152, l.296-300), minuteur (l.109-110, l.305) et
    /// renvoi (l.335-339).
    func testEnvoiDuCodeMinuteurEtRenvoiCommeLeRenduWeb() {
        let otp = LibellesWeb.SignatureOtp.self
        XCTAssertEqual(otp.codeEnvoye(telephoneMasque: "06 •• •• •• 12", minutes: 10), "Code envoyé au 06 •• •• •• 12. Valide 10 min.")
        XCTAssertEqual(otp.codeEnvoyeAu(telephoneMasque: "06 •• •• •• 12"), "Code envoyé au 06 •• •• •• 12")
        XCTAssertEqual(otp.codeEnvoyeAu(telephoneMasque: nil), "Code envoyé au numéro masqué")
        XCTAssertEqual(otp.codeEnvoyeAu(telephoneMasque: ""), "Code envoyé au numéro masqué")
        // « (dernier envoi possible) » à 0 : formulation du web, signalée à Gabrielle (à 0, le
        // bouton de renvoi est désactivé avec l'infobulle du plafond).
        XCTAssertEqual(otp.smsRestants(n: 0), "(dernier envoi possible)")
        XCTAssertEqual(otp.smsRestants(n: 1), "(1 envoi restant)")
        XCTAssertEqual(otp.smsRestants(n: 2), "(2 envois restants)")
        XCTAssertEqual(otp.minuteur(secondesRestantes: 600), "10:00")
        XCTAssertEqual(otp.minuteur(secondesRestantes: 65), "01:05")
        XCTAssertEqual(otp.minuteur(secondesRestantes: 0), "Expiré")
        XCTAssertEqual(otp.erreurReseauEnvoi, "Erreur réseau. Réessayez.")
        XCTAssertEqual(otp.erreurReseauSignature, otp.erreurReseauEnvoi)
        XCTAssertEqual(otp.renvoi(otpExpire: true), "Recevoir un nouveau code")
        XCTAssertEqual(otp.renvoi(otpExpire: false), "Renvoyer le code")
        XCTAssertEqual(otp.infobulleRenvoi(nouvelEnvoiAutorise: false, smsRestants: 2), "Aucun nouvel envoi autorisé pour cette recette")
        XCTAssertEqual(otp.infobulleRenvoi(nouvelEnvoiAutorise: false, smsRestants: 0), otp.renvoiNonAutoriseRecette)
        XCTAssertEqual(otp.infobulleRenvoi(nouvelEnvoiAutorise: true, smsRestants: 0), "3 SMS max par 24h atteints")
        XCTAssertNil(otp.infobulleRenvoi(nouvelEnvoiAutorise: true, smsRestants: 1))
        XCTAssertNil(otp.infobulleRenvoi(nouvelEnvoiAutorise: true, smsRestants: nil))
    }

    /// Durée restante du compte à rebours (`Countdown72hSignature.tsx` l.49-51, l.72).
    func testDureeDuCompteAReboursCommeLeRenduWeb() {
        let rebours = LibellesWeb.CompteARebours.self
        XCTAssertEqual(rebours.duree(restantSecondes: 62 * 3600), "62h 00m 00s")
        XCTAssertEqual(rebours.duree(restantSecondes: 3661), "1h 01m 01s")
        XCTAssertEqual(rebours.duree(restantSecondes: 59), "0h 00m 59s")
    }

    /// En-tête de la page certificat (`CertificatSignaturePage.tsx` l.186).
    func testEnTeteDuCertificatCommeLeRenduWeb() {
        XCTAssertEqual(LibellesWeb.Certificat.contrat(numero: "CTR-2026-0001", id: "c-001"), "Contrat CTR-2026-0001")
        XCTAssertEqual(LibellesWeb.Certificat.contrat(numero: nil, id: "c-001"), "Contrat c-001")
        XCTAssertEqual(LibellesWeb.Certificat.contrat(numero: "", id: "c-001"), "Contrat c-001")
    }

    /// Page Présences (lot 2, T4a) : onglets, états vides, lignes et bloc de pointage, repris tels quels de
    /// `PresencesSoignant.tsx` et `BlocPointageMission.tsx` (égalité prouvée par la garde Node), tous au catalogue.
    func testLibellesDeLaPageDesPresencesAuCatalogue() {
        let liste = LibellesWeb.ListePresences.self, ligne = LibellesWeb.LignePresence.self, bloc = LibellesWeb.BlocPointage.self
        XCTAssertEqual([liste.ongletAVenir, liste.ongletActives, liste.ongletAujourdhui, liste.ongletHistorique],
                       ["À venir", "Actives", "Aujourd'hui", "Historique"])
        XCTAssertEqual(liste.titre, "Mes présences")
        XCTAssertEqual(liste.planningAConfirmer, "Planning détaillé à confirmer avec l’établissement", "apostrophe ’ du web")
        XCTAssertEqual(ligne.badgeValidee, "✅ Validée")
        XCTAssertEqual(ligne.badgeNonValidee, "⏳ Non validée")
        XCTAssertEqual(bloc.contratNonSigne, "Contrat non signé")
        XCTAssertEqual(bloc.contratDoitEtreSigne, "Le contrat doit être signé par les deux parties avant le premier pointage.")
        XCTAssertEqual(LibellesWeb.EspaceSoignant.mesDocuments, "Mes documents")
        XCTAssertEqual(LibellesWeb.EspaceSoignant.mesContrats, "Mes contrats")
        let cles = Set(LibellesWeb.catalogue.map(\.cle))
        for cle in ["ListePresences.titre", "ListePresences.ongletAVenir", "ListePresences.ongletActives",
                    "ListePresences.ongletAujourdhui", "ListePresences.ongletHistorique", "ListePresences.validee",
                    "ListePresences.videHistoriqueTitre", "LignePresence.releveReconstruit", "LignePresence.voirOuSignalerLitige",
                    "BlocPointage.contratNonSigne", "BlocPointage.tousTermines", "BlocPointage.voirLeContrat",
                    "EspaceSoignant.mesDocuments", "EspaceSoignant.mesContrats"] {
            XCTAssertTrue(cles.contains(cle), "\(cle) absent du catalogue")
        }
    }

    /// Liste des contrats (`ListeContrats.tsx`, T9a) : filtres (l.121), pastille de statut (l.163), états vides du
    /// soignant (l.128-145) et carte mobile (l.210-223).
    func testListeDesContratsCommeLeRenduWeb() {
        let liste = LibellesWeb.Contrats.self
        XCTAssertEqual(liste.titre, "Mes contrats")
        XCTAssertEqual(FiltreContrat.allCases.map(liste.libelleFiltre), ["Tous", "En attente", "Signés", "Annulés"])
        XCTAssertEqual(liste.libelleFiltre(.enAttenteSignatures), "En attente")
        XCTAssertEqual(liste.libelleFiltre(.annule), "Annulés")
        XCTAssertEqual(liste.badge(.signe), "✅ Signé")
        XCTAssertEqual(liste.badge(.enAttente), "⏳ En attente")
        XCTAssertEqual(liste.badge(.annule), "❌ Annulé")
        XCTAssertEqual(liste.titreVide(.enAttenteSignatures), "Aucun contrat en attente")
        XCTAssertEqual(liste.titreVide(.signeComplet), "Aucun contrat")
        XCTAssertEqual(liste.titreVide(.tous), liste.videTitre)
        XCTAssertEqual(liste.titreVide(.annule), liste.videTitre)
        XCTAssertEqual(liste.descriptionVide(.tous), "Vos contrats apparaîtront ici après avoir accepté une mission.")
        XCTAssertEqual(liste.descriptionVide(.annule), "Aucun contrat annulé.")
        XCTAssertEqual(liste.descriptionVide(.enAttenteSignatures), "Aucun contrat en attente de signature pour le moment.")
        XCTAssertEqual(liste.descriptionVide(.signeComplet), "Aucun contrat signé pour le moment.")
        XCTAssertEqual(liste.numero(nil), "—")
        XCTAssertEqual(liste.numero(""), "—")
        XCTAssertEqual(liste.numero("DEMO-0002"), "DEMO-0002")
        XCTAssertEqual(liste.mission(intitule: "Démonstration · Mission terminée 1"), "📋 Démonstration · Mission terminée 1")
        XCTAssertEqual(liste.mission(intitule: nil), "📋 —")
        XCTAssertEqual(liste.typeEtDate(type: "CDD", dateFormatee: "29/10/2026"), "CDD · Créé le 29/10/2026")
        XCTAssertEqual(liste.typeEtDate(type: nil, dateFormatee: "29/10/2026"), " · Créé le 29/10/2026")
        XCTAssertEqual(liste.action(aSigner: true), "✍️ Signer le contrat")
        XCTAssertEqual(liste.action(aSigner: false), "Voir le contrat")
        XCTAssertEqual(liste.indisponiblesTitre, "Contrats indisponibles")
        XCTAssertEqual(liste.chargementNAbouti, "Le chargement n'a pas abouti. Réessayez dans un instant.")
        XCTAssertEqual(liste.reessayer, "Réessayer")
    }

    /// Page du contrat (`ContratMission.tsx`, T9a) : en-tête (l.591-597), section Signatures (l.666-706), préparation
    /// du document (l.372-377, l.388), zone « Votre signature » (l.711), boutons (l.611, l.614), téléchargement (l.428).
    func testPageDuContratCommeLeRenduWeb() {
        let contrat = LibellesWeb.Contrat.self
        XCTAssertEqual(contrat.titre(numero: "DEMO-0001"), "Contrat DEMO-0001")
        XCTAssertEqual(contrat.titre(numero: nil), "Contrat ", "`Contrat {contrat.numero_contrat}` : rien après l'espace")
        XCTAssertEqual(contrat.statut(.signe), "Statut : ✅ Signé")
        XCTAssertEqual(contrat.statut(.annule), "Statut : ❌ Annulé")
        XCTAssertEqual(contrat.statut(.enAttente), "Statut : ⏳ En attente de signatures")
        XCTAssertEqual(contrat.ligneSignature(.etablissement, signee: true, dateFormatee: "29/10/2026 à 02:00"),
                       "Établissement : ✅ Signé le 29/10/2026 à 02:00")
        XCTAssertEqual(contrat.ligneSignature(.soignant, signee: false, dateFormatee: nil), "Soignant(e) : ⏳ En attente")
        XCTAssertEqual(contrat.ligneSignature(.soignant, signee: false, dateFormatee: "29/10/2026 à 02:00"), "Soignant(e) : ⏳ En attente")
        XCTAssertEqual(contrat.ligneSignature(.soignant, signee: true, dateFormatee: nil), "Soignant(e) : ✅ Signé")
        XCTAssertEqual(contrat.renduRefuse(messageServeur: nil),
                       "Le document contractuel final n’a pas pu être préparé. Réessayez avant de signer.")
        XCTAssertEqual(contrat.renduRefuse(messageServeur: ""), contrat.renduRefuse(messageServeur: nil), "`motifBrut ?` : vide = absent")
        XCTAssertEqual(contrat.renduRefuse(messageServeur: "Contrat introuvable."),
                       "Le document contractuel final n’a pas pu être préparé. Contrat introuvable. Réessayez avant de signer.")
        // `String(motifBrut).slice(0, 180)` : 180 unités UTF-16 au plus.
        let long = String(repeating: "é", count: 200)
        XCTAssertEqual(contrat.renduRefuse(messageServeur: long),
                       contrat.renduImpossible + " " + String(repeating: "é", count: 180) + " " + contrat.reessayerAvantDeSigner)
        XCTAssertEqual(contrat.renduIncomplet, "Le document contractuel final est encore incomplet. Réessayez avant de signer.")
        XCTAssertEqual(contrat.votreSignature, "Votre signature")
        XCTAssertEqual(contrat.signaturesTitre, "Signatures")
        XCTAssertEqual(contrat.telecharger, "Télécharger le contrat")
        XCTAssertEqual(contrat.imprimer, "Imprimer")
        XCTAssertEqual(contrat.introuvable, "Contrat introuvable")
        XCTAssertEqual(contrat.aucunTelechargeable, "Aucun contrat téléchargeable pour le moment.")
        XCTAssertEqual(contrat.formatDateHeure, "dd/MM/yyyy 'à' HH:mm")
        XCTAssertEqual(LibellesWeb.Certificat.formatDateHeure, "dd/MM/yyyy 'à' HH:mm:ss")
        XCTAssertEqual(LibellesWeb.Certificat.telechargerPdf, "Télécharger PDF")
    }

    /// `String(valeur).padStart(2, '0')` du web.
    func testDeuxChiffres() {
        XCTAssertEqual(LibellesWeb.deuxChiffres(0), "00")
        XCTAssertEqual(LibellesWeb.deuxChiffres(7), "07")
        XCTAssertEqual(LibellesWeb.deuxChiffres(42), "42")
    }
}
