import Foundation

/// Règles des favoris (lot 1, T4b), port de `MesFavorisSoignant.tsx` et de `BoutonSauvegarderMission.tsx`.
/// Aucune règle juridique ni montant : filtre d'affichage du web et état de l'étoile.
public enum FavorisRegles {
    /// Seul statut listé dans « Mes favoris » (web l.47 : `m.statut === 'OUVERTE'`).
    public static let statutAffiche = "OUVERTE"

    /// Verrou de la décision 8 du lot 1 : l'ajout d'un établissement favori n'est exposé nulle part sur le
    /// web (`BoutonFavoriEtab` non monté) et n'est pas porté. Les deux mondes refusent `actif = true` avant
    /// tout appel, avec ce message (`.contract`) : jamais un `p_actif = true` envoyé en silence.
    public static let ajoutEtablissementNonPropose =
        "L'ajout d'un établissement aux favoris n'est pas proposé dans l'application (décision 8 du lot 1, docs/mobile-swift/LOT1_PLAN.md)."

    /// Port du filtre du web (l.46-49) : mission jointe lisible, statut `OUVERTE`, début strictement après
    /// `maintenant` (`new Date(m.debut_le) > new Date()` ; date illisible → exclue, comme `Invalid Date`) ;
    /// ordre serveur conservé (`cree_le DESC`), une seule ligne par mission (la première).
    public static func missionsAffichees(_ lignes: [MissionSauvegardee], maintenant: Date) -> [MissionSauvegardee] {
        var vues = Set<String>()
        return lignes.filter { ligne in
            guard let mission = ligne.mission, mission.statut == statutAffiche,
                  let debut = mission.debutLe, let instant = PlanningHorlogeParis.instant(debut), instant > maintenant
            else { return false }
            return vues.insert(mission.id).inserted
        }
    }

    /// État de l'étoile : une ligne `missions_sauvegardees` existe pour la mission (web : `.maybeSingle()`),
    /// qu'elle soit listée ou non dans « Mes favoris ».
    public static func estSauvegardee(_ missionId: String, dans lignes: [MissionSauvegardee]) -> Bool {
        !missionId.isEmpty && lignes.contains { $0.missionId == missionId }
    }
}

/// Libellés des favoris (vouvoiement, décision 9). Valeurs serveur affichées telles quelles
/// (`nb_missions_ouvertes`, dates) ; aucun texte juridique.
public enum FavorisPresentation {
    public static let titreEcran = "Mes favoris"
    public static let titreEtablissements = "Établissements suivis"
    /// Web l.123-125, au vouvoiement : les favoris établissement déclenchent `FAVORI_NOUVELLE_MISSION`.
    public static let explicationEtablissements =
        "Vous êtes prévenu dès que ces établissements publient une nouvelle mission compatible avec votre profil."
    public static let missionsVides =
        "Aucune mission sauvegardée. Touchez l'étoile d'une mission dans Explorer pour la retrouver ici."
    /// Le texte vide du web (« Clique sur l'étoile ⭐ d'une mission pour ajouter l'établissement ») n'est pas
    /// repris : l'étoile d'une mission ne suit pas son établissement (décision 8).
    public static let etablissementsVides = "Aucun établissement suivi pour le moment."
    public static let voirMissions = "Voir les missions ouvertes"
    public static let retirer = "Retirer"
    public static let titreRetraitEtablissement = "Retirer cet établissement de vos favoris ?"

    public static func messageRetraitEtablissement(nom: String?) -> String {
        "Vous ne serez plus prévenu des nouvelles missions de « \(nomOuRepli(nom)) »."
    }

    /// « Missions sauvegardées (N) » (web l.57 : `⭐ Missions sauvegardées ({n})`), sans compte s'il n'y en a aucune.
    public static func titreMissions(_ nombre: Int) -> String {
        nombre > 0 ? "Missions sauvegardées (\(nombre))" : "Missions sauvegardées"
    }

    public static func titreMission(_ apercu: MissionSauvegardee.Apercu) -> String {
        let titre = apercu.intitule?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return titre.isEmpty ? "Mission" : titre
    }

    /// Web l.71 : `formatDateMission(m) · formatDureeCompacte(m)`.
    public static func detailMission(_ apercu: MissionSauvegardee.Apercu) -> String {
        "\(FormatMission.formatDateMission(apercu.horaires)) · \(FormatMission.formatDureeCompacte(apercu.horaires))"
    }

    public static func nom(_ etablissement: EtablissementFavori) -> String { nomOuRepli(etablissement.nom) }

    /// Web l.149-150 : `{ville ?? '—'}` puis ` · type` (tirets bas en espaces, minuscules).
    public static func lieu(_ etablissement: EtablissementFavori) -> String {
        var texte = etablissement.ville ?? "—"
        if let type = etablissement.typeEtablissement, !type.isEmpty {
            texte += " · " + type.replacingOccurrences(of: "_", with: " ").lowercased()
        }
        return texte
    }

    /// Web l.153-157 : badge seulement au-delà de 0, « N mission(s) ».
    public static func badgeMissions(_ nombre: Int?) -> String? {
        guard let nombre, nombre > 0 else { return nil }
        return "\(nombre) mission\(nombre > 1 ? "s" : "")"
    }

    /// Web l.164 : « Voir missions ouvertes » seulement si l'établissement en a.
    public static func afficheVoirMissions(_ nombre: Int?) -> Bool { (nombre ?? 0) > 0 }

    /// Web l.160 : `Favorisé le {d MMM yyyy}` (date-fns, `fr`), en heure de Paris ; `nil` si illisible.
    public static func favoriDepuis(_ creeLe: String?) -> String? {
        guard let creeLe, let instant = PlanningHorlogeParis.instant(creeLe) else { return nil }
        return "Favori depuis le \(DateHeureParis.format(instant, "d MMM yyyy"))"
    }

    public static func libelleEtoile(sauvegardee: Bool) -> String {
        // Web : `aria-label` de `BoutonSauvegarderMission` (l.89).
        sauvegardee ? "Retirer de mes missions sauvegardées" : "Sauvegarder cette mission"
    }

    public static func valeurEtoile(sauvegardee: Bool) -> String { sauvegardee ? "Sauvegardée" : "Non sauvegardée" }

    /// Bandeau d'Explorer filtré par « Voir les missions ouvertes ».
    public static func libelleFiltreEtablissement(nom: String?) -> String {
        guard let nom = nom?.trimmingCharacters(in: .whitespacesAndNewlines), !nom.isEmpty else {
            return "Missions d'un établissement sélectionné"
        }
        return "Missions de « \(nom) »"
    }

    private static func nomOuRepli(_ nom: String?) -> String {
        let texte = nom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return texte.isEmpty ? "Établissement" : texte
    }
}

public extension ExplorerFiltres {
    /// Critères d'Explorer avec (ou sans, `nil`) le filtre établissement, les autres critères inchangés :
    /// retrait du bandeau « Missions de … ». « Voir les missions ouvertes » part, comme le web
    /// (`/soignant/recherche-missions?etablissement=`), des filtres initiaux du profil :
    /// `ExplorerFiltres.initiaux(profile:etablissementId:)`.
    func filtrantEtablissement(_ etablissementId: String?) -> ExplorerFiltres {
        var filtres = self
        let id = etablissementId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        filtres.etablissementId = id.isEmpty ? nil : id
        return filtres
    }
}
