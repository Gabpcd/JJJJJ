import XCTest
@testable import JoleneCore

/// Textes de la messagerie native (lot 4, T7b ; HARD STOP n°4 pour l'anti-fuite, le blocage et le signalement) : chaque
/// texte repris du web figure tel quel à sa ligne source (échappements `\'` du JS ramenés à `'`), et les assemblages
/// rendent exactement le texte du web. Règles d'affichage pures prouvées sur des vecteurs.
final class MessagerieVerbatimTests: XCTestCase {
    private typealias T = MessagerieTextes
    private typealias A = MessagerieTextes.AntiFuite
    private typealias B = MessagerieTextes.Blocage
    private typealias S = MessagerieTextes.Signalement

    private static let page = "src/pages/PageMessagerie.tsx"
    private static let input = "src/components/messagerie/InputMessage.tsx"
    private static let antiFuite = "src/components/messagerie/ModaleEducativeAntiLeak.tsx"
    private static let bloquer = "src/components/BloquerUtilisateur.tsx"
    private static let signaler = "src/components/SignalerUtilisateur.tsx"
    private static let barre = "src/components/BarreNavigation.tsx"
    private static let ouvrir = "src/hooks/useOuvrirConversation.ts"
    private static let detail = "src/pages/DetailMissionSoignant.tsx"

    private static var attendus: [(String, String, Int)] {
        var liste: [(String, String, Int)] = [
            (T.titre, page, 545), (T.recherche, page, 557), (T.ongletActives, page, 571), (T.ongletArchivees, page, 580),
            (T.echecListe, page, 589), (T.reessayerListe, page, 591), (T.videActives, page, 598), (T.videArchivees, page, 598),
            (T.videRecherche, page, 602), (T.videArchiveesDetail, page, 604), (T.videActivesDetail, page, 605),
            (T.prefixeMission, page, 644), (T.prefixeMission, page, 686), (T.aucunMessage, page, 648),
            (T.archiveeLectureSeule, page, 651), (T.nomParDefaut, page, 260), (T.conversationIndisponible, page, 523),
            (T.retourConversations, page, 669), (T.echecFil, page, 721), (T.reessayerFil, page, 723), (T.filVide, page, 729),
            (T.maintenant, page, 106), (T.hier, page, 108), (T.enLigne, page, 118), (T.absent, page, 119),
            (T.horsLigne, page, 120), ("`" + T.prefixeVu + "${", page, 121),
            (T.refusLimite, input, 113), (T.refusTropLong, input, 115), (T.refusArchivee, input, 117),
            (T.refusGenerique, input, 123), (T.boutonMessages, barre, 401),
            (T.ouvertureImpossible, ouvrir, 46), (T.autresActions, detail, 1170),
            // Anti-fuite
            (A.titre, antiFuite, 60), (A.sousTitre, antiFuite, 62), (A.telephone, antiFuite, 44), (A.email, antiFuite, 45),
            (A.url, antiFuite, 46), (A.handle, antiFuite, 47), (A.motCle, antiFuite, 48), (A.explication, antiFuite, 51),
            (A.compris, antiFuite, 74),
            // Blocage
            ("'\(B.debloquer)' : '\(B.bloquer)'", bloquer, 80), (B.confirmer, bloquer, 88), (B.annuler, bloquer, 89),
            (B.statutIndisponible, bloquer, 74), (B.reessayerStatut, bloquer, 75), ("'\(B.echec)'", bloquer, 55),
            (B.echecReessayer, bloquer, 66), ("libelleCible = '\(B.cibleUtilisateur)'", bloquer, 20),
            ("'\(B.cibleEtablissement)'", page, 710), (B.suiteBlocage + "`", bloquer, 63),
            ("\(B.bloquer) {libelleCible} ?", bloquer, 87),
            ("libelleCible === '\(B.cibleEtablissement)' ? '' : '·e'", bloquer, 62),
            (" débloqué${", bloquer, 62), (" bloqué${", bloquer, 63),
            // Signalement
            ("useState('\(S.categorieParDefaut)')", signaler, 30), (S.signaler, signaler, 68), (S.titre, signaler, 75),
            (S.introduction, signaler, 76), (S.motif, signaler, 78), (S.precisez, signaler, 84), (S.placeholder, signaler, 86),
            (S.annuler, signaler, 89), ("'\(S.envoi)' : '\(S.envoyer)'", signaler, 92), (S.motifTropCourt, signaler, 36),
            (S.echec, signaler, 50), (S.succes, signaler, 53), ("length < 10", signaler, 35),
        ]
        for (index, categorie) in S.categories.enumerated() {
            let libelle = categorie.libelle.contains("'") ? "\"\(categorie.libelle)\"" : "'\(categorie.libelle)'"
            liste.append(("{ value: '\(categorie.valeur)', label: \(libelle) }", signaler, 7 + index))
        }
        return liste
    }

