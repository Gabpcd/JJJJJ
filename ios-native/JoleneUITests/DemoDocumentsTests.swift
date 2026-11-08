import XCTest

/// Justificatifs en démo (lot 2 T7 ; blueprint `LOT2_PLAN.md` §3 T7, critères P10 et P4 niveau 2) : Profil › Mes
/// documents › Justificatifs, statuts du web (REJETE avant la date passée, expiration proche, vérifié), téléversement par
/// `DemoMediaPicker` (`-JOLENE_DEMO_SOURCE_DOC heic / png / trop-gros / annule`), réponse perdue réconciliée sans second
/// envoi (`-JOLENE_DEMO_SCENARIO upload-incertain`), attestation de santé, onglets en renvoi web. Écrit pour l'iPhone,
/// l'iPad portrait et l'iPad paysage (`JOLENE_UI_ORIENTATION`) ; aucune attente par délai fixe (`require`).
///
/// Textes : ceux du web (`DocumentsSoignant.tsx`, `ModalTeleversement.tsx`, `MesDocuments.tsx`), vouvoyés quand le web
/// tutoie ; textes de l'attestation verbatim (HARD STOP n°4, `TextesWeb.AttestationSante`). Le compteur DEBUG
/// `documents-demo-envois` lit le monde démo (envois acceptés, appels `verify-document`) : la preuve « une seule fois ».
final class DemoDocumentsTests: JoleneUITestCase {
    func testJustificatifsAffichentLesStatutsDuWeb() throws {
        launchDemo()
        signInDemo()
        ouvrirMesDocuments()

        let identite = element("document-statut-CARTE_IDENTITE")
        require("La pièce d'identité rejetée est affichée") { identite.exists }
        XCTAssertEqual(identite.label, "Rejeté", "REJETE prime sur la date de validité passée")
        XCTAssertTrue(element("document-message-CARTE_IDENTITE").label.contains("Pièce de démonstration illisible."),
                      "motif du rejet affiché")
        XCTAssertEqual(element("documents-prochaine-etape").label, "Téléverser — Pièce d'identité")
        XCTAssertTrue(element("documents-entete-titre").label.hasPrefix("Il vous reste 1 document"))

        let rcp = element("document-expire-bientot-demo-doc-rcp")
        require("L'expiration proche de la RCP est signalée") { rcp.exists }
        XCTAssertEqual(rcp.label, "⏰ Votre Assurance RCP expire dans 12 jours (14 nov. 2026).")

        let liste = element("documents-justificatifs")
        let diplome = element("document-statut-DIPLOME")
        scrollTo(diplome, in: liste)
        XCTAssertEqual(diplome.label, "Vérifié ✅")
        let rib = element("document-statut-RIB")
        scrollTo(rib, in: liste)
        XCTAssertEqual(rib.label, "Expiré")
        let carte = element("document-exigence-RIB").frame
        XCTAssertTrue(carte.minX >= app.frame.minX - 1 && carte.maxX <= app.frame.maxX + 1, "aucun débordement horizontal")
        record("\(proofPrefix)-justificatifs")
    }

    func testTeleverserLeDiplomeHeicPuisVerifie() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SOURCE_DOC", "heic"])
        signInDemo()
        ouvrirMesDocuments()

        let remplacer = element("document-televerser-DIPLOME")
        scrollTo(remplacer, in: element("documents-justificatifs"))
        XCTAssertEqual(remplacer.label, "Remplacer")
        tap("document-televerser-DIPLOME")
        attendreFeuille(type: "Diplôme d'État")
        XCTAssertFalse(element("document-confirmer").isEnabled, "aucun fichier choisi")
        XCTAssertEqual(element("document-libelle").placeholderValue, "Ex : Diplôme IDE 2020")

        tap("document-source-galerie")
        let choisi = element("document-fichier-choisi")
        require("Le HEIC est converti en JPEG avant l'envoi") { choisi.exists }
        XCTAssertEqual(choisi.label, "📎 justificatif-demo.jpg")
        record("\(proofPrefix)-televersement-heic")
        tap("document-confirmer")

        require("La feuille se ferme après l'enregistrement", timeout: 30) { !self.element("document-televersement").exists }
        let issue = element("documents-envoi-issue")
        require("L'issue de l'envoi est annoncée") { issue.exists }
        XCTAssertTrue(issue.label.contains("Document téléversé — vérification en cours (~30 s)."))
        let statut = element("document-statut-DIPLOME")
        require("Le verdict est relu en ligne", timeout: 30) { statut.exists && statut.label == "Vérifié ✅" }

