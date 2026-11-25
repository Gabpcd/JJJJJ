import Foundation

/// Textes du détail de série (L4-T12), repris de `src/pages/DetailSerieSoignant.tsx` (route
/// `/soignant/missions/serie/:serieId`), chacun à sa ligne (`SerieVerbatimTests`). Aucun texte juridique ici :
/// - les refus du serveur (conflit de planning, repos, plafond hebdomadaire, exception des triggers de conformité)
///   sont affichés mot pour mot depuis l'issue de la gateway, jamais écrits ni reformulés dans ce fichier
///   (HARD STOP n°4, décision 2 du lot 1) ;
/// - le bloc « Vérification de compatibilité » du web (l.376-428 : règles de repos et de durée calculées côté client,
///   articles de loi) et la modale d'explication d'un article ne sont pas portés (décision 2 du lot 1) ;
/// - les totaux par régime et leurs mentions (l.499-509) ne sont pas portés : aucun montant n'est additionné côté
///   client (PRINCIPES §3), chaque ligne affiche la rémunération serveur de sa mission.
/// Les textes tutoyés du web, non juridiques, passent au vouvoiement (décision 9 du lot 1, D24 du lot 4, liste
/// `vouvoiements`), comme le récapitulatif de candidature du lot 1 (`LibellesCandidature.recapTitre`). Textes sans
/// équivalent web, opérationnels (D24) : `nonEnvoyee`, `arret`, `ouvrirDetail`, `voirContrats`, `nonConfirmee`.
public enum SerieTextes {
    // source: DetailSerieSoignant.tsx l.359 (pastille de l'en-tête ; le titre de la barre en est le libellé sans pictogramme)
    public static let pastille = "🔁 Pack de missions"
    public static let titre = "Pack de missions"

    // source: l.228-230 (lecture en échec)
    public static let indisponibleTitre = "Pack indisponible"
    public static let indisponibleTexte = "Les missions de ce pack n’ont pas pu être chargées. Réessayez pour vérifier les créneaux disponibles."
    public static let reessayer = "Réessayer"

    // source: l.237-239 (aucune mission accessible)
    public static let introuvableTitre = "Pack introuvable"
    public static let introuvableTexte = "Ce pack ne contient plus de mission accessible. Vous pouvez poursuivre votre recherche."
    public static let explorer = "Explorer les missions"

    // source: l.432
    public static let creneaux = "📋 Créneaux"
    // source: l.469 (mission attribuée ; sinon le statut brut, comme le web)
    public static let dejaPourvue = "Déjà pourvue"
    // source: l.472
    public static let conflit = "⚠️ Conflit détecté"
    // source: l.474
    public static let planningIndisponible = "⚠️ Planning détaillé indisponible"

    // source: l.525
    public static let acceptationEnCours = "Acceptation en cours…"
    // source: l.527 (vouvoyé : « Décoche »)
    public static let decocherConflits = "Décochez les missions en conflit pour continuer"
    // source: l.541 (vouvoyé : « Vérifie tous tes »)
    public static let confirmationTitre = "Vérifiez tous vos engagements"
    // source: l.543 (vouvoyé : « Confirme », « tu peux »)
    public static let confirmationDescription = "Confirmez uniquement si vous pouvez assurer chacun des créneaux exacts sélectionnés."
    // source: l.557
    public static let annuler = "Annuler"
    // source: l.564
    public static let accepterTous = "Accepter tous ces créneaux"
    // source: l.278 (vouvoyé : « Corrige »)
    public static let selectionACorriger = "Corrigez la sélection : aucune mission en conflit ou au planning incomplet ne sera omise automatiquement."

    // source: l.312
    public static let choixContratTitre = "Choix de contrat requis"
    // source: l.346
    public static let bilanAucune = "Aucune mission n'a pu être acceptée."

    /// Mission acceptée : relue attribuée au soignant par la gateway (libellé du détail de mission, lot 1).
    public static let acceptee = LibellesCandidature.assignee
    /// Boucle arrêtée avant cette mission (refus de conformité, session expirée, issue inconnue) : rien n'a été envoyé.
    public static let nonEnvoyee = "Non envoyée"
    /// Sous le refus de conformité affiché tel que servi : ce que l'app a fait, sans qualifier le refus.
    public static let arret = "L’acceptation s’est arrêtée sur ce refus. Les missions suivantes n’ont pas été envoyées."
    /// Lien d'une mission au choix de contrat requis vers son détail (web l.313 : « ouvre son détail »).
    public static let ouvrirDetail = "Ouvrir le détail de la mission"
    /// Après une acceptation : le web redirige vers `/soignant/contrats` (l.341-344) ; ici le bilan reste affiché et ce
    /// bouton mène aux contrats (« Mes documents », onglet Contrats).
    public static let voirContrats = "Voir mes contrats"
    /// Réponse perdue (délai, réseau) : rien n'est renvoyé, la série est relue.
    public static let nonConfirmee = "L’acceptation de cette mission n’a pas pu être confirmée. Vérifiez Mes missions avant de réessayer."

