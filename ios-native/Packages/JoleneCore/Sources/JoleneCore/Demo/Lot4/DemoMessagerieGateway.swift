import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « messagerie » (`Gateways.messagerie`), T7a : `DemoMessagerieGateway`, dont les canaux
    /// simulés (`diffusion`) sont aussi ceux du port Realtime démo du même monde (`DemoLot4.realtime`).
    static func messagerie() -> MessageriePort { DemoMessagerieGateway() }
}

extension DemoFixtures {
    /// Conversation démo : ligne de `fn_lister_conversations_messagerie` sans ses colonnes dérivées des messages, et
    /// statut de la mission liée (`mission_statut`, propre à la démo, lu par l'anti-fuite simulé).
    public struct ConversationDemo: Decodable, Equatable, Sendable {
        public var apercu: ConversationApercu
        public var missionStatut: String?

        enum CodingKeys: String, CodingKey { case missionStatut = "mission_statut" }

        public init(apercu: ConversationApercu, missionStatut: String?) {
            self.apercu = apercu; self.missionStatut = missionStatut
        }

        public init(from decoder: Decoder) throws {
            apercu = try ConversationApercu(from: decoder)
            missionStatut = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .missionStatut)
        }
    }

    /// Interlocuteur opérationnel d'un établissement démo (réponse simulée de `fn_user_id_pour_etablissement`).
    public struct EtablissementMessagerieDemo: Decodable, Equatable, Sendable {
        public var id: String
        public var nom: String
        public var interlocuteurId: String
        enum CodingKeys: String, CodingKey { case id, nom, interlocuteurId = "interlocuteur_id" }
    }

    /// `demo-conversations.json` (`scripts/mobile/demo-fixtures/messagerie.mjs`).
    public struct ConversationsFile: Decodable, Sendable {
        public var fixedNow: String
        public var conversations: [ConversationDemo]
        public var interlocuteurs: [Interlocuteur]
        public var etablissements: [EtablissementMessagerieDemo]
        public var presences: [LignePresence]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", conversations, interlocuteurs, etablissements, presences }
    }

    /// `demo-messages.json` : lignes de `messages_chat` et réponse de l'établissement démo.
    public struct MessagesFile: Decodable, Sendable {
        public struct Reponse: Decodable, Equatable, Sendable { public var contenu: String }
        public var fixedNow: String
        public var messages: [MessageChat]
        public var reponseDemo: Reponse
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", messages, reponseDemo = "reponse_demo" }
    }

    public static func loadConversations() throws -> ConversationsFile { try load("demo-conversations") }
    public static func loadMessages() throws -> MessagesFile { try load("demo-messages") }
}

