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
/// Lot 5 (T11) : le même acteur sert la messagerie de l'établissement démo (`demo-etab-messagerie.json`), avec un état
/// propre à cet espace et les mêmes règles ; l'auteur d'un message envoyé est l'utilisateur de la session
/// (`demo-etablissement`), jamais l'identifiant de l'établissement ; les non-lus comptent les messages du soignant de la
/// conversation (`fn_messages_non_lus`, branche d'équipe), si bien qu'un message d'un collègue n'en est pas un.
/// Refuse tout contexte qui n'est pas celui du profil fictif (`.demoOnly`) ou du compte établissement fictif.
public actor DemoMessagerieGateway: MessageriePort {
    // Refus serveur repris mot pour mot (`supabase/schema/public.sql`).
    public static let cibleInvalide = "Cible invalide."                                  // fn_bloquer_utilisateur
    public static let categorieInvalide = "Catégorie invalide"                           // fn_signaler_utilisateur
    public static let motifObligatoire = "Motif obligatoire (10 caractères minimum)."    // fn_signaler_utilisateur
    public static let autoSignalement = "Vous ne pouvez pas vous signaler vous-même."    // fn_signaler_utilisateur
    public static let nonAutorise = "Non autorisé"                                       // fn_user_id_pour_etablissement
    public static let conversationNonAutorisee = "Conversation non autorisée"            // fn_obtenir_conversation
    /// Statuts de mission qui lèvent l'anti-fuite (`messagerie-validate`).
    public static let statutsCoordonneesAdmises: Set<String> = ["ASSIGNEE", "EN_COURS", "TERMINEE"]

    /// Canaux simulés, partagés avec `DemoRealtimeGateway`.
    public nonisolated let diffusion: DemoDiffusionMessagerie

    /// État d'un espace démo (soignant ou établissement), en mémoire pour la session.
    private struct Monde {
        var moi: String
        var etablissement: Bool
        var conversations: [DemoFixtures.ConversationDemo] = []
        var messages: [MessageChat] = []
        var interlocuteurs: [Interlocuteur] = []
        var reponse = ""
        var bloques: Set<String> = []
        var envois = 0
        /// Messages envoyés dont la relecture déclenchera la réponse de l'interlocuteur démo.
        var reponsesAttendues: Set<String> = []

        func fil(_ conversationId: String) -> [MessageChat] {
            FilMessages.fusionner([], messages.filter { $0.conversationId == conversationId }, conversationId: conversationId)
        }

        /// Message à compter comme non lu pour `moi` (soignant : tout autre auteur ; établissement, conversation d'un
        /// soignant : le soignant seul).
        func nonLu(_ message: MessageChat, dans conversation: ConversationApercu) -> Bool {
            !message.lu && ListeConversations.estEntrant(message, dans: conversation, moi: moi, etablissement: etablissement)
        }
    }

    private let clock: any ClockPort
    private var soignant: Monde?
    private var etablissementDemo: Monde?
    private var etablissements: [DemoFixtures.EtablissementMessagerieDemo] = []
    public private(set) var signalements = 0
    public private(set) var battements = 0
    public private(set) var saisiesSignalees = 0

    public init(clock: any ClockPort = FixedClock(DemoWorld.fixedNow), diffusion: DemoDiffusionMessagerie = DemoDiffusionMessagerie()) {
        self.clock = clock
        self.diffusion = diffusion
    }

    // MARK: - Contexte soignant

    public func conversations(avant: CurseurConversations?, context: MissionReadContext) async throws -> PageConversations {
        try charger(context); return page(&soignant!, avant: avant)
    }

    public func interlocuteurs(ids: [String], context: MissionReadContext) async throws -> [Interlocuteur] {
        try charger(context); return try interlocuteurs(soignant!, ids: ids)
    }

    public func messages(conversationId: String, context: MissionReadContext) async throws -> [MessageChat] {
        try charger(context); return Array(soignant!.fil(conversationId).suffix(FilMessages.limite))
    }

    public func messages(conversationId: String, depuis: String, context: MissionReadContext) async throws -> [MessageChat] {
        try charger(context)
        return Array(soignant!.fil(conversationId).filter { FilMessages.pasAvant($0, depuis) }.suffix(FilMessages.limite))
    }

    public func envoyer(conversationId: String, contenu: String, context: MissionReadContext) async throws -> EnvoiOutcome {
        try charger(context); return envoyer(&soignant!, conversationId: conversationId, contenu: contenu)
    }

    public func message(id: String, conversationId: String, context: MissionReadContext) async throws -> MessageChat? {
        try charger(context); return relire(&soignant!, id: id, conversationId: conversationId)
    }

    public func marquerLus(conversationId: String, context: MissionReadContext) async throws -> IssueLecture {
        try charger(context); return marquerLus(&soignant!, conversationId: conversationId)
    }

    public func saisie(debut: Bool, conversationId: String, context: MissionReadContext) async throws {
        try charger(context); saisie(soignant!, conversationId: conversationId)
    }

    public func presence(context: MissionReadContext) async throws {
        try charger(context)
        battements += 1
    }

    public func nonLus(context: MissionReadContext) async throws -> Int {
        try charger(context); return nonLus(soignant!)
    }

    public func bloque(cibleId: String, context: MissionReadContext) async throws -> Bool {
        try charger(context); return soignant!.bloques.contains(cibleId)
    }

    public func basculerBlocage(cibleId: String, bloquer: Bool, context: MissionReadContext) async throws -> Bool {
        try charger(context); return try basculer(&soignant!, cibleId: cibleId, bloquer: bloquer)
    }

    public func signaler(cibleId: String, type: TypeCibleSignalement, categorie: String, motif: String, missionId: String?,
                         context: MissionReadContext) async throws -> IssueSignalement {
        try charger(context); return signaler(soignant!, cibleId: cibleId, categorie: categorie, motif: motif)
    }

    // MARK: - « Écrire à l'établissement »

    public func conversationPourMission(missionId: String, etablissementId: String,
                                        context: MissionReadContext) async throws -> IssueConversationMission {
        try charger(context)
        guard let etablissement = etablissements.first(where: { $0.id == etablissementId }) else {
            return .indisponible(message: Self.nonAutorise)
        }
        if let existante = soignant!.conversations.first(where: {
            $0.apercu.missionId == missionId && $0.apercu.etablissementId == etablissementId
        }) {
            return .conversation(id: existante.apercu.id)
        }
        // `fn_obtenir_conversation` : fil de la mission créé à la demande (mission attribuée : coordonnées admises).
        let id = "demo-conv-mission-\(missionId)"
        let moi = soignant!.moi
        let intitule = (try? DemoFixtures.loadMissions().missions.first { $0.record.id == missionId })?.record.intitule
        let apercu = ConversationApercu(id: id, autreId: etablissement.interlocuteurId, missionId: missionId,
                                        etablissementId: etablissementId, participant1Id: moi,
                                        participant2Id: etablissement.interlocuteurId, soignantId: moi,
                                        creeLe: horodatage(decalage: 0), missionIntitule: intitule)
        soignant!.conversations.append(DemoFixtures.ConversationDemo(apercu: apercu, missionStatut: "ASSIGNEE"))
        soignant!.interlocuteurs.append(Interlocuteur(conversationId: id, participantId: etablissement.interlocuteurId,
                                                      prenom: etablissement.nom, nom: nil))
        return .conversation(id: id)
    }

    // MARK: - Contexte établissement (lot 5, T11)

    public func conversations(avant: CurseurConversations?, etab: EtablissementReadContext) async throws -> PageConversations {
        try charger(etab); return page(&etablissementDemo!, avant: avant)
    }

    public func interlocuteurs(ids: [String], etab: EtablissementReadContext) async throws -> [Interlocuteur] {
        try charger(etab); return try interlocuteurs(etablissementDemo!, ids: ids)
    }

    public func messages(conversationId: String, etab: EtablissementReadContext) async throws -> [MessageChat] {
        try charger(etab); return Array(etablissementDemo!.fil(conversationId).suffix(FilMessages.limite))
    }

    public func messages(conversationId: String, depuis: String, etab: EtablissementReadContext) async throws -> [MessageChat] {
        try charger(etab)
        return Array(etablissementDemo!.fil(conversationId).filter { FilMessages.pasAvant($0, depuis) }.suffix(FilMessages.limite))
    }

    public func envoyer(conversationId: String, contenu: String, etab: EtablissementReadContext) async throws -> EnvoiOutcome {
        try charger(etab); return envoyer(&etablissementDemo!, conversationId: conversationId, contenu: contenu)
    }

    public func message(id: String, conversationId: String, etab: EtablissementReadContext) async throws -> MessageChat? {
        try charger(etab); return relire(&etablissementDemo!, id: id, conversationId: conversationId)
    }

    public func marquerLus(conversationId: String, etab: EtablissementReadContext) async throws -> IssueLecture {
        try charger(etab); return marquerLus(&etablissementDemo!, conversationId: conversationId)
    }

    public func saisie(debut: Bool, conversationId: String, etab: EtablissementReadContext) async throws {
        try charger(etab); saisie(etablissementDemo!, conversationId: conversationId)
    }

    public func presence(etab: EtablissementReadContext) async throws {
        try charger(etab)
        battements += 1
    }

    public func nonLus(etab: EtablissementReadContext) async throws -> Int {
        try charger(etab); return nonLus(etablissementDemo!)
    }

    public func bloque(cibleId: String, etab: EtablissementReadContext) async throws -> Bool {
        try charger(etab); return etablissementDemo!.bloques.contains(cibleId)
    }

    public func basculerBlocage(cibleId: String, bloquer: Bool, etab: EtablissementReadContext) async throws -> Bool {
        try charger(etab); return try basculer(&etablissementDemo!, cibleId: cibleId, bloquer: bloquer)
    }

    public func signaler(cibleId: String, type: TypeCibleSignalement, categorie: String, motif: String, missionId: String?,
                         etab: EtablissementReadContext) async throws -> IssueSignalement {
        try charger(etab); return signaler(etablissementDemo!, cibleId: cibleId, categorie: categorie, motif: motif)
    }

    /// `fn_obtenir_conversation(p_autre_id := soignant, p_mission_id)` : fil existant de la mission, sinon créé pour une
    /// mission de l'établissement démo assignée à ce soignant ; toute autre relation → « Conversation non autorisée ».
    public func conversationPourSoignant(missionId: String, soignantId: String,
                                         etab: EtablissementReadContext) async throws -> IssueConversationMission {
        try charger(etab)
        if let existante = etablissementDemo!.conversations.first(where: {
            $0.apercu.missionId == missionId && $0.apercu.soignantId == soignantId
        }) {
            return .conversation(id: existante.apercu.id)
        }
        let fichier = try DemoFixtures.loadEtabMissionsMessagerie()
        guard let mission = fichier.missions.first(where: { $0.id == missionId && $0.soignantAssigneId == soignantId }) else {
            return .indisponible(message: Self.conversationNonAutorisee)
        }
        let soignant = fichier.soignants.first { $0.id == soignantId }
        let id = "demo-etab-conv-mission-\(missionId)"
        let moi = etablissementDemo!.moi
        let apercu = ConversationApercu(id: id, autreId: soignantId, missionId: missionId, etablissementId: etab.etablissementId,
                                        participant1Id: soignantId, participant2Id: moi, soignantId: soignantId,
                                        creeLe: horodatage(decalage: 0), missionIntitule: mission.intitule)
        etablissementDemo!.conversations.append(DemoFixtures.ConversationDemo(apercu: apercu, missionStatut: mission.statut))
        etablissementDemo!.interlocuteurs.append(Interlocuteur(conversationId: id, participantId: soignantId,
                                                               prenom: soignant?.prenom, nom: soignant?.nom))
        return .conversation(id: id)
    }

    /// Non-lus de l'établissement démo, relus par l'Accueil démo à la place de la valeur figée de la fixture
    /// (`fn_stats_dashboard_etablissement` les compte depuis `messages_chat`, comme ici) ; `nil` hors du compte fictif.
    public func nonLusEtablissement(_ etab: EtablissementReadContext) async -> Int? {
        guard (try? charger(etab)) != nil, let monde = etablissementDemo else { return nil }
        return nonLus(monde)
    }

    // MARK: - Règles partagées

    /// Motifs de téléphone de `detecterLeak` (`supabase/functions/_shared/anti-leak.ts`) ; les autres types (email,
    /// URL, pseudonyme, mot-clé) ne sont pas simulés en démo.
    static func contientTelephone(_ contenu: String) -> Bool {
        let motifs = [#"(?:(?:\+|00)33|0)\s*[1-9](?:[\s.-]*\d{2}){4}"#, #"\b(?:08\d{2}|36\d{2}|39\d{2})[\s.-]?\d{0,6}"#]
        return motifs.contains { contenu.range(of: $0, options: .regularExpression) != nil }
    }

    private func page(_ monde: inout Monde, avant: CurseurConversations?) -> PageConversations {
        var lignes = monde.conversations.map { apercu($0, monde) }.sorted { a, b in
            (a.ordreLe ?? "", a.id) > (b.ordreLe ?? "", b.id)
        }
        if let avant { lignes = lignes.filter { ($0.ordreLe ?? "", $0.id) < (avant.ordreLe, avant.id) } }
        let page = Array(lignes.prefix(PageConversations.taille))
        let suivant = page.count == PageConversations.taille ? page.last?.curseur : nil
        return PageConversations(conversations: page, suivant: suivant == avant ? nil : suivant)
    }

    private func interlocuteurs(_ monde: Monde, ids: [String]) throws -> [Interlocuteur] {
        guard ids.count <= Interlocuteur.lotMax else { throw JoleneError(.contract, MessagerieRepli.message) }
        return monde.interlocuteurs.filter { ids.contains($0.conversationId) }
    }

    private func envoyer(_ monde: inout Monde, conversationId: String, contenu: String) -> EnvoiOutcome {
        guard contenu.count <= CodeEnvoi.longueurMax else { return refus(CodeEnvoi.contenuTropLong) }
        guard !contenu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return refus(CodeEnvoi.contenuVide) }
        guard let conversation = monde.conversations.first(where: { $0.apercu.id == conversationId }) else {
            return refus(CodeEnvoi.conversationNonAutorisee)
        }
        guard !conversation.apercu.archivee else { return refus(CodeEnvoi.conversationArchivee) }
        if Self.contientTelephone(contenu), !Self.statutsCoordonneesAdmises.contains(conversation.missionStatut ?? "") {
            return .antiFuite(.telephone)
        }
        if let autre = conversation.apercu.autreId, monde.bloques.contains(autre) { return refus(CodeEnvoi.envoiRefuse) }
        monde.envois += 1
        let prefixe = monde.etablissement ? "demo-etab-message-envoi" : "demo-message-envoi"
        let id = "\(prefixe)-\(monde.envois)"
        // Auteur = utilisateur de la session (`auth.uid()` de l'edge), jamais l'établissement.
        monde.messages.append(MessageChat(id: id, conversationId: conversationId, auteurId: monde.moi, contenu: contenu,
                                          creeLe: horodatage(decalage: Double(monde.envois) * 2), estAdmin: false, lu: false))
        // Le soignant démo répond à l'établissement ; l'établissement démo répond au soignant.
        if monde.etablissement ? conversation.apercu.soignantId != nil : conversation.apercu.etablissementId != nil {
            monde.reponsesAttendues.insert(id)
        }
        return .envoye(messageId: id)
    }

    private func relire(_ monde: inout Monde, id: String, conversationId: String) -> MessageChat? {
        let relu = monde.messages.first { $0.id == id && $0.conversationId == conversationId }
        if relu != nil, monde.reponsesAttendues.remove(id) != nil { repondre(&monde, conversationId) }
        return relu
    }

    private func marquerLus(_ monde: inout Monde, conversationId: String) -> IssueLecture {
        guard let conversation = monde.conversations.first(where: { $0.apercu.id == conversationId }) else { return .accesRefuse }
        for index in monde.messages.indices where monde.messages[index].conversationId == conversationId
            && ListeConversations.estEntrant(monde.messages[index], dans: conversation.apercu, moi: monde.moi,
                                             etablissement: monde.etablissement) {
            monde.messages[index].lu = true
        }
        return .lus
    }

    private func saisie(_ monde: Monde, conversationId: String) {
        // `fn_typing_start` refuse une conversation inaccessible (42501 `NON_AUTORISE`) : indicateur abandonné.
        guard monde.conversations.contains(where: { $0.apercu.id == conversationId }) else { return }
        saisiesSignalees += 1
    }

    private func nonLus(_ monde: Monde) -> Int {
        monde.conversations.filter { !$0.apercu.archivee }.reduce(0) { total, conversation in
            total + monde.messages.filter { $0.conversationId == conversation.apercu.id && monde.nonLu($0, dans: conversation.apercu) }.count
        }
    }

    private func basculer(_ monde: inout Monde, cibleId: String, bloquer: Bool) throws -> Bool {
        if bloquer {
            guard !cibleId.isEmpty, cibleId != monde.moi else { throw JoleneError(.unknown, Self.cibleInvalide) }
            monde.bloques.insert(cibleId)
        } else {
            monde.bloques.remove(cibleId)
        }
        return monde.bloques.contains(cibleId)
    }

    private func signaler(_ monde: Monde, cibleId: String, categorie: String, motif: String) -> IssueSignalement {
        guard SignalementUtilisateur.categories.contains(categorie) else { return .refuse(message: Self.categorieInvalide) }
        guard motif.trimmingCharacters(in: .whitespacesAndNewlines).count >= SignalementUtilisateur.longueurMotifMin else {
            return .refuse(message: Self.motifObligatoire)
        }
        guard cibleId != monde.moi else { return .refuse(message: Self.autoSignalement) }
        signalements += 1
        return .signale
    }

    private func refus(_ code: String) -> EnvoiOutcome { .refuse(code: code, message: MessagerieRepli.message) }

    /// Colonnes dérivées des messages, comme le SQL de la liste.
    private func apercu(_ conversation: DemoFixtures.ConversationDemo, _ monde: Monde) -> ConversationApercu {
        var ligne = conversation.apercu
        let messages = monde.fil(ligne.id)
        ligne.dernierContenu = messages.last?.contenu
        ligne.dernierMessageLe = messages.last?.creeLe
        ligne.nonLus = messages.filter { monde.nonLu($0, dans: ligne) }.count
        ligne.ordreLe = ligne.dernierMessageLe ?? ligne.creeLe
        return ligne
    }

    private func horodatage(decalage: TimeInterval) -> String {
        DateHeureParis.isoUTC(clock.now().addingTimeInterval(decalage))
    }

    /// Réponse de l'interlocuteur démo : saisie signalée, message inséré une seconde après le dernier du fil, puis émis
    /// sur le flux entrant (fil et liste).
    private func repondre(_ monde: inout Monde, _ conversationId: String) {
        guard let conversation = monde.conversations.first(where: { $0.apercu.id == conversationId }),
              let autre = conversation.apercu.autreId, !monde.bloques.contains(autre) else { return }
        let dernier = monde.fil(conversationId).last?.instant ?? clock.now()
        let prefixe = monde.etablissement ? "demo-etab-message-reponse" : "demo-message-reponse"
        let reponse = MessageChat(id: "\(prefixe)-\(monde.envois)", conversationId: conversationId, auteurId: autre,
                                  contenu: monde.reponse, creeLe: DateHeureParis.isoUTC(dernier.addingTimeInterval(1)),
                                  estAdmin: false, lu: false)
        monde.messages.append(reponse)
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
        guard soignant == nil else { return }
        let conversations = try DemoFixtures.loadConversations()
        let messages = try DemoFixtures.loadMessages()
        var monde = Monde(moi: DemoWorld.context.userId, etablissement: false)
        monde.conversations = conversations.conversations
        monde.interlocuteurs = conversations.interlocuteurs
        monde.messages = messages.messages
        monde.reponse = messages.reponseDemo.contenu
        etablissements = conversations.etablissements
        soignant = monde
        emettre(conversations.presences)
    }

    /// Contexte du compte établissement fictif exigé (`DemoEtablissementWorld.verifier`), puis fixtures lues une fois.
    private func charger(_ etab: EtablissementReadContext) throws {
        try DemoEtablissementWorld.verifier(etab)
        guard etablissementDemo == nil else { return }
        let fichier = try DemoFixtures.loadEtabMessagerie()
        var monde = Monde(moi: etab.userId, etablissement: true)
        monde.conversations = fichier.conversations
        monde.interlocuteurs = fichier.interlocuteurs
        monde.messages = fichier.messages
        monde.reponse = fichier.reponseDemo.contenu
        etablissementDemo = monde
        emettre(fichier.presences)
    }

    private func emettre(_ presences: [LignePresence]) {
        for presence in presences {
            guard let userId = presence.userId else { continue }
            diffusion.emettre(presence: presence.etat(userId: userId))
        }
    }
}

