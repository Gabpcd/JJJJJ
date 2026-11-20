import Foundation

/// Coordonnées bancaires du soignant (lot 3, T14b, B9 ; D20, TJ6, TJ8), port de `SectionIbanPrime`
/// (`src/components/profil-soignant/SectionPaiements.tsx` l.212-376). L'IBAN confirmé est celui du RIB vérifié
/// (règle serveur : `fn_enregistrer_mon_iban`, puis `fn_lier_iban_verifie_document`, dump `supabase/schema/public.sql`
/// l.32692-32751 et l.39856-39975) ; le contrôle local ne fait qu'éviter un envoi voué à l'échec.
///
/// L'IBAN saisi n'est jamais journalisé ni persisté : il ne vit que dans le champ, vidé dès l'envoi (`IbanModel`).
public enum IbanRules {
    /// Classe `\s` de JavaScript (ECMAScript : WhiteSpace et LineTerminator), utilisée par `replace(/\s/g, '')`
    /// (l.213, l.248) et `trim()` (l.252, l.256) : espaces insécables U+00A0 et U+202F comprises. Différente de
    /// `Character.isWhitespace` (U+0085 en plus, U+FEFF en moins).
    static let blancsJavaScript: Set<Unicode.Scalar> = [
        "\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}", "\u{0020}", "\u{00A0}", "\u{1680}",
        "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}", "\u{2006}", "\u{2007}",
        "\u{2008}", "\u{2009}", "\u{200A}", "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}", "\u{FEFF}",
    ]

    /// `iban.toUpperCase().replace(/\s/g, '')` (l.248) : valeur envoyée en `p_iban` (l.255).
    public static func nettoyer(_ saisie: String) -> String {
        var scalaires = String.UnicodeScalarView()
        scalaires.append(contentsOf: saisie.uppercased().unicodeScalars.filter { !blancsJavaScript.contains($0) })
        return String(scalaires)
    }

    /// `titulaire.trim()` (l.252, l.256) : valeur envoyée en `p_titulaire`.
    public static func titulaireNettoye(_ saisie: String) -> String {
        var scalaires = Substring(saisie).unicodeScalars
        while let premier = scalaires.first, blancsJavaScript.contains(premier) { scalaires.removeFirst() }
        while let dernier = scalaires.last, blancsJavaScript.contains(dernier) { scalaires.removeLast() }
        return String(Substring(scalaires))
    }

    /// `validateIbanChecksum` (l.212-225) : format `^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$` puis clé ISO 13616 (mod 97 = 1).
    public static func checksumValide(_ iban: String) -> Bool {
        let octets = Array(nettoyer(iban).utf8)
        guard (14...34).contains(octets.count) else { return false }
        let lettre: (UInt8) -> Bool = { (65...90).contains($0) }
        let chiffre: (UInt8) -> Bool = { (48...57).contains($0) }
        guard lettre(octets[0]), lettre(octets[1]), chiffre(octets[2]), chiffre(octets[3]),
              octets[4...].allSatisfy({ lettre($0) || chiffre($0) }) else { return false }
        var reste = 0
        for octet in octets[4...] + octets[..<4] {
            // Lettre → `charCodeAt(0) - 55` (A = 10 … Z = 35), chiffre par chiffre comme la chaîne `numeric` du web.
            let valeur = lettre(octet) ? Int(octet) - 55 : Int(octet) - 48
            for c in String(valeur).utf8 { reste = (reste * 10 + Int(c) - 48) % 97 }
        }
        return reste == 1
    }

    /// `ibanClean.length >= 14 && validateIbanChecksum(ibanClean)` (l.249).
    public static func estValide(_ saisie: String) -> Bool {
        let propre = nettoyer(saisie)
        return propre.utf16.count >= 14 && checksumValide(propre)
    }

    /// « IBAN invalide » sous le champ : `iban.length > 4 && !ibanValid` (l.337), longueur de la saisie mise en
    /// majuscules (`setIban(e.target.value.toUpperCase())`, l.331), espaces compris.
    public static func afficheInvalide(_ saisie: String) -> Bool {
        saisie.uppercased().utf16.count > 4 && !estValide(saisie)
    }

