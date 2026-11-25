import Foundation
import Combine

/// Textes de l'écran Parrainage, repris mot pour mot de `src/pages/PageParrainage.tsx` (numéros de ligne en regard).
///
/// **Hors de cette tranche (T6-HS, HARD STOP n°4)** : le bloc « conditions de la prime » (l.181-189), le badge
/// Ambassadeur visible (l.190-196), sa condition (l.167, l.172-178), la liste « Comment ça marche ? » (l.292-303), la
/// colonne « Vers la prime » (l.322, l.354-376) et le sous-titre promotionnel (l.123) : aucun montant, aucune condition,
/// aucune promesse dans l'écran natif. Les conditions restent consultables sur la page web, par le renvoi neutre
/// « Voir sur jolene.app » (`RenvoiWebScreen.bouton`).
public enum ParrainageTextes {
    public static let titre = "Parrainage"                                                                  // l.121
    public static let chargement = "Chargement de votre parrainage…"                                       // l.129
    public static let indisponibleTitre = "Parrainage indisponible"                                       // l.133
    public static let indisponible = "Le parrainage est temporairement indisponible. Réessayez dans un instant." // l.85
    public static let reessayer = "Réessayer"                                                              // l.135, l.150
    public static let aPreparerTitre = "Votre lien de parrainage n’est pas encore disponible"              // l.141
    public static let aPreparerProfil =
        "Aucun code personnel n’est disponible pour le moment. Réessayez pour actualiser votre parrainage."   // l.144
    public static let aPreparerSansProfil = "Votre code personnel sera disponible après la création de votre dossier "
        + "professionnel. Vous pouvez continuer à explorer les missions sans le préparer maintenant."        // l.145
    public static let explorer = "Explorer les missions"                                                   // l.148
    public static let preparerDossier = "Préparer mon dossier"                                             // l.151
    public static let badgeTitre = "Badge Ambassadeur"                                                     // l.163
    public static let badgeDebloque = "✅ Débloqué !"                                                       // l.165
    public static let tonCode = "Ton code parrainage"                                                      // l.203
    public static let copierCode = "Copier le code parrainage"                                             // l.210 (aria-label)
    public static let qrCode = "QR code de ton lien de parrainage"                                         // l.219 (aria-label)
    public static let copierLien = "Copier le lien"                                                        // l.229
    public static let copie = "Copié !"                                                                    // l.229
    /// Feuille de partage du système, à la place des quatre boutons du web (WhatsApp, SMS, Email, LinkedIn, l.234-251),
    /// qui partagent le même message : libellé générique du bouton, sans équivalent textuel sur le web.
    public static let partager = "Partager"
    public static let mesFilleuls = "Mes filleuls"                                                         // l.308
    public static let aucunFilleul = "Aucun filleul pour le moment. Partage ton lien !"                    // l.312
    public static let filleulsAVenir = "Vos filleuls et leur progression apparaîtront ici."               // l.312
    public static let colonnePrenom = "Prénom"                                                             // l.319
    public static let colonneInscription = "Inscription"                                                   // l.320
    public static let colonneStatut = "Statut"                                                             // l.321
    public static let statutMissionFaite = "1ère mission faite"                                            // l.344
    public static let statutEnAttente = "⏳ En attente"                                                     // l.348
    public static let statutInscrit = "Inscrit"                                                            // l.351
    public static let prenomParDefaut = "Soignant"                                                         // l.72

    /// Tous les textes fixes de l'écran (garde « aucun montant ni condition », `ParrainageModelTests`).
    public static let tous = [titre, chargement, indisponibleTitre, indisponible, reessayer, aPreparerTitre, aPreparerProfil,
                              aPreparerSansProfil, explorer, preparerDossier, badgeTitre, badgeDebloque, tonCode, copierCode,
                              qrCode, copierLien, copie, partager, mesFilleuls, aucunFilleul, filleulsAVenir, colonnePrenom,
                              colonneInscription, colonneStatut, statutMissionFaite, statutEnAttente, statutInscrit,
                              prenomParDefaut]
}

/// Lecture des réponses serveur (même forme en démo et sur Supabase) : profil `soignants` et `fn_obtenir_mes_parrainages`
/// (`supabase/schema/public.sql`, `jsonb_build_object('filleuls', …, 'mon_parrain', …)`).
public enum ParrainageDecodage {
    /// `nil` si la réponse n'est pas lisible (`result?.error || !Array.isArray(result?.filleuls)`, l.64) : une erreur,
    /// jamais un parrainage vide. `profil` : ligne `soignants` (`nil` ou `null` : aucune ligne, `maybeSingle`).
    public static func etat(profil: ValeurJSON?, reponse: ValeurJSON) -> EtatParrainage? {
        guard case let .objet(objet) = reponse, objet["error"] == nil || objet["error"] == .null,
              case let .tableau(lignes)? = objet["filleuls"] else { return nil }
        let filleuls = lignes.compactMap(filleul)
        var profilPresent = false
        var code: String?
        var badge = false
        if case let .objet(ligne)? = profil {
            profilPresent = true
            if case let .chaine(brut)? = ligne["code_parrainage"] {
                let nettoye = brut.trimmingCharacters(in: .whitespacesAndNewlines)
                code = nettoye.isEmpty ? nil : nettoye
            }
            badge = ligne["badge_ambassadeur"] == .booleen(true)
        }
        var monParrain: MonParrain?
        if case let .objet(parrain)? = objet["mon_parrain"] {
            monParrain = MonParrain(prenom: texte(parrain["parrain_prenom"]), statut: texte(parrain["statut"]))
        }
        return EtatParrainage(profilPresent: profilPresent, code: code, badgeAmbassadeur: badge, filleuls: filleuls,
                              primeEur: nombre(objet["prime_eur"]), seuilGmvEur: nombre(objet["seuil_gmv_eur"]),
                              monParrain: monParrain)
    }

