import XCTest
@testable import JoleneCore

/// Préférences de notifications (lot 3, T6 ; blueprint `docs/mobile-swift/LOT3_PLAN.md` §3 T6) : port de
/// `src/pages/PageParametresNotifications.tsx`. Catalogue `EVENTS_SOIGNANT` verbatim (l.42-56) et filtre de
/// régime (l.79-84), absence de ligne `par_evenement` = actif (l.194-197), canal global coupé → case grisée
/// et non modifiable (l.396-410), décodage strict des quatre booléens (l.117) et de la ligne `soignants`
/// (l.122-131), seuls les types du catalogue envoyés (fiche `fn_modifier_preferences_notifications`), textes
/// verbatim (HARD STOP n°4, gardés par lecture du fichier web).
final class PreferencesNotificationsTests: XCTestCase {
    private static let source = "src/pages/PageParametresNotifications.tsx"

    private func web() throws -> String {
        try String(contentsOf: Lot3PortsTests.racine.appendingPathComponent(Self.source), encoding: .utf8)
    }

    private func prefs(email: Bool = true, sms: Bool = false, push: Bool = true, inApp: Bool = true,
                       parEvenement: [PreferenceEvenement] = [], smsAlertes: Bool? = true,
                       typeExercice: String? = "MIXTE") -> PreferencesNotifications {
        PreferencesNotifications(canalEmail: email, canalSms: sms, canalPush: push, canalInApp: inApp,
                                 parEvenement: parEvenement, smsAlertesActives: smsAlertes, typeExercice: typeExercice)
    }

    // MARK: - Catalogue `EVENTS_SOIGNANT` (verbatim, garde de dérive)

