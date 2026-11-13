import Foundation

/// Fichier rendu par les sélecteurs du monde démo (`-JOLENE_DEMO_SOURCE_DOC`, blueprint §2.8 « Justificatifs »), lu par
/// `AppContainer` en DEBUG et rendu par `DemoMediaPicker` à la place de l'appareil photo, de la photothèque et de Fichiers
/// (non pilotables en XCUITest, absents du simulateur). Fichiers fictifs, aucune donnée réelle : trois pixels du pilote
/// (`mobile-native/src/workflows/documents/demoFixture.ts`), HEIC de T6 (GPS fictif, `Resources/media-demo`), PDF vide.
public enum SourceDocumentDemo: String, CaseIterable, Sendable {
    case png, heic, pdf
    /// Plus de 10 Mo : refus local du web, avant tout reçu.
    case tropGros = "trop-gros"
    /// Sélection annulée : aucun fichier, aucun envoi.
    case annule

    public static let argument = "-JOLENE_DEMO_SOURCE_DOC"

    /// Valeur qui suit `-JOLENE_DEMO_SOURCE_DOC` ; absente ou inconnue : `.png`.
    public init(arguments: [String]) {
        self = ArgumentsDemo.valeur(Self.argument, dans: arguments).flatMap(SourceDocumentDemo.init(rawValue:)) ?? .png
    }

    /// Fichier démo tel que l'aurait rendu le sélecteur `origine` ; nil si la sélection est annulée.
    public func fichier(origine: SourceFichier) -> FichierSelectionne? {
        switch self {
        case .png:
            return FichierSelectionne(nom: "justificatif-demo.png", type: MimeDocument.png.rawValue, octets: Data(Self.troisPixels),
                                      source: origine)
        case .heic:
            guard let url = Bundle.module.url(forResource: "justificatif-demo", withExtension: "heic", subdirectory: Self.sousDossier),
                  let octets = try? Data(contentsOf: url) else { return nil }
            return FichierSelectionne(nom: "justificatif-demo.heic", type: "image/heic", octets: octets, source: origine)
        case .pdf:
            return FichierSelectionne(nom: "justificatif-demo.pdf", type: MimeDocument.pdf.rawValue,
                                      octets: DemoDocumentsGateway.pdfDemonstration, source: origine)
        case .tropGros:
            var octets = Data("%PDF-1.4\n".utf8)
            octets.append(Data(count: ClassementDocument.tailleMaxParDefaut + 1 - octets.count))
            return FichierSelectionne(nom: "justificatif-demo.pdf", type: MimeDocument.pdf.rawValue, octets: octets, source: origine)
        case .annule:
            return nil
        }
    }

    static let sousDossier = "Resources/media-demo"

    /// PNG 3 × 1 sans métadonnée du pilote (`demoFixture.ts` l.4), octet pour octet.
    static let troisPixels: [UInt8] = [
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 3, 0, 0, 0, 1, 8, 2, 0, 0, 0, 148, 130, 131, 227,
        0, 0, 0, 18, 73, 68, 65, 84, 120, 156, 99, 56, 41, 90, 88, 104, 185, 240, 255, 255, 255, 0, 23, 27, 5, 152, 82, 199, 73,
        41, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
    ]
}

extension ScenarioDocumentsDemo {
    public static let argument = "-JOLENE_DEMO_SCENARIO"

    /// Valeur qui suit `-JOLENE_DEMO_SCENARIO` ; celle d'un autre domaine (`scan-incertain`, `otp-expire`) : `.normal`.
    public init(arguments: [String]) {
        self = ArgumentsDemo.valeur(Self.argument, dans: arguments).flatMap(ScenarioDocumentsDemo.init(rawValue:)) ?? .normal
    }
}

/// Arguments de lancement du monde démo (`-NOM valeur`).
enum ArgumentsDemo {
    static func valeur(_ nom: String, dans arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: nom), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