    func testChaqueTexteRepriseDuWebEstVerbatimASaLigne() throws {
        var fichiers: [String: [String]] = [:]
        for (texte, chemin, ligne) in Self.attendus {
            if fichiers[chemin] == nil { fichiers[chemin] = try CompteVerbatimTests.lignes(chemin) }
            let lignes = try XCTUnwrap(fichiers[chemin])
            XCTAssertLessThanOrEqual(ligne, lignes.count, "\(chemin):\(ligne)")
            guard ligne <= lignes.count else { continue }
            let source = lignes[ligne - 1].replacingOccurrences(of: "\\'", with: "'")
            XCTAssertTrue(source.contains(texte), "« \(texte) » absent de \(chemin):\(ligne) : \(source)")
        }
    }

    func testCategoriesDuSignalementSontCellesDuServeur() {
        XCTAssertEqual(Set(S.categories.map(\.valeur)), Set(SignalementUtilisateur.categories))
        XCTAssertEqual(S.categories.count, SignalementUtilisateur.categories.count)
        XCTAssertTrue(S.categories.map(\.valeur).contains(S.categorieParDefaut))
    }

    // MARK: Assemblages (rendus du web)

    func testRendusDuBlocage() {
        XCTAssertEqual(B.question(cible: B.cibleEtablissement), "Bloquer l’établissement ?")
        XCTAssertEqual(B.succes(cible: B.cibleEtablissement, bloque: true),
                       "L’établissement bloqué — les nouveaux messages sont coupés dans les deux sens.")
        XCTAssertEqual(B.succes(cible: B.cibleEtablissement, bloque: false), "L’établissement débloqué.")
        XCTAssertEqual(B.succes(cible: B.cibleUtilisateur, bloque: true),
                       "Cet utilisateur bloqué·e — les nouveaux messages sont coupés dans les deux sens.")
        XCTAssertEqual(B.succes(cible: B.cibleUtilisateur, bloque: false), "Cet utilisateur débloqué·e.")
    }

    func testAntiFuiteParType() {
        XCTAssertEqual(A.description(.telephone), A.telephone)
        XCTAssertEqual(A.description(.email), A.email)
        XCTAssertEqual(A.description(.url), A.url)
        XCTAssertEqual(A.description(.handle), A.handle)
        XCTAssertEqual(A.description(.keyword), A.motCle)
        XCTAssertEqual(A.description(nil), A.motCle, "type absent : KEYWORD (l.54)")
    }

    func testLibellesDesRefusDEnvoi() {
        XCTAssertEqual(MessageriePresentation.libelleRefus(code: CodeEnvoi.limite), T.refusLimite)
        XCTAssertEqual(MessageriePresentation.libelleRefus(code: CodeEnvoi.contenuTropLong), T.refusTropLong)
        XCTAssertEqual(MessageriePresentation.libelleRefus(code: CodeEnvoi.conversationArchivee), T.refusArchivee)
        for code in [CodeEnvoi.envoiRefuse, CodeEnvoi.conversationNonAutorisee, CodeEnvoi.antiFuite, CodeEnvoi.erreurInterne, nil] {
            XCTAssertEqual(MessageriePresentation.libelleRefus(code: code), T.refusGenerique, "\(code ?? "nil")")
        }
    }