    /// Chaque entrée du web, relue dans le fichier source : type, libellé, description, canaux et régime.
    func testCatalogueIdentiqueAEventsSoignantDuWeb() throws {
        let source = try web()
        let debut = try XCTUnwrap(source.range(of: "const EVENTS_SOIGNANT: EventDef[] = ["), "bloc EVENTS_SOIGNANT introuvable")
        let fin = try XCTUnwrap(source.range(of: "];", range: debut.upperBound..<source.endIndex))
        let bloc = String(source[debut.upperBound..<fin.lowerBound])
        let motif = try NSRegularExpression(pattern:
            #"\{ type: '([A-Z0-9_]+)', label: '((?:[^'\\]|\\.)*)', description: '((?:[^'\\]|\\.)*)', canaux: \[([^\]]*)\](?:, regime: '([A-Z]+)')? \}"#)
        let lignes = motif.matches(in: bloc, range: NSRange(bloc.startIndex..., in: bloc))
        XCTAssertEqual(lignes.count, 13, "13 événements soignant sur le web")
        let unJS = { (texte: String) in texte.replacingOccurrences(of: "\\'", with: "'") }
        let lus: [EvenementNotification] = lignes.map { ligne in
            func groupe(_ i: Int) -> String? {
                guard let r = Range(ligne.range(at: i), in: bloc) else { return nil }
                return String(bloc[r])
            }
            let canaux = (groupe(4) ?? "").split(separator: ",").map {
                CanalNotification(rawValue: $0.trimmingCharacters(in: CharacterSet(charactersIn: "' ")))!
            }
            return EvenementNotification(type: groupe(1)!, libelle: unJS(groupe(2)!), description: unJS(groupe(3)!),
                                         canaux: canaux, regime: groupe(5).flatMap(RegimeEvenement.init(rawValue:)))
        }
        XCTAssertEqual(CatalogueNotificationsSoignant.evenements, lus, "catalogue natif = EVENTS_SOIGNANT, dans l'ordre")
    }

    func testChaqueTypeDuCatalogueAppartientALEnumDuDump() throws {
        let dump = try String(contentsOf: Lot3PortsTests.dumpURL, encoding: .utf8)
        let debut = try XCTUnwrap(dump.range(of: #"CREATE TYPE "public"."type_evenement_notification" AS ENUM ("#))
        let fin = try XCTUnwrap(dump.range(of: ");", range: debut.upperBound..<dump.endIndex))
        let enumSQL = String(dump[debut.upperBound..<fin.lowerBound])
        for evenement in CatalogueNotificationsSoignant.evenements {
            XCTAssertTrue(enumSQL.contains("'\(evenement.type)'"), "\(evenement.type) hors enum : 22P02 côté serveur")
        }
        XCTAssertEqual(CatalogueNotificationsSoignant.colonnes, [.email, .push, .sms], "colonnes du tableau web (l.383-385)")
        XCTAssertFalse(CatalogueNotificationsSoignant.evenements.contains { $0.canaux.contains(.inApp) },
                       "aucune case In-app dans la matrice : canal global seulement")
    }

    func testFiltreDeRegimeCommeLeWeb() {
        let tous = CatalogueNotificationsSoignant.evenements.map(\.type)
        XCTAssertEqual(CatalogueNotificationsSoignant.visibles(typeExercice: "MIXTE").map(\.type), tous)
        XCTAssertEqual(CatalogueNotificationsSoignant.visibles(typeExercice: nil).map(\.type), tous, "régime inconnu → tout")
        XCTAssertEqual(CatalogueNotificationsSoignant.visibles(typeExercice: "AUTRE").map(\.type), tous)
        XCTAssertEqual(CatalogueNotificationsSoignant.visibles(typeExercice: "liberal").map(\.type), tous,
                       "comparaison stricte comme le web (`===`)")
        let liberal = CatalogueNotificationsSoignant.visibles(typeExercice: "LIBERAL").map(\.type)
        XCTAssertEqual(liberal, tous.filter { $0 != "CONTRAT_TRAVAIL_DEPOSE" }, "un libéral ne voit pas l'événement salarié")
        let salarie = CatalogueNotificationsSoignant.visibles(typeExercice: "SALARIE").map(\.type)
        XCTAssertEqual(salarie, tous.filter { !["FACTURE_EMISE", "PAIEMENT_RECU", "MANDAT_RE_SIGNATURE"].contains($0) },
                       "un salarié ne voit pas les événements libéraux")
        XCTAssertEqual(prefs(typeExercice: "LIBERAL").evenementsVisibles.map(\.type), liberal,
                       "régime lu avec l'alerte SMS (`soignants.type_exercice`, l.122)")
    }

    // MARK: - Matrice : absence = actif, canal global, bascule

    func testAbsenceDeLigneParEvenementVautActif() {
        let p = prefs(parEvenement: [PreferenceEvenement(typeEvenement: "LITIGE_RESOLU", canal: .push, actif: false),
                                     PreferenceEvenement(typeEvenement: "LITIGE_OUVERT", canal: .email, actif: true)])
        XCTAssertTrue(p.estActif(type: "CANDIDATURE_ACCEPTEE", canal: .email), "aucune ligne → actif (web l.196)")
        XCTAssertFalse(p.estActif(type: "LITIGE_RESOLU", canal: .push))
        XCTAssertTrue(p.estActif(type: "LITIGE_RESOLU", canal: .email), "la clé est (type, canal)")
        XCTAssertTrue(p.estActif(type: "LITIGE_OUVERT", canal: .email))
    }

    func testCanalGlobalCoupeGriseEtBloqueLesCases() {
        var p = prefs(email: true, sms: false, push: true, inApp: true)
        XCTAssertEqual(CanalNotification.allCases.map(p.canalGlobalActif), [true, false, true, true])
        XCTAssertFalse(p.peutBasculer(type: "CANDIDATURE_ACCEPTEE", canal: .sms), "canal SMS coupé : case grisée")
        XCTAssertFalse(p.basculer(type: "CANDIDATURE_ACCEPTEE", canal: .sms), "clic ignoré (web l.407)")
        XCTAssertEqual(p.parEvenement, [], "aucune ligne posée par un clic ignoré")
        p.definirCanalGlobal(.sms, actif: true)
        XCTAssertTrue(p.canalSms)
        XCTAssertTrue(p.peutBasculer(type: "CANDIDATURE_ACCEPTEE", canal: .sms))
        p.definirCanalGlobal(.email, actif: false)
        p.definirCanalGlobal(.inApp, actif: false)
        p.definirCanalGlobal(.push, actif: false)
        XCTAssertEqual([p.canalEmail, p.canalSms, p.canalPush, p.canalInApp], [false, true, false, false])
        XCTAssertFalse(p.peutBasculer(type: "CANDIDATURE_ACCEPTEE", canal: .email))
    }

    func testBasculePoseUneLigneExpliciteEtSInverse() {
        var p = prefs()
        XCTAssertTrue(p.basculer(type: "MISSION_ASSIGNEE", canal: .email))
        XCTAssertEqual(p.parEvenement, [PreferenceEvenement(typeEvenement: "MISSION_ASSIGNEE", canal: .email, actif: false)])
        XCTAssertTrue(p.basculer(type: "MISSION_ASSIGNEE", canal: .email))
        XCTAssertEqual(p.parEvenement, [PreferenceEvenement(typeEvenement: "MISSION_ASSIGNEE", canal: .email, actif: true)],
                       "la ligne explicite est mise à jour, jamais dupliquée")
        // Doublon reçu (impossible par contrainte unique) : la dernière ligne fait foi comme la Map web, et la bascule le résorbe.
        var doublon = prefs(parEvenement: [PreferenceEvenement(typeEvenement: "LITIGE_OUVERT", canal: .push, actif: true),
                                           PreferenceEvenement(typeEvenement: "LITIGE_OUVERT", canal: .push, actif: false)])
        XCTAssertFalse(doublon.estActif(type: "LITIGE_OUVERT", canal: .push))
        XCTAssertTrue(doublon.basculer(type: "LITIGE_OUVERT", canal: .push))
        XCTAssertEqual(doublon.parEvenement, [PreferenceEvenement(typeEvenement: "LITIGE_OUVERT", canal: .push, actif: true)])
    }

    func testBasculeRefuseeHorsCatalogueOuHorsCanauxDeLEvenement() {
        var p = prefs(sms: true)
        XCTAssertFalse(p.peutBasculer(type: "SERIE_ONBOARDING", canal: .push), "SERIE_ONBOARDING : e-mail seulement (« — » sur le web)")
        XCTAssertFalse(p.basculer(type: "MISSION_ASSIGNEE", canal: .sms), "MISSION_ASSIGNEE : pas de SMS")
        XCTAssertFalse(p.basculer(type: "URGENCE", canal: .email), "type hors catalogue soignant")
        XCTAssertFalse(p.basculer(type: "CANDIDATURE_RECUE", canal: .email), "événement établissement")
        XCTAssertFalse(p.basculer(type: "CANDIDATURE_ACCEPTEE", canal: .inApp), "aucune case In-app")
        XCTAssertEqual(p.parEvenement, [])
    }

    func testSeulsLesTypesDuCatalogueSontEnvoyes() {
        let p = prefs(parEvenement: [
            PreferenceEvenement(typeEvenement: "LITIGE_RESOLU", canal: .push, actif: false),
            PreferenceEvenement(typeEvenement: "URGENCE", canal: .email, actif: false),
            PreferenceEvenement(typeEvenement: "NOUVEAU_SOIGNANT_MATCHANT_FILTRE", canal: .email, actif: false),
            PreferenceEvenement(typeEvenement: "TYPE_INCONNU", canal: .sms, actif: true),
            PreferenceEvenement(typeEvenement: "FACTURE_EMISE", canal: .email, actif: false),
        ], typeExercice: "SALARIE")
        XCTAssertEqual(p.parEvenementAEnvoyer, [
            PreferenceEvenement(typeEvenement: "LITIGE_RESOLU", canal: .push, actif: false),
            PreferenceEvenement(typeEvenement: "FACTURE_EMISE", canal: .email, actif: false),
        ], "catalogue soignant entier (le filtre de régime n'efface rien) ; jamais un type hors catalogue")
    }

    // MARK: - Alerte SMS (`soignants.sms_alertes_actives`)

    func testAlerteSmsAfficheeSeulementSiLaLigneSoignantALuEtModifiableSiCanalSms() {
        XCTAssertFalse(prefs(smsAlertes: nil).afficheAlerteSms, "ligne soignants non lue : section masquée, jamais écrite (l.290, l.230)")
        XCTAssertTrue(prefs(smsAlertes: false).afficheAlerteSms)
        XCTAssertFalse(prefs(sms: false).alerteSmsModifiable, "interrupteur grisé si le canal SMS est coupé (l.309)")
        XCTAssertTrue(prefs(sms: false).afficheAvertissementCanalSms)
        XCTAssertTrue(prefs(sms: true).alerteSmsModifiable)
        XCTAssertFalse(prefs(sms: true).afficheAvertissementCanalSms)
    }

    // MARK: - Décodage strict (web l.117-131)

    private func json(_ texte: String) throws -> ValeurJSON {
        try JSONDecoder().decode(ValeurJSON.self, from: Data(texte.utf8))
    }

    private let reponseValide = """
    {"global":{"canal_email":true,"canal_sms":false,"canal_push":true,"canal_in_app":false,
               "cree_le":"2026-10-01T08:00:00+00:00","mis_a_jour_le":"2026-10-02T08:00:00+00:00"},
     "par_evenement":[{"type_evenement":"LITIGE_RESOLU","canal":"PUSH","actif":false},
                      {"type_evenement":"URGENCE","canal":"IN_APP","actif":true}]}
    """

    func testDecodageDUneReponseValideEtDeLaLigneSoignant() throws {
        let p = try PreferencesNotifications.decoder(preferences: json(reponseValide),
                                                     soignant: json(#"{"sms_alertes_actives":false,"type_exercice":"LIBERAL"}"#))
        XCTAssertEqual(p, PreferencesNotifications(
            canalEmail: true, canalSms: false, canalPush: true, canalInApp: false,
            parEvenement: [PreferenceEvenement(typeEvenement: "LITIGE_RESOLU", canal: .push, actif: false),
                           PreferenceEvenement(typeEvenement: "URGENCE", canal: .inApp, actif: true)],
            smsAlertesActives: false, typeExercice: "LIBERAL"),
            "clés supplémentaires de `global` tolérées ; lignes hors catalogue conservées (relues, jamais envoyées)")
    }

    func testLigneSoignantAbsenteOuChampsNulsCommeLeWeb() throws {
        let sansLigne = try PreferencesNotifications.decoder(preferences: json(reponseValide), soignant: nil)
        XCTAssertNil(sansLigne.smsAlertesActives, "`profilSmsPresent` faux")
        XCTAssertNil(sansLigne.typeExercice)
        let nulle = try PreferencesNotifications.decoder(preferences: json(reponseValide), soignant: .null)
        XCTAssertNil(nulle.smsAlertesActives, "maybeSingle sans ligne = null")
        let champsNuls = try PreferencesNotifications.decoder(preferences: json(reponseValide),
                                                              soignant: json(#"{"sms_alertes_actives":null,"type_exercice":null}"#))
        XCTAssertEqual(champsNuls.smsAlertesActives, true, "`sms_alertes_actives ?? true` (l.129)")
        XCTAssertNil(champsNuls.typeExercice)
        let vide = try PreferencesNotifications.decoder(preferences: json(reponseValide), soignant: json("{}"))
        XCTAssertEqual(vide.smsAlertesActives, true)
    }

    func testDecodageRefuseTouteReponseQueLeWebRefuse() throws {
        let invalides = [
            #"{"error":"Non authentifié"}"#,
            #"{"par_evenement":[]}"#,
            #"{"global":null,"par_evenement":[]}"#,
            #"{"global":{"canal_email":true,"canal_sms":false,"canal_push":true},"par_evenement":[]}"#,
            #"{"global":{"canal_email":"true","canal_sms":false,"canal_push":true,"canal_in_app":true},"par_evenement":[]}"#,
            #"{"global":{"canal_email":true,"canal_sms":null,"canal_push":true,"canal_in_app":true},"par_evenement":[]}"#,
            #"{"global":{"canal_email":true,"canal_sms":false,"canal_push":1,"canal_in_app":true},"par_evenement":[]}"#,
            #"{"global":{"canal_email":true,"canal_sms":false,"canal_push":true,"canal_in_app":true}}"#,
            #"{"global":{"canal_email":true,"canal_sms":false,"canal_push":true,"canal_in_app":true},"par_evenement":{}}"#,
            #"[]"#,
            #"null"#,
        ]
        for texte in invalides {
            XCTAssertThrowsError(try PreferencesNotifications.decoder(preferences: json(texte), soignant: nil), texte) { erreur in
                XCTAssertEqual(erreur as? JoleneError, JoleneError(.contract, PreferencesNotifications.messageIndisponible))
            }
        }
    }

    /// Une ligne `par_evenement` illisible n'est jamais lue comme une absence (qui vaudrait « actif ») :
    /// erreur d'écran, aucun défaut affiché.
    func testLigneParEvenementIllisibleEstUneErreurDEcran() throws {
        let global = #""global":{"canal_email":true,"canal_sms":false,"canal_push":true,"canal_in_app":true}"#
        for ligne in [#"{"type_evenement":"LITIGE_RESOLU","canal":"FAX","actif":false}"#,
                      #"{"type_evenement":"LITIGE_RESOLU","canal":"PUSH","actif":"false"}"#,
                      #"{"type_evenement":"","canal":"PUSH","actif":false}"#,
                      #"{"canal":"PUSH","actif":false}"#,
                      #""LITIGE_RESOLU:PUSH""#] {
            XCTAssertThrowsError(try PreferencesNotifications.decoder(preferences: json("{\(global),\"par_evenement\":[\(ligne)]}"),
                                                                      soignant: nil), ligne)
        }
        XCTAssertThrowsError(try PreferencesNotifications.decoder(
            preferences: json(reponseValide), soignant: json(#"{"sms_alertes_actives":"oui"}"#)),
            "alerte SMS ni booléenne ni nulle : erreur d'écran")
    }

    // MARK: - Concordance de la relecture (aucun succès fabriqué)

    func testConcordanceDeLaRelectureAvecLaDemande() {
        var demande = prefs(sms: true, smsAlertes: false)
        demande.basculer(type: "LITIGE_OUVERT", canal: .sms)
        var relu = demande
        XCTAssertEqual(relu.concordance(avec: demande), ConcordancePreferences(generales: true, alerteSms: true))
        relu.smsAlertesActives = true
        XCTAssertEqual(relu.concordance(avec: demande), ConcordancePreferences(generales: true, alerteSms: false),
                       "alerte SMS non relue : échec partiel (web l.236-238)")
        relu = demande
        relu.canalPush = false
        XCTAssertFalse(relu.concordance(avec: demande).generales, "canal global non relu")
        relu = demande
        relu.parEvenement = []
        XCTAssertFalse(relu.concordance(avec: demande).generales, "exception envoyée (SMS coupé) mais relue absente (= actif)")
        var sansAlerte = demande
        sansAlerte.smsAlertesActives = nil
        relu = sansAlerte
        relu.smsAlertesActives = nil
        XCTAssertTrue(relu.concordance(avec: sansAlerte).alerteSms, "alerte non demandée : rien à vérifier")
        relu.typeExercice = "SALARIE"
        XCTAssertEqual(relu.concordance(avec: sansAlerte), ConcordancePreferences(generales: true, alerteSms: true),
                       "le régime est relu, jamais écrit : hors concordance")
    }

    // MARK: - Textes verbatim (HARD STOP n°4) et identifiants

    func testTextesVerbatimDuWeb() throws {
        let source = try web()
        let verbatim = [
            PreferencesTextes.titre, PreferencesTextes.sousTitre, PreferencesTextes.titreAlerteSms,
            PreferencesTextes.libelleAlerteSms, PreferencesTextes.titreCanaux, PreferencesTextes.descriptionCanaux,
            PreferencesTextes.titreEvenements, PreferencesTextes.descriptionEvenements, PreferencesTextes.texteUrgence,
            PreferencesTextes.enregistrer, PreferencesTextes.chargementImpossible, PreferencesTextes.reessayer,
            PreferencesTextes.enregistre, PreferencesTextes.echecEnregistrement,
        ] + CanalNotification.allCases.map(PreferencesTextes.libelleCanalGlobal)
          + CatalogueNotificationsSoignant.colonnes.map(PreferencesTextes.libelleColonne)
        for texte in verbatim {
            XCTAssertTrue(source.contains(texte) || source.contains(texte.replacingOccurrences(of: "'", with: "\\'")),
                          "« \(texte) » absent de \(Self.source)")
        }
        XCTAssertTrue(source.contains("'Préférences générales enregistrées, mais flag SMS d\\'alerte non sauvegardé.'"))
        XCTAssertEqual(PreferencesTextes.echecPartielAlerteSms, "Préférences générales enregistrées, mais flag SMS d'alerte non sauvegardé.")
        XCTAssertTrue(source.contains("Notifications d'urgence"))
        XCTAssertEqual(PreferencesTextes.titreUrgence, "Notifications d'urgence", "emoji ⚠️ remplacé par l'icône du ton « Attention »")
        XCTAssertTrue(source.contains("title={!canalGlobalActif ? `Canal ${c} désactivé dans les canaux globaux` : undefined}"))
        XCTAssertEqual(PreferencesTextes.raisonCanalDesactive(.sms), "Canal SMS désactivé dans les canaux globaux")
        XCTAssertEqual(PreferencesTextes.raisonCanalDesactive(.email), "Canal EMAIL désactivé dans les canaux globaux")
    }

    /// Décision 9 du lot 1 : textes non juridiques passés du tutoiement web au vouvoiement, seul écart.
    func testVouvoiementDesDeuxTextesTutoyesDuWeb() throws {
        let source = try web()
        XCTAssertTrue(source.contains("Recevoir un SMS pour les missions urgentes et le rappel mission J-1.\n"
                                      + "              Coût supporté par Jolene. Tu peux désactiver à tout moment."))
        XCTAssertEqual(PreferencesTextes.descriptionAlerteSms,
                       "Recevoir un SMS pour les missions urgentes et le rappel mission J-1. Coût supporté par Jolene. Vous pouvez désactiver à tout moment.")
        XCTAssertTrue(source.contains("Le canal « SMS » est désactivé dans les canaux globaux ci-dessous : active-le pour recevoir ces alertes."))
        XCTAssertEqual(PreferencesTextes.avertissementCanalSms,
                       "Le canal « SMS » est désactivé dans les canaux globaux ci-dessous : activez-le pour recevoir ces alertes.")
        let tous = [PreferencesTextes.descriptionAlerteSms, PreferencesTextes.avertissementCanalSms, PreferencesTextes.descriptionCanaux,
                    PreferencesTextes.descriptionEvenements, PreferencesTextes.texteUrgence, PreferencesTextes.sousTitre]
        for texte in tous {
            XCTAssertNil(texte.range(of: #"\b(tu|te|ton|ta|tes|toi)\b"#, options: [.regularExpression, .caseInsensitive]),
                         "tutoiement restant : « \(texte) »")
        }
    }

    /// Entrée du hub Profil vers l'écran (T6, repris par le hub de T11) : section « Réglages » (l.113) et
    /// ligne « Notifications » (l.115) de `MonCompteSoignant.tsx`, verbatim. Remplace le titre de section
    /// provisoire de la carte d'autorisation de T4 (`EtatNotificationsAppareil.sectionHub`, retiré). Le titre de
    /// la section a une seule source, `HubCompte.titreReglages` (revue B8 de T11, m7 : `PreferencesTextes.sectionHub`
    /// retiré, il n'était plus lu par l'app).
    func testEntreeDuHubVerbatim() throws {
        let hub = try String(contentsOf: Lot3PortsTests.racine.appendingPathComponent("src/pages/MonCompteSoignant.tsx"),
                             encoding: .utf8).components(separatedBy: "\n")
        XCTAssertEqual(HubCompte.titreReglages, "Réglages")
        XCTAssertEqual(PreferencesTextes.entreeHub, "Notifications")
        XCTAssertTrue(hub[112].contains("titre: '\(HubCompte.titreReglages)'"), "MonCompteSoignant.tsx l.113")
        XCTAssertTrue(hub[114].contains("label: '\(PreferencesTextes.entreeHub)', route: '/soignant/parametres/notifications'"),
                      "MonCompteSoignant.tsx l.115")
        XCTAssertEqual(PreferencesTextes.identifiantEntreeHub, "profile-preferences-notifications")
    }

    func testIdentifiantsDAccessibilite() {
        XCTAssertEqual(CanalNotification.allCases.map(PreferencesTextes.identifiantCanal),
                       ["prefs-canal-email", "prefs-canal-sms", "prefs-canal-push", "prefs-canal-inapp"])
        XCTAssertEqual(PreferencesTextes.identifiantEvenement(type: "CANDIDATURE_ACCEPTEE", canal: .sms),
                       "prefs-evt-CANDIDATURE_ACCEPTEE-SMS")
        XCTAssertEqual(PreferencesTextes.identifiantEvenement(type: "LITIGE_RESOLU", canal: .push), "prefs-evt-LITIGE_RESOLU-PUSH")
    }
}
