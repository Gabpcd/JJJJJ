import XCTest
@testable import JoleneCore

/// Coordinateur push du lot 3 (blueprint `docs/mobile-swift/LOT3_PLAN.md` §2.5 et §3 T4 ; D1-D3) :
/// enregistrement du token APNs hexadécimal à `.ready` et au retour au premier plan, seulement si
/// l'appareil l'autorise (jamais de demande implicite) ; identité vérifiée (epoch) avant l'appel ;
/// rotation ; déconnexion volontaire « RPC bornée à 2,5 s → désinscription → oubli » ; déconnexion
/// subie et suppression de compte : désinscription locale seule, sans RPC. Parité web :
/// `src/lib/pushNative.ts` l.25-38 et l.73-207, `src/lib/pushDeviceToken.ts` l.68-124.
final class PushCoordinatorTests: XCTestCase {
    private let hexA = JetonsTest.hex(JetonsTest.a)
    private let hexB = JetonsTest.hex(JetonsTest.b)

    // MARK: - Constantes et format

    func testDelaisDuWeb() {
        // `pushDeviceToken.ts` l.90-92 et l.113 (2 500 ms) ; `pushNative.ts` l.178-191 (15 000 ms).
        XCTAssertEqual(PushCoordinator.delaiDesactivation, 2.5)
        XCTAssertEqual(PushCoordinator.delaiToken, 15)
        XCTAssertEqual(PushCoordinator.plateforme, "IOS")
    }

    func testHexMinusculeSansSeparateur() {
        XCTAssertEqual(PushCoordinator.hex(Data([0x00, 0xAB, 0x0F, 0xFF])), "00ab0fff")
        XCTAssertEqual(PushCoordinator.hex(JetonsTest.a), hexA)
        XCTAssertEqual(PushCoordinator.hex(JetonsTest.b), hexB)
        XCTAssertEqual(hexA.count, 64)
        XCTAssertEqual(hexB, hexB.lowercased())
        XCTAssertEqual(PushCoordinator.hex(Data()), "")
    }

    func testValiditeDuTokenSelonLaFonctionServeur() {
        // `fn_upsert_token_push` l.64644-64645 : longueur 16 à 4096 caractères après trim.
        XCTAssertFalse(PushCoordinator.tokenValide(""))
        XCTAssertFalse(PushCoordinator.tokenValide(String(repeating: "a", count: 15)))
        XCTAssertTrue(PushCoordinator.tokenValide(String(repeating: "a", count: 16)))
        XCTAssertTrue(PushCoordinator.tokenValide(hexA))
        XCTAssertTrue(PushCoordinator.tokenValide(String(repeating: "a", count: 4096)))
        XCTAssertFalse(PushCoordinator.tokenValide(String(repeating: "a", count: 4097)))
    }

    // MARK: - Enregistrement

    func testSansAutorisationAucunAppelNiDemande() async throws {
        for etat in [AutorisationPush.nonDemandee, .refusee] {
            let monde = MondePush(etat: etat)
            let snapshot = try await monde.pret()
            await monde.coordinator.surReady(snapshot)
            await monde.coordinator.surActive(snapshot)
            let enregistrements = await monde.registrar.enregistrements
            let demandes = await monde.permission.demandes
            let upserts = await monde.gateway.upserts
            XCTAssertEqual(enregistrements, 0, "\(etat) : aucun enregistrement APNs")
            XCTAssertEqual(demandes, 0, "\(etat) : jamais de demande d'autorisation implicite (D1)")
            XCTAssertEqual(upserts, [], "\(etat) : aucun upsert")
            XCTAssertNil(monde.memoire.lire())
            let confirme = await monde.coordinator.enregistrementConfirme(epoch: snapshot.epoch)
            XCTAssertFalse(confirme)
        }
    }