    private static func filleul(_ valeur: ValeurJSON) -> Filleul? {
        guard case let .objet(ligne) = valeur, let id = texte(ligne["filleul_id"]) else { return nil }
        return Filleul(id: id,
                       prenom: texte(ligne["prenom"]) ?? ParrainageTextes.prenomParDefaut,
                       statut: texte(ligne["statut"]) ?? "INSCRIT",
                       creeLe: texte(ligne["cree_le"]),
                       premiereMissionLe: texte(ligne["premiere_mission_le"]),
                       primeVerseeLe: texte(ligne["prime_versee_le"]),
                       seuilAtteint: { if case let .booleen(b)? = ligne["seuil_atteint"] { return b }; return nil }(),
                       resteGmvAvantPrime: nombre(ligne["reste_gmv_avant_prime"]))
    }

    private static func texte(_ valeur: ValeurJSON?) -> String? {
        guard case let .chaine(texte)? = valeur, !texte.isEmpty else { return nil }
        return texte
    }

    private static func nombre(_ valeur: ValeurJSON?) -> Double? {
        guard case let .nombre(nombre)? = valeur else { return nil }
        return nombre
    }
}

/// Présentation de l'écran (règles du web, sans montant).
public enum ParrainagePresentation {
    /// Lien de parrainage partagé : `https://jolene.app/inscription/soignant?ref=${encodeURIComponent(code)}` (l.41). Il
    /// ne porte que le code : aucun identifiant d'utilisateur, aucun jeton. `nil` sans code.
    public static func lien(code: String) -> URL? {
        guard !code.isEmpty else { return nil }
        // `encodeURIComponent` : lettres, chiffres et `-_.!~*'()` gardés, tout le reste encodé en UTF-8.
        var permis = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        permis.insert(charactersIn: "-_.!~*'()")
        guard let encode = code.addingPercentEncoding(withAllowedCharacters: permis) else { return nil }
        return URL(string: "https://jolene.app/inscription/soignant?ref=\(encode)")
    }

    /// Message partagé avec le lien (l.107-109).
    public static func messagePartage(lien: URL) -> String {
        "Rejoignez Jolene, la plateforme de staffing médical ! Inscrivez-vous avec mon lien : \(lien.absoluteString)"
    }

    /// Statut affiché d'un filleul (l.327-351) : première mission faite, en attente, sinon inscrit.
    public static func statut(_ filleul: Filleul) -> String {
        if filleul.premiereMissionLe != nil || filleul.statut == "VALIDE" { return ParrainageTextes.statutMissionFaite }
        if filleul.statut == "EN_ATTENTE" { return ParrainageTextes.statutEnAttente }
        return ParrainageTextes.statutInscrit
    }

    /// Filleuls « validés » du compteur (l.112).
    public static func valides(_ filleuls: [Filleul]) -> Int {
        filleuls.filter { $0.statut == "VALIDE" || $0.premiereMissionLe != nil }.count
    }

    public static func compteurInscrits(_ nombre: Int) -> String {
        nombre > 1 ? "filleuls inscrits" : "filleul inscrit"                                               // l.284
    }

    public static func compteurMissions(_ nombre: Int) -> String {
        nombre > 1 ? "missions terminées" : "mission terminée"                                             // l.288
    }

    /// Date d'inscription au format `fr-FR` (`toLocaleDateString`, l.339), jour civil de Paris ; « — » sans date.
    public static func dateInscription(_ iso: String?) -> String {
        guard let iso, let instant = try? DateHeureParis.instantJolene(iso) else { return "—" }
        let p = DateHeureParis.parties(instant)
        return String(format: "%02d/%02d/%04d", p.jour, p.mois, p.annee)
    }
}

/// État de l'écran : en attente de la première réponse, prêt, ou en échec (message affiché).
public enum EcranParrainage: Equatable, Sendable {
    case chargement
    case pret(EtatParrainage)
    case echec(String)
}

/// Modèle de l'écran Parrainage (L4-T6), port de la lecture de `PageParrainage.tsx` (l.44-94) : lecture bornée à
/// `SessionController.resolutionTimeout`, gateways de l'epoch de l'écran, réponse d'un epoch périmé ignorée, deux
/// lectures qui se chevauchent : seule la dernière publie. Échec : message du web (l.85), sauf session expirée (message
/// de la session) ; une annulation n'est jamais une erreur.
@MainActor
public final class ParrainageModel: ObservableObject {
    @Published public private(set) var etat: EcranParrainage = .chargement

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var revision = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    /// À chaque apparition et « Réessayer » (le web recharge et repart de l'état de chargement, l.46-52).
    public func charger() async {
        revision += 1
        let revisionLecture = revision
        etat = .chargement
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.parrainage
        let context = snapshot.context
        do {
            let lu = try await bounded(timeout: controller.resolutionTimeout) { try await port.etat(context: context) }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return }
            etat = .pret(lu)
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled else { return }
            if error is CancellationError || (error as? JoleneError)?.kind == .cancelled { return }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized {
                etat = .echec(jolene.message)
            } else {
                etat = .echec(ParrainageTextes.indisponible)
            }
        }
    }
}
