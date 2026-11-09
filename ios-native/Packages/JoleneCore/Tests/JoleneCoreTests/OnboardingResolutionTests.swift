import XCTest
@testable import JoleneCore

/// Aiguillage d'onboarding (lot 3, T7) : ports de `registrationIntent` / `registrationDraft`
/// (`mobile-native/src/account/resolveContext.ts` l.8-22) et de la décision de `ParcoursInscription.tsx` l.39-75.
final class OnboardingResolutionTests: XCTestCase {
    private let userId = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66"

    private func ligne(userId: String? = nil, type: ValeurJSON = .chaine("SOIGNANT"),
                       donnees: ValeurJSON = .objet(["profession": .chaine("IDE")]),
                       modifieLe: ValeurJSON = .chaine("2026-11-02T10:00:00+00:00")) -> ValeurJSON {
        .objet([
            "user_id": .chaine(userId ?? self.userId), "type_compte": type, "donnees": donnees,
            "consentement_cgu_le": .chaine("2026-11-02T09:59:00+00:00"), "modifie_le": modifieLe,
        ])
    }

    // MARK: - Intention (`registrationIntent`)

    func testIntentionSoignantValideAvecCguVraie() {
        let valeur: ValeurJSON = .objet(["type": .chaine("SOIGNANT"), "profession": .chaine("IDE"), "nom": .chaine(""),
                                         "cgu": .booleen(true), "cgv": .booleen(false)])
        XCTAssertEqual(OnboardingResolution.intention(depuis: valeur),
                       IntentionInscription(typeCompte: "SOIGNANT", profession: "IDE", nom: "", cgu: true, cgv: false))
    }

    func testIntentionSansCguVraieIgnoree() {
        for cgu in [ValeurJSON.booleen(false), .chaine("true"), .nombre(1), .null] {
            XCTAssertNil(OnboardingResolution.intention(depuis: .objet(["type": .chaine("SOIGNANT"), "cgu": cgu])), "\(cgu)")
        }
        XCTAssertNil(OnboardingResolution.intention(depuis: .objet(["type": .chaine("SOIGNANT")])))
    }

    func testIntentionTypeInconnuOuAbsenteIgnoree() {
        XCTAssertNil(OnboardingResolution.intention(depuis: nil))
        XCTAssertNil(OnboardingResolution.intention(depuis: .null))
        XCTAssertNil(OnboardingResolution.intention(depuis: .chaine("SOIGNANT")))
        XCTAssertNil(OnboardingResolution.intention(depuis: .objet(["type": .chaine("ADMIN_PLATEFORME"), "cgu": .booleen(true)])))
        XCTAssertNil(OnboardingResolution.intention(depuis: .objet(["type": .chaine("soignant"), "cgu": .booleen(true)])))
    }

    func testIntentionEtablissementExigeCgv() {
        XCTAssertNil(OnboardingResolution.intention(depuis: .objet(["type": .chaine("ETABLISSEMENT"), "cgu": .booleen(true)])))
        XCTAssertEqual(OnboardingResolution.intention(depuis: .objet([
            "type": .chaine("ETABLISSEMENT"), "nom": .chaine("Clinique"), "cgu": .booleen(true), "cgv": .booleen(true),
        ])), IntentionInscription(typeCompte: "ETABLISSEMENT", profession: "", nom: "Clinique", cgu: true, cgv: true))
    }

    func testProfessionEtNomNonTextuelsDeviennentVides() {
        let intention = OnboardingResolution.intention(depuis: .objet([
            "type": .chaine("SOIGNANT"), "profession": .nombre(3), "nom": .null, "cgu": .booleen(true),
        ]))
        XCTAssertEqual(intention?.profession, "")
        XCTAssertEqual(intention?.nom, "")
        XCTAssertEqual(intention?.cgv, false)
    }

    // MARK: - Parcours (`registrationDraft`)

    func testParcoursAbsentRendNil() throws {
        XCTAssertNil(try OnboardingResolution.parcours(depuis: nil, userId: userId))
        XCTAssertNil(try OnboardingResolution.parcours(depuis: .null, userId: userId))
    }

    func testParcoursValideRestitueLeBrouillonDeLaListeBlanche() throws {
        let donnees: ValeurJSON = .objet([
            "profession": .chaine("IDE"), "prenom": .chaine("Léa"), "nom": .chaine("Martin"), "telephone": .chaine("0600000000"),
            "dateNaissance": .chaine("1990-05-14"), "typesContrat": .tableau([.chaine("SALARIE"), .nombre(1), .chaine("LIBERAL")]),
            "rpps": .nombre(10_000_000_000), "rayon": .nombre(30), "estSalarieEtablissement": .booleen(true),
        ])
        let parcours = try XCTUnwrap(try OnboardingResolution.parcours(depuis: ligne(userId: userId.uppercased(), donnees: donnees),
                                                                       userId: userId))
        XCTAssertEqual(parcours.typeCompte, "SOIGNANT")
        XCTAssertEqual(parcours.modifieLe, "2026-11-02T10:00:00+00:00")
        XCTAssertEqual(parcours.consentementCguLe, "2026-11-02T09:59:00+00:00")
        // Revue B8 de T8, m4 : la réponse « salarié(e) » est restaurée comme le web (`restaurerFormulaire` l.134-136).
        XCTAssertEqual(parcours.brouillon, FormulaireInscription(prenom: "Léa", nom: "Martin", telephone: "0600000000",
                                                                 dateNaissance: "1990-05-14", profession: "IDE",
                                                                 typesContrat: ["SALARIE", "LIBERAL"], rpps: nil, rayon: 30,
                                                                 estSalarieEtablissement: true))
        XCTAssertNil(parcours.brouillon.estEtudiant, "aucune déclaration étudiant dans ce brouillon")
    }

