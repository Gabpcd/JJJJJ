import Foundation

/// Textes de la candidature du détail de mission (lot 1, T6b, `LOT1_PLAN.md` §3 T6b). Repris du web
/// (`DetailMissionSoignant.tsx`, `RecapitulatifCandidatureDialog.tsx`, `ChoixContratDialog.tsx`,
/// `CarteProposition.tsx`) ; les textes que le web tutoie sont vouvoyés (décision 9 : seule la personne change).
/// `LibellesCandidatureTests` relit `DetailMissionSoignant.tsx` pour les textes de cette page.
///
/// Aucun texte juridique ni à portée contractuelle (HARD STOP n°4) : les refus du serveur (Code du travail,
/// plafond de 48 h, documents, conflit) sont affichés verbatim depuis l'issue de la gateway, jamais écrits ici.
/// Non portés au lot 1, faute de validation : les phrases d'engagement du récapitulatif (« En confirmant, tu
/// t'engages… », « tu acceptes immédiatement tous ces créneaux… »), la mention sous « Accepter » (« En acceptant,
/// tu t'engages à être présent(e)… »), la modale « Mission bloquée par le Code du Travail » et l'attestation
/// hebdomadaire des propositions (`CarteProposition.tsx`, renvoi web : `CandidatureEcran.propositionWeb`).
public enum LibellesCandidature {
    // source: src/pages/DetailMissionSoignant.tsx:1356
    public static let postuler = "📨 Vérifier et postuler"
    // source: src/pages/DetailMissionSoignant.tsx:1356
    public static let postulerEnCours = "Envoi en cours…"
    // source: src/pages/DetailMissionSoignant.tsx:1370
    public static let accepter = "★ Accepter cette mission"
    // source: src/pages/DetailMissionSoignant.tsx:1370
    public static let accepterEnCours = "Acceptation en cours…"
    // source: src/pages/DetailMissionSoignant.tsx:1340
    public static let messageLibelle = "Message à l'établissement (optionnel)"
    // source: src/pages/DetailMissionSoignant.tsx:1344 (vouvoyé : « Présente-toi »)
    public static let messagePlaceholder = "Présentez-vous brièvement…"
    /// `maxLength={300}` et `.slice(0, 300)` du web (l.1343-1347).
    public static let messageLongueurMax = 300
    // source: src/pages/DetailMissionSoignant.tsx:1359 (vouvoyé : « ta candidature. Tu seras »)
    public static let postulerAide = "L'établissement examinera votre candidature. Vous serez notifié(e) de sa décision."
    // source: src/pages/DetailMissionSoignant.tsx:1386
    public static let envoyee = "✅ Candidature envoyée — En attente de réponse"
    // source: src/pages/DetailMissionSoignant.tsx:1392 (vouvoyé : « valide tes », « t'accepter »)
    public static let envoyeeDocuments = "Prochaine étape : validez vos documents pour que l'établissement puisse vous accepter."
    // source: src/pages/DetailMissionSoignant.tsx:1399 (vouvoyé : « ton profil », « vers toi »)
    public static let envoyeeProfil = "L'établissement examinera votre profil et reviendra vers vous."
    // source: src/pages/DetailMissionSoignant.tsx:1409 (vouvoyé : « Tu es »)
    public static let assignee = "✅ Vous êtes assigné(e) à cette mission"
    // source: src/pages/DetailMissionSoignant.tsx:1542
    public static let dejaAttribuee = "Cette mission a déjà été attribuée"
    // source: src/pages/DetailMissionSoignant.tsx:1544
    public static let voirAutresMissions = "Voir d'autres missions →"
    // source: src/pages/DetailMissionSoignant.tsx:1331
    public static let completerProfil = "Compléter mon profil pour postuler"
    // source: src/pages/DetailMissionSoignant.tsx:1625
    public static let recapEnvoyer = "Envoyer ma candidature"
    // source: src/pages/DetailMissionSoignant.tsx:1625
    public static let recapAccepter = "Accepter tous ces créneaux"
    // source: src/components/planning/RecapitulatifCandidatureDialog.tsx:43 (vouvoyé : « Vérifie ton »)
    public static let recapTitre = "Vérifiez votre engagement"
    // source: src/components/planning/RecapitulatifCandidatureDialog.tsx:59
    public static let recapAnnuler = "Annuler"
    // source: src/components/ChoixContratDialog.tsx:44
    public static let choixTitre = "Choisissez votre mode de contrat"
    // source: src/components/ChoixContratDialog.tsx:46
    public static let choixDescription = "Cette mission accepte les deux types de contrat. Sélectionnez celui qui correspond à votre situation."
    // source: src/components/ChoixContratDialog.tsx:85
    public static let choixConfirmer = "Confirmer"
    // source: src/components/CarteProposition.tsx:347
    public static let propositionAccepter = "✅ Accepter"
    // source: src/components/CarteProposition.tsx:350
    public static let propositionRefuser = "❌ Refuser"
    // source: src/components/CarteProposition.tsx:309
    public static let propositionRefuseeTitre = "Mission déclinée"
    // source: src/components/CarteProposition.tsx:309
    public static let propositionRefuseeTexte = "La proposition a été refusée."
    /// Texte opérationnel hors web (T6b) : la proposition d'un contrat salarié exige l'attestation hebdomadaire
    /// des heures externes (`CarteProposition.tsx` l.154-256, HARD STOP n°4), non portée au lot 1 : réponse sur
    /// jolene.app, refus natif.
    public static let propositionWeb = "Pour accepter cette proposition, répondez depuis votre tableau de bord sur jolene.app."
    /// Libellé du bouton du renvoi (texte opérationnel, même forme que les autres renvois du natif).
    public static let propositionWebAction = "Répondre sur jolene.app"

    /// « {intitulé} — confirmez uniquement si vous pouvez assurer tous les créneaux ci-dessous. »
    /// (`RecapitulatifCandidatureDialog.tsx` l.45, vouvoyé : « confirme », « tu peux » ; intitulé absent → « Mission »).
    public static func recapDescription(intitule: String?) -> String {
        let titre = (intitule ?? "").isEmpty ? "Mission" : intitule ?? ""
        return titre + " — confirmez uniquement si vous pouvez assurer tous les créneaux ci-dessous."
    }

    /// « Il manque N information(s) pour pouvoir postuler : » (l.1319).
    public static func manquants(_ nombre: Int) -> String {
        "Il manque " + String(nombre) + " information" + (nombre > 1 ? "s" : "") + " pour pouvoir postuler :"
    }

    /// Compteur « n/300 » du message (l.1349).
    public static func compteur(_ message: String) -> String {
        String(message.count) + "/" + String(messageLongueurMax)
    }
}