    func testAutoriseEnregistreLeTokenHexEtLeMemorisePourLUtilisateur() async throws {
        for etat in [AutorisationPush.accordee, .provisoire] {
            let monde = MondePush(etat: etat, token: JetonsTest.b)
            let snapshot = try await monde.pret()
            await monde.coordinator.surReady(snapshot)
            XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:"), ["upsert:\(hexB):\(MondePush.utilisateur.id)"], "\(etat)")
            XCTAssertEqual(monde.memoire.lire(), TokenPushMemorise(token: hexB, userId: MondePush.utilisateur.id))
            let confirme = await monde.coordinator.enregistrementConfirme(epoch: snapshot.epoch)
            XCTAssertTrue(confirme, "\(etat) : enregistrement confirmé pour cet epoch")
            let autreEpoch = await monde.coordinator.enregistrementConfirme(epoch: snapshot.epoch + 1)
            XCTAssertFalse(autreEpoch)
            let demandes = await monde.permission.demandes
            XCTAssertEqual(demandes, 0, "\(etat) : aucune demande d'autorisation")
        }
    }

    func testEpochChangePendantLEnregistrementAucunUpsert() async throws {
        let barriere = Gate()
        let monde = MondePush(barriere: barriere)
        let snapshot = try await monde.pret()
        let tache = Task { await monde.coordinator.surReady(snapshot) }
        await waitUntil { await monde.registrar.enregistrements == 1 }
        _ = await monde.controller.signOut() // identité changée pendant l'appel APNs (web l.25-29)
        await barriere.open()
        await tache.value
        XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:"), [], "aucun upsert pour un epoch périmé")
        XCTAssertNil(monde.memoire.lire())
    }

    func testTokenTourneNouvelUpsert() async throws {
        let monde = MondePush(token: JetonsTest.a)
        let snapshot = try await monde.pret()
        await monde.coordinator.surReady(snapshot)
        await monde.registrar.regler(token: JetonsTest.b)
        await monde.coordinator.surActive(snapshot)
        let upserts = await monde.gateway.upserts
        XCTAssertEqual(upserts, [hexA, hexB], "rotation : le nouveau token est enregistré")
        XCTAssertEqual(monde.memoire.lire()?.token, hexB, "le token mémorisé est le dernier enregistré")
    }

    func testActiveSansChangementEstIdempotent() async throws {
        let monde = MondePush()
        let snapshot = try await monde.pret()
        await monde.coordinator.surReady(snapshot)
        await monde.coordinator.surActive(snapshot)
        await monde.coordinator.surActive(snapshot)
        let upserts = await monde.gateway.upserts
        XCTAssertEqual(upserts, [hexA], "même epoch, même token : un seul upsert")
        XCTAssertEqual(monde.journal.entrees(prefixe: "memoriser:").count, 1)
    }

    func testActiveRetenteUnEnregistrementEchoue() async throws {
        // Web `AuthContext.tsx` l.151-153 : la reprise retente un enregistrement échoué hors ligne.
        let monde = MondePush()
        await monde.gateway.echouerUpserts([JoleneError(.network, "hors ligne")])
        let snapshot = try await monde.pret()
        await monde.coordinator.surReady(snapshot)
        var confirme = await monde.coordinator.enregistrementConfirme(epoch: snapshot.epoch)
        XCTAssertFalse(confirme, "échec : rien n'est confirmé")
        XCTAssertNil(monde.memoire.lire(), "échec : rien n'est mémorisé")
        await monde.coordinator.surActive(snapshot)
        confirme = await monde.coordinator.enregistrementConfirme(epoch: snapshot.epoch)
        XCTAssertTrue(confirme)
        XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:").count, 2, "un essai par événement, aucun renvoi automatique")
    }

    func testEchecDeLUpsertNeDeconnecteJamais() async throws {
        let monde = MondePush()
        await monde.gateway.echouerUpserts([JoleneError(.unauthorized, SessionController.sessionExpiredMessage)])
        let snapshot = try await monde.pret()
        await monde.coordinator.surReady(snapshot)
        let etat = await monde.controller.state
        XCTAssertTrue(etat.isReady, "best-effort : la session reste ouverte")
        XCTAssertEqual(monde.journal.entrees(prefixe: "auth."), [], "aucune révocation")
    }

    func testRegistrarEnEchecAucunUpsert() async throws {
        let monde = MondePush()
        await monde.registrar.regler(echec: JoleneError(.unknown, "aps-environment absent"))
        let snapshot = try await monde.pret()
        await monde.coordinator.surReady(snapshot)
        XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:"), [])
    }

