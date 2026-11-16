import Foundation
import Combine

/// Modèle de la section « Paiements à confirmer » de l'onglet Revenus (lot 3, T13, B9), port de
/// `BandeauPaiementDeclare.tsx` : lignes `DECLARE` du soignant, détail dépliable, « Confirmer la réception » et
/// « Contester » (motif obligatoire, 500 caractères au plus), contrat de `fn_contester_paiement_soignant` d'après B3
/// (#1118, D19, TJ7).
///
/// Règles (PRINCIPES §3 et §4, blueprint §2.5 « Paiement déclaré ») :
/// - une seule mutation à la fois (`enCours`, posé avant tout `await`) : un double tap, ou un tap sur une autre carte,
///   n'envoie rien de plus ; les boutons restent désactivés jusqu'à la relecture de la liste ;
/// - « Paiement confirmé ✅ » / « Contestation envoyée » seulement quand le port rend `.confirme` / `.conteste`, c'est-à-dire
///   après relecture de la ligne (`PaiementsDeclaresRelecture`) ; un refus serveur `{error}` est affiché verbatim ; toute
///   autre issue (délai dépassé, réseau, 23505 non restituée, relecture non probante) affiche le message de l'erreur,
///   jamais un succès ;
/// - après toute issue, la liste est relue (`aConfirmer`) : une carte ne disparaît que parce que le serveur ne la rend
///   plus (jamais de retrait local d'office), et rien n'est renvoyé automatiquement ; `miseAJour` avance alors pour que
///   l'onglet relise l'état des missions (`onUpdate` → `reloadKey` du web, l.198 et `MesGains.tsx` l.383) ;
/// - la contestation n'est jamais envoyée sans motif non blanc (`disabled={!motif.trim()}`, l.61) ; le repli du web
///   `'Contesté par le soignant'` (l.61, l.190) n'est jamais envoyé (TJ7) ; le motif est borné à 500 scalaires Unicode,
///   borne du serveur après `btrim` (`char_length`) ;
/// - lecture bornée au délai de la session, epoch vérifié avant toute publication ; une annulation n'est jamais une erreur.
@MainActor
public final class PaiementsDeclaresModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case pret([PaiementDeclare])
        case echec(String)
    }

    /// Issue de la dernière mutation, affichée en encart (`paiement-confirme`, `paiement-conteste`, `paiement-erreur`).
    public enum Issue: Equatable, Sendable {
        case confirme
        case conteste
        case erreur(String)
    }

    /// `maxLength={500}` du web (l.58) et borne serveur (`char_length(v_motif) > 500`, l.25760 du dump).
    nonisolated public static let longueurMaxMotif = 500
    /// Même borne de fraîcheur que l'onglet (`RevenusModel.delaiRelecture`).
    public static let delaiRelecture: TimeInterval = RevenusModel.delaiRelecture

    @Published public private(set) var etat: Etat = .chargement
    /// Identifiant du paiement en cours de traitement (une seule mutation à la fois).
    @Published public private(set) var enCours: String?
    /// Carte dépliée (`expanded`, l.84).
    @Published public private(set) var deplie: String?
    /// Carte dont le formulaire de contestation est ouvert (`contesting`, l.85).
    @Published public private(set) var contestation: String?
    @Published public private(set) var motif = ""
    @Published public private(set) var issue: Issue?
    /// Jeton d'annonce de l'issue (une même issue répétée est réannoncée).
    @Published public private(set) var numeroIssue = 0
    /// Avance après chaque mutation terminée (succès, refus ou erreur) : l'onglet relit ses missions.
    @Published public private(set) var miseAJour = 0

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var generation = 0
    private var luLe: Date?
    private var peremptionVue = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    // MARK: - Présentation

    public var cartes: [CartePaiementDeclare] {
        guard case let .pret(lignes) = etat else { return [] }
        return lignes.map(PaiementsDeclaresPresentation.carte)
    }

    /// Section rendue : erreur de lecture, au moins une carte, ou l'issue d'une mutation (même si la liste est vide).
    /// Le web ne rend rien pendant le chargement ni sans paiement (`return null`, l.216).
    public var afficheSection: Bool {
        switch etat {
        case .echec: return true
        case .pret(let lignes): return !lignes.isEmpty || issue != nil
        case .chargement: return issue != nil
        }
    }

    /// « Envoyer la contestation » : motif non blanc (`!motif.trim()`), aucune mutation en cours.
    public var peutEnvoyerContestation: Bool {
        enCours == nil && contestation != nil && !motif.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Lecture

    /// Apparition de l'onglet : lit si jamais lu, si la lecture date de plus de `delaiRelecture`, ou si le jeton de
    /// péremption avance (lien universel ou tap qui présente l'onglet). Un échec attend « Réessayer ».
    public func chargerSiNecessaire(peremption: Int? = nil) async {
        if let peremption, peremption != peremptionVue {
            peremptionVue = peremption
            luLe = nil
        }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        switch etat {
        case .echec: return
        case .chargement: break
        case .pret:
            if let luLe, gateways.clock.now().timeIntervalSince(luLe) <= Self.delaiRelecture { return }
        }
        await lire()
    }

    /// Tirer pour actualiser, « Réessayer ».
    public func charger() async {
        if case .echec = etat { etat = .chargement }
        await lire()
    }

    // MARK: - Interactions

    /// Déplie ou replie une carte (`setExpanded(isExpanded ? null : p.id)`, l.246).
    public func basculer(_ id: String) {
        deplie = deplie == id ? nil : id
    }

    /// « Contester » ouvre ou ferme le formulaire de la carte (`setContesting(isContesting ? null : p.id)`, l.402) ;
    /// un nouveau formulaire part d'un motif vide (`useState('')`, l.48).
    public func basculerContestation(_ id: String) {
        guard enCours == nil else { return }
        if contestation == id {
            contestation = nil
        } else {
            contestation = id
            motif = ""
        }
    }

    /// « Annuler » (`onCancel`, l.64).
    public func annulerContestation() {
        guard enCours == nil else { return }
        contestation = nil
        motif = ""
    }

    public func saisirMotif(_ texte: String) {
        motif = Self.limiter(texte)
    }

    /// Motif borné à `longueurMaxMotif` scalaires Unicode (le serveur compte `char_length` après `btrim` : une saisie
    /// dans la borne l'est toujours côté serveur).
    nonisolated public static func limiter(_ texte: String) -> String {
        guard texte.unicodeScalars.count > longueurMaxMotif else { return texte }
        var scalaires = String.UnicodeScalarView()
        scalaires.append(contentsOf: texte.unicodeScalars.prefix(longueurMaxMotif))
        return String(scalaires)
    }

    /// « Confirmer la réception » (`traiter(p.id, true)`, l.391).
    public func confirmer(_ id: String) async {
        await muter(id) { port, context in try await port.confirmer(id: id, context: context) }
    }

    /// « Envoyer la contestation » (`traiter(p.id, false, motif)`, l.414) : jamais sans motif non blanc.
    public func envoyerContestation() async {
        guard peutEnvoyerContestation, let id = contestation else { return }
        let motif = self.motif
        await muter(id) { port, context in try await port.contester(id: id, motif: motif, context: context) }
    }

    // MARK: - Interne

    private func muter(_ id: String,
                       _ appel: @escaping @Sendable (PaiementsDeclaresPort, MissionReadContext) async throws -> IssuePaiement) async {
        guard enCours == nil else { return }
        enCours = id
        issue = nil
        defer { enCours = nil }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.paiements
        let context = snapshot.context
        do {
            let resultat = try await bounded(timeout: controller.resolutionTimeout) { try await appel(port, context) }
            guard await memeEpoch() else { return }
            switch resultat {
            case .confirme:
                publier(.confirme)
            case .conteste:
                publier(.conteste)
                contestation = nil
                motif = ""
            case .refuse(let message):
                publier(.erreur(message))
            }
        } catch {
            guard await memeEpoch() else { return }
            if let message = message(error, defaut: PaiementsDeclaresTextes.erreurTraitement) {
                publier(.erreur(message))
            }
        }
        // Relecture après toute issue (un délai dépassé ne prouve pas que le serveur n'a pas agi) ; jamais un renvoi.
        await lire()
        miseAJour += 1
    }

    private func lire() async {
        generation += 1
        let courant = generation
        guard let gateways = await controller.gateways(for: snapshot.epoch), generation == courant else { return }
        let port = gateways.paiements
        let context = snapshot.context
        do {
            let lus = try await bounded(timeout: controller.resolutionTimeout) { try await port.aConfirmer(context: context) }
            guard await memeEpoch(), generation == courant else { return }
            etat = .pret(lus)
            luLe = gateways.clock.now()
            if let deplie, !lus.contains(where: { $0.id == deplie }) { self.deplie = nil }
            if let ouverte = contestation, !lus.contains(where: { $0.id == ouverte }) {
                contestation = nil
                motif = ""
            }
        } catch {
            guard await memeEpoch(), generation == courant,
                  let message = message(error, defaut: PaiementsDeclaresTextes.erreurChargement) else { return }
            etat = .echec(message)
        }
    }

    private func publier(_ nouvelle: Issue) {
        issue = nouvelle
        numeroIssue += 1
    }

    private func memeEpoch() async -> Bool { await controller.epoch == snapshot.epoch }

    /// Message affiché d'une erreur ; nil pour une annulation (la vue a disparu : rien à afficher).
    private func message(_ error: Error, defaut: String) -> String? {
        if error is CancellationError { return nil }
        guard let jolene = error as? JoleneError else { return defaut }
        return jolene.kind == .cancelled ? nil : jolene.message
    }
}
