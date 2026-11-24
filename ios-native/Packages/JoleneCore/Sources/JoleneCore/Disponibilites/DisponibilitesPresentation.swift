import Foundation

/// Textes de « Mes disponibilités » (L4-T5), repris mot pour mot de `src/pages/MesDisponibilites.tsx` (route
/// `/soignant/disponibilites`) et, pour le refus de fenêtre, du corps de `fn_definir_disponibilite`
/// (`supabase/schema/public.sql`). Aucun texte juridique nouveau ; les refus serveur sont affichés tels quels
/// (`IssueDisponibilite.refusee`). Garde : `DisponibilitesLectureTests` relit ces sources par leur contenu.
///
/// Portés ailleurs, du même fichier web : « Jour », « Nuit », « aujourd'hui » et le compteur « N créneau(x)
/// déclaré(s). » (`AvailabilityWeekGrid`, JoleneDesign, L4-T1b) ; « Semaine du … » (`SemainesDisponibilites`, L4-T2).
///
/// Textes sans équivalent web (vouvoiement sobre, non juridiques, D24) : `basculeImpossible` (le web affiche le
/// message de l'erreur de transport, `extraireMessageErreur`) et `nonConfirmee` (relecture qui ne montre pas la bascule,
/// PRINCIPES §3 ; même phrase que les recherches sauvegardées).
public enum DisponibilitesTextes {
    /// Fragment d'un texte dont le web met des mots en gras (`<strong>`).
    public struct Segment: Equatable, Sendable {
        public var texte: String
        public var gras: Bool

        public init(_ texte: String, gras: Bool = false) {
            self.texte = texte; self.gras = gras
        }
    }

    // source: src/pages/MesDisponibilites.tsx:29 (`usePageTitle`) et :128 (titre de la page)
    public static let titre = "Mes disponibilités"
    // source: src/pages/MesDisponibilites.tsx:131-133
    public static let introduction = "Indiquez vos jours et nuits disponibles : vous êtes alertée dès que des missions correspondent à votre planning, et les établissements voient qu'ils peuvent compter sur vous ce jour-là (prénom et score uniquement, jamais vos coordonnées)."
    // source: src/pages/MesDisponibilites.tsx:141-142 (affichée seulement sans créneau déclaré, l.137)
    public static let aide: [Segment] = [
        Segment("Touchez "), Segment("Jour", gras: true), Segment(" ou "), Segment("Nuit", gras: true),
        Segment(" sur les dates où vous êtes disponible. Vous pouvez tout modifier à tout moment."),
    ]
    /// L'aide sans mise en forme (VoiceOver).
    public static var aideTexte: String { aide.map(\.texte).joined() }
    // source: src/pages/MesDisponibilites.tsx:210 (fin du paragraphe du compteur, toujours affichée)
    public static let mention = "Déclarer une disponibilité n'engage à rien : c'est un signal de matching, pas un engagement."
    // source: src/pages/MesDisponibilites.tsx:114
    public static let echecTitre = "Disponibilités indisponibles"
    // source: src/pages/MesDisponibilites.tsx:115
    public static let echecMessage = "Vos disponibilités n’ont pas pu être chargées. Réessayez avant de les modifier."
    // source: src/pages/MesDisponibilites.tsx:116
    public static let reessayer = "Réessayer"
    // source: supabase/schema/public.sql, corps de `fn_definir_disponibilite` (`p_jour < CURRENT_DATE OR p_jour >
    // CURRENT_DATE + 90`) : refus du serveur, repris tel quel pour un jour que l'app n'envoie pas (jour passé ou hors de
    // la grille).
    public static let horsFenetre = "La disponibilité doit être entre aujourd'hui et J+90"

    /// Bascule en échec sans message exploitable (refus muet, erreur inconnue).
    public static let basculeImpossible = "Votre disponibilité n’a pas pu être enregistrée. Réessayez."
    /// Relecture qui ne montre pas la bascule demandée : jamais un succès annoncé.
    public static let nonConfirmee = "La modification n’a pas pu être confirmée. Réessayez."
}

/// État d'une bascule de la grille : déclarée (valeur relue du serveur) et appel en vol sur cette case.
public struct CaseDisponibilite: Equatable, Sendable {
    public var declaree: Bool
    public var enCours: Bool

    public init(declaree: Bool, enCours: Bool) {
        self.declaree = declaree; self.enCours = enCours
    }
}

/// Jour présenté par la grille : libellé du web, jour courant, jour passé (bascules inertes) et ses deux créneaux.
public struct JourDisponibilitesAffiche: Equatable, Sendable, Identifiable {
    public var jour: JourParis
    /// « Lundi 2 Nov. » (`EEEE d MMM` de date-fns `fr`, classe CSS `capitalize`).
    public var libelle: String
    public var estAujourdhui: Bool
    public var passe: Bool
    public var journee: CaseDisponibilite
    public var nuit: CaseDisponibilite

    /// Jour `yyyy-MM-dd` (clé serveur `p_jour`, suffixe des identifiants `dispo-<jour>-<créneau>`).
    public var id: String { jour.iso }

    public init(jour: JourParis, libelle: String, estAujourdhui: Bool, passe: Bool, journee: CaseDisponibilite,
                nuit: CaseDisponibilite) {
        self.jour = jour; self.libelle = libelle; self.estAujourdhui = estAujourdhui; self.passe = passe
        self.journee = journee; self.nuit = nuit
    }

    public func etat(_ creneau: CreneauDispo) -> CaseDisponibilite {
        switch creneau {
        case .journee: return journee
        case .nuit: return nuit
        }
    }
}

/// Semaine présentée par la grille : en-tête « Semaine du 2 novembre » et sept jours depuis le lundi.
public struct SemaineDisponibilitesAffichee: Equatable, Sendable, Identifiable {
    /// Identifiant d'accessibilité du bloc : `dispos-semaine-1` … `dispos-semaine-4`.
    public var id: String
    public var entete: String
    public var jours: [JourDisponibilitesAffiche]

    public init(id: String, entete: String, jours: [JourDisponibilitesAffiche]) {
        self.id = id; self.entete = entete; self.jours = jours
    }
}

/// Mise en forme de la grille, sans règle : croise la grille dérivée de l'horloge (`SemainesDisponibilites`, L4-T2),
/// les cases relues du serveur et les appels en vol.
public enum DisponibilitesPresentation {
    private static let francais = Locale(identifier: "fr_FR")

    /// Libellé du jour mis en capitales comme la classe CSS `capitalize` du web (l.164) : « lundi 2 nov. » →
    /// « Lundi 2 Nov. ».
    public static func libelle(_ brut: String) -> String { brut.capitalized(with: francais) }

    public static func semaines(grille: GrilleDisponibilites, declarees: Set<DispoCle>,
                                enCours: Set<DispoCle>) -> [SemaineDisponibilitesAffichee] {
        func etat(_ jour: JourParis, _ creneau: CreneauDispo) -> CaseDisponibilite {
            let cle = DispoCle(jour: jour, creneau: creneau)
            return CaseDisponibilite(declaree: declarees.contains(cle), enCours: enCours.contains(cle))
        }
        return grille.semaines.enumerated().map { rang, semaine in
            SemaineDisponibilitesAffichee(id: "dispos-semaine-\(rang + 1)", entete: semaine.entete, jours: semaine.jours.map { jour in
                JourDisponibilitesAffiche(jour: jour.jour, libelle: libelle(jour.libelle), estAujourdhui: jour.estAujourdhui,
                                          passe: jour.passe, journee: etat(jour.jour, .journee), nuit: etat(jour.jour, .nuit))
            })
        }
    }
}
