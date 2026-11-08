import Foundation

/// Aiguillage d'onboarding (lot 3, T7) d'une identité confirmée qui n'a pas encore d'espace soignant : rôle serveur
/// `INCONNU` (`.blocked(.unsupportedRole(nil))`) ou rôle SOIGNANT sans ligne `soignants`
/// (`.blocked(.unsupportedRole("PROFIL_INCOMPLET"))`). Port de `registrationIntent` et `registrationDraft`
/// (`mobile-native/src/account/resolveContext.ts` l.8-22) et de la décision de `src/pages/ParcoursInscription.tsx`
/// l.39-75 : le parcours serveur (`parcours_inscription`) prime ; sans parcours, une intention
/// `user_metadata.inscription_progressive` valide (`cgu: true`) démarre le parcours (`fn_demarrer_inscription`) ;
/// sinon l'utilisateur choisit son espace. Le droit de naviguer n'est jamais tiré de `user_metadata` (`useRole.ts`
/// l.153-154) : seule la ligne réservée par le serveur ouvre la complétion. `SessionController` et `MobileAccess`
/// sont inchangés (blueprint §2.5) : l'écart « rôle INCONNU » de PRINCIPES §5 est résolu dans la vue.
public enum OnboardingResolution {
    /// Familles de compte de `parcours_inscription_type_compte_check` (`public.sql` l.71026).
    public static let typesCompte: Set<String> = ["SOIGNANT", "ETABLISSEMENT"]

    /// Étape à présenter, dans l'ordre de `ParcoursInscription.tsx`.
    public enum Etape: Equatable, Sendable {
        /// Parcours soignant réservé : complétion du profil puis `register-soignant` (T8).
        case completerSoignant(ParcoursInscription)
        /// Parcours ou intention établissement : renvoi web (inscription établissement hors périmètre natif, §1.2).
        case espaceEtablissement
        /// Intention soignant valide sans parcours : `fn_demarrer_inscription` avec cette intention.
        case demarrer(IntentionInscription)
        /// Ni parcours ni intention valide : « Choisissez votre espace… » (l.97-124).
        case choixEspace
    }

    public static func etape(parcours: ParcoursInscription?, intention: IntentionInscription?) -> Etape {
        if let parcours {
            return parcours.typeCompte == UserRole.soignant.rawValue ? .completerSoignant(parcours) : .espaceEtablissement
        }
        guard let intention else { return .choixEspace }
        // Le natif ne démarre que le parcours soignant ; une intention établissement est réservée par le web.
        return intention.typeCompte == UserRole.soignant.rawValue ? .demarrer(intention) : .espaceEtablissement
    }

    /// `registrationIntent` : type connu, `cgu === true`, `cgv === true` exigé pour un établissement ; profession et
    /// nom repris seulement s'ils sont des chaînes (`''` sinon).
    public static func intention(depuis valeur: ValeurJSON?) -> IntentionInscription? {
        guard case .objet(let objet)? = valeur, case .chaine(let type)? = objet["type"], typesCompte.contains(type),
              objet["cgu"] == .booleen(true) else { return nil }
        let cgv = objet["cgv"] == .booleen(true)
        if type == "ETABLISSEMENT" && !cgv { return nil }
        return IntentionInscription(typeCompte: type, profession: chaine(objet["profession"]) ?? "",
                                    nom: chaine(objet["nom"]) ?? "", cgu: true, cgv: cgv)
    }

    /// `registrationDraft` : `null` (aucune ligne) → nil ; ligne d'un autre utilisateur, type inconnu, `donnees` non
    /// objet ou `modifie_le` absent → erreur (jamais un parcours supposé). Le brouillon ne reprend que les clés de la
    /// liste blanche de `fn_enregistrer_parcours_inscription` portées par `FormulaireInscription`, chacune avec son
    /// type (une valeur d'un autre type est ignorée).
    public static func parcours(depuis valeur: ValeurJSON?, userId: String) throws -> ParcoursInscription? {
        guard let valeur, valeur != .null else { return nil }
        guard case .objet(let ligne) = valeur, let proprietaire = chaine(ligne["user_id"]),
              proprietaire.lowercased() == userId.lowercased(),
              let type = chaine(ligne["type_compte"]), typesCompte.contains(type),
              case .objet(let donnees)? = ligne["donnees"], let modifieLe = chaine(ligne["modifie_le"]) else {
            throw JoleneError(.contract, InscriptionTextes.espaceIndisponible)
        }
        return ParcoursInscription(userId: proprietaire, typeCompte: type, brouillon: brouillon(donnees),
                                   consentementCguLe: chaine(ligne["consentement_cgu_le"]), modifieLe: modifieLe)
    }

    static func brouillon(_ donnees: [String: ValeurJSON]) -> FormulaireInscription {
        var typesContrat: [String] = []
        if case .tableau(let valeurs)? = donnees["typesContrat"] { typesContrat = valeurs.compactMap { chaine($0) } }
        var rayon: Int?
        if case .nombre(let nombre)? = donnees["rayon"], nombre.rounded() == nombre, abs(nombre) < 1_000_000 { rayon = Int(nombre) }
        return FormulaireInscription(prenom: chaine(donnees["prenom"]), nom: chaine(donnees["nom"]),
                                     telephone: chaine(donnees["telephone"]), dateNaissance: chaine(donnees["dateNaissance"]),
                                     profession: chaine(donnees["profession"]), typesContrat: typesContrat,
                                     rpps: chaine(donnees["rpps"]), rayon: rayon)
    }

    private static func chaine(_ valeur: ValeurJSON?) -> String? {
        if case .chaine(let texte)? = valeur { return texte }
        return nil
    }

    /// `.blocked` servi par l'aiguillage d'onboarding : rôle non résolu (`INCONNU`) ou profil soignant absent. Un
    /// autre rôle (établissement, administrateur) et l'email non confirmé gardent l'écran bloquant du lot 0.
    public static func concerne(_ acces: MobileAccess) -> Bool {
        if case .unsupportedRole(let code) = acces { return code == nil || code == SessionState.profilIncompletCode }
        return false
    }
}