    /// `disabled={!ibanValid || !titulaire.trim() || saving}` (l.366), hors `saving`.
    public static func peutEnregistrer(iban: String, titulaire: String) -> Bool {
        estValide(iban) && !titulaireNettoye(titulaire).isEmpty
    }

    /// `•••• •••• •••• •••• •••• {current.iban_last4}` (l.293) : seuls les quatre derniers caractères, jamais l'IBAN.
    public static func masque(last4: String) -> String {
        "•••• •••• •••• •••• •••• \(last4)"
    }

    /// Quatre derniers caractères de l'IBAN envoyé (`right(v_iban, 4)` du serveur, l.39941, sur la même valeur nettoyée).
    public static func quatreDerniers(_ iban: String) -> String {
        String(nettoyer(iban).suffix(4))
    }
}

/// Textes de l'écran IBAN. Verbatim du web à leur ligne (`IbanTests.testChaqueTexteRepriseDuWebEstVerbatimASaLigne`),
/// sauf les deux textes nouveaux des refus d'identité (TJ6, règle 3), tranchés par délégation et listés dans
/// `docs/mobile-swift/DECISIONS_LOT3.md` (section T14b). Non portés (TJ6, TJ8) : l.280 (destinataires de l'IBAN,
/// inexact) et l.308 (« L'ancien IBAN est conservé dans ton historique… », inexact : voir le mémo).
public enum IbanTextes {
    /// `MonCompteSoignant.tsx` l.73 (entrée). Le titre de la section du hub (l.65), partagé avec T14a, est
    /// `StripeConnectTextes.sectionHub` seul (intégration vague A, revue B8 de #1144 : un seul titre).
    public static let entreeHub = "Coordonnées bancaires"
    /// l.277.
    public static let titre = "Coordonnées bancaires"
    /// l.291 (état vérifié) et l.262 (succès, `result?.message || 'IBAN enregistré'` : le serveur ne pose pas `message`).
    public static let ibanEnregistre = "IBAN enregistré"
    /// l.296 : `Titulaire : {current.iban_titulaire}`.
    public static let titulairePrefixe = "Titulaire : "
    /// l.306 (état `iban_renseigne && !iban_verifie`) ; titre des refus RIB (TJ6, règle 2).
    public static let ribVerifieRequis = "RIB vérifié requis"
    /// l.316.
    public static let televerserRib = "Téléverser mon RIB"
    /// l.325.
    public static let libelleIban = "IBAN"
    public static let libelleModifier = "Modifier l'IBAN"
    /// l.332.
    public static let placeholderIban = "FR76 3000 6000 0112 3456 7890 189"
    /// l.339.
    public static let ibanInvalide = "IBAN invalide"
    /// l.344.
    public static let ibanValide = "IBAN valide"
    /// l.350.
    public static let libelleTitulaire = "Nom du titulaire"
    /// l.356.
    public static let placeholderTitulaire = "Prénom Nom"
    /// l.369.
    public static let enregistrement = "Enregistrement…"
    public static let mettreAJour = "Mettre à jour"
    public static let enregistrer = "Enregistrer l'IBAN"
    /// Message générique du web (`src/lib/erreurs.ts` l.532) : `PROFIL_INTROUVABLE`, code inconnu, succès non relu.
    public static let erreurGenerique = "Une erreur est survenue. Veuillez réessayer."
    /// Refus `RIB_VERIFIE_REQUIS` du serveur (`public.sql` l.32743), repris pour `RIB_COURANT_REQUIS` et
    /// `RIB_NON_CONCORDANT` qui n'ont pas d'`error` (TJ6, règle 2).
    public static let ribCorrespondant = "Téléversez puis faites vérifier le RIB correspondant."
    /// Texte nouveau (TJ6, règle 3) : `IDENTITE_VERIFIEE_REQUISE` (`identite_verifiee` et `coherence_identite =
    /// 'COHERENT'`, `public.sql` l.39892-39897).
    public static let identiteVerifieeRequise =
        "Faites d'abord vérifier votre identité, cohérente avec votre profil, depuis Mes documents."
    /// Texte nouveau (TJ6, règle 3) : `IDENTITE_COURANTE_REQUISE` (pièce d'identité `VERIFIE` dont les noms extraits
    /// concordent avec le profil, `public.sql` l.39899-39915).
    public static let identiteCouranteRequise =
        "Une pièce d'identité vérifiée à vos nom et prénom est requise : téléversez-la depuis Mes documents."
    /// Libellé de la page web « Mes documents » (`LibellesWeb.EspaceSoignant.mesDocuments`), action des refus d'identité.
    public static let mesDocuments = LibellesWeb.EspaceSoignant.mesDocuments
}

