import Foundation

/// Textes de la candidature du détail de mission (lot 1, T6b, `LOT1_PLAN.md` §3 T6b). Les libellés repris tels quels
/// sont dans `LibellesWeb.Candidature` (garde Node `textes-juridiques-ios`, au caractère près ; revue B8 m7) et les
/// phrases d'engagement dans `TextesWeb.Candidature` (HARD STOP n°4, reprises à l'identique). Ce fichier ne porte que
/// les textes que le web tutoie, vouvoyés (décision 9 : seule la personne change ; relus par
/// `CandidatureEcranTests.testTextesVouvoyesDuDetailDeMission`), les assemblages et deux textes opérationnels.
///
/// Les refus du serveur (Code du travail, plafond de 48 h, documents, conflit) sont affichés verbatim depuis l'issue
/// de la gateway, jamais écrits ici. Non portés au lot 1 : la modale « Mission bloquée par le Code du Travail » et
/// l'attestation hebdomadaire des propositions (`CarteProposition.tsx`, renvoi web : `CandidatureEcran.propositionWeb`).
public enum LibellesCandidature {
    private typealias Web = LibellesWeb.Candidature

    public static let postuler = Web.postuler
    public static let postulerEnCours = Web.postulerEnCours
    public static let accepter = Web.accepter
    public static let accepterEnCours = Web.accepterEnCours
    public static let messageLibelle = Web.messageLibelle
    // source: src/pages/DetailMissionSoignant.tsx:1344 (vouvoyé : « Présente-toi »)
    public static let messagePlaceholder = "Présentez-vous brièvement…"
    /// `maxLength={300}` et `.slice(0, 300)` du web (l.1343-1347).
    public static let messageLongueurMax = 300
    // source: src/pages/DetailMissionSoignant.tsx:1359 (vouvoyé : « ta candidature. Tu seras »)
    public static let postulerAide = "L'établissement examinera votre candidature. Vous serez notifié(e) de sa décision."
    public static let envoyee = Web.envoyee
    // source: src/pages/DetailMissionSoignant.tsx:1392 (vouvoyé : « valide tes », « t'accepter »)
    public static let envoyeeDocuments = "Prochaine étape : validez vos documents pour que l'établissement puisse vous accepter."
    public static let validerDocuments = Web.validerDocuments
    // source: src/pages/DetailMissionSoignant.tsx:1399 (vouvoyé : « ton profil », « vers toi »)
    public static let envoyeeProfil = "L'établissement examinera votre profil et reviendra vers vous."
    // source: src/pages/DetailMissionSoignant.tsx:1409 (vouvoyé : « Tu es »)
    public static let assignee = "✅ Vous êtes assigné(e) à cette mission"
    public static let dejaAttribuee = Web.dejaAttribuee
    public static let voirAutresMissions = Web.voirAutresMissions
    public static let completerProfil = Web.completerProfil
    public static let recapEnvoyer = Web.recapEnvoyer
    public static let recapAccepter = Web.recapAccepter
    // source: src/components/planning/RecapitulatifCandidatureDialog.tsx:43 (vouvoyé : « Vérifie ton »)
    public static let recapTitre = "Vérifiez votre engagement"
    public static let recapAnnuler = Web.recapAnnuler
    public static let choixTitre = Web.choixTitre
    public static let choixDescription = Web.choixDescription
    public static let choixConfirmer = Web.choixConfirmer
    public static let propositionAccepter = Web.propositionAccepter
    public static let propositionRefuser = Web.propositionRefuser
    public static let propositionRefuseeTitre = Web.propositionRefuseeTitre
    public static let propositionRefuseeTexte = Web.propositionRefuseeTexte
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

    /// Phrase d'engagement du récapitulatif (`RecapitulatifCandidatureDialog.tsx` l.52-54, verbatim) : candidature
    /// retirable pour POSTULER (`retraitPossible`), acceptation immédiate pour ACCEPTER et PROPOSITION
    /// (`CarteProposition.tsx` l.391 : `retraitPossible={false}`). Affichée seulement quand le planning est exact.
    /// L4-T3b : le ❤️ du swipe (SWIPE_LIKE) pose une candidature retirable, comme POSTULER (`VueSwipeMissions.tsx`
    /// monte le récapitulatif sans `retraitPossible`, donc à sa valeur par défaut `true`).
    public static func recapEngagement(_ action: ActionPlanning) -> String {
        action == .postuler || action == .swipeLike
            ? TextesWeb.Candidature.engagementCandidature : TextesWeb.Candidature.engagementAcceptation
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