    // MARK: Présentation

    private let maintenant = DemoWorld.fixedNow // lundi 2 novembre 2026, 01:00 à Paris

    func testHorodatageDeLaListe() {
        let p = MessageriePresentation.self
        XCTAssertEqual(p.horodatage("2026-11-01T23:59:30.000Z", maintenant: maintenant), "Maintenant")
        XCTAssertEqual(p.horodatage("2026-11-01T23:10:00.000Z", maintenant: maintenant), "00:10", "même jour à Paris")
        XCTAssertEqual(p.horodatage("2026-11-01T21:10:00.000Z", maintenant: maintenant), "Hier")
        XCTAssertEqual(p.horodatage("2026-10-30T00:00:00.000Z", maintenant: maintenant), "ven.")
        XCTAssertEqual(p.horodatage("2026-09-27T00:10:00.000Z", maintenant: maintenant), "27 sept.")
        XCTAssertNil(p.horodatage(nil, maintenant: maintenant))
        XCTAssertNil(p.horodatage("pas une date", maintenant: maintenant))
    }

    func testPresenceEtDistanceStricte() {
        let p = MessageriePresentation.self
        XCTAssertEqual(p.presence(EtatPresence(userId: "a", statut: .enLigne, vuLe: nil), maintenant: maintenant), "En ligne")
        XCTAssertEqual(p.presence(EtatPresence(userId: "a", statut: .absent, vuLe: nil), maintenant: maintenant), "Absent")
        XCTAssertEqual(p.presence(nil, maintenant: maintenant), "Hors ligne")
        XCTAssertEqual(p.presence(EtatPresence(userId: "a", statut: .horsLigne, vuLe: nil), maintenant: maintenant), "Hors ligne")
        let vu = maintenant.addingTimeInterval(-6 * 86_400)
        XCTAssertEqual(p.presence(EtatPresence(userId: "a", statut: .horsLigne, vuLe: vu), maintenant: maintenant), "Vu il y a 6 jours")
        XCTAssertEqual(p.distanceStricte(depuis: maintenant.addingTimeInterval(-30), maintenant: maintenant), "il y a 30 secondes")
        XCTAssertEqual(p.distanceStricte(depuis: maintenant.addingTimeInterval(-60), maintenant: maintenant), "il y a 1 minute")
        XCTAssertEqual(p.distanceStricte(depuis: maintenant.addingTimeInterval(-90 * 60), maintenant: maintenant), "il y a 2 heures")
        XCTAssertEqual(p.distanceStricte(depuis: maintenant.addingTimeInterval(-86_400), maintenant: maintenant), "il y a 1 jour")
        XCTAssertEqual(p.distanceStricte(depuis: maintenant.addingTimeInterval(-45 * 86_400), maintenant: maintenant), "il y a 2 mois")
        XCTAssertEqual(p.distanceStricte(depuis: maintenant.addingTimeInterval(-400 * 86_400), maintenant: maintenant), "il y a 1 an")
    }

    private func conversation(_ id: String, prenom: String?, nom: String? = "", jolene: Bool = false, etablissement: String? = "e-1",
                              mission: String? = "m-1", intitule: String? = nil, contenu: String? = nil,
                              autre: String? = "autre-1", nonLus: Int = 0) -> ConversationAffichee {
        var apercu = ConversationApercu(id: id, autreId: autre, missionId: mission, etablissementId: etablissement, missionIntitule: intitule)
        apercu.dernierContenu = contenu
        apercu.nonLus = nonLus
        let interlocuteur = prenom.map { Interlocuteur(conversationId: id, participantId: autre ?? "", prenom: $0, nom: nom, estJolene: jolene) }
        return ConversationAffichee(apercu: apercu, interlocuteur: interlocuteur)
    }