        // Verdict VERIFIE : la prochaine exigence critique s'ouvre (`DocumentsSoignant.tsx` l.272-274).
        attendreFeuille(type: "Pièce d'identité")
        tap("document-annuler")
        require("La feuille suivante se ferme sans envoi") { !self.element("document-televersement").exists }
        XCTAssertEqual(element("documents-demo-envois").label, "1 envoi · 1 vérification", "verify-document une seule fois")
        record("\(proofPrefix)-televersement-verifie")
        retourAuProfilSansRequete()
    }

    func testFichierTropLourdRefuseAvantToutEnvoi() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SOURCE_DOC", "trop-gros"])
        signInDemo()
        ouvrirMesDocuments()

        tap("documents-prochaine-etape")
        attendreFeuille(type: "Pièce d'identité")
        tap("document-source-fichiers")
        let erreur = element("document-fichier-erreur")
        require("Le refus local du web est affiché") { erreur.exists }
        XCTAssertTrue(erreur.label.contains("Le fichier ne doit pas dépasser 10 Mo."))
        XCTAssertFalse(element("document-fichier-choisi").exists)
        XCTAssertFalse(element("document-confirmer").isEnabled)
        record("\(proofPrefix)-televersement-trop-lourd")

        tap("document-annuler")
        require("La feuille se ferme") { !self.element("document-televersement").exists }
        XCTAssertEqual(element("document-statut-CARTE_IDENTITE").label, "Rejeté", "rien n'a changé")
        XCTAssertEqual(element("documents-demo-envois").label, "0 envoi · 0 vérification")
    }

    func testSelectionAnnuleeNEnvoieRien() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SOURCE_DOC", "annule"])
        signInDemo()
        ouvrirMesDocuments()

        tap("documents-prochaine-etape")
        attendreFeuille(type: "Pièce d'identité")
        tap("document-source-camera")
        tap("document-source-galerie")
        tap("document-source-fichiers")
        XCTAssertFalse(element("document-fichier-choisi").exists, "aucun fichier rendu")
        XCTAssertFalse(element("document-fichier-erreur").exists)
        XCTAssertFalse(element("document-confirmer").isEnabled)

        tap("document-annuler")
        require("La feuille se ferme") { !self.element("document-televersement").exists }
        XCTAssertFalse(element("documents-envoi-issue").exists, "aucune issue d'envoi")
        XCTAssertEqual(element("documents-demo-envois").label, "0 envoi · 0 vérification")
    }

    func testEnvoiIncertainReconcilieSansSecondEnvoi() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SOURCE_DOC", "png", "-JOLENE_DEMO_SCENARIO", "upload-incertain"])
        signInDemo()
        ouvrirMesDocuments()

        tap("documents-prochaine-etape")
        attendreFeuille(type: "Pièce d'identité")
        tap("document-source-fichiers")
        let choisi = element("document-fichier-choisi")
        require("Le PNG est choisi tel quel depuis Fichiers") { choisi.exists }
        XCTAssertEqual(choisi.label, "📎 justificatif-demo.png")
        XCTAssertEqual(element("document-fichier-taille").label, "0 Ko")
        tap("document-confirmer")

        // Réponse perdue après application : réconciliation par relecture de la ligne, jamais de renvoi.
        require("La feuille se ferme après la réconciliation", timeout: 30) { !self.element("document-televersement").exists }
        let issue = element("documents-envoi-issue")
        require("La ligne relue donne la vérification en cours") { issue.exists }
        XCTAssertTrue(issue.label.contains("Document téléversé — vérification en cours (~30 s)."))
        XCTAssertEqual(element("documents-demo-envois").label, "1 envoi · 1 vérification", "aucun second envoi")
        let statut = element("document-statut-CARTE_IDENTITE")
        require("Le verdict est relu en ligne", timeout: 30) { statut.exists && statut.label == "Vérifié ✅" }
        let aJour = element("documents-entete-titre")
        require("Toutes les pièces obligatoires sont valides") { aJour.label == "Tous vos documents obligatoires sont à jour 🎉" }
        XCTAssertFalse(element("document-televersement").exists, "aucune exigence suivante à ouvrir")
        record("\(proofPrefix)-televersement-reconcilie")
    }

    func testAttestationDeSanteSigneeApresLesDeuxCases() throws {
        launchDemo()
        signInDemo()
        ouvrirMesDocuments()

        let liste = element("documents-justificatifs")
        let vaccins = element("attestation-vaccins")
        scrollTo(vaccins, in: liste)
        XCTAssertTrue(vaccins.label.contains("J'atteste sur l'honneur que mes vaccinations obligatoires sont à jour"),
                      "texte verbatim du web (HARD STOP n°4)")
        let signer = element("attestation-signer")
        scrollTo(signer, in: liste)
        XCTAssertFalse(signer.isEnabled, "les deux cases d'abord")
        if !visible(vaccins) { scrollTo(vaccins, in: liste) }
        tap("attestation-vaccins")
        let medecine = element("attestation-medecine")
        if !visible(medecine) { scrollTo(medecine, in: liste) }
        tap("attestation-medecine")
        if !visible(signer) { scrollTo(signer, in: liste) }
        require("La signature est possible après les deux cases") { signer.isEnabled }
        XCTAssertEqual(signer.label, "✅ Signer mon attestation")
        tap("attestation-signer")

        let signee = element("attestation-signee")
        require("La date relue au serveur est affichée", timeout: 30) { signee.exists }
        XCTAssertEqual(signee.label, "✅ Attestation signée le 2 novembre 2026")
        XCTAssertEqual(element("attestation-badge").label, "Signée")
        XCTAssertFalse(element("attestation-signer").exists, "jamais une seconde signature")
        record("\(proofPrefix)-attestation-signee")
    }

    /// Contrats : liste native de T9a depuis l'intégration (migré du renvoi web de T7) ; DPAE : renvoi web (décision 16).
    func testOngletContratsNatifEtDpaeEnRenvoiWeb() throws {
        launchDemo()
        signInDemo()
        ouvrirMesDocuments()

        tap("documents-tab-dpae")
        let dpae = element("documents-dpae-renvoi")
        require("L'onglet DPAE renvoie au web") { dpae.exists }
        XCTAssertTrue(dpae.label.contains("Cet espace n'est pas encore disponible dans l'application. Rendez-vous sur jolene.app."))
        // Verrou du gap (`PresentateurRenvoiWeb`) : aucun bouton tant que le présentateur n'est pas injecté.
        XCTAssertFalse(element("documents-dpae-web").exists)
        XCTAssertTrue(element("documents-tab-dpae").isSelected)
        record("\(proofPrefix)-documents-dpae")

        tap("documents-tab-contrats")
        require("L'onglet Contrats affiche la liste native (T9a)") { self.containerVisible(self.element("contrats-liste")) }
        require("Les contrats démo sont chargés", timeout: 30) { self.element("contrat-carte-demo-contrat-001").exists }
        XCTAssertTrue(element("documents-tab-contrats").isSelected)
        XCTAssertFalse(element("documents-contrats-renvoi").exists, "renvoi web retiré par T9a")
        XCTAssertFalse(element("documents-dpae-renvoi").exists)

        tap("documents-tab-justificatifs")
        require("Les justificatifs reviennent") { self.element("document-statut-CARTE_IDENTITE").exists }
        XCTAssertFalse(element("documents-dpae-renvoi").exists)
    }

    // MARK: Étapes

    private func signInDemo() {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.visible(scroll) }
        let email = element("login-email")
        focus(email, in: scroll)
        email.typeText(Self.demoEmail)
        let password = element("login-password")
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(Self.demoPassword)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) { scrollTo(submit, in: scroll) }
        submit.tap()
        require("La session est prête : la barre d'onglets est affichée", timeout: 30) { self.tabBarExists }
    }

    /// Profil › Mon espace › Mes documents : l'onglet Justificatifs est ouvert par défaut (`MesDocuments.tsx` l.24).
    private func ouvrirMesDocuments() {
        tabButton("tab-profil", label: "Profil").tap()
        let entree = element("profil-documents")
        require("Le profil est affiché") { self.containerVisible(self.element("profile-list")) }
        // « Mon espace » est sous « Application » (intégration de T4a) : une cellule hors écran d'une `List` n'existe
        // pas encore dans l'arbre, d'où un défilement borné vers le bas avant le tap.
        if !visible(entree) { scrollTo(entree, in: element("profile-list")) }
        tap("profil-documents")
        require("L'écran Mes documents est affiché") { self.containerVisible(self.element("documents-screen")) }
        require("Le dossier est chargé", timeout: 30) { self.element("document-exigence-CARTE_IDENTITE").exists }
        XCTAssertTrue(element("documents-tab-justificatifs").isSelected)
    }

    /// Feuille de téléversement ouverte pour le type annoncé (`ModalTeleversement.tsx` l.121-125).
    private func attendreFeuille(type: String) {
        let feuille = element("document-televersement")
        require("La feuille de téléversement est affichée", timeout: 30) {
            self.containerVisible(feuille) && self.element("document-televersement-type").label == type
        }
        XCTAssertEqual(element("document-televersement-titre").label, "📤 Téléverser")
    }

    /// Retour au Profil : la sentinelle réseau reste à « 0 requête » après l'envoi démo.
    private func retourAuProfilSansRequete() {
        let retour = app.navigationBars.buttons.element(boundBy: 0)
        require("Le bouton de retour est affiché") { self.visible(retour) }
        retour.tap()
        let liste = element("profile-list")
        require("Le profil est de retour") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        // La sentinelle (« Application ») est au-dessus de « Mon espace », d'où la liste a été ouverte : défilement
        // borné vers le haut (intégration de T4a).
        if !visible(sentinelle) { scrollTo(sentinelle, in: liste, downward: false) }
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "aucune requête réseau en démonstration")
    }
}