    // source: l.369 (`'d MMM'` puis `'d MMM yyyy'`, heure de Paris ; date illisible : valeur brute)
    public static func periode(debut: String, fin: String) -> String {
        "📅 Du \(jour(debut, "d MMM")) au \(jour(fin, "d MMM yyyy"))"
    }

    // source: l.372
    public static func disponibles(_ ouvertes: Int, sur total: Int) -> String {
        "📋 \(ouvertes) mission\(ouvertes > 1 ? "s" : "") disponible\(ouvertes > 1 ? "s" : "") sur \(total)"
    }

    // source: l.364 (ville absente : nom seul)
    public static func etablissement(nom: String, ville: String?) -> String {
        guard let ville, !ville.isEmpty else { return "🏥 \(nom)" }
        return "🏥 \(nom) · \(ville)"
    }

    // source: l.450 (libellé de la case à cocher, `'d MMMM yyyy'`)
    public static func selectionner(debut: String) -> String {
        "Sélectionner la mission du \(jour(debut, "d MMMM yyyy"))"
    }

    // source: l.528
    public static func accepterSelection(_ nombre: Int) -> String { "★ Accepter la sélection (\(nombre))" }

    // source: l.313 (vouvoyé : « ouvre », « ton »)
    public static func choixContratDescription(intitule: String) -> String {
        "La mission \"\(intitule)\" accepte salarié ou libéral : ouvrez son détail pour choisir votre mode de contrat avant d'accepter."
    }

    // source: l.343 (bilan partiel ; « en conflit » compte, comme le web, toute mission envoyée et non acceptée)
    public static func bilanPartiel(reussies: Int, echouees: Int) -> String {
        "\(reussies) mission(s) acceptée(s), \(echouees) en conflit."
    }

    // source: l.574 (toutes les missions envoyées sont acceptées)
    public static func bilanSucces(_ reussies: Int) -> String {
        "\(reussies) mission\(reussies > 1 ? "s" : "") acceptée\(reussies > 1 ? "s" : "") !"
    }

    /// Statut d'une mission qui n'est plus ouverte (l.469) : « Déjà pourvue » si elle est attribuée, sinon son statut.
    public static func statutFerme(_ mission: Mission) -> String {
        mission.record.soignantAssigneId == nil ? MesMissionsPresentation.statut(mission.record.statut) : dejaPourvue
    }

    /// Textes tutoyés du web et leur forme vouvoyée (décision 9 du lot 1 ; aucun n'est juridique).
    public static let vouvoiements: [(web: String, natif: String)] = [
        ("Décoche les missions en conflit pour continuer", decocherConflits),
        ("Vérifie tous tes engagements", confirmationTitre),
        ("Confirme uniquement si tu peux assurer chacun des créneaux exacts sélectionnés.", confirmationDescription),
        ("Corrige la sélection : aucune mission en conflit ou au planning incomplet ne sera omise automatiquement.", selectionACorriger),
        ("accepte salarié ou libéral : ouvre son détail pour choisir ton mode de contrat avant d'accepter.",
         "accepte salarié ou libéral : ouvrez son détail pour choisir votre mode de contrat avant d'accepter."),
    ]

    private static func jour(_ iso: String, _ masque: String) -> String {
        guard let instant = try? DateHeureParis.instantJolene(iso) else { return iso }
        return DateHeureParis.format(instant, masque)
    }
}

/// Ligne d'issue affichée sous une mission après la boucle (`serie-resultat-<id>`).
public struct LigneResultatSerie: Equatable, Sendable {
    public enum Ton: Equatable, Sendable { case succes, attention, erreur, information }

    public var titre: String?
    public var texte: String
    public var ton: Ton
    /// Lien vers le détail de la mission (choix de contrat requis, web l.313).
    public var lienDetail: Bool

    public init(titre: String? = nil, texte: String, ton: Ton, lienDetail: Bool = false) {
        self.titre = titre; self.texte = texte; self.ton = ton; self.lienDetail = lienDetail
    }
}

public extension IssueMissionSerie {
    /// Texte de l'issue. Un refus du serveur est rendu seul et tel quel : ni titre, ni préfixe, ni suffixe
    /// (HARD STOP n°4), qu'il vienne d'un refus structuré ou de l'exception d'un trigger de conformité.
    func ligne(intitule: String) -> LigneResultatSerie {
        switch self {
        case .acceptee:
            return LigneResultatSerie(texte: SerieTextes.acceptee, ton: .succes)
        case .choixContratRequis:
            return LigneResultatSerie(titre: SerieTextes.choixContratTitre, texte: SerieTextes.choixContratDescription(intitule: intitule),
                                      ton: .attention, lienDetail: true)
        case let .refusee(_, message), let .codeDuTravail(message):
            return LigneResultatSerie(texte: message, ton: .erreur)
        case let .planningModifie(message):
            return LigneResultatSerie(texte: message, ton: .attention)
        case .planningIncomplet:
            return LigneResultatSerie(texte: PlanningCandidatRules.messagePlanningIncomplet, ton: .attention)
        case let .nonConfirmee(message):
            return LigneResultatSerie(texte: message, ton: .attention)
        case .nonEnvoyee:
            return LigneResultatSerie(texte: SerieTextes.nonEnvoyee, ton: .information)
        }
    }
}