    func testNomApercuPastillesEtFiltre() {
        let p = MessageriePresentation.self
        let etab = conversation("c-1", prenom: "Clinique Démo", intitule: "Soins de suite", contenu: String(repeating: "a", count: 80))
        let sansLigne = conversation("c-2", prenom: nil)
        XCTAssertEqual(p.nom(etab), "Clinique Démo")
        XCTAssertEqual(p.nom(sansLigne), "Jolene", "interlocuteur sans ligne : Jolene, comme le web")
        XCTAssertEqual(p.apercu(etab).count, 60)
        XCTAssertEqual(p.apercu(sansLigne), "Aucun message")
        XCTAssertNil(p.pastille(0))
        XCTAssertEqual(p.pastille(7), "7")
        XCTAssertEqual(p.pastille(120), "99+")
        XCTAssertNil(p.badge(nil))
        XCTAssertNil(p.badge(0))
        XCTAssertEqual(p.badge(2), "2")
        XCTAssertEqual(p.badge(12), "9+")
        XCTAssertEqual(p.filtrer([etab, sansLigne], terme: "  SUITE ").map(\.id), ["c-1"])
        XCTAssertEqual(p.filtrer([etab, sansLigne], terme: "jolene").map(\.id), ["c-2"])
        XCTAssertEqual(p.filtrer([etab, sansLigne], terme: "").map(\.id), ["c-1", "c-2"])
    }

    func testNatureDesBulles() {
        let p = MessageriePresentation.self
        func message(_ auteur: String?, admin: Bool) -> MessageChat {
            MessageChat(id: "m", conversationId: "c", auteurId: auteur, contenu: "x", creeLe: nil, estAdmin: admin, lu: false)
        }
        XCTAssertEqual(p.nature(message(p.auteurSysteme, admin: true), moi: "u-1"), .systeme)
        XCTAssertEqual(p.nature(message("U-1", admin: false), moi: "u-1"), .moi)
        XCTAssertEqual(p.nature(message("jolene-admin", admin: true), moi: "u-1"), .jolene)
        XCTAssertEqual(p.nature(message("etab", admin: false), moi: "u-1"), .interlocuteur)
    }

    /// Blocage sur `autre_id`, signalement de l'établissement avec la mission ; rien pour la plateforme ni pour l'auteur
    /// système.
    func testCiblesDeModeration() {
        let etab = ModerationConversation.pour(conversation("c-1", prenom: "Clinique", etablissement: "e-1", mission: "m-1"))
        XCTAssertEqual(etab.blocage, "autre-1")
        XCTAssertEqual(etab.libelleCible, "l’établissement")
        XCTAssertEqual(etab.signalement, .init(cibleId: "e-1", type: .etablissement, missionId: "m-1"))
        let jolene = ModerationConversation.pour(conversation("c-2", prenom: "Jolene", jolene: true, etablissement: nil, mission: nil))
        XCTAssertNil(jolene.blocage)
        XCTAssertNil(jolene.signalement)
        let sansLigne = ModerationConversation.pour(conversation("c-3", prenom: nil))
        XCTAssertNil(sansLigne.blocage, "sans ligne d'interlocuteur : la plateforme (web `?? true`)")
        let autre = ModerationConversation.pour(conversation("c-4", prenom: "Camille", etablissement: nil, mission: nil))
        XCTAssertEqual(autre.blocage, "autre-1")
        XCTAssertEqual(autre.libelleCible, "cet utilisateur")
        XCTAssertNil(autre.signalement, "aucun établissement à signaler")
        let systeme = ModerationConversation.pour(conversation("c-5", prenom: "X", autre: MessageriePresentation.auteurSysteme))
        XCTAssertNil(systeme.blocage)
    }
}
