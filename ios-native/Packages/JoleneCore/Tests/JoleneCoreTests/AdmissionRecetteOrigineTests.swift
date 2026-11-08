import XCTest
@testable import JoleneCore

/// Lot 2, T8 — garde d'environnement de l'admission de recette (revue fraîche de T2, constat 2) : l'URL du
/// projet est ramenée à son origine `https://<hôte>` avant la comparaison exacte de `AdmissionRecette`
/// (`STAGING_URL` du web, `signatureSmsStagingAdmission.ts` l.6) ; une barre finale, un chemin (`/storage/v1`)
/// ou la casse de l'hôte ne refusent plus en silence l'URL STAGING ; tout autre projet, schéma, port,
/// identifiant ou requête reste refusé (aucun appel).
final class AdmissionRecetteOrigineTests: XCTestCase {
    private let contrat = "3f2c9a10-5b7d-4e21-9c3a-0d8e6f4b2a17"
    private var staging: String { JoleneEnvironment.allowedProjectRefs[.staging]! }
    private var production: String { JoleneEnvironment.allowedProjectRefs[.production]! }

    func testBarreFinaleCheminEtCasseRamenesALOrigineStaging() throws {
        for brute in ["https://\(staging).supabase.co", "https://\(staging).supabase.co/", "https://\(staging).supabase.co/storage/v1",
                      "https://\(staging.uppercased()).SUPABASE.co/"] {
            let url = try XCTUnwrap(URL(string: brute))
            XCTAssertEqual(AdmissionRecette.origine(url), AdmissionRecette.urlStaging, brute)
            XCTAssertTrue(AdmissionRecette.doitInterroger(projet: url, contratId: contrat), brute)
        }
    }

    func testAutresProjetsEtFormesRefuses() throws {
        for brute in ["https://\(production).supabase.co", "http://\(staging).supabase.co", "https://\(staging).supabase.co:8443",
                      "https://user@\(staging).supabase.co", "https://\(staging).supabase.co?x=1", "https://\(staging).supabase.co.evil.test"] {
            let url = try XCTUnwrap(URL(string: brute))
            XCTAssertFalse(AdmissionRecette.doitInterroger(projet: url, contratId: contrat), brute)
        }
        let url = try XCTUnwrap(URL(string: "https://\(staging).supabase.co/"))
        XCTAssertFalse(AdmissionRecette.doitInterroger(projet: url, contratId: "pas-un-uuid"))
    }

    func testLectureSansAppelHorsStaging() async throws {
        let url = try XCTUnwrap(URL(string: "https://\(production).supabase.co/storage/v1"))
        var appels = 0
        let admission = await AdmissionRecette.lire(projet: url, contratId: contrat, maintenant: DemoWorld.fixedNow) { _ in
            appels += 1
            return .objet(["admitted": .booleen(true)])
        }
        XCTAssertNil(admission)
        XCTAssertEqual(appels, 0, "production : la RPC n'existe pas et n'est jamais appelée")
    }
}
