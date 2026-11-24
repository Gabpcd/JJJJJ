import Foundation
import JoleneCore
import Supabase

// Realtime de la messagerie (lot 4, T7a ; `docs/mobile-swift/LOT4_PLAN.md` §2.5, fiche « Realtime : tables, RLS,
// filtres, cycle de vie » de `CONTRATS_RPC_SOIGNANT.md`, décision D7). La passerelle ne connaît le SDK que par un
// transport minimal (`TransportRealtime`, `CanalRealtime`) : ses règles (flux déclarés avant l'abonnement, canal fermé
// par le serveur → nouveau canal, fermeture de tout) sont prouvées sur un transport simulé ; `TransportRealtimeSDK`
// est le seul code qui touche `client.realtimeV2`.

// MARK: - Transport

/// Changement d'une ligne reçu d'un canal `postgres_changes` (enregistrement brut ; pour une suppression, l'ancienne
/// ligne).
enum ChangementRealtime: Equatable, Sendable {
    case insertion(JSONObject)
    case miseAJour(JSONObject)
    case suppression(JSONObject)
}

enum StatutCanalRealtime: Equatable, Sendable {
    case desabonne, abonnement, abonne, desabonnement
}

/// Flux `postgres_changes` d'une table du schéma `public`, filtré par égalité sur une colonne ou non filtré (la RLS
/// reste le seul filtre d'accès).
struct FluxRealtime: Equatable, Sendable {
    enum Evenements: String, Equatable, Sendable { case insertions, tous }

    var evenements: Evenements
    var table: String
    var colonne: String?
    var valeur: String?

    init(_ evenements: Evenements, table: String, colonne: String? = nil, valeur: String? = nil) {
        self.evenements = evenements; self.table = table; self.colonne = colonne; self.valeur = valeur
    }
}

/// Canal Realtime : les flux se déclarent AVANT `abonner()` (exigence du SDK, `RealtimeChannelV2.subscribeWithError`).
protocol CanalRealtime: AnyObject, Sendable {
    func declarer(_ flux: FluxRealtime) -> AsyncStream<ChangementRealtime>
    func abonner() async throws
    var statut: StatutCanalRealtime { get }
    /// Statut courant d'abord, puis chaque changement.
    func statuts() -> AsyncStream<StatutCanalRealtime>
}

protocol TransportRealtime: Sendable {
    /// Identifiant de l'utilisateur de la session (sujet du canal de la liste) ; `nil` sans session.
    func utilisateur() -> String?
    /// Canal neuf pour ce sujet, pas encore abonné.
    func canal(_ sujet: String) -> any CanalRealtime
    /// Faux quand le client ne connaît plus ce canal : retiré, ou fermé par le serveur — il ne rejoindra plus jamais.
    func estEnregistre(_ canal: any CanalRealtime) -> Bool
    func retirer(_ canal: any CanalRealtime) async
    func retirerTout() async
    /// Lecture PostgREST d'une ligne par égalité (état initial d'une présence) ; `nil` si absente ou illisible.
    func ligne(table: String, colonnes: String, colonne: String, valeur: String) async -> JSONObject?
}

// MARK: - Passerelle