/// Codes `error_code` de `fn_enregistrer_mon_iban` (neuf, dont deux avec `error` : `TITULAIRE_NON_CONCORDANT`,
/// `RIB_VERIFIE_REQUIS`). Fiche `fn_enregistrer_mon_iban` de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`.
public enum CodeRefusIban: String, CaseIterable, Sendable {
    case nonAuthentifie = "NON_AUTHENTIFIE"
    case profilIntrouvable = "PROFIL_INTROUVABLE"
    case titulaireNonConcordant = "TITULAIRE_NON_CONCORDANT"
    case ribVerifieRequis = "RIB_VERIFIE_REQUIS"
    case ibanInvalide = "IBAN_INVALIDE"
    case ribCourantRequis = "RIB_COURANT_REQUIS"
    case identiteVerifieeRequise = "IDENTITE_VERIFIEE_REQUISE"
    case identiteCouranteRequise = "IDENTITE_COURANTE_REQUISE"
    case ribNonConcordant = "RIB_NON_CONCORDANT"
}

/// Refus affiché : message, titre éventuel et action vers les documents (lot 2).
public struct RefusIbanAffiche: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// « Téléverser mon RIB » (l.316) : refus portant sur le RIB vérifié.
        case televerserRib
        /// « Mes documents » : refus portant sur la pièce d'identité.
        case mesDocuments
    }

    public let titre: String?
    public let message: String
    public let action: Action?

    public init(titre: String? = nil, message: String, action: Action? = nil) {
        self.titre = titre; self.message = message; self.action = action
    }
}

public enum IbanPresentation {
    /// Refus de `fn_enregistrer_mon_iban` (TJ6) : `error` serveur verbatim s'il existe (règle 1), sinon texte existant
    /// (règle 2) ou nouveau (règle 3) ; un code inconnu → message générique. Jamais « IBAN enregistré ».
    public static func refus(code: String?, message: String?) -> RefusIbanAffiche {
        let serveur = message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        switch code.flatMap(CodeRefusIban.init(rawValue:)) {
        case .ribVerifieRequis?, .ribCourantRequis?, .ribNonConcordant?:
            return RefusIbanAffiche(titre: IbanTextes.ribVerifieRequis, message: serveur ?? IbanTextes.ribCorrespondant,
                                    action: .televerserRib)
        case .identiteVerifieeRequise?:
            return RefusIbanAffiche(message: serveur ?? IbanTextes.identiteVerifieeRequise, action: .mesDocuments)
        case .identiteCouranteRequise?:
            return RefusIbanAffiche(message: serveur ?? IbanTextes.identiteCouranteRequise, action: .mesDocuments)
        case .ibanInvalide?:
            return RefusIbanAffiche(message: serveur ?? IbanTextes.ibanInvalide)
        case .titulaireNonConcordant?, .nonAuthentifie?, .profilIntrouvable?, nil:
            return RefusIbanAffiche(message: serveur ?? IbanTextes.erreurGenerique)
        }
    }
}

/// Succès strict (D20) : `success == true` ne suffit pas, la relecture `fn_consulter_mon_iban` doit montrer un IBAN
/// renseigné, vérifié, et dont les quatre derniers caractères sont ceux de l'IBAN envoyé. Partagé par les deux mondes.
public enum IbanRelecture {
    public static func enregistrement(relue: ConsultationIban, ibanEnvoye: String) throws -> ResultatIban {
        guard relue.ibanRenseigne, relue.ibanVerifie, relue.ibanLast4 == IbanRules.quatreDerniers(ibanEnvoye) else {
            throw JoleneError(.unknown, IbanTextes.erreurGenerique)
        }
        return .enregistre(relue)
    }
}
