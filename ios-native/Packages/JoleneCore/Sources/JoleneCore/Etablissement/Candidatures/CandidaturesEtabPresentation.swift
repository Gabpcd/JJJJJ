import Foundation

/// Textes et mise en forme de l'écran des candidatures d'une mission (lot 5, T6). Libellés d'interface repris du web
/// (`src/components/ListeCandidatures.tsx`, annotés `// source:`, non juridiques) et quelques textes natifs de
/// navigation, sans qualification juridique. Les refus du serveur (`[CODE DU TRAVAIL]`, cadre étudiant, paiement,
/// planning) ne sont jamais écrits ici : ils viennent verbatim de l'issue de la gateway.
///
/// **HARD STOP n°4, non affiché** : la mention CGV art. 8 du web (l.390-398) est verbatim dans
/// `TextesWeb.CandidaturesEtablissement`, verrouillée jusqu'à la validation d'écran de Gabrielle
/// (`contrats-etablissement-ios.node.mjs`, liste `VALIDES` vide). D'ici là, l'écran ne montre qu'un lien de navigation
/// neutre vers la page des CGV (`cgvLienNeutre`), sans en résumer le contenu. Non portés (D10) : badges « hors
/// profession », statuts d'internat, case du cadre étudiant, régime d'exercice du profil, notes.
public enum CandidaturesEtabPresentation {
    // MARK: - Libellés repris du web (non juridiques)

    public static let titreEcran = "Candidatures"
    // source: src/components/ListeCandidatures.tsx:333
    public static let chargement = "Chargement des candidatures…"
    // source: src/components/ListeCandidatures.tsx:340
    public static let titreErreur = "Impossible de charger les candidatures"
    // source: src/components/ListeCandidatures.tsx:344
    public static let reessayer = "Réessayer"
    // source: src/components/ListeCandidatures.tsx:355
    public static let videTitre = "En attente de candidats"
    // source: src/components/ListeCandidatures.tsx:356
    public static let videMessage = "Les soignants qualifiés peuvent postuler à cette mission. Vérifiez que les critères (profession, taux, dates) sont cohérents avec le marché."
    // source: src/components/ListeCandidatures.tsx:495
    public static let accepter = "Accepter"
    // source: src/components/ListeCandidatures.tsx:506
    public static let refuser = "Refuser"
    // source: src/components/ListeCandidatures.tsx:524
    public static let statutAcceptee = "✅ Acceptée"
    // source: src/components/ListeCandidatures.tsx:524
    public static let statutRefusee = "❌ Refusée"
    // source: src/components/ListeCandidatures.tsx:419
    public static let badgeEtudiant = "🎓 Étudiant"
    // source: src/components/ListeCandidatures.tsx:451
    public static let badgeDocumentsValides = "✅ Documents validés"
    // source: src/components/ListeCandidatures.tsx:455
    public static let badgeDocumentsEnVerification = "📄 Documents en vérification"
    // source: src/components/ListeCandidatures.tsx:464
    public static let badgePasEvaluation = "Pas encore d'évaluation"
    // source: src/components/ListeCandidatures.tsx:537
    public static let recapTitre = "Confirmer l’acceptation"
    // source: src/components/ListeCandidatures.tsx:539
    public static let recapMessage = "Vérifiez le planning contractuel avant d’assigner définitivement ce candidat."
    // source: src/components/ListeCandidatures.tsx:569
    public static let recapNote = "En confirmant, ce soignant sera assigné à l’ensemble de ce planning."
    // source: src/components/ListeCandidatures.tsx:595
    public static let recapAnnuler = "Annuler"
    // source: src/components/ListeCandidatures.tsx:605
    public static let recapConfirmer = "Confirmer et assigner"
    // source: src/components/ListeCandidatures.tsx:298
    public static let succesAcceptation = "Candidature acceptée ! Le soignant est assigné."
    // source: src/components/ListeCandidatures.tsx:324
    public static let succesRefus = "Candidature refusée."

    /// « En attente (N) » (l.375).
    public static func titreEnAttente(_ nombre: Int) -> String { "En attente (\(nombre))" }
    /// « Traitées (N) » (l.517).
    public static func titreTraitees(_ nombre: Int) -> String { "Traitées (\(nombre))" }
    /// « ⭐ 74/100 » (l.460).
    public static func badgeScore(_ score: Int) -> String { "⭐ \(score)/100" }

    // MARK: - Textes natifs (navigation, non juridiques)

    /// Bouton qui remplace « Accepter » hors périmètre natif (D10, D25).
    public static let accepterSurWeb = "Accepter sur jolene.app"
    /// Explication du renvoi, sans qualifier la mission ni le candidat (D16 : reconnexion annoncée).
    public static let renvoiWebAcceptation = "L'acceptation de cette candidature se fait sur jolene.app, où une nouvelle connexion peut vous être demandée."
    /// Bouton du renvoi vers la facturation après un refus de paiement (message serveur verbatim au-dessus).
    public static let voirFacturation = "Voir sur jolene.app"
    /// Lien neutre vers les CGV, en attendant la mention verbatim validée (HARD STOP n°4).
    public static let cgvLienNeutre = "Conditions générales de vente sur jolene.app"
    /// Issue non confirmée par la relecture (PRINCIPES §3 : jamais un succès supposé).
    public static let nonConfirmee = "La décision n'a pas pu être confirmée par une relecture. Vérifiez les candidatures avant de recommencer."
    /// La candidature relue n'est plus en attente : la liste relue la range parmi les traitées.
    public static let plusEnAttente = "Cette candidature n'est plus en attente."
    public static let messageErreurGenerique = "Les candidatures n'ont pas pu être chargées. Vérifiez votre connexion puis réessayez."