/// `RealtimePort` sur Supabase.
/// - Canaux, comme le web : `messagerie-liste-<uid>` (INSERT `messages_chat`, sans filtre : la RLS `pol_msg_select` ne
///   laisse passer que les messages visibles par le JWT), `chat-conv-<id>` (INSERT filtré `conversation_id=eq.<id>`),
///   `typing-<id>` (tous changements de `typing_status`), `presence-<autre>` (tous changements de `presence_status`).
///   Aucun abonnement `conversations` (absente de la publication, D7).
/// - Un canal par sujet, partagé entre ses lecteurs ; ouvert au premier flux demandé, retiré quand son dernier lecteur
///   part. Ordre : canal créé → flux déclarés → `abonner()` → `.rejoint` → relais des changements.
/// - État d'un canal de messages : `.connexion`, `.rejoint` (abonnement confirmé, ou rejoint par le SDK après une
///   reconnexion), `.coupe`, `.ferme` (`fermerTout()`). `etat(conversationId:)` rend le dernier état connu d'abord.
/// - Canal fermé par le serveur (le client ne le connaît plus) ou resté désabonné trop longtemps : il ne rejoindrait
///   plus jamais, il est remplacé par un canal neuf, flux redéclarés avant l'abonnement ; les lecteurs gardent leurs
///   flux et relisent sur `.rejoint`. Un abonnement en échec est repris, sans limite tant qu'un lecteur écoute, à
///   intervalles croissants.
/// - Présence : la ligne courante est lue après chaque abonnement (lecture initiale du web), puis les changements ;
///   une suppression vaut hors ligne. Saisie : INSERT / UPDATE = en train, DELETE = arrêt (la lecture initiale du web
///   n'est pas portée : l'indicateur suit le prochain changement, au plus 2 s plus tard tant que l'autre écrit).
/// - `fermerTout()` : `removeAllChannels()`, tous les flux se terminent ; rien n'est gardé pour l'arrière-plan.
/// - Un flux n'est jamais une preuve d'envoi : une ligne illisible est ignorée, jamais complétée.
///
/// `@unchecked Sendable` : tout l'état mutable est protégé par `verrou`, dans des sections synchrones.
public final class SupabaseRealtimeGateway: RealtimePort, @unchecked Sendable {
    public static let tableMessages = "messages_chat"
    public static let tableSaisies = "typing_status"
    public static let tablePresences = "presence_status"
    static let colonnesPresence = "user_id,status,last_seen_at"

    public static func sujetListe(_ userId: String) -> String { "messagerie-liste-\(userId)" }
    public static func sujetFil(_ conversationId: String) -> String { "chat-conv-\(conversationId)" }
    public static func sujetSaisies(_ conversationId: String) -> String { "typing-\(conversationId)" }
    public static func sujetPresence(_ userId: String) -> String { "presence-\(userId)" }

    /// Délais de surveillance d'un canal.
    struct Reglages: Sendable {
        /// Période du contrôle d'un canal abonné (fermé par le serveur ? désabonné depuis trop longtemps ?).
        var surveillance: TimeInterval = 5
        /// Durée désabonné au-delà de laquelle le canal est remplacé (le SDK rejoint de lui-même après une
        /// reconnexion : délai de reconnexion de 7 s puis abonnement borné à 10 s).
        var sansRejoint: TimeInterval = 30
        /// Attentes successives avant de reprendre un abonnement en échec ; la dernière est répétée.
        var reprises: [TimeInterval] = [2, 5, 15, 30]
    }

    private final class Abonnement: @unchecked Sendable {
        let sujet: String
        let flux: [FluxRealtime]
        let messages: Bool
        let initiale: (@Sendable () async -> ChangementRealtime?)?
        let changements = DiffusionEvenements<ChangementRealtime>()
        var lecteurs = 0
        var tache: Task<Void, Never>?
        var canal: (any CanalRealtime)?

        init(sujet: String, flux: [FluxRealtime], messages: Bool, initiale: (@Sendable () async -> ChangementRealtime?)?) {
            self.sujet = sujet; self.flux = flux; self.messages = messages; self.initiale = initiale
        }
    }

    private let transport: any TransportRealtime
    private let reglages: Reglages
    private let verrou = NSLock()
    private var abonnements: [String: Abonnement] = [:]
    private var etats: [String: DiffusionEtat<EtatCanal>] = [:]
    private var etatsGlobaux = DiffusionEvenements<EtatCanal>()

    public convenience init(client: SupabaseClient) {
        self.init(transport: TransportRealtimeSDK(client: client))
    }

    init(transport: any TransportRealtime, reglages: Reglages = Reglages()) {
        self.transport = transport
        self.reglages = reglages
    }

    // MARK: - RealtimePort

    public func messagesEntrants(conversationId: String?) -> AsyncStream<MessageChat> {
        guard let sujet = sujetMessages(conversationId) else { return AsyncStream { $0.finish() } }
        let flux = conversationId.map { FluxRealtime(.insertions, table: Self.tableMessages, colonne: "conversation_id", valeur: $0) }
            ?? FluxRealtime(.insertions, table: Self.tableMessages)
        return lire(sujet: sujet, flux: [flux], messages: true) { changement in
            guard case .insertion(let ligne) = changement else { return nil }
            return Self.decoder(MessageChat.self, ligne)
        }
    }

