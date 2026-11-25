import CoreImage
import CryptoKit
import XCTest

/// Entrée privée du run (schéma `lot5-staging-etab-v1`, écrite par `staging-lot5-fixture.mjs`).
private struct CohorteLot5Staging: Sendable {
    let marker: String
    let email: String
    let password: String
    let m1: String
    let m1Intitule: String
    let m2: String
    let m2Intitule: String
    let candidature: String
    let contrat: String
    let codeSha256: String
    let presence: String?
}

/// Parcours réel de l'espace établissement contre le serveur de test (lot 5, T13 ; `docs/mobile-swift/LOT5_PLAN.md`
/// §3 T13, `DECISIONS_LOT5.md` section T13). Lancé uniquement par `ios-swift-lot5-staging.yml`, en deux invocations
/// `-only-testing` séparées par les scans du soignant que le job fait sous le JWT de S1 ; scheme `Jolene-Staging`. La
/// cohorte (E1 propriétaire legacy, S1, M1 et sa candidature, M2 au contrat signé) est préparée par
/// `scripts/mobile/staging-lot5-fixture.mjs` et décrite dans `JOLENE_LOT5_STAGING_JSON` (runner seulement, jamais
/// dans l'environnement de l'app). Hors de ce contexte, chaque test est ignoré (`XCTSkip`) ; le job UI démo l'exclut
/// explicitement (`-skip-testing`).
///
/// Étapes, assertions sur texte et identifiants (aucune capture d'écran n'est une preuve, aucune n'est jointe) :
/// - phase 1 : (a) connexion d'E1 → espace établissement, nom affiché égal au marqueur du run ; (b) M1 et M2 listées ;
///   (c) candidature de S1 sur M1 acceptée par le récapitulatif, relue « Acceptée » ; (d) contrat de M2 lu
///   « Statut : ✅ Signé » ; (e) code de pointage de M2 affiché, son empreinte SHA-256 égale à celle du code relu côté
///   service à la préparation, et le QR du plein écran décodé (`CIDetector`) égal au code affiché — jamais le code
///   en clair dans un message ou une pièce jointe ;
/// - phase 2 (après les deux scans et la fin du créneau planifié) : présence de S1 sur M2 validée avec une note de 4,
///   annoncée après relecture puis relue « Validée ».
/// Les relectures en base (candidature ACCEPTEE, `presences.valide_par_etablissement`, aucune ligne d'escrow) et le
/// nettoyage sont faits par le job (`staging-lot5-fixture.mjs verifier` puis `nettoyer`).
final class StagingEtabParcoursTests: JoleneUITestCase {
    /// Lue dans `setUpWithError` (crochet XCTest non isolé, thread principal), comme `proofPrefix` du socle.
    nonisolated(unsafe) private var cohorte: CohorteLot5Staging!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let environment = ProcessInfo.processInfo.environment
        guard environment["JOLENE_MODE"] == "staging" else {
            throw XCTSkip("Parcours établissement STAGING : JOLENE_MODE=staging absent du runner (lancé hors ios-swift-lot5-staging.yml).")
        }
        guard let brut = environment["JOLENE_LOT5_STAGING_JSON"], !brut.isEmpty else {
            throw XCTSkip("Parcours établissement STAGING : cohorte absente (JOLENE_LOT5_STAGING_JSON).")
        }
        cohorte = try Self.lire(brut)
    }

    /// Lit la cohorte sans rien journaliser ; refuse tout autre projet que le STAGING.
    nonisolated private static func lire(_ brut: String) throws -> CohorteLot5Staging {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(brut.utf8)) as? [String: Any], "cohorte illisible")
        XCTAssertEqual(json["purpose"] as? String, "lot5-staging-etab-v1")
        XCTAssertEqual(json["projectRef"] as? String, "mejpriaetwgtcstbgfid", "STAGING uniquement")
        let etab = try XCTUnwrap(json["etablissement"] as? [String: Any])
        let m1 = try XCTUnwrap(json["m1"] as? [String: Any])
        let m2 = try XCTUnwrap(json["m2"] as? [String: Any])
        let email = try XCTUnwrap(etab["email"] as? String)
        XCTAssertTrue(email.hasSuffix("@example.invalid"), "la cohorte n'emploie que des adresses invalides")
        let empreinte = try XCTUnwrap(json["codeSha256"] as? String)
        XCTAssertEqual(empreinte.count, 64, "empreinte SHA-256 hexadécimale")
        return CohorteLot5Staging(marker: try XCTUnwrap(json["marker"] as? String), email: email,
                       password: try XCTUnwrap(etab["password"] as? String),
                       m1: try XCTUnwrap(m1["id"] as? String), m1Intitule: try XCTUnwrap(m1["intitule"] as? String),
                       m2: try XCTUnwrap(m2["id"] as? String), m2Intitule: try XCTUnwrap(m2["intitule"] as? String),
                       candidature: try XCTUnwrap(json["candidatureId"] as? String),
                       contrat: try XCTUnwrap(json["contratM2Id"] as? String), codeSha256: empreinte,
                       presence: json["presenceId"] as? String)
    }

    // MARK: Phases

    func testPhase1ConnexionCandidatureAccepteeContratSigneEtCodeDePointage() throws {
        lancerEtConnecter()

        // (a) Espace établissement d'E1 : le nom affiché est celui du run, servi par le serveur.
        let nom = element("etab-accueil-nom")
        require("Le nom de l'établissement est relu") { nom.exists && !nom.label.isEmpty }
        XCTAssertEqual(nom.label, cohorte.marker, "nom de l'établissement servi par fn_mon_etablissement_complet")
        XCTAssertFalse(element("access-blocked").exists, "espace ouvert en STAGING (T13), jamais le refus d'avant le lot 5")
        XCTAssertFalse(element("etab-scope-divergent").exists, "périmètre confirmé (propriétaire legacy)")

        // (b) Missions de la cohorte listées par leur statut.
        ouvrirMissions(filtre: "OUVERTE", carte: cohorte.m1)
        ouvrirMissions(filtre: "ASSIGNEE", carte: cohorte.m2)

        // (c) Candidature de S1 sur M1 : récapitulatif relu, confirmation, statut relu « Acceptée ».
        ouvrirDetail(mission: cohorte.m1, filtre: "OUVERTE", intitule: cohorte.m1Intitule)
        let lienCandidatures = element("etab-mission-lien-candidatures")
        scrollTo(lienCandidatures, in: element("etab-mission-detail"))
        lienCandidatures.tap()
        let ecran = element("etab-candidatures-screen")
        let accepter = element("etab-candidature-accepter-\(cohorte.candidature)")
        require("La candidature de S1 est relue", timeout: 45) { self.containerVisible(ecran) && accepter.exists }
        scrollTo(accepter, in: ecran)
        require("L'acceptation est offerte") { accepter.isEnabled }
        accepter.tap()
        let confirmer = element("etab-recap-confirm")
        require("Le récapitulatif relu est présenté", timeout: 45) { self.element("etab-recap").exists && confirmer.exists }
        XCTAssertEqual(element("etab-recap-title").label, "Confirmer l’acceptation")
        scrollTo(confirmer, in: element("etab-recap"))
        require("La confirmation est active") { confirmer.isEnabled }
        confirmer.tap()
        let statut = element("etab-candidature-statut-\(cohorte.candidature)")
        require("La candidature est relue « Acceptée »", timeout: 60) {
            !self.element("etab-recap").exists && statut.exists && statut.label == "Acceptée"
        }
        XCTAssertTrue(element("etab-candidatures-succes").exists, "succès affiché après relecture seulement")
        revenirALaListe()

        // (d) Contrat de M2, inséré signé côté service : lu « Statut : ✅ Signé » dans l'écran du contrat.
        let entree = element("etab-missions-contrats")
        require("L'entrée « Contrats » est rendue") { entree.exists }
        entree.tap()
        let carteContrat = element("etab-contrat-\(cohorte.contrat)")
        require("Le contrat de M2 est listé", timeout: 45) {
            self.containerVisible(self.element("etab-contrats-screen")) && carteContrat.exists
        }
        scrollTo(carteContrat, in: element("etab-contrats-screen"))
        carteContrat.tap()
        let statutContrat = element("contrat-statut")
        require("Le contrat est relu", timeout: 45) { self.containerVisible(self.element("contrat-detail")) && statutContrat.exists }
        XCTAssertEqual(statutContrat.label, "Statut : ✅ Signé", "contrat SIGNE_COMPLET relu au serveur")
        XCTAssertFalse(element("contrat-otp-envoyer").exists, "aucune signature à faire : aucun OTP, aucun SMS")
        revenirALaListe()

        // (e) Code de pointage de M2 : égal (empreinte) au code relu côté service, QR égal au code affiché.
        ouvrirDetail(mission: cohorte.m2, filtre: "ASSIGNEE", intitule: cohorte.m2Intitule)
        let lienPointage = element("etab-mission-lien-pointage")
        scrollTo(lienPointage, in: element("etab-mission-detail"))
        lienPointage.tap()
        let code = element("etab-pointage-code")
        require("Le code de pointage de M2 est affiché", timeout: 60) {
            self.containerVisible(self.element("etab-pointage-screen")) && !self.element("etab-pointage-loading").exists
                && (code.exists || self.element("etab-pointage-masque").exists)
        }
        XCTAssertFalse(element("etab-pointage-masque").exists, "contrat signé, créneau dans la fenêtre : code non masqué")
        XCTAssertFalse(element("etab-pointage-reserve").exists, "propriétaire : permission pointage servie")
        let chiffres = code.label.filter(\.isNumber)
        XCTAssertEqual(chiffres.count, 6, "code à six chiffres")
        XCTAssertEqual(Self.empreinte(chiffres), cohorte.codeSha256,
                       "code affiché = code_pointage_actif relu côté service à la préparation (empreintes comparées)")
        XCTAssertTrue(element("etab-pointage-qr").exists, "QR du code rendu")

        // QR décodé en plein écran, comme `DemoEtabPointageTests` (le QR en ligne peut être rogné sous la barre d'onglets).
        scrollTo(element("etab-pointage-plein-ecran"), in: defilementPointage)
        tap("etab-pointage-plein-ecran")
        let vue = element("etab-pointage-plein-ecran-vue")
        require("Le code est présenté en plein écran") { vue.exists && self.element("etab-pointage-plein-ecran-qr").exists }
        let affichePleinEcran = element("etab-pointage-plein-ecran-code").label.filter(\.isNumber)
        XCTAssertEqual(Self.empreinte(affichePleinEcran), cohorte.codeSha256, "plein écran : même code relu au serveur")
        let lu = decoderQR(element("etab-pointage-plein-ecran-qr"))
        XCTAssertNotNil(lu, "QR du plein écran lisible")
        XCTAssertTrue(lu == affichePleinEcran, "le QR encode la valeur affichée (D4) ; valeurs jamais recopiées")
        tap("etab-pointage-fermer")
        require("Le plein écran est fermé") { !vue.exists && self.element("etab-pointage-code").exists }
    }

    func testPhase2ValidationDeLaPresenceApresLesScansDuSoignant() throws {
        let presence = try XCTUnwrap(cohorte.presence, "présence absente : la phase 2 suit l'étape « scanner » du job")
        lancerEtConnecter()
        tabButton("tab-etab-presences", label: "Présences").tap()
        require("Les présences de l'établissement sont relues", timeout: 45) {
            self.containerVisible(self.element("etab-presences-screen")) && !self.element("etab-presences-loading").exists
                && self.element("etab-presences-tab-a_valider").exists
        }
        let valider = element("etab-presence-valider-\(presence)")
        require("La présence de S1 sur M2 est à valider", timeout: 45) { valider.exists }
        XCTAssertEqual(element("etab-presence-statut-\(presence)").label, "À valider")
        scrollTo(valider, in: defilementPresences)
        valider.tap()
        let confirmer = element("etab-presence-confirmer")
        require("La note est demandée avant la validation") { confirmer.exists && self.element("etab-presence-note-4").exists }
        XCTAssertFalse(confirmer.isEnabled, "aucune validation sans note")
        tap("etab-presence-note-4")
        require("La note choisie active la validation") { confirmer.isEnabled }
        scrollTo(confirmer, in: element("etab-validation-feuille"))
        confirmer.tap()
        let succes = element("etab-presences-succes")
        require("La validation relue est annoncée", timeout: 60) { !confirmer.exists && succes.exists }
        XCTAssertTrue(succes.label.contains("Présence validée"), succes.label)
        XCTAssertFalse(element("etab-presence-valider-\(presence)").exists, "une présence validée n'est plus proposée")
        tap("etab-presences-tab-validees")
        let statut = element("etab-presence-statut-\(presence)")
        require("La présence est relue « Validée »", timeout: 45) { statut.exists && statut.label == "Validée" }
    }

    // MARK: Étapes

    private func lancerEtConnecter() {
        // 1re session imposée (DEBUG) : le pré-prompt de notification ne recouvre jamais le parcours.
        app.launchArguments = ["-JOLENE_MODE", "staging", "-JOLENE_SESSION_COUNT", "1"]
        app.launchEnvironment = [:] // jamais la cohorte dans l'environnement de l'app
        app.launch()
        applyOrientation()
        let scroll = element("login-scroll")
        if !visible(scroll) {
            // Session restaurée d'une phase précédente : l'espace établissement est déjà ouvert.
            require("L'espace établissement ou la connexion est affiché", timeout: 60) {
                self.visible(scroll) || self.containerVisible(self.element("etab-accueil-screen"))
            }
            if !visible(scroll) { return }
        }
        XCTAssertFalse(element("env-blocked").exists, "la garde d'environnement accepte la configuration STAGING")
        let email = element("login-email")
        focus(email, in: scroll)
        viderChamp(email)
        email.typeText(cohorte.email)
        let password = element("login-password")
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(cohorte.password)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) { scrollTo(submit, in: scroll) }
        // Second parcours STAGING (25/11/2026) : l'attente s'arrête aussi sur un refus de connexion, qui est alors nommé
        // avec son diagnostic DEBUG (`login-error`, valeur d'accessibilité : étape et nature de l'échec, sans secret).
        let erreur = element("login-error")
        toucherSeConnecter(submit, "L'espace établissement STAGING est prêt, ou la connexion est refusée", timeout: 90) {
            (self.tabBarExists && self.containerVisible(self.element("etab-accueil-screen"))) || erreur.exists
        }
        if erreur.exists {
            XCTFail("Connexion STAGING refusée : « \(erreur.label) » — diagnostic : \((erreur.value as? String) ?? "absent")")
            return
        }
    }

    private func ouvrirMissions(filtre: String, carte id: String) {
        if !containerVisible(element("etab-missions-screen")) { tabButton("tab-etab-missions", label: "Missions").tap() }
        require("La liste des missions est relue", timeout: 45) {
            self.containerVisible(self.element("etab-missions-screen")) && self.element("etab-missions-count").exists
        }
        tap("etab-missions-filtre-\(filtre)")
        let carte = element("etab-mission-card-\(id)")
        require("La mission \(filtre) de la cohorte est listée", timeout: 45) { carte.exists }
    }

    private func ouvrirDetail(mission id: String, filtre: String, intitule: String) {
        ouvrirMissions(filtre: filtre, carte: id)
        let carte = element("etab-mission-card-\(id)")
        scrollTo(carte, in: element("etab-missions-scroll"))
        carte.tap()
        require("Le détail de la mission est relu", timeout: 45) { self.element("etab-mission-titre").label == intitule }
    }

    private func revenirALaListe() {
        for _ in 0..<4 where !containerVisible(element("etab-missions-screen")) {
            let retour = app.navigationBars.buttons.firstMatch
            require("Le bouton retour est disponible") { self.visible(retour) }
            retour.tap()
        }
        require("La liste des missions est affichée") { self.containerVisible(self.element("etab-missions-screen")) }
    }

    /// Défilement de l'écran du code (même règle que `DemoEtabPointageTests` : SwiftUI peut fondre les deux identifiants).
    private var defilementPointage: XCUIElement {
        app.scrollViews.matching(NSPredicate(format: "identifier IN %@", ["etab-pointage-scroll", "etab-pointage-screen"])).firstMatch
    }

    /// Défilement des présences (même règle que `DemoEtabPresencesTests`).
    private var defilementPresences: XCUIElement {
        app.scrollViews.matching(NSPredicate(format: "identifier IN %@", ["etab-presences-scroll", "etab-presences-screen"])).firstMatch
    }

    private static func empreinte(_ valeur: String) -> String {
        SHA256.hash(data: Data(valeur.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// QR de l'élément relu sur sa capture (`CIDetector`, précision haute) ; `nil` si aucun QR n'est lu.
    private func decoderQR(_ element: XCUIElement) -> String? {
        guard element.exists, let image = CIImage(image: element.screenshot().image),
              let detecteur = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(options: [.useSoftwareRenderer: true]),
                                         options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return detecteur.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}