    // MARK: - URL des renvois (Safari, D16)

    /// Page web où se trouvent les candidatures de la mission (`DetailMission.tsx`).
    public static func urlAcceptationWeb(missionId: String) -> URL { EtabDestination.candidatures(missionId: missionId).urlWeb }
    /// Facturation de l'établissement (refus de paiement, correction 16).
    public static let urlFacturation = URL(string: "https://jolene.app/etablissement/facturation")!
    /// Page des CGV, ancre du web (`ListeCandidatures.tsx` l.394, chemin repris tel quel).
    public static let urlCgv = URL(string: "https://jolene.app/cgv#art8")!

    // MARK: - Mise en forme

    /// « Prénom N. » tel que servi ; repli neutre sans nom.
    public static func nom(_ candidat: CandidatHabilite?) -> String {
        let nom = [candidat?.prenom, candidat?.nom].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return nom.isEmpty ? "Soignant" : nom
    }

    /// Badges d'une candidature en attente, dans l'ordre du web (l.410-466) : profession, étudiant (hors médecin),
    /// documents, fiabilité (au moins trois missions terminées, l.458) ou « Pas encore d'évaluation ».
    public static func badges(_ candidat: CandidatHabilite?) -> [MesMissionsPresentation.Badge] {
        guard let candidat else { return [] }
        var badges: [MesMissionsPresentation.Badge] = []
        if let profession = candidat.profession, !profession.isEmpty {
            badges.append(.init(MissionPresentation.professionLabel(profession), ton: .info))
        }
        if candidat.estEtudiant == true, candidat.profession != CandidaturesEtabRules.professionRenvoyeeAuWeb {
            badges.append(.init(badgeEtudiant, ton: .info, texteAccessible: "Étudiant"))
        }
        badges.append(candidat.tousDocumentsValides == true
            ? .init(badgeDocumentsValides, ton: .succes, texteAccessible: "Documents validés")
            : .init(badgeDocumentsEnVerification, ton: .attention, texteAccessible: "Documents en vérification"))
        if let score = candidat.scoreFiabilite, (candidat.totalMissionsTerminees ?? 0) >= 3 {
            badges.append(.init(badgeScore(score), ton: score >= 70 ? .succes : (score >= 40 ? .attention : .erreur),
                                texteAccessible: "\(score)/100"))
        } else {
            badges.append(.init(badgePasEvaluation, ton: .info))
        }
        return badges
    }

    /// Statut d'une candidature traitée (l.524 : tout autre statut qu'`ACCEPTEE` s'affiche « Refusée », comme le web).
    public static func statut(_ candidature: CandidatureHabilitee) -> MesMissionsPresentation.Badge {
        candidature.statut == CandidaturesEtabRules.statutAcceptee
            ? .init(statutAcceptee, ton: .succes, texteAccessible: "Acceptée")
            : .init(statutRefusee, ton: .erreur, texteAccessible: "Refusée")
    }

    /// « 2 créneaux · 16 h au total » (l.553 ; `toLocaleString('fr-FR', { maximumFractionDigits: 2 })`).
    public static func resumeRecap(_ creneaux: [MissionSlot]) -> String {
        let nombre = creneaux.count
        return "\(nombre) créneau\(nombre > 1 ? "x" : "") · \(heures(PlanningExactEtab.dureeTotaleHeures(creneaux))) h au total"
    }

    /// Ligne d'un créneau du récapitulatif (l.558-563) : « jeudi 5 novembre 2026 · 07:00 → 19:00 », fin un autre jour
    /// « … → ven. 6 nov. · 07:00 ». `nil` sans bornes lisibles.
    public static func ligneRecap(_ creneau: MissionSlot) -> String? {
        guard let debut = PlanningHorlogeParis.instant(creneau.debut), let finISO = creneau.finRenseignee,
              let fin = PlanningHorlogeParis.instant(finISO) else { return nil }
        let finTexte = DateHeureParis.memeJour(debut, fin) ? DateHeureParis.format(fin, "HH:mm") : DateHeureParis.format(fin, "EEE d MMM · HH:mm")
        return "\(DateHeureParis.format(debut, "EEEE d MMMM yyyy")) · \(DateHeureParis.format(debut, "HH:mm")) → \(finTexte)"
    }

    /// Nombre d'heures au format français, deux décimales au plus, zéros finaux retirés (« 7,5 », « 8,33 », « 12 »).
    public static func heures(_ valeur: Double) -> String {
        guard valeur.isFinite else { return "0" }
        let centiemes = (valeur * 100).rounded()
        let entier = Int(centiemes / 100)
        let reste = Int(centiemes) - entier * 100
        guard reste != 0 else { return String(entier) }
        var decimales = String(format: "%02d", reste)
        while decimales.hasSuffix("0") { decimales.removeLast() }
        return "\(entier),\(decimales)"
    }
}