    public func saisies(conversationId: String) -> AsyncStream<EtatSaisie> {
        let flux = FluxRealtime(.tous, table: Self.tableSaisies, colonne: "conversation_id", valeur: conversationId)
        return lire(sujet: Self.sujetSaisies(conversationId), flux: [flux], messages: false) { changement in
            switch changement {
            case .insertion(let ligne), .miseAJour(let ligne):
                return Self.decoder(LigneSaisie.self, ligne).map { EtatSaisie(userId: $0.userId, enTrain: true) }
            case .suppression(let ancienne):
                return Self.decoder(LigneSaisie.self, ancienne).map { EtatSaisie(userId: $0.userId, enTrain: false) }
            }
        }
    }

    public func presence(userId: String) -> AsyncStream<EtatPresence> {
        let flux = FluxRealtime(.tous, table: Self.tablePresences, colonne: "user_id", valeur: userId)
        let transport = self.transport
        let initiale: @Sendable () async -> ChangementRealtime? = {
            await transport.ligne(table: Self.tablePresences, colonnes: Self.colonnesPresence, colonne: "user_id", valeur: userId)
                .map { ChangementRealtime.miseAJour($0) }
        }
        return lire(sujet: Self.sujetPresence(userId), flux: [flux], messages: false, initiale: initiale) { changement in
            switch changement {
            case .insertion(let ligne), .miseAJour(let ligne):
                return Self.decoder(LignePresence.self, ligne)?.etat(userId: userId)
            case .suppression:
                return EtatPresence(userId: userId, statut: .horsLigne, vuLe: nil)
            }
        }
    }

    public func etat() -> AsyncStream<EtatCanal> {
        verrou.withLock { etatsGlobaux }.flux()
    }

    public func etat(conversationId: String?) -> AsyncStream<EtatCanal> {
        guard let sujet = sujetMessages(conversationId) else { return AsyncStream { $0.finish() } }
        return diffusionEtat(sujet).flux()
    }

    public func fermerTout() async {
        let (anciens, etatsFermes, globaux) = verrou.withLock {
            let tout = (Array(abonnements.values), Array(etats.values), etatsGlobaux)
            abonnements = [:]
            etats = [:]
            etatsGlobaux = DiffusionEvenements()
            return tout
        }
        for ancien in anciens { tache(ancien)?.cancel() }
        await transport.retirerTout()
        for ancien in anciens { ancien.changements.terminer() }
        for etat in etatsFermes {
            etat.recevoir(.ferme)
            etat.terminer()
        }
        globaux.terminer()
    }

    // MARK: - Lecteurs

    private func sujetMessages(_ conversationId: String?) -> String? {
        if let conversationId { return Self.sujetFil(conversationId) }
        return transport.utilisateur().map(Self.sujetListe)
    }

    private func diffusionEtat(_ sujet: String) -> DiffusionEtat<EtatCanal> {
        verrou.withLock {
            if let existante = etats[sujet] { return existante }
            let nouvelle = DiffusionEtat<EtatCanal>()
            etats[sujet] = nouvelle
            return nouvelle
        }
    }

    /// Flux d'un lecteur sur le canal du sujet, ouvert s'il ne l'est pas. Le lecteur est compté dès maintenant ; quand
    /// le dernier part, le canal est retiré.
    private func lire<Valeur: Sendable>(sujet: String, flux: [FluxRealtime], messages: Bool,
                                        initiale: (@Sendable () async -> ChangementRealtime?)? = nil,
                                        _ traduire: @escaping @Sendable (ChangementRealtime) -> Valeur?) -> AsyncStream<Valeur> {
        let (abonnement, source) = verrou.withLock { () -> (Abonnement, AsyncStream<ChangementRealtime>) in
            let abonnement: Abonnement
            if let existant = abonnements[sujet] {
                abonnement = existant
            } else {
                abonnement = Abonnement(sujet: sujet, flux: flux, messages: messages, initiale: initiale)
                abonnements[sujet] = abonnement
                abonnement.tache = Task { [weak self] in await self?.tenir(abonnement) }
            }
            abonnement.lecteurs += 1
            return (abonnement, abonnement.changements.flux())
        }
        return AsyncStream { suite in
            let relais = Task {
                for await changement in source {
                    if let valeur = traduire(changement) { suite.yield(valeur) }
                }
                suite.finish()
            }
            suite.onTermination = { [weak self] _ in
                relais.cancel()
                self?.lecteurParti(abonnement)
            }
        }
    }