extension DemoFixtures {
    /// `demo-etab-messagerie.json` (`scripts/mobile/demo-etab-messagerie.mjs`, lot 5 T11) : conversations de
    /// l'établissement démo vues par son compte (`demo-etablissement`), interlocuteurs (les soignants des missions
    /// démo), messages et réponse du soignant démo.
    public struct EtabMessagerieFile: Decodable, Sendable {
        public var fixedNow: String
        public var conversations: [ConversationDemo]
        public var interlocuteurs: [Interlocuteur]
        public var presences: [LignePresence]
        public var messages: [MessageChat]
        public var reponseDemo: MessagesFile.Reponse
        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now", conversations, interlocuteurs, presences, messages, reponseDemo = "reponse_demo"
        }
    }

    /// Missions et soignants de `demo-etab-missions.json` lus par la messagerie démo (relation mission × soignant).
    struct EtabMissionsMessagerieFile: Decodable, Sendable {
        struct Mission: Decodable, Sendable {
            var id: String
            var statut: String
            var intitule: String?
            var soignantAssigneId: String?
            enum CodingKeys: String, CodingKey { case id, statut, intitule, soignantAssigneId = "soignant_assigne_id" }
        }
        struct Soignant: Decodable, Sendable { var id: String; var prenom: String?; var nom: String? }
        var missions: [Mission]
        var soignants: [Soignant]
    }

    public static func loadEtabMessagerie() throws -> EtabMessagerieFile { try load("demo-etab-messagerie") }
    static func loadEtabMissionsMessagerie() throws -> EtabMissionsMessagerieFile { try load("demo-etab-missions") }
}
