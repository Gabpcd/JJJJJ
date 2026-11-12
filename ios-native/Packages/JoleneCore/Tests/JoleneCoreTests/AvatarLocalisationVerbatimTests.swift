import XCTest
@testable import JoleneCore

/// Textes de la photo et de l'adresse de « Mon profil » (lot 3, T10 ; règle des textes du mémo des lots 2 à 5) :
/// chaque texte affiché est repris mot pour mot du web, à sa ligne source ; les textes tutoyés du web (non juridiques)
/// passent au vouvoiement (décision 9 du lot 1) et leur forme web reste à sa ligne ; aucun texte juridique ;
/// coordonnées jamais affichées. Seuls textes sans équivalent web : le choix de la source de la photo (listés dans
/// `DECISIONS_LOT3.md`, section T10).
final class AvatarLocalisationVerbatimTests: XCTestCase {
    private typealias A = AvatarProfil.Textes
    private typealias L = ProfilLocalisation.Textes

    private static func sourceDepot(_ chemin: String) throws -> [String] {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8).components(separatedBy: "\n")
    }

    private static let avatar = "src/components/AvatarUpload.tsx"
    private static let documents = "src/lib/documentUpload.ts"
    private static let principal = "src/components/profil-soignant/SectionProfilPrincipal.tsx"
    private static let geocodage = "src/lib/geocodage.ts"

    private static var attendus: [(String, String, Int)] {
        [
            (A.changerPhoto, avatar, 179), (A.succes, avatar, 164), (A.echecEnvoi.replacingOccurrences(of: "'", with: "\\'"), avatar, 166),
            (A.fichierVide, documents, 135), ("Le fichier ne doit pas dépasser ${maxMo} Mo.", documents, 139),
            (A.fichierIllisible, documents, 174),
            (L.titre, principal, 861), (L.utiliserPosition, principal, 871), (L.recuperationEnCours, principal, 871),
            (L.positionRecuperee, principal, 637),
            // Règles portées, à leur ligne.
            ("const MAX = 256", avatar, 39), ("'image/webp'", avatar, 51), ("0.8", avatar, 52),
            ("maxBytes: 2 * 1024 * 1024", avatar, 123),
            ("avatar' : 'logo'", avatar, 135), ("`${user.id}/${assetPrefix}-${Date.now()}.webp`", avatar, 136),
            ("upsert: false", avatar, 140), ("5 * 365 * 24 * 60 * 60", avatar, 148), ("p_avatar_url: signedUrl", avatar, 154),
            ("enableHighAccuracy: true, timeout: 15_000", principal, 628), ("`📍 ${adr.label}`", principal, 635),
            ("https://api-adresse.data.gouv.fr/reverse/?lon=${encodeURIComponent(lng)}&lat=${encodeURIComponent(lat)}", geocodage, 18),
            ("label: p.label || ''", geocodage, 26), ("ville: p.city || null", geocodage, 28),
            ("codePostal: p.postcode || null", geocodage, 29),
        ]
    }

    func testChaqueTexteEtRegleEstVerbatimASaLigneWeb() throws {
        var lignes: [String: [String]] = [:]
        for (texte, fichier, ligne) in Self.attendus {
            if lignes[fichier] == nil { lignes[fichier] = try Self.sourceDepot(fichier) }
            let source = try XCTUnwrap(lignes[fichier])
            XCTAssertGreaterThanOrEqual(source.count, ligne, fichier)
            XCTAssertTrue(source[ligne - 1].contains(texte), "« \(texte) » absent de \(fichier) l.\(ligne)")
        }
        // Le message de taille est le gabarit du web évalué pour `maxBytes` = 2 Mo (`Math.floor(maxBytes / (1024 * 1024))`).
        XCTAssertEqual(A.fichierTropLourd, "Le fichier ne doit pas dépasser \(AvatarProfil.tailleMaxOctets / (1024 * 1024)) Mo.")
        XCTAssertEqual(A.changerPhoto, "Changer ma photo de profil")
    }

    func testTextesTutoyesDuWebAuVouvoiement() throws {
        let source = try Self.sourceDepot(Self.principal)
        let lignes = [876, 875, 640]
        XCTAssertEqual(ProfilLocalisation.vouvoiements.map { $0.natif }, [L.aide, L.positionEnregistree, L.refusee])
        for ((web, _), ligne) in zip(ProfilLocalisation.vouvoiements, lignes) {
            XCTAssertTrue(source[ligne - 1].contains(web), "« \(web) » absent de l.\(ligne)")
        }
        for natif in ProfilLocalisation.vouvoiements.map({ $0.natif }) {
            for tutoiement in [" tu ", " ta ", " ton ", "Tu ", "Utilise ta", " tes "] {
                XCTAssertFalse(natif.contains(tutoiement), "« \(natif) » doit être vouvoyé")
            }
        }
    }

    func testAucuneCoordonneeNiPictogrammeAffiche() {
        let tous = [L.titre, L.utiliserPosition, L.recuperationEnCours, L.aide, L.positionEnregistree, L.positionRecuperee,
                    L.refusee, A.changerPhoto, A.succes, A.echecEnvoi, A.fichierVide, A.fichierTropLourd, A.fichierIllisible,
                    A.choisirPhototheque, A.prendrePhoto, A.annuler]
        for texte in tous {
            XCTAssertFalse(texte.contains("📍") || texte.contains("coordonnées"), "« \(texte) »")
        }
        XCTAssertEqual(ProfilLocalisation.avis(adresse: AdresseGeocodee(libelle: "Place Bellecour 69002 Lyon")),
                       .succes("Place Bellecour 69002 Lyon"))
        XCTAssertEqual(ProfilLocalisation.avis(adresse: nil), .succes(L.positionRecuperee))
        XCTAssertEqual(String(describing: PositionPonctuelle.disponible(latitude: 45.7578, longitude: 4.832)),
                       "PositionPonctuelle.disponible(position masquée)")
        let modification = ModificationProfil(adresseLat: 45.7578, adresseLng: 4.832)
        XCTAssertFalse(String(describing: modification).contains("45.75"), "position jamais restituée")
        XCTAssertFalse(String(reflecting: modification).contains("4.832"))
    }

    func testTextesSansEquivalentWebListesPourRelecture() throws {
        // Libellés du choix de la source et bouton d'annulation natif (`ConfirmationSheet`, L1-T1b).
        let decisions = try Self.sourceDepot("docs/mobile-swift/DECISIONS_LOT3.md").joined(separator: "\n")
        for texte in [A.choisirPhototheque, A.prendrePhoto] {
            XCTAssertTrue(decisions.contains(texte), "« \(texte) » listé dans DECISIONS_LOT3.md")
        }
        let feuille = try Self.sourceDepot("ios-native/Packages/JoleneDesign/Sources/JoleneDesign/Components/ConfirmationSheet.swift")
        XCTAssertTrue(feuille[34 - 1].contains("cancelTitle: String = \"\(A.annuler)\""))
    }
}