    private func lecteurParti(_ abonnement: Abonnement) {
        let aRetirer = verrou.withLock { () -> (Task<Void, Never>?, (any CanalRealtime)?)? in
            abonnement.lecteurs -= 1
            // Déjà remplacé ou fermé (`fermerTout`), ou encore écouté : rien à retirer.
            guard abonnement.lecteurs <= 0, abonnements[abonnement.sujet] === abonnement else { return nil }
            abonnements[abonnement.sujet] = nil
            return (abonnement.tache, abonnement.canal)
        }
        guard let (tache, canal) = aRetirer else { return }
        tache?.cancel()
        abonnement.changements.terminer()
        publier(.ferme, abonnement)
        if let canal {
            let transport = self.transport
            Task { await transport.retirer(canal) }
        }
    }

    private func tache(_ abonnement: Abonnement) -> Task<Void, Never>? { verrou.withLock { abonnement.tache } }

    private func actif(_ abonnement: Abonnement) -> Bool {
        !Task.isCancelled && verrou.withLock { abonnements[abonnement.sujet] === abonnement }
    }

    private func publier(_ etat: EtatCanal, _ abonnement: Abonnement) {
        guard abonnement.messages else { return }
        diffusionEtat(abonnement.sujet).recevoir(etat)
        verrou.withLock { etatsGlobaux }.emettre(etat)
    }

    // MARK: - Vie d'un canal

    /// Tient le canal du sujet abonné tant que l'abonnement est actif : canal → flux déclarés → abonnement → relais ;
    /// un canal perdu est remplacé.
    private func tenir(_ abonnement: Abonnement) async {
        var echecs = 0
        while actif(abonnement) {
            let canal = transport.canal(abonnement.sujet)
            verrou.withLock { abonnement.canal = canal }
            let sources = abonnement.flux.map { canal.declarer($0) } // avant `abonner()`
            publier(.connexion, abonnement)
            do {
                try await canal.abonner()
            } catch {
                guard actif(abonnement) else { break }
                publier(.coupe, abonnement)
                await transport.retirer(canal)
                await Self.attendre(reglages.reprises.isEmpty ? 0 : reglages.reprises[min(echecs, reglages.reprises.count - 1)])
                echecs += 1
                continue
            }
            guard actif(abonnement) else {
                await transport.retirer(canal)
                break
            }
            echecs = 0
            publier(.rejoint, abonnement)
            if let initiale = abonnement.initiale, let changement = await initiale() { abonnement.changements.emettre(changement) }
            let perdu = await relayer(sources, canal, abonnement)
            guard perdu, actif(abonnement) else { break }
            // Fermé par le serveur ou resté désabonné : ce canal ne rejoindra plus, un canal neuf le remplace.
            await transport.retirer(canal)
        }
    }

    private enum Fin { case fluxTermine, canalPerdu }

    /// Relaie les changements et suit le statut du canal. Vrai : le canal est perdu et doit être remplacé.
    private func relayer(_ sources: [AsyncStream<ChangementRealtime>], _ canal: any CanalRealtime, _ abonnement: Abonnement) async -> Bool {
        await withTaskGroup(of: Fin.self) { groupe in
            for source in sources {
                groupe.addTask {
                    for await changement in source { abonnement.changements.emettre(changement) }
                    return .fluxTermine
                }
            }
            // Statut : état publié sans attendre (coupé, puis rejoint quand le SDK se réabonne après une reconnexion).
            groupe.addTask { [weak self] in
                var abonne = true
                for await statut in canal.statuts() {
                    switch statut {
                    case .abonne:
                        if !abonne { self?.publier(.rejoint, abonnement) }
                        abonne = true
                    case .abonnement:
                        if !abonne { self?.publier(.connexion, abonnement) }
                    case .desabonne, .desabonnement:
                        if abonne { self?.publier(.coupe, abonnement) }
                        abonne = false
                    }
                }
                return .fluxTermine
            }
            // Surveillance : le SDK ne signale pas qu'un canal fermé par le serveur ne rejoindra plus.
            groupe.addTask { [reglages, transport] in
                var desabonneDepuis: TimeInterval = 0
                while !Task.isCancelled {
                    await Self.attendre(reglages.surveillance)
                    if Task.isCancelled { return .fluxTermine }
                    if !transport.estEnregistre(canal) { return .canalPerdu }
                    desabonneDepuis = canal.statut == .abonne ? 0 : desabonneDepuis + reglages.surveillance
                    if desabonneDepuis >= reglages.sansRejoint { return .canalPerdu }
                }
                return .fluxTermine
            }
            var perdu = false
            while let fin = await groupe.next() {
                if fin == .canalPerdu {
                    perdu = true
                    groupe.cancelAll()
                }
            }
            return perdu
        }
    }