    /// Revue B8 de T8, B1 et m4 : la déclaration étudiant du web (`estEtudiant`, `DeclarationEtudiant.tsx`) et la réponse
    /// « salarié(e) » sont lues dans `parcours_inscription.donnees` (liste blanche serveur, `public.sql` l.32485-32490),
    /// booléens seulement, comme `restaurerFormulaire` (`inscriptionProgressive.ts` l.126-149 : `typeof value === typeof
    /// initial`, et le cas `estSalarieEtablissement` l.134-136) — une autre valeur est ignorée, jamais supposée.
    func testBrouillonLitLaDeclarationEtudiantEtLaReponseSalarieEnBooleensSeulement() throws {
        func brouillon(_ donnees: [String: ValeurJSON]) throws -> FormulaireInscription {
            var objet = donnees
            objet["profession"] = .chaine("AS")
            return try XCTUnwrap(try OnboardingResolution.parcours(depuis: ligne(donnees: .objet(objet)), userId: userId)).brouillon
        }
        let etudiant = try brouillon(["estEtudiant": .booleen(true), "scolariteFormation": .chaine("IFSI"),
                                      "scolariteAnnee": .chaine("1"), "estSalarieEtablissement": .booleen(false)])
        XCTAssertEqual(etudiant.estEtudiant, true, "« Je suis étudiant(e) » déclaré sur le web")
        XCTAssertEqual(etudiant.estSalarieEtablissement, false)
        XCTAssertEqual(try brouillon(["estEtudiant": .booleen(false)]).estEtudiant, false)
        for illisible: ValeurJSON in [.chaine("true"), .nombre(1), .null, .tableau([.booleen(true)])] {
            let lu = try brouillon(["estEtudiant": illisible, "estSalarieEtablissement": illisible])
            XCTAssertNil(lu.estEtudiant, "\(illisible) : ignoré comme sur le web")
            XCTAssertNil(lu.estSalarieEtablissement, "\(illisible) : ignoré comme sur le web")
        }
        XCTAssertNil(try brouillon([:]).estEtudiant)
    }

    func testParcoursIncoherentEstUneErreurJamaisUnParcoursSuppose() {
        let incoherents: [ValeurJSON] = [
            ligne(userId: "autre-utilisateur"),
            ligne(type: .chaine("ADMIN")),
            ligne(donnees: .tableau([])),
            ligne(modifieLe: .null),
            .tableau([]),
            .chaine("SOIGNANT"),
        ]
        for valeur in incoherents {
            XCTAssertThrowsError(try OnboardingResolution.parcours(depuis: valeur, userId: userId)) { erreur in
                XCTAssertEqual(erreur as? JoleneError, JoleneError(.contract, InscriptionTextes.espaceIndisponible))
            }
        }
    }

    // MARK: - Étape

    func testLeParcoursPrimeSurLIntention() throws {
        let soignant = try XCTUnwrap(try OnboardingResolution.parcours(depuis: ligne(), userId: userId))
        let intentionEtablissement = IntentionInscription(typeCompte: "ETABLISSEMENT", profession: "", nom: "C", cgu: true, cgv: true)
        XCTAssertEqual(OnboardingResolution.etape(parcours: soignant, intention: intentionEtablissement), .completerSoignant(soignant))
        let etablissement = try XCTUnwrap(try OnboardingResolution.parcours(depuis: ligne(type: .chaine("ETABLISSEMENT")), userId: userId))
        XCTAssertEqual(OnboardingResolution.etape(parcours: etablissement, intention: InscriptionRules.intention(profession: "IDE", cgu: true)),
                       .espaceEtablissement)
    }

    func testSansParcoursUneIntentionSoignantDemarreEtUneIntentionEtablissementRenvoieAuWeb() {
        let soignant = InscriptionRules.intention(profession: "IDE", cgu: true)
        XCTAssertEqual(OnboardingResolution.etape(parcours: nil, intention: soignant), .demarrer(soignant))
        let etablissement = IntentionInscription(typeCompte: "ETABLISSEMENT", profession: "", nom: "C", cgu: true, cgv: true)
        XCTAssertEqual(OnboardingResolution.etape(parcours: nil, intention: etablissement), .espaceEtablissement,
                       "le natif ne réserve jamais un compte établissement")
        XCTAssertEqual(OnboardingResolution.etape(parcours: nil, intention: nil), .choixEspace)
    }

    func testSeulsLeRoleInconnuEtLeProfilIncompletOuvrentLAiguillage() {
        XCTAssertTrue(OnboardingResolution.concerne(.unsupportedRole(nil)))
        XCTAssertTrue(OnboardingResolution.concerne(.unsupportedRole(SessionState.profilIncompletCode)))
        XCTAssertFalse(OnboardingResolution.concerne(.unsupportedRole("ADMIN_ETABLISSEMENT")))
        XCTAssertFalse(OnboardingResolution.concerne(.unsupportedRole("ADMIN_PLATEFORME")))
        XCTAssertFalse(OnboardingResolution.concerne(.emailUnconfirmed))
        XCTAssertFalse(OnboardingResolution.concerne(.signInRequired))
        XCTAssertFalse(OnboardingResolution.concerne(.allowed))
    }
}
