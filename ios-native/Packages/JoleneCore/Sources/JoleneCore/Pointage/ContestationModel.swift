import Combine
import Foundation

/// Contestation d'une présence validée (lot 2, T5b, HARD STOP n°4 ; décision 9, D11 et D12 de `DECISIONS_LOT2.md`).
/// Parité du soignant de `PanneauContestation.tsx` (l.89-160, l.257-395), sans aucun texte de délai (Q9 : la garde
/// `ANCRES_Q9` les refuse) et sans réponse ni clôture (renvoi web, lot 4).
///
/// - `charger()` relit le dernier litige de la présence (`litiges` par `presence_id`, l.92-101) : s'il existe, seul son
///   statut est affiché (`TextesWeb.Contestation.libelleStatut`). Sinon le bouton « Contester cette présence » n'apparaît
///   que si `valide_le` est non nul ET si le serveur dit la fenêtre ouverte
///   (`fn_fenetre_contestation_ouverte('DESACCORD_HEURES_POINTAGE', mission)`, même prédicat que le refus de
///   `fn_ouvrir_litige_rate_limited`). Aucune constante de délai ici : la fenêtre est un paramètre serveur
///   (`parametres_litiges.delai_contestation_pointage_h`). Toute erreur de lecture masque le panneau (fail-closed).
/// - Motif borné à 500 scalaires comme la saisie du web (`slice(0, 500)`, l.374), nettoyé comme `sanitizeText`
///   (balises retirées, `trim`) ; sous 10 caractères nettoyés, le refus du serveur est affiché tel quel sans requête.
/// - `envoyer()` : une seule requête ; `.ouverte` (litige créé ET relu par la gateway) → statut affiché, formulaire
///   fermé ; `.refusee` → message serveur verbatim dans la feuille, puis dans le panneau, et le bouton n'est plus
///   proposé (revue B8 de T5b, m3) ; erreur de transport ou délai dépassé → message du port dans la feuille restée
///   ouverte, puis relecture du litige, « Envoyer » verrouillé jusqu'à sa fin : seul un litige relu change l'état (une
///   contestation reçue malgré une réponse perdue apparaît par son statut, jamais par un renvoi ; revue B8, M1).
@MainActor
public final class ContestationModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        /// Rien n'est rendu : présence non validée sans litige, fenêtre fermée, ou erreur de lecture (fail-closed).
        case masque
        /// Bouton « Contester cette présence ».
        case contestable
        /// Refus du serveur à l'envoi, affiché tel quel ; plus de bouton jusqu'à la prochaine lecture.
        case refusee(String)
        /// Litige relu : statut seul (réponse et clôture : renvoi web).
        case litige(LitigePresence)
    }

    /// Type unique de la contestation d'une présence (`p_type_litige`, l.129).
    nonisolated public static let typeLitige = "DESACCORD_HEURES_POINTAGE"
    /// Saisie bornée comme le web (`e.target.value.slice(0, 500)`, l.374).
    nonisolated public static let longueurMaxMotif = 500
    /// Borne basse du serveur (`length(trim(p_motif)) < 10`, `public.sql` l.46859-46864).
    nonisolated public static let longueurMinMotif = 10

    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var formulaireOuvert = false
    @Published public private(set) var motif = ""
    @Published public private(set) var envoiEnCours = false
    @Published public private(set) var erreur: String?

    public let presenceId: String
    public let missionId: String
    public let valideLe: String?
    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var generation = 0

    public init(presenceId: String, missionId: String, valideLe: String?, controller: SessionController, snapshot: SessionSnapshot) {
        self.presenceId = presenceId
        self.missionId = missionId
        self.valideLe = valideLe
        self.controller = controller
        self.snapshot = snapshot
    }

    /// Litige relu, nil sinon.
    public var litige: LitigePresence? {
        if case let .litige(litige) = etat { return litige }
        return nil
    }

    /// `STATUT_CONFIG[litige.statut]?.label || litige.statut` (l.266).
    public var libelleStatut: String? {
        litige.map { TextesWeb.Contestation.libelleStatut(code: $0.statut ?? "") }
    }

    public var motifNettoye: String { Self.nettoyer(motif) }

    /// « Envoyer la contestation » : `disabled={!motif.trim() || envoi}` (l.383).
    public var peutEnvoyer: Bool {
        etat == .contestable && formulaireOuvert && !envoiEnCours && !motifNettoye.isEmpty
    }

    public func charger() async {
        generation += 1
        let courant = generation
        guard let gateways = await controller.gateways(for: snapshot.epoch), generation == courant else { return }
        let port = gateways.contestation, presence = presenceId, mission = missionId, context = snapshot.context
        let delai = controller.resolutionTimeout
        do {
            let lu = try await bounded(timeout: delai) { try await port.litige(presenceId: presence, context: context) }
            guard await estCourant(courant) else { return }
            if let lu {
                appliquer(.litige(lu))
                return
            }
            guard let valideLe, !valideLe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                appliquer(.masque)
                return
            }
            let ouverte = try await bounded(timeout: delai) { try await port.fenetreOuverte(missionId: mission, context: context) }
            guard await estCourant(courant) else { return }
            appliquer(ouverte ? .contestable : .masque)
        } catch {
            guard await estCourant(courant), !Self.estAnnulation(error) else { return }
            appliquer(.masque)
        }
    }

    /// « Contester cette présence » (l.364).
    public func ouvrirFormulaire() {
        guard etat == .contestable, !envoiEnCours else { return }
        erreur = nil
        formulaireOuvert = true
    }

    /// « Annuler » (l.389) ou feuille fermée par l'utilisateur : le motif est effacé.
    public func annuler() {
        guard !envoiEnCours else { return }
        formulaireOuvert = false
        motif = ""
        erreur = nil
    }

    public func saisirMotif(_ texte: String) {
        guard !envoiEnCours else { return }
        motif = Self.limiter(texte)
    }

    /// « Envoyer la contestation » (l.118-160), sans l'appel `fn_creer_notification` du web (décision 9).
    public func envoyer() async {
        guard peutEnvoyer else { return }
        let nettoye = motifNettoye
        guard nettoye.unicodeScalars.count >= Self.longueurMinMotif else {
            erreur = MessagesContestationServeur.motifLongueur
            return
        }
        envoiEnCours = true
        erreur = nil
        defer { envoiEnCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.contestation, presence = presenceId, mission = missionId, context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.contester(missionId: mission, presenceId: presence, motif: nettoye, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            generation += 1 // une lecture en vol ne remplace pas l'issue de l'envoi
            switch issue {
            case let .ouverte(litige):
                appliquer(.litige(litige))
            case let .refusee(message):
                erreur = message
                etat = .refusee(message)
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Self.estAnnulation(error) else { return }
            let jolene = error as? JoleneError
            erreur = Self.message(jolene?.message)
            guard jolene?.kind != .unauthorized else { return } // session expirée : message seul, rien à relire
            await reconcilier(port: port)
        }
    }

    // MARK: - Interne

    /// Relecture après une erreur de transport, « Envoyer » encore verrouillé (`envoiEnCours`) : la contestation a pu être
    /// reçue (réponse perdue). Seul un litige relu change l'état ; une relecture vide ou en échec laisse la feuille ouverte,
    /// avec l'erreur de l'envoi.
    private func reconcilier(port: any ContestationPort) async {
        let presence = presenceId, context = snapshot.context
        let lu: LitigePresence?
        do {
            lu = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.litige(presenceId: presence, context: context)
            }
        } catch {
            return
        }
        guard let lu, await controller.epoch == snapshot.epoch else { return }
        generation += 1
        appliquer(.litige(lu))
    }

    /// Un litige relu (après une réponse perdue compris) fait foi : le formulaire se ferme et l'erreur s'efface.
    private func appliquer(_ nouvel: Etat) {
        etat = nouvel
        guard nouvel != .contestable else { return }
        formulaireOuvert = false
        if case .litige = nouvel {
            motif = ""
            erreur = nil
        }
    }

    private func estCourant(_ jeton: Int) async -> Bool {
        guard generation == jeton, !Task.isCancelled else { return false }
        return await controller.epoch == snapshot.epoch && generation == jeton
    }

    private static func estAnnulation(_ error: Error) -> Bool {
        error is CancellationError || (error as? JoleneError)?.kind == .cancelled
    }

    private static func message(_ message: String?) -> String {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return LibellesDetailPresences.Contestation.erreurEnvoi
        }
        return message
    }

    /// Motif borné à `longueurMaxMotif` scalaires Unicode.
    nonisolated public static func limiter(_ texte: String) -> String {
        guard texte.unicodeScalars.count > longueurMaxMotif else { return texte }
        var scalaires = String.UnicodeScalarView()
        scalaires.append(contentsOf: texte.unicodeScalars.prefix(longueurMaxMotif))
        return String(scalaires)
    }

    /// Ouverture d'une balise selon l'analyseur HTML que suit DOMPurify : `<` suivi d'une lettre, de `/`, `!` ou `?` ;
    /// tout autre `<` (« 7h<8h », « < 7h », « -> ») reste du texte (revue B8 de T5b, M2).
    nonisolated public static let motifBalise = "<(?=[A-Za-z/!?])[^>]*>"

    /// `sanitizeText` (`src/lib/sanitize.ts` : DOMPurify sans balise autorisée, puis `trim`) : balises retirées, texte
    /// conservé, espaces de bord retirés. Écarts assumés : aucune entité HTML n'est produite (DOMPurify sérialise `&` en
    /// `&amp;`, que le web enregistre puis affiche tel quel) ; le contenu d'un `<script>` est gardé comme texte (DOMPurify
    /// le retire) ; une balise jamais fermée reste du texte.
    nonisolated public static func nettoyer(_ texte: String) -> String {
        texte.replacingOccurrences(of: motifBalise, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Refus de `fn_ouvrir_litige_rate_limited(uuid, type_litige, text)` repris mot pour mot (affichés tels quels, jamais
/// reformulés) : borne du motif vérifiée avant l'envoi par `ContestationModel`, et refus simulés par le monde démo.
/// Garde : `ContestationModelTests.testMessagesServeurPresentsDansLeDump` (chaque texte figure dans le dump versionné).
public enum MessagesContestationServeur {
    // source: supabase/schema/public.sql:46871
    public static let motifLongueur = "Le motif doit contenir entre 10 et 2 000 caractères."
    // source: supabase/schema/public.sql:46913
    public static let dejaOuvert = "Un litige de ce type est déjà ouvert pour cette mission."
    // source: supabase/schema/public.sql:46984
    public static let fenetreFermee = "Fenêtre de contestation fermée pour ce type de litige. Contactez le support."

    public static let tous = [motifLongueur, dejaOuvert, fenetreFermee]
}
