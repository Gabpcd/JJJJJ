import XCTest
@testable import JoleneCore

/// Contrats de décodage de la messagerie (lot 4, T7a) : colonnes de `fn_lister_conversations_messagerie`, de
/// `fn_interlocuteurs_conversations` et des tables `messages_chat`, `typing_status`, `presence_status`
/// (`supabase/schema/public.sql`), décodage tolérant, règles pures du fil et de la liste (`PageMessagerie.tsx`).
final class MessagerieDecodingTests: XCTestCase {
    private func decoder<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Conversations

    func testConversationToutesLesColonnesDeLaRPC() throws {
        let c = try decoder(ConversationApercu.self, """
        {"id":"c-1","participant_1_id":"u-1","participant_2_id":"u-2","mission_id":"m-1","etablissement_id":"e-1",
         "soignant_id":"u-1","dernier_message_le":"2026-11-01T18:30:00.123456+00:00","cree_le":"2026-10-20T08:00:00+00:00",
         "archived_at":null,"autre_id":"u-9","dernier_contenu":"À demain","non_lus":2,"mission_intitule":"Nuit IDE",
         "ordre_le":"2026-11-01T18:30:00.123456+00:00"}
        """)
        XCTAssertEqual(c, ConversationApercu(
            id: "c-1", autreId: "u-9", missionId: "m-1", etablissementId: "e-1", dernierContenu: "À demain", nonLus: 2,
            archivedAt: nil, participant1Id: "u-1", participant2Id: "u-2", soignantId: "u-1",
            dernierMessageLe: "2026-11-01T18:30:00.123456+00:00", creeLe: "2026-10-20T08:00:00+00:00",
            missionIntitule: "Nuit IDE", ordreLe: "2026-11-01T18:30:00.123456+00:00"))
        XCTAssertFalse(c.archivee)
        XCTAssertEqual(c.curseur, CurseurConversations(ordreLe: "2026-11-01T18:30:00.123456+00:00", id: "c-1"),
                       "curseur = (ordre_le, id) tels que servis, microsecondes comprises")
    }