/// Messagerie du monde démo (lot 4, T7a ; `LOT4_PLAN.md` §2.7) : aucun réseau, horloge fixée, état en mémoire pour la
/// session démo (rien n'est persisté). Mêmes contrôles que le serveur, dans le même ordre :
/// - liste : colonnes dérivées (`dernier_contenu`, `dernier_message_le`, `non_lus`, `ordre_le`) calculées depuis les
///   messages, comme `fn_lister_conversations_messagerie` ; tri `(ordre_le, id)` décroissant, curseur keyset, pages de
///   100 ; plus de 100 identifiants d'interlocuteurs → défaut de contrat (22023 du serveur) ;
/// - envoi (edge `messagerie-validate`) : contenu trop long, vide, conversation inconnue, archivée, puis anti-fuite —
///   seuls les numéros de téléphone sont simulés (motifs de `_shared/anti-leak.ts`), et, comme l'edge, ils ne bloquent
///   plus dès que la mission liée est `ASSIGNEE`, `EN_COURS` ou `TERMINEE` ; interlocuteur bloqué → `ENVOI_REFUSE` ;
///   sinon le message est inséré et son `message_id` rendu ;
/// - réponse démo : à la relecture d'un message envoyé (`message(id:)`) dans une conversation d'établissement,
///   l'établissement « écrit » puis sa réponse est émise sur le flux entrant (une seconde après le message) : elle
///   prouve l'affichage d'un INSERT reçu, jamais l'envoi ;
/// - lecture : `marquerLus` passe à lus les messages des autres participants (conversation inconnue → `accesRefuse`) ;
///   `nonLus` les compte hors conversations archivées, comme `fn_messages_non_lus` ;
/// - blocage, signalement et « Écrire à l'établissement » : mêmes refus que les RPC, messages verbatim.
/// Refuse tout contexte qui n'est pas celui du profil fictif (`.demoOnly`).
public actor DemoMessagerieGateway: MessageriePort {
    // Refus serveur repris mot pour mot (`supabase/schema/public.sql`).
    public static let cibleInvalide = "Cible invalide."                                  // fn_bloquer_utilisateur
    public static let categorieInvalide = "Catégorie invalide"                           // fn_signaler_utilisateur
    public static let motifObligatoire = "Motif obligatoire (10 caractères minimum)."    // fn_signaler_utilisateur
    public static let autoSignalement = "Vous ne pouvez pas vous signaler vous-même."    // fn_signaler_utilisateur
    public static let nonAutorise = "Non autorisé"                                       // fn_user_id_pour_etablissement
    /// Statuts de mission qui lèvent l'anti-fuite (`messagerie-validate`).
    public static let statutsCoordonneesAdmises: Set<String> = ["ASSIGNEE", "EN_COURS", "TERMINEE"]

    /// Canaux simulés, partagés avec `DemoRealtimeGateway`.
    public nonisolated let diffusion: DemoDiffusionMessagerie

    private let clock: any ClockPort
    private var charge = false
    private var conversationsDemo: [DemoFixtures.ConversationDemo] = []
    private var messagesDemo: [MessageChat] = []
    private var interlocuteursDemo: [Interlocuteur] = []
    private var etablissements: [DemoFixtures.EtablissementMessagerieDemo] = []
    private var reponseDemo = ""
    private var bloques: Set<String> = []
    private var envois = 0
    /// Messages envoyés dont la relecture déclenchera la réponse de l'établissement démo.
    private var reponsesAttendues: Set<String> = []
    public private(set) var signalements = 0
    public private(set) var battements = 0
    public private(set) var saisiesSignalees = 0

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), diffusion: DemoDiffusionMessagerie = DemoDiffusionMessagerie()) {
        self.clock = clock
        self.diffusion = diffusion
    }

    private var moi: String { DemoWorld.context.userId }

    // MARK: - Liste

    public func conversations(avant: CurseurConversations?, context: MissionReadContext) async throws -> PageConversations {
        try charger(context)
        var lignes = conversationsDemo.map(apercu).sorted { a, b in
            (a.ordreLe ?? "", a.id) > (b.ordreLe ?? "", b.id)
        }
        if let avant { lignes = lignes.filter { ($0.ordreLe ?? "", $0.id) < (avant.ordreLe, avant.id) } }
        let page = Array(lignes.prefix(PageConversations.taille))
        let suivant = page.count == PageConversations.taille ? page.last?.curseur : nil
        return PageConversations(conversations: page, suivant: suivant == avant ? nil : suivant)
    }

    public func interlocuteurs(ids: [String], context: MissionReadContext) async throws -> [Interlocuteur] {
        try charger(context)
        guard ids.count <= Interlocuteur.lotMax else { throw JoleneError(.contract, MessagerieRepli.message) }
        return interlocuteursDemo.filter { ids.contains($0.conversationId) }
    }

    // MARK: - Fil

    public func messages(conversationId: String, context: MissionReadContext) async throws -> [MessageChat] {
        try charger(context)
        return Array(fil(conversationId).suffix(FilMessages.limite))
    }

    public func messages(conversationId: String, depuis: String, context: MissionReadContext) async throws -> [MessageChat] {
        try charger(context)
        return Array(fil(conversationId).filter { FilMessages.pasAvant($0, depuis) }.suffix(FilMessages.limite))
    }

    public func envoyer(conversationId: String, contenu: String, context: MissionReadContext) async throws -> EnvoiOutcome {
        try charger(context)
        guard contenu.count <= CodeEnvoi.longueurMax else { return refus(CodeEnvoi.contenuTropLong) }
        guard !contenu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return refus(CodeEnvoi.contenuVide) }
        guard let conversation = conversationsDemo.first(where: { $0.apercu.id == conversationId }) else {
            return refus(CodeEnvoi.conversationNonAutorisee)
        }
        guard !conversation.apercu.archivee else { return refus(CodeEnvoi.conversationArchivee) }
        if Self.contientTelephone(contenu), !Self.statutsCoordonneesAdmises.contains(conversation.missionStatut ?? "") {
            return .antiFuite(.telephone)
        }
        if let autre = conversation.apercu.autreId, bloques.contains(autre) { return refus(CodeEnvoi.envoiRefuse) }
        envois += 1
        let id = "demo-message-envoi-\(envois)"
        messagesDemo.append(MessageChat(id: id, conversationId: conversationId, auteurId: moi, contenu: contenu,
                                        creeLe: horodatage(decalage: Double(envois) * 2), estAdmin: false, lu: false))
        if conversation.apercu.etablissementId != nil { reponsesAttendues.insert(id) }
        return .envoye(messageId: id)
    }

    public func message(id: String, conversationId: String, context: MissionReadContext) async throws -> MessageChat? {
        try charger(context)
        let relu = messagesDemo.first { $0.id == id && $0.conversationId == conversationId }
        if relu != nil, reponsesAttendues.remove(id) != nil { repondre(conversationId) }
        return relu
    }

    public func marquerLus(conversationId: String, context: MissionReadContext) async throws -> IssueLecture {
        try charger(context)
        guard conversationsDemo.contains(where: { $0.apercu.id == conversationId }) else { return .accesRefuse }
        for index in messagesDemo.indices where messagesDemo[index].conversationId == conversationId
            && FilMessages.estEntrant(messagesDemo[index], moi: moi) {
            messagesDemo[index].lu = true
        }
        return .lus
    }

    public func saisie(debut: Bool, conversationId: String, context: MissionReadContext) async throws {
        try charger(context)
        // `fn_typing_start` refuse une conversation inaccessible (42501 `NON_AUTORISE`) : indicateur abandonné.
        guard conversationsDemo.contains(where: { $0.apercu.id == conversationId }) else { return }
        saisiesSignalees += 1
    }

    public func presence(context: MissionReadContext) async throws {
        try charger(context)
        battements += 1
    }

    public func nonLus(context: MissionReadContext) async throws -> Int {
        try charger(context)
        let actives = Set(conversationsDemo.filter { !$0.apercu.archivee }.map(\.apercu.id))
        return messagesDemo.filter { actives.contains($0.conversationId) && !$0.lu && FilMessages.estEntrant($0, moi: moi) }.count
    }

    // MARK: - Blocage et signalement

    public func bloque(cibleId: String, context: MissionReadContext) async throws -> Bool {
        try charger(context)
        return bloques.contains(cibleId)
    }

    public func basculerBlocage(cibleId: String, bloquer: Bool, context: MissionReadContext) async throws -> Bool {
        try charger(context)
        if bloquer {
            guard !cibleId.isEmpty, cibleId != moi else { throw JoleneError(.unknown, Self.cibleInvalide) }
            bloques.insert(cibleId)
        } else {
            bloques.remove(cibleId)
        }
        return bloques.contains(cibleId)
    }

    public func signaler(cibleId: String, type: TypeCibleSignalement, categorie: String, motif: String, missionId: String?,
                         context: MissionReadContext) async throws -> IssueSignalement {
        try charger(context)
        guard SignalementUtilisateur.categories.contains(categorie) else { return .refuse(message: Self.categorieInvalide) }
        guard motif.trimmingCharacters(in: .whitespacesAndNewlines).count >= SignalementUtilisateur.longueurMotifMin else {
            return .refuse(message: Self.motifObligatoire)
        }
        guard cibleId != moi else { return .refuse(message: Self.autoSignalement) }
        signalements += 1
        return .signale
    }

    // MARK: - « Écrire à l'établissement »

    public func conversationPourMission(missionId: String, etablissementId: String,
                                        context: MissionReadContext) async throws -> IssueConversationMission {
        try charger(context)
        guard let etablissement = etablissements.first(where: { $0.id == etablissementId }) else {
            return .indisponible(message: Self.nonAutorise)
        }
        if let existante = conversationsDemo.first(where: { $0.apercu.missionId == missionId && $0.apercu.etablissementId == etablissementId }) {
            return .conversation(id: existante.apercu.id)
        }
        // `fn_obtenir_conversation` : fil de la mission créé à la demande (mission attribuée : coordonnées admises).
        let id = "demo-conv-mission-\(missionId)"
        let intitule = (try? DemoFixtures.loadMissions().missions.first { $0.record.id == missionId })?.record.intitule
        let apercu = ConversationApercu(id: id, autreId: etablissement.interlocuteurId, missionId: missionId,
                                        etablissementId: etablissementId, participant1Id: moi,
                                        participant2Id: etablissement.interlocuteurId, soignantId: moi,
                                        creeLe: horodatage(decalage: 0), missionIntitule: intitule)
        conversationsDemo.append(DemoFixtures.ConversationDemo(apercu: apercu, missionStatut: "ASSIGNEE"))
        interlocuteursDemo.append(Interlocuteur(conversationId: id, participantId: etablissement.interlocuteurId,
                                                prenom: etablissement.nom, nom: nil))
        return .conversation(id: id)
    }

    // MARK: - Interne

    /// Motifs de téléphone de `detecterLeak` (`supabase/functions/_shared/anti-leak.ts`) ; les autres types (email,
    /// URL, pseudonyme, mot-clé) ne sont pas simulés en démo.
    static func contientTelephone(_ contenu: String) -> Bool {
        let motifs = [#"(?:(?:\+|00)33|0)\s*[1-9](?:[\s.-]*\d{2}){4}"#, #"\b(?:08\d{2}|36\d{2}|39\d{2})[\s.-]?\d{0,6}"#]
        return motifs.contains { contenu.range(of: $0, options: .regularExpression) != nil }
    }

    private func refus(_ code: String) -> EnvoiOutcome { .refuse(code: code, message: MessagerieRepli.message) }

    private func fil(_ conversationId: String) -> [MessageChat] {
        FilMessages.fusionner([], messagesDemo.filter { $0.conversationId == conversationId }, conversationId: conversationId)
    }

    /// Colonnes dérivées des messages, comme le SQL de la liste.
    private func apercu(_ conversation: DemoFixtures.ConversationDemo) -> ConversationApercu {
        var ligne = conversation.apercu
        let messages = fil(ligne.id)
        ligne.dernierContenu = messages.last?.contenu
        ligne.dernierMessageLe = messages.last?.creeLe
        ligne.nonLus = messages.filter { !$0.lu && FilMessages.estEntrant($0, moi: ligne.soignantId ?? moi) }.count
        ligne.ordreLe = ligne.dernierMessageLe ?? ligne.creeLe
        return ligne
    }

    private func horodatage(decalage: TimeInterval) -> String {
        DateHeureParis.isoUTC(clock.now().addingTimeInterval(decalage))
    }

    /// Réponse de l'établissement démo : saisie signalée, message inséré une seconde après le dernier du fil, puis
    /// émis sur le flux entrant (fil et liste).
    private func repondre(_ conversationId: String) {
        guard let conversation = conversationsDemo.first(where: { $0.apercu.id == conversationId }),
              let autre = conversation.apercu.autreId, !bloques.contains(autre) else { return }
        let dernier = fil(conversationId).last?.instant ?? clock.now()
        let reponse = MessageChat(id: "demo-message-reponse-\(envois)", conversationId: conversationId, auteurId: autre,
                                  contenu: reponseDemo, creeLe: DateHeureParis.isoUTC(dernier.addingTimeInterval(1)),
                                  estAdmin: false, lu: false)
        messagesDemo.append(reponse)
        diffusion.emettre(saisie: EtatSaisie(userId: autre, enTrain: true), conversationId: conversationId)
        diffusion.emettre(reponse)
        diffusion.emettre(saisie: EtatSaisie(userId: autre, enTrain: false), conversationId: conversationId)
    }

    /// Contexte du profil fictif exigé, puis fixtures lues une fois.
    private func charger(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        guard !charge else { return }
        let conversations = try DemoFixtures.loadConversations()
        let messages = try DemoFixtures.loadMessages()
        conversationsDemo = conversations.conversations
        interlocuteursDemo = conversations.interlocuteurs
        etablissements = conversations.etablissements
        messagesDemo = messages.messages
        reponseDemo = messages.reponseDemo.contenu
        charge = true
        for presence in conversations.presences {
            guard let userId = presence.userId else { continue }
            diffusion.emettre(presence: presence.etat(userId: userId))
        }
    }
}