    func testTokenTropCourtNestPasEnvoye() async throws {
        let monde = MondePush(token: Data([0x01, 0x02, 0x03]))
        let snapshot = try await monde.pret()
        await monde.coordinator.surReady(snapshot)
        XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:"), [], "un token hors 16-4096 caractères serait un 22023")
    }

    func testRegistrarMuetBorneAuDelaiDuToken() async throws {
        let monde = MondePush(barriere: Gate(), delaiToken: 0.05) // barrière jamais ouverte
        let snapshot = try await monde.pret()
        let debut = Date()
        await monde.coordinator.surReady(snapshot)
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2, "le délai du token borne l'attente APNs")
        XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:"), [])
    }

    func testReadyEtActiveSimultanesUnSeulEnregistrement() async throws {
        let barriere = Gate()
        let monde = MondePush(barriere: barriere)
        let snapshot = try await monde.pret()
        let ready = Task { await monde.coordinator.surReady(snapshot) }
        await waitUntil { await monde.registrar.enregistrements == 1 }
        let active = Task { await monde.coordinator.surActive(snapshot) }
        // Le retour au premier plan arrive pendant que le token APNs est attendu (barrière fermée) : on
        // attend qu'il ait rejoint l'enregistrement en vol (condition observable, aucun délai arbitraire).
        await waitUntil { await monde.coordinator.enregistrementsRejoints == 1 }
        let lectures = await monde.permission.lectures
        XCTAssertEqual(lectures, 1, "l'appel rejoint ne relit pas l'autorisation : il attend l'enregistrement en vol")
        await barriere.open()
        await ready.value
        await active.value
        let enregistrements = await monde.registrar.enregistrements
        XCTAssertEqual(enregistrements, 1, "le retour au premier plan rejoint l'enregistrement en vol")
        XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:").count, 1)
    }

    // MARK: - Déconnexion volontaire (D2, D3, correction 11)

    func testDeconnexionRPCPuisDesinscriptionPuisOubli() async throws {
        let monde = MondePush()
        let snapshot = try await monde.pret()
        await monde.coordinator.surReady(snapshot)
        await monde.coordinator.avantDeconnexion(epoch: snapshot.epoch)
        let apres = Array(monde.journal.entrees.drop { !$0.hasPrefix("desactiver:") })
        XCTAssertEqual(apres, ["desactiver:\(hexA)", "desinscrire", "oublier"])
        XCTAssertNil(monde.memoire.lire())
        let confirme = await monde.coordinator.enregistrementConfirme(epoch: snapshot.epoch)
        XCTAssertFalse(confirme)
    }

    func testDeconnexionDesactiveLeTokenMemoriseAuLancementPrecedent() async throws {
        // Token enregistré par un lancement précédent (Keychain) : désactivé même sans enregistrement ici.
        let memorise = TokenPushMemorise(token: hexB, userId: MondePush.utilisateur.id)
        let monde = MondePush(etat: .refusee, memorise: memorise)
        let snapshot = try await monde.pret()
        await monde.coordinator.avantDeconnexion(epoch: snapshot.epoch)
        XCTAssertEqual(monde.journal.entrees, ["desactiver:\(hexB)", "desinscrire", "oublier"])
    }

    func testDeconnexionRPCEnEchecOuRefuseeDesinscritQuandMeme() async throws {
        let echec = MondePush()
        await echec.gateway.echouerDesactivation(JoleneError(.network, "hors ligne"))
        var snapshot = try await echec.pret()
        await echec.coordinator.surReady(snapshot)
        await echec.coordinator.avantDeconnexion(epoch: snapshot.epoch)
        XCTAssertEqual(Array(echec.journal.entrees.suffix(3)), ["desactiver:\(hexA)", "desinscrire", "oublier"])

        let refus = MondePush()
        await refus.gateway.repondreDesactivation(.nonDesactive)
        snapshot = try await refus.pret()
        await refus.coordinator.surReady(snapshot)
        await refus.coordinator.avantDeconnexion(epoch: snapshot.epoch)
        XCTAssertEqual(Array(refus.journal.entrees.suffix(3)), ["desactiver:\(hexA)", "desinscrire", "oublier"])
        XCTAssertNil(refus.memoire.lire())
    }

    func testDeconnexionRPCTropLongueBorneeEtDesinscritQuandMeme() async throws {
        let monde = MondePush(delaiDesactivation: 0.05)
        await monde.gateway.ralentirDesactivation(secondes: 10)
        let snapshot = try await monde.pret()
        await monde.coordinator.surReady(snapshot)
        let debut = Date()
        await monde.coordinator.avantDeconnexion(epoch: snapshot.epoch)
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2, "la déconnexion n'attend jamais la RPC au-delà du délai")
        XCTAssertEqual(Array(monde.journal.entrees.suffix(3)), ["desactiver:\(hexA)", "desinscrire", "oublier"])
    }

    func testDeconnexionSansTokenMemoriseAucuneRPC() async throws {
        // Web `pushDeviceToken.ts` l.88 : pas de token local, pas de RPC ; jamais « tous les tokens du compte ».
        let monde = MondePush(etat: .refusee)
        let snapshot = try await monde.pret()
        await monde.coordinator.avantDeconnexion(epoch: snapshot.epoch)
        XCTAssertEqual(monde.journal.entrees, ["desinscrire", "oublier"])
    }

    func testDeconnexionSansIdentiteOuEpochPerimeAucuneRPC() async throws {
        let memorise = TokenPushMemorise(token: hexA, userId: MondePush.utilisateur.id)
        let sansIdentite = MondePush(memorise: memorise)
        await sansIdentite.coordinator.avantDeconnexion(epoch: nil)
        XCTAssertEqual(sansIdentite.journal.entrees, ["desinscrire", "oublier"], "sans JWT : désinscription locale seule")

        let perime = MondePush(memorise: memorise)
        let snapshot = try await perime.pret()
        await perime.coordinator.avantDeconnexion(epoch: snapshot.epoch + 1)
        XCTAssertEqual(perime.journal.entrees, ["desinscrire", "oublier"], "epoch périmé : aucune RPC")
    }

    func testDeconnexionPendantUnEnregistrementEnVolLAbandonne() async throws {
        let barriere = Gate()
        let monde = MondePush(barriere: barriere)
        let snapshot = try await monde.pret()
        let tache = Task { await monde.coordinator.surReady(snapshot) }
        await waitUntil { await monde.registrar.enregistrements == 1 }
        await monde.coordinator.avantDeconnexion(epoch: snapshot.epoch)
        await barriere.open()
        await tache.value
        XCTAssertEqual(monde.journal.entrees(prefixe: "upsert:"), [], "l'enregistrement en vol n'aboutit plus")
        XCTAssertEqual(monde.journal.entrees(prefixe: "memoriser:"), [])
        XCTAssertNil(monde.memoire.lire())
    }

    // MARK: - Déconnexion subie, suppression de compte

    func testDeconnexionSubieDesinscritSansRPC() async throws {
        let monde = MondePush()
        let snapshot = try await monde.pret()
        await monde.coordinator.surReady(snapshot)
        await monde.coordinator.surDeconnexionSubie(epoch: snapshot.epoch)
        XCTAssertEqual(Array(monde.journal.entrees.suffix(2)), ["desinscrire", "oublier"])
        XCTAssertEqual(monde.journal.entrees(prefixe: "desactiver:"), [], "JWT absent : aucune RPC")
        XCTAssertNil(monde.memoire.lire())
        let confirme = await monde.coordinator.enregistrementConfirme(epoch: snapshot.epoch)
        XCTAssertFalse(confirme)
    }

    func testDeconnexionSubieFermeLEpochPerduMemeAvantSonEnregistrement() async throws {
        // `.ready` publié, tâche d'enregistrement pas encore arrivée au coordinateur, puis session effacée :
        // l'enregistrement de l'identité perdue n'a jamais lieu (aucun appel APNs après la désinscription).
        let monde = MondePush()
        let snapshot = try await monde.pret()
        _ = await monde.controller.signOut()
        await monde.coordinator.surDeconnexionSubie(epoch: snapshot.epoch)
        await monde.coordinator.surReady(snapshot)
        let enregistrements = await monde.registrar.enregistrements
        XCTAssertEqual(enregistrements, 0, "aucun enregistrement APNs pour l'identité perdue")
        XCTAssertEqual(monde.journal.entrees, ["desinscrire", "oublier"])
    }

    func testDeconnexionSubieNeFermeJamaisLIdentiteSuivante() async throws {
        // La fin subie est traitée après la publication de l'état : si une nouvelle identité est déjà
        // ouverte, seul l'epoch perdu est fermé (l'epoch courant du contrôleur n'est pas lu).
        let monde = MondePush()
        let perdue = try await monde.pret()
        _ = await monde.controller.signOut()
        let suivante = try await monde.pret()
        XCTAssertGreaterThan(suivante.epoch, perdue.epoch)
        await monde.coordinator.surDeconnexionSubie(epoch: perdue.epoch)
        await monde.coordinator.surReady(suivante)
        let upserts = await monde.gateway.upserts
        XCTAssertEqual(upserts, [hexA], "l'identité suivante enregistre son token")
        let confirme = await monde.coordinator.enregistrementConfirme(epoch: suivante.epoch)
        XCTAssertTrue(confirme)
    }

    // MARK: - Lancement à froid sans session

    func testSessionAbsenteOublieLeTokenLaisseParUneSessionPrecedente() async throws {
        let memorise = TokenPushMemorise(token: hexB, userId: MondePush.utilisateur.id)
        let monde = MondePush(memorise: memorise)
        await monde.coordinator.surSessionAbsente()
        XCTAssertEqual(monde.journal.entrees, ["desinscrire", "oublier"], "aucun JWT : désinscription locale et oubli, sans RPC")
        XCTAssertNil(monde.memoire.lire())
    }

    func testSessionAbsenteSansTokenMemoriseNeFaitRien() async throws {
        let monde = MondePush()
        await monde.coordinator.surSessionAbsente()
        let desinscriptions = await monde.registrar.desinscriptions
        XCTAssertEqual(desinscriptions, 0, "rien à nettoyer : aucun appel système")
        XCTAssertEqual(monde.journal.entrees, [])
    }

    // MARK: - Journal DEBUG (§2.4 ; T17 distingue non autorisé, APNs muet, 22023 et réseau)

    func testMotifDuJournalCategorieSeulementJamaisLeToken() {
        // Catégorie d'erreur seulement : ni message (il pourrait citer un token ou un texte serveur), ni token.
        XCTAssertEqual(PushCoordinator.motif(JoleneError(.contract, "Token push invalide \(hexA)")), "contract",
                       "22023 → refus de contrat (`SupabasePushGateway`)")
        XCTAssertEqual(PushCoordinator.motif(JoleneError(.unauthorized, SessionController.sessionExpiredMessage)), "unauthorized")
        XCTAssertEqual(PushCoordinator.motif(JoleneError(.network, "hors ligne")), "network")
        XCTAssertEqual(PushCoordinator.motif(JoleneError(.network, SessionController.timeoutMessage)), "network (délai dépassé)",
                       "APNs ou serveur muet : borne de `bounded` atteinte")
        XCTAssertEqual(PushCoordinator.motif(CancellationError()), "annulé")
        XCTAssertEqual(PushCoordinator.motif(NSError(domain: NSCocoaErrorDomain, code: 3010)), "NSCocoaErrorDomain 3010",
                       "échec APNs (`didFailToRegisterForRemoteNotificationsWithError`) : domaine et code")
        for erreur: Error in [JoleneError(.unknown, hexA), NSError(domain: "d", code: 1, userInfo: [NSLocalizedDescriptionKey: hexA])] {
            XCTAssertFalse(PushCoordinator.motif(erreur).contains(hexA), "jamais le token ni le message dans le journal")
        }
    }

    func testNouvelleSessionApresDeconnexionReenregistre() async throws {
        let monde = MondePush()
        let premiere = try await monde.pret()
        await monde.coordinator.surReady(premiere)
        await monde.coordinator.avantDeconnexion(epoch: premiere.epoch)
        _ = await monde.controller.signOut()
        let seconde = try await monde.pret()
        XCTAssertNotEqual(premiere.epoch, seconde.epoch)
        await monde.coordinator.surReady(seconde)
        let upserts = await monde.gateway.upserts
        XCTAssertEqual(upserts, [hexA, hexA], "nouvel epoch : nouvel enregistrement")
        XCTAssertEqual(monde.memoire.lire()?.token, hexA)
    }
}