    private static func attendre(_ secondes: TimeInterval) async {
        guard secondes > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(secondes * 1_000_000_000))
    }

    static func decoder<T: Decodable>(_ type: T.Type, _ objet: JSONObject) -> T? {
        guard let donnees = try? JSONEncoder().encode(objet) else { return nil }
        return try? JSONDecoder().decode(T.self, from: donnees)
    }
}

// MARK: - SDK

/// Canal du SDK (`RealtimeChannelV2`). `postgresChange` inscrit son rappel dès l'appel : `declarer` le fait avant de
/// rendre la main, donc avant tout `subscribeWithError()`. Schéma : celui par défaut du SDK (le schéma des tables
/// exposées), jamais redit ici.
final class CanalRealtimeSDK: CanalRealtime {
    let canal: RealtimeChannelV2

    init(_ canal: RealtimeChannelV2) { self.canal = canal }

    func declarer(_ flux: FluxRealtime) -> AsyncStream<ChangementRealtime> {
        var filtre: RealtimePostgresFilter?
        if let colonne = flux.colonne, let valeur = flux.valeur { filtre = .eq(colonne, value: valeur) }
        switch flux.evenements {
        case .insertions:
            let insertions = canal.postgresChange(InsertAction.self, table: flux.table, filter: filtre)
            return Self.relayer(insertions) { .insertion($0.record) }
        case .tous:
            let actions = canal.postgresChange(AnyAction.self, table: flux.table, filter: filtre)
            return Self.relayer(actions) { action in
                switch action {
                case .insert(let insertion): return .insertion(insertion.record)
                case .update(let miseAJour): return .miseAJour(miseAJour.record)
                case .delete(let suppression): return .suppression(suppression.oldRecord)
                }
            }
        }
    }

    func abonner() async throws { try await canal.subscribeWithError() }

    var statut: StatutCanalRealtime { Self.statut(canal.status) }

    func statuts() -> AsyncStream<StatutCanalRealtime> {
        Self.relayer(canal.statusChange) { Self.statut($0) }
    }

    static func statut(_ statut: RealtimeChannelStatus) -> StatutCanalRealtime {
        switch statut {
        case .unsubscribed: return .desabonne
        case .subscribing: return .abonnement
        case .subscribed: return .abonne
        case .unsubscribing: return .desabonnement
        }
    }

    private static func relayer<Source: Sendable, Valeur: Sendable>(_ source: AsyncStream<Source>,
                                                                    _ traduire: @escaping @Sendable (Source) -> Valeur) -> AsyncStream<Valeur> {
        AsyncStream { suite in
            let relais = Task {
                for await element in source { suite.yield(traduire(element)) }
                suite.finish()
            }
            suite.onTermination = { _ in relais.cancel() }
        }
    }
}

/// Transport sur `client.realtimeV2` (seul code de l'app qui touche au Realtime du SDK).
struct TransportRealtimeSDK: TransportRealtime {
    let client: SupabaseClient

    func utilisateur() -> String? { client.auth.currentUser?.id.uuidString.lowercased() }

    func canal(_ sujet: String) -> any CanalRealtime { CanalRealtimeSDK(client.realtimeV2.channel(sujet)) }

    func estEnregistre(_ canal: any CanalRealtime) -> Bool {
        guard let sdk = canal as? CanalRealtimeSDK else { return false }
        return client.realtimeV2.channels[sdk.canal.topic] === sdk.canal
    }

    func retirer(_ canal: any CanalRealtime) async {
        guard let sdk = canal as? CanalRealtimeSDK else { return }
        await client.realtimeV2.removeChannel(sdk.canal)
    }

    func retirerTout() async { await client.realtimeV2.removeAllChannels() }

    func ligne(table: String, colonnes: String, colonne: String, valeur: String) async -> JSONObject? {
        let lignes: AnyJSON? = try? await client.from(table).select(colonnes).eq(colonne, value: valeur).limit(1).execute().value
        return lignes?.arrayValue?.first?.objectValue
    }
}
