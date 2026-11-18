import XCTest

/// Stripe Connect en démo (lot 3, T14a, B9) sur iPhone, iPad portrait et iPad paysage (`JOLENE_UI_ORIENTATION`,
/// `proofPrefix`). Serveur simulé `DemoStripeConnectGateway` (profil fictif `MIXTE`, statut `NON_DEMANDE` ; variante
/// `-JOLENE_DEMO_STRIPE TEST`), flux hébergé simulé `DemoExternalFlow` (retour `?success=true` aussitôt, sans feuille).
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - l'entrée « Compte de paiement (Stripe) » du hub ouvre l'écran natif réellement monté sur l'onglet Profil ;
/// - « Connecter mon compte bancaire » ouvre le flux puis relit le statut avec `force=true` : le serveur simulé ne rend
///   `COMPLET` qu'à une lecture forcée (une lecture du cache rendrait encore `NON_DEMANDE`) ;
/// - le retour de Stripe par lien (`/soignant/stripe-connect?success=true`) ouvre l'écran natif, et un compte de test y
///   voit « Stripe désactivé sur ce compte de test » sans bouton d'onboarding.
/// Les règles (six statuts, `COMPLET` et ses drapeaux, en-tête `Origin`, 403, aucun appel d'edge pour un compte de test)
/// sont prouvées au niveau 1 (`StripeConnectTests`, `SupabaseStripeConnectGatewayTests`). L'onboarding Stripe TEST réel
/// et le retour par lien universel se prouvent sur STAGING et sur appareil (T16, T17).
final class DemoStripeTests: JoleneUITestCase {
    func testEntreeDuHubPuisOnboardingRelitLeStatutForce() throws {
        launchDemo()
        connexionDemo()
        tabButton("tab-profil", label: "Profil").tap()
        let hub = element("profile-list")
        require("Le hub est affiché") { self.containerVisible(hub) }
        // Ligne Stripe montée une fois l'exercice lu (profil MIXTE), en tête de la section « Paiements & facturation »,
        // juste au-dessus de « Coordonnées bancaires » (toujours montée) depuis l'intégration vague A (revue B8 de #1154,
        // m2). Cellule hors écran absente de l'arbre : on amène d'abord `iban-ouvrir` à l'écran (il arrive par le bas,
        // la ligne qui le précède est donc dans le cadre), on attend la lecture de l'exercice, puis on cherche la ligne
        // Stripe vers le haut, sans jamais la dépasser vers le bas.
        scrollTo(element("iban-ouvrir"), in: hub)
        let entree = element("profile-stripe-connect")
        _ = entree.waitForExistence(timeout: 15)
        scrollTo(entree, in: hub, downward: false)
        XCTAssertEqual(entree.label, "Compte de paiement (Stripe)")
        entree.tap()
        let nonDemande = element("stripe-statut-NON_DEMANDE")
        require("Statut NON_DEMANDE lu", timeout: 30) { self.containerVisible(self.element("stripe-screen")) && nonDemande.exists }
        XCTAssertEqual(element("stripe-statut-NON_DEMANDE-titre").label, "Reçois tes honoraires directement")
        record("\(proofPrefix)-stripe-non-demande")
        let onboarding = element("stripe-onboarding")
        scrollTo(onboarding, in: element("stripe-screen"))
        XCTAssertEqual(onboarding.label, "Connecter mon compte bancaire")
        onboarding.tap()
        require("Statut relu avec force=true après le retour du flux", timeout: 30) {
            self.element("stripe-statut-COMPLET").exists
        }
        XCTAssertFalse(nonDemande.exists)
        XCTAssertEqual(element("stripe-statut-COMPLET-titre").label, "Compte connecté")
        XCTAssertFalse(element("stripe-erreur").exists)
        record("\(proofPrefix)-stripe-complet")
    }

    func testRetourParLienCompteTestSansOnboarding() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_STRIPE", "TEST",
                                    "-JOLENE_OPEN_URL", "https://jolene.app/soignant/stripe-connect?success=true"])
        connexionDemo()
        let carte = element("stripe-compte-test")
        require("Écran natif ouvert par le lien, compte de test", timeout: 30) {
            self.containerVisible(self.element("stripe-screen")) && carte.exists
        }
        XCTAssertEqual(element("stripe-compte-test-titre").label, "Stripe désactivé sur ce compte de test")
        XCTAssertFalse(element("stripe-onboarding").exists, "compte de test : aucun onboarding proposé")
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T14a) : jamais un renvoi web")
        XCTAssertEqual(element("deeplink-route").label, "stripeConnect(succes)")
        record("\(proofPrefix)-stripe-compte-test")
    }

    private func connexionDemo() {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.containerVisible(scroll) }
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
        toucherSeConnecter(submit, "La session démo est prête") { self.tabBarExists }
    }
}
