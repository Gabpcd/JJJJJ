import Foundation

/// `IbanPort` du monde démo (lot 3, T14b), sans réseau : serveur simulé en mémoire (un acteur par lancement) qui
/// applique, dans leur ordre, les refus de `fn_enregistrer_mon_iban` et de `fn_lier_iban_verifie_document`
/// (`supabase/schema/public.sql` l.32684-32743, l.39848-39967), puis la même règle de relecture que le monde Supabase
/// (`IbanRelecture`) : aucun succès fabriqué. Le RIB vérifié de la démo porte le seul IBAN d'exemple ISO 13616
/// (`FR7630006000011234567890189`, blueprint §2.7) ; le titulaire attendu est le prénom et le nom du profil fictif
/// (`demo-profil-complet.json`). Refuse tout contexte qui n'est pas celui du profil fictif (`.demoOnly`).
///
/// Variantes de recette DEBUG `JOLENE_DEMO_IBAN=<scenario>` (`DemoIbanTests`) : `rib-requis` (aucun RIB vérifié :
/// `RIB_VERIFIE_REQUIS`, message serveur), `non-verifie` (IBAN renseigné mais non vérifié au départ).
public actor DemoIbanGateway: IbanPort {
    public enum Scenario: String, Sendable {
        case normal
        case ribRequis = "rib-requis"
        case nonVerifie = "non-verifie"
    }

    public static let variableEnvironnement = "JOLENE_DEMO_IBAN"
    /// IBAN du RIB vérifié de la démo (exemple ISO 13616).
    public static let ibanRibDemo = "FR7630006000011234567890189"
    /// Refus du serveur portant un `error`, verbatim.
    static let titulaireNonConcordant = "Le titulaire doit correspondre exactement à votre identité vérifiée." // source: public.sql:32719

    private let scenario: Scenario
    private var etat: ConsultationIban

    public init(scenario: Scenario = .normal) {
        self.scenario = scenario
        switch scenario {
        case .normal, .ribRequis:
            etat = ConsultationIban(ibanRenseigne: false, ibanVerifie: false, verificationRequise: false)
        case .nonVerifie:
            etat = ConsultationIban(ibanRenseigne: true, ibanVerifie: false, verificationRequise: true,
                                    ibanLast4: String(Self.ibanRibDemo.suffix(4)), ibanTitulaire: nil)
        }
    }

    public func consulter(context: MissionReadContext) async throws -> ConsultationIban {
        try DemoRevenusGateway.verifier(context)
        return etat
    }

    public func enregistrer(iban: String, titulaire: String, context: MissionReadContext) async throws -> ResultatIban {
        try DemoRevenusGateway.verifier(context)
        let (prenom, nom) = try Self.identite()
        let saisi = Self.normaliser(titulaire)
        guard saisi == Self.normaliser(prenom + " " + nom) || saisi == Self.normaliser(nom + " " + prenom) else {
            return .refuse(code: CodeRefusIban.titulaireNonConcordant.rawValue, message: Self.titulaireNonConcordant)
        }
        if scenario == .ribRequis {
            return .refuse(code: CodeRefusIban.ribVerifieRequis.rawValue, message: IbanTextes.ribCorrespondant)
        }
        // `upper(regexp_replace(p_iban, '[^A-Za-z0-9]', '', 'g'))` puis `fn_iban_est_valide` (15 à 34 caractères).
        let propre = String(String.UnicodeScalarView(iban.uppercased().unicodeScalars.filter {
            ("A"..."Z").contains($0) || ("0"..."9").contains($0)
        }))
        guard propre.utf8.count >= 15, IbanRules.checksumValide(propre) else {
            return .refuse(code: CodeRefusIban.ibanInvalide.rawValue, message: nil)
        }
        guard propre == Self.ibanRibDemo else { return .refuse(code: CodeRefusIban.ribNonConcordant.rawValue, message: nil) }
        etat = ConsultationIban(ibanRenseigne: true, ibanVerifie: true, verificationRequise: false,
                                ibanLast4: String(propre.suffix(4)), ibanTitulaire: (prenom + " " + nom)
                                    .trimmingCharacters(in: .whitespaces))
        // `{success:true, …}` puis relecture, comme le monde Supabase.
        return try IbanRelecture.enregistrement(relue: etat, ibanEnvoye: iban)
    }

    // MARK: - Interne

    private static func identite() throws -> (String, String) {
        guard case .objet(let profil) = try DemoFixtures.loadProfilComplet().profil,
              case .chaine(let prenom)? = profil["prenom"], case .chaine(let nom)? = profil["nom"] else {
            throw JoleneError(.contract, "Fixture démo illisible : demo-profil-complet.json.")
        }
        return (prenom, nom)
    }

    /// `btrim(regexp_replace(fn_normaliser_nom(x), '[^a-z0-9]+', ' ', 'g'))` (l.32708-32716), accents retirés par
    /// repliement (le serveur translittère les seules lettres accentuées du français).
    static func normaliser(_ texte: String) -> String {
        let replie = texte.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        var morceaux: [String] = []
        var courant = ""
        for scalaire in replie.unicodeScalars {
            if ("a"..."z").contains(scalaire) || ("0"..."9").contains(scalaire) {
                courant.unicodeScalars.append(scalaire)
            } else if !courant.isEmpty {
                morceaux.append(courant)
                courant = ""
            }
        }
        if !courant.isEmpty { morceaux.append(courant) }
        return morceaux.joined(separator: " ")
    }
}