    func testConversationToleranteEtArchivageDerive() throws {
        let c = try decoder(ConversationApercu.self, """
        {"id":"c-2","archived_at":"2026-10-01T00:00:00+00:00","non_lus":"3","dernier_contenu":"","mission_id":42}
        """)
        XCTAssertTrue(c.archivee, "archivée dérivée de archived_at")
        XCTAssertEqual(c.nonLus, 3, "bigint servi en texte toléré, comme Number(c.non_lus) du web")
        XCTAssertNil(c.dernierContenu, "texte vide = absent")
        XCTAssertNil(c.missionId, "valeur d'un autre type ignorée seule")
        XCTAssertNil(c.curseur, "sans ordre_le : pas de curseur, pagination arrêtée")
        let negatif = try decoder(ConversationApercu.self, #"{"id":"c-3","non_lus":-4}"#)
        XCTAssertEqual(negatif.nonLus, 0)
        XCTAssertThrowsError(try decoder(ConversationApercu.self, #"{"autre_id":"u-9"}"#), "id requis")
    }

    func testInterlocuteurEtablissementJoleneEtCle() throws {
        let lignes = try decoder([Interlocuteur].self, """
        [{"conversation_id":"c-1","participant_id":"u-9","prenom":"Clinique fictive","nom":"","avatar_url":"https://exemple.invalid/logo.png","est_jolene":false},
         {"conversation_id":"c-2","participant_id":"u-7","prenom":"Jolene","nom":"","avatar_url":null,"est_jolene":true},
         {"conversation_id":"c-3","participant_id":"u-5","prenom":"Camille","nom":"Martin","est_jolene":"oui"}]
        """)
        XCTAssertEqual(lignes.map(\.id), ["c-1:u-9", "c-2:u-7", "c-3:u-5"], "clé cleInterlocuteur du web")
        XCTAssertEqual(lignes.map(\.nomServeur), ["Clinique fictive", "Jolene", "Camille Martin"])
        XCTAssertEqual(lignes.map(\.estJolene), [false, true, false], "est_jolene : vrai seulement si le serveur sert true")
        XCTAssertEqual(lignes[0].avatarUrl, "https://exemple.invalid/logo.png")
        XCTAssertNil(Interlocuteur(conversationId: "c", participantId: "p", prenom: nil, nom: " ").nomServeur)
        XCTAssertThrowsError(try decoder(Interlocuteur.self, #"{"conversation_id":"c-1","prenom":"x"}"#))
    }

    // MARK: - Messages

    func testMessageLigneDeMessagesChatEtEnregistrementRealtime() throws {
        let postgrest = try decoder(MessageChat.self, """
        {"id":"msg-1","conversation_id":"c-1","auteur_id":"u-9","contenu":"Bonjour","est_admin":false,"lu":true,
         "cree_le":"2026-11-02T09:15:00.654321+00:00"}
        """)
        XCTAssertEqual(postgrest, MessageChat(id: "msg-1", conversationId: "c-1", auteurId: "u-9", contenu: "Bonjour",
                                              creeLe: "2026-11-02T09:15:00.654321+00:00", estAdmin: false, lu: true))
        XCTAssertEqual(postgrest.instant, Date(timeIntervalSince1970: 1_793_610_900.654))
        // Enregistrement d'un INSERT Realtime : mêmes clés, colonnes en plus tolérées, `lu` absent → faux.
        let realtime = try decoder(MessageChat.self, """
        {"id":"msg-2","conversation_id":"c-1","auteur_id":"u-1","contenu":"","est_admin":true,"inconnue":1,
         "cree_le":"2026-11-02T09:16:00+00:00"}
        """)
        XCTAssertEqual(realtime.contenu, "", "contenu vide gardé tel quel")
        XCTAssertTrue(realtime.estAdmin)
        XCTAssertFalse(realtime.lu)
        for illisible in [#"{"conversation_id":"c-1","contenu":"x"}"#, #"{"id":"m","contenu":"x"}"#, #"{"id":"m","conversation_id":"c-1"}"#] {
            XCTAssertThrowsError(try decoder(MessageChat.self, illisible), illisible)
        }
    }

    func testTypesDetectesEtStatutsDePresenceDuServeur() {
        XCTAssertEqual(DetectedType.allCases.map(\.rawValue), ["TELEPHONE", "EMAIL", "URL", "HANDLE", "KEYWORD"],
                       "types de l'anti-fuite de l'edge")
        XCTAssertEqual(StatutPresence.allCases.map(\.rawValue), ["ONLINE", "AWAY", "OFFLINE"], "presence_status_enum")
        XCTAssertEqual(TypeCibleSignalement.allCases.map(\.rawValue), ["ETABLISSEMENT", "SOIGNANT"])
        XCTAssertEqual(CodeEnvoi.longueurMax, 4000)
        XCTAssertEqual(PageConversations.taille, 100)
        XCTAssertEqual(FilMessages.limite, 500)
        XCTAssertEqual(Interlocuteur.lotMax, 100)
        XCTAssertEqual(EtatSaisie.peremption, 6)
    }

    func testLignesDePresenceEtDeSaisie() throws {
        let presence = try decoder(LignePresence.self, #"{"user_id":"u-9","status":"AWAY","last_seen_at":"2026-11-02T09:00:00+00:00","maj_le":"x"}"#)
        XCTAssertEqual(presence.etat(userId: "u-9"),
                       EtatPresence(userId: "u-9", statut: .absent, vuLe: Date(timeIntervalSince1970: 1_793_610_000)))
        XCTAssertFalse(presence.etat(userId: "u-9").enLigne)
        let inconnue = try decoder(LignePresence.self, #"{"user_id":"u-9","status":"EN_VOL"}"#)
        XCTAssertEqual(inconnue.etat(userId: "u-9"), EtatPresence(userId: "u-9", statut: .horsLigne, vuLe: nil),
                       "statut inconnu : jamais un « en ligne » supposé")
        XCTAssertTrue(try decoder(LignePresence.self, #"{"user_id":"u-9","status":"ONLINE"}"#).etat(userId: "u-9").enLigne)
        let saisie = try decoder(LigneSaisie.self, #"{"conversation_id":"c-1","user_id":"u-9","started_at":"2026-11-02T09:00:00+00:00"}"#)
        XCTAssertEqual(saisie.userId, "u-9")
        XCTAssertThrowsError(try decoder(LigneSaisie.self, #"{"conversation_id":"c-1"}"#), "user_id requis")
    }

    // MARK: - Règles du fil

    func testFusionParIdOrdreParCreeLeEtAutreConversationEcartee() {
        let a = SessionMessagerie.message("a", creeLe: "2026-11-02T10:00:00.000100+00:00")
        let b = SessionMessagerie.message("b", creeLe: "2026-11-02T10:00:00.000200+00:00")
        let c = SessionMessagerie.message("c", creeLe: "2026-11-02T09:00:00+00:00")
        let sansDate = MessageChat(id: "z", conversationId: "c-1", auteurId: nil, contenu: "?", creeLe: nil)
        let ailleurs = SessionMessagerie.message("x", conversation: "c-2")
        var relu = a
        relu.lu = true
        let fil = FilMessages.fusionner([b, sansDate, a], [c, relu, ailleurs], conversationId: "c-1")
        XCTAssertEqual(fil.map(\.id), ["c", "a", "b", "z"], "cree_le croissant, même milliseconde départagée par la valeur servie")
        XCTAssertEqual(fil.first { $0.id == "a" }?.lu, true, "le message relu remplace celui déjà affiché")
        XCTAssertEqual(FilMessages.fusionner(fil, [a, b], conversationId: "c-1").count, 4, "jamais de doublon")
        XCTAssertEqual(FilMessages.dernierCreeLe(fil), "2026-11-02T10:00:00.000200+00:00")
        XCTAssertNil(FilMessages.dernierCreeLe([sansDate]))
    }

    func testPasAvantEtMessageEntrant() {
        let borne = "2026-11-02T10:00:00.000500+00:00"
        XCTAssertTrue(FilMessages.pasAvant(SessionMessagerie.message("a", creeLe: "2026-11-02T10:00:00.000100+00:00"), borne),
                      "même milliseconde gardée : la fusion par id dédoublonne")
        XCTAssertTrue(FilMessages.pasAvant(SessionMessagerie.message("b", creeLe: "2026-11-02T10:00:01+00:00"), borne))
        XCTAssertFalse(FilMessages.pasAvant(SessionMessagerie.message("c", creeLe: "2026-11-02T09:59:59+00:00"), borne))
        XCTAssertTrue(FilMessages.pasAvant(MessageChat(id: "d", conversationId: "c-1", auteurId: nil, contenu: "", creeLe: nil), borne))
        XCTAssertTrue(FilMessages.estEntrant(SessionMessagerie.message("a", auteur: "u-9"), moi: "u-1"))
        XCTAssertFalse(FilMessages.estEntrant(SessionMessagerie.message("a", auteur: "U-1"), moi: "u-1"), "identifiants sans casse")
    }

    // MARK: - Règles de la liste

    func testInsertRecuMetAJourLApercuLesNonLusEtLOrdre() throws {
        let ancienne = ConversationApercu(id: "c-1", nonLus: 0, soignantId: "u-1", dernierMessageLe: "2026-11-01T08:00:00+00:00")
        let recente = ConversationApercu(id: "c-2", nonLus: 1, soignantId: "u-1", dernierMessageLe: "2026-11-01T12:00:00+00:00")
        let entrant = SessionMessagerie.message("m-1", conversation: "c-1", auteur: "u-9", contenu: "Êtes-vous disponible ?",
                                                creeLe: "2026-11-02T09:00:00+00:00")
        let liste = try XCTUnwrap(ListeConversations.appliquer(entrant, a: [recente, ancienne], moi: "u-1", filOuvert: nil))
        XCTAssertEqual(liste.map(\.id), ["c-1", "c-2"], "la conversation du message remonte en tête")
        XCTAssertEqual(liste[0].dernierContenu, "Êtes-vous disponible ?")
        XCTAssertEqual(liste[0].dernierMessageLe, "2026-11-02T09:00:00+00:00")
        XCTAssertEqual(liste[0].nonLus, 1)
        let ouvert = try XCTUnwrap(ListeConversations.appliquer(entrant, a: [recente, ancienne], moi: "u-1", filOuvert: "c-1"))
        XCTAssertEqual(ouvert[0].nonLus, 0, "fil ouvert : pas de non-lu")
        let sortant = SessionMessagerie.message("m-2", conversation: "c-1", auteur: "u-1", creeLe: "2026-11-02T09:01:00+00:00")
        XCTAssertEqual(try XCTUnwrap(ListeConversations.appliquer(sortant, a: [recente, ancienne], moi: "u-1", filOuvert: nil))[0].nonLus, 0,
                       "mon propre message n'est pas un non-lu")
        XCTAssertNil(ListeConversations.appliquer(SessionMessagerie.message("m-3", conversation: "c-9"), a: [recente], moi: "u-1",
                                                  filOuvert: nil), "conversation inconnue : liste à relire")
    }

    func testTriDeLaListeCommeLeServeur() {
        let liste = ListeConversations.trier([
            ConversationApercu(id: "a", creeLe: "2026-10-01T00:00:00+00:00"),
            ConversationApercu(id: "c", dernierMessageLe: "2026-11-01T00:00:00+00:00"),
            ConversationApercu(id: "b", dernierMessageLe: "2026-11-01T00:00:00+00:00"),
            ConversationApercu(id: "sans-date"),
        ])
        XCTAssertEqual(liste.map(\.id), ["c", "b", "a", "sans-date"], "date décroissante puis id décroissant")
    }

    // MARK: - Diffusion

    func testDiffusionSansRejeuEtFluxFermesApresTerminer() async {
        let diffusion = DiffusionEvenements<Int>()
        diffusion.emettre(1) // aucun abonné : perdu, jamais rejoué
        let premier = diffusion.flux()
        let second = diffusion.flux()
        XCTAssertEqual(diffusion.nombreAbonnes, 2)
        diffusion.emettre(2)
        diffusion.emettre(3)
        diffusion.terminer()
        var recus: [Int] = []
        for await valeur in premier { recus.append(valeur) }
        XCTAssertEqual(recus, [2, 3])
        recus = []
        for await valeur in second { recus.append(valeur) }
        XCTAssertEqual(recus, [2, 3], "chaque abonné reçoit tout")
        for await valeur in diffusion.flux() { recus.append(valeur) }
        XCTAssertEqual(recus, [2, 3], "un flux demandé après terminer() est fermé d'emblée")
        XCTAssertEqual(diffusion.nombreAbonnes, 0)
    }
}
