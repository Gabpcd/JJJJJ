import Foundation

/// Textes de l'inscription native (lot 3, T7 ; HARD STOP n°4) : chacun est repris **mot pour mot** du web ou
/// du serveur, à sa ligne source (`// source: fichier:ligne`), et épinglé par `InscriptionVerbatimTests`. Aucun
/// texte juridique n'est écrit ni reformulé ici : la phrase de consentement aux CGU et à la politique de
/// confidentialité est l'assemblage exact du JSX de `src/pages/InscriptionRapide.tsx` l.264-284 (mêmes
/// espaces que le rendu React), ses deux liens visent les pages web (`/cgu`, `/confidentialite`).
/// Apostrophes typographiques du web conservées. Le seul texte affiché qui n'a pas de source dans les fichiers
/// d'inscription vient de l'écran de connexion du web (`creerCompteSoignant`).
public enum InscriptionTextes {
    // MARK: Écran de connexion

    // source: src/pages/PageConnexion.tsx:334
    public static let creerCompteSoignant = "Créer un compte soignant"

    // MARK: Compte rapide (`InscriptionRapide.tsx`, soignant)

    // source: src/pages/InscriptionRapide.tsx:132
    public static let titre = "Créez votre compte."
    // source: src/pages/InscriptionRapide.tsx:136
    public static let sousTitre = "Découvrez les missions. Votre dossier professionnel se complète ensuite."
    // source: src/pages/InscriptionRapide.tsx:157
    public static let email = "Email"
    // source: src/pages/InscriptionRapide.tsx:180
    public static let motDePasse = "Mot de passe"
    // source: src/pages/InscriptionRapide.tsx:211
    public static let aideMotDePasse = "8 caractères minimum"
    // source: src/pages/InscriptionRapide.tsx:221
    public static let profession = "Profession"
    // source: src/pages/InscriptionRapide.tsx:230
    public static let choisirProfession = "Choisir ma profession"

    /// Consentement [consentement] — fragments du JSX l.265, l.272, l.274, l.281, l.283 ; liens l.267 et l.276.
    // source: src/pages/InscriptionRapide.tsx:265
    public static let cguDebut = "J’accepte les"
    // source: src/pages/InscriptionRapide.tsx:272
    public static let cguLienCGU = "CGU"
    // source: src/pages/InscriptionRapide.tsx:274
    public static let cguMilieu = "et la"
    // source: src/pages/InscriptionRapide.tsx:281
    public static let cguLienConfidentialite = "politique de confidentialité"
    // source: src/pages/InscriptionRapide.tsx:283
    public static let cguFin = "."
    /// Phrase rendue par React (fragments joints par les `{" "}` du JSX, le point collé au second lien).
    public static var cguPhrase: String {
        [cguDebut, cguLienCGU, cguMilieu, cguLienConfidentialite].joined(separator: " ") + cguFin
    }
    /// `href="/cgu"` (l.267) et `href="/confidentialite"` (l.276), sur l'hôte web canonique ; hors AASA (aucun
    /// retour dans l'app par lien universel), ouverts dans `SFSafariViewController`.
    public static let urlCGU = URL(string: "https://jolene.app/cgu")!
    public static let urlConfidentialite = URL(string: "https://jolene.app/confidentialite")!

    // source: src/pages/InscriptionRapide.tsx:60
    public static let erreurEmail = "Saisissez une adresse email valide."
    // source: src/pages/InscriptionRapide.tsx:62
    public static let erreurMotDePasse = "Choisissez un mot de passe de 8 caractères minimum."
    // source: src/pages/InscriptionRapide.tsx:64
    public static let erreurProfession = "Choisissez votre profession."
    // source: src/pages/InscriptionRapide.tsx:68
    public static let erreurCGU = "Acceptez les conditions pour créer votre compte."

    // source: src/pages/InscriptionRapide.tsx:322-324
    public static let confirmationEnvoyee = "Un lien de confirmation vient de vous être envoyé. Ouvrez-le pour accéder à votre espace. Vous pouvez aussi revenir ici après confirmation."

    // source: src/pages/InscriptionRapide.tsx:347
    public static let creationEnCours = "Création du compte…"
    // source: src/pages/InscriptionRapide.tsx:349
    public static let seConnecterEtContinuer = "Se connecter et continuer"
    // source: src/pages/InscriptionRapide.tsx:351
    public static let jaiConfirme = "J’ai confirmé mon email"
    // source: src/pages/InscriptionRapide.tsx:352
    public static let creerMonCompte = "Créer mon compte"
    // source: src/pages/InscriptionRapide.tsx:356
    public static let aucunDocument = "Aucun document à préparer maintenant."
    // source: src/pages/InscriptionRapide.tsx:361
    public static let dejaUnCompte = "Déjà un compte ?"
    // source: src/pages/InscriptionRapide.tsx:363
    public static let seConnecter = "Se connecter"

    // source: src/pages/InscriptionRapide.tsx:101
    public static let compteDejaEspace = "Ce compte possède déjà un espace Jolene. Connectez-vous pour le retrouver."
    // source: src/pages/InscriptionRapide.tsx:107
    public static let compteExistant = "Ce compte existe déjà. Connectez-vous pour le reprendre."

    // MARK: Refus de création (`mapperErreurInscription`, `src/lib/erreurs.ts`)

    // source: src/lib/erreurs.ts:86
    public static let motDePasseDivulgue = "Ce mot de passe est trop facile à deviner ou a déjà été divulgué. Choisissez un autre mot de passe."
    // source: src/lib/erreurs.ts:102
    public static let tropDeTentatives = "Trop de tentatives récentes. Veuillez réessayer dans quelques minutes."
    // source: src/lib/erreurs.ts:109
    public static let emailInvalide = "L'adresse email saisie n'est pas valide."
    /// `Le mot de passe doit contenir au moins ${n} caractères.`
    // source: src/lib/erreurs.ts:119
    public static func motDePasseLongueur(_ minimum: String) -> String {
        "Le mot de passe doit contenir au moins \(minimum) caractères."
    }
    // source: src/lib/erreurs.ts:127
    public static let motDePasseFaible = "Mot de passe trop faible. Utilisez au moins 8 caractères avec majuscules, minuscules, chiffres et caractères spéciaux."
    // source: src/lib/erreurs.ts:149
    public static let connexionInstable = "Connexion internet instable. Vérifiez votre connexion et réessayez."
    // source: src/lib/erreurs.ts:178
    public static let erreurInattendue = "Une erreur inattendue est survenue. Réessayez ou contactez le support."

    // MARK: Lien de confirmation (`ConfirmationInscription.tsx`)

    // source: src/pages/ConfirmationInscription.tsx:74
    public static let reprendreInscription = "Reprendre votre inscription"
    // source: src/pages/ConfirmationInscription.tsx:76-77
    public static let lienNonValide = "Ce lien n’a pas pu être validé. S’il a déjà confirmé votre email, connectez-vous pour retrouver votre inscription."

    // MARK: Aiguillage (`ParcoursInscription.tsx`)

    // source: src/pages/ParcoursInscription.tsx:100
    public static let choisirEspace = "Choisissez votre espace pour terminer la création de votre compte."
    // source: src/pages/ParcoursInscription.tsx:115
    public static let jeSuisSoignant = "Je suis soignant"
    // source: src/pages/ParcoursInscription.tsx:121
    public static let jeRepresenteEtablissement = "Je représente un établissement"
    // source: src/pages/ParcoursInscription.tsx:80
    public static let espaceIndisponible = "Votre espace est momentanément indisponible. Réessayez."
    // source: src/pages/ParcoursInscription.tsx:107
    public static let reessayer = "Réessayer"
    // source: src/pages/ParcoursInscription.tsx:126
    public static let seDeconnecter = "Se déconnecter"
}

/// Refus certain d'une étape d'inscription (création du compte, démarrage du parcours) : le serveur a répondu et
/// n'a rien appliqué. `message` est affiché tel quel (texte web ou serveur verbatim) ; `code` est le code machine
/// (`CAPTCHA_FAILED`, `WEAK_PASSWORD`, `SQLSTATE_23505`…), jamais affiché. Toute autre erreur (délai, réseau)
/// reste un `JoleneError` : une création de compte dont l'issue est inconnue n'est jamais renvoyée d'office.
public struct RefusInscription: Error, Equatable, Sendable, LocalizedError {
    public let code: String?
    public let message: String

    public init(code: String?, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }

    /// Code d'un refus captcha GoTrue (`mapperErreurInscription`, `src/lib/erreurs.ts` l.132-137).
    public static let codeCaptcha = "CAPTCHA_FAILED"
    public var estCaptcha: Bool { code == Self.codeCaptcha }
}

/// Champ du formulaire « Créer un compte », dans l'ordre du web (focus sur le premier en erreur, l.76).
public enum ChampInscription: String, CaseIterable, Sendable {
    case email, motDePasse, profession, cgu
}

/// Règles pures du compte rapide soignant (lot 3, T7), portées de `src/pages/InscriptionRapide.tsx` l.55-115 et
/// `src/lib/inscriptionProgressive.ts` l.26-99. Aucune règle juridique : le consentement est une case à cocher
/// obligatoire, son texte vit dans `InscriptionTextes` et sa preuve côté serveur (`consentement_cgu_le`).
public enum InscriptionRules {
    /// `/^[^\s@]+@[^\s@]+\.[^\s@]+$/` appliqué à `email.trim()` (l.59) ; après le `trim`, aucun saut de ligne final
    /// ne peut satisfaire `$` (ICU) et `[^\s@]` exclut tout saut de ligne interne : même langage que le web.
    private static let motifEmail = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
    /// `form.password.length < 8` (l.61) : longueur JavaScript en unités UTF-16.
    public static let longueurMinimaleMotDePasse = 8
    /// `emailRedirectTo` de `signUp` (`inscriptionProgressive.ts` l.75, `urlCallbackPublique("/inscription/confirmer")`) :
    /// hôte web canonique, couvert par l'AASA (`/inscription/*`) et par les Redirect URLs de GoTrue (D10, §6.4).
    public static let redirectionConfirmation = URL(string: "https://jolene.app/inscription/confirmer")!

    public static func emailValide(_ email: String) -> Bool {
        let saisi = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return saisi.range(of: motifEmail, options: .regularExpression) != nil
    }

    /// Adresse envoyée à GoTrue : `input.email.trim().toLowerCase()` (`inscriptionProgressive.ts` l.45).
    public static func emailNormalise(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Profession du catalogue web (`PROFESSIONS`, `MissionPresentation.professions`).
    public static func professionConnue(_ code: String) -> Bool {
        MissionPresentation.professions.contains { $0.valeur == code }
    }

    /// Profession pré-remplie par un lien `/inscription/soignant?profession=…` : port de `lireCriteresInscription`
    /// (`src/lib/recherchePubliqueInscription.ts` l.5-10), valeur ignorée hors catalogue.
    public static func professionDepuisLien(_ etape: EtapeInscription?) -> String {
        guard let code = etape?.parametre("profession"), professionConnue(code) else { return "" }
        return code
    }

    /// Erreurs de saisie (l.58-70), dans l'ordre des champs. `avecIdentifiants` faux : compte déjà ouvert dans le SDK
    /// (aiguillage d'onboarding), seuls la profession et le consentement sont saisis.
    public static func erreurs(email: String, motDePasse: String, profession: String, cgu: Bool,
                               avecIdentifiants: Bool = true) -> [ChampInscription: String] {
        var erreurs: [ChampInscription: String] = [:]
        if avecIdentifiants {
            if !emailValide(email) { erreurs[.email] = InscriptionTextes.erreurEmail }
            if motDePasse.utf16.count < longueurMinimaleMotDePasse { erreurs[.motDePasse] = InscriptionTextes.erreurMotDePasse }
        }
        if profession.isEmpty { erreurs[.profession] = InscriptionTextes.erreurProfession }
        if !cgu { erreurs[.cgu] = InscriptionTextes.erreurCGU }
        return erreurs
    }

    /// Premier champ en erreur (ordre du formulaire).
    public static func premierChampEnErreur(_ erreurs: [ChampInscription: String]) -> ChampInscription? {
        ChampInscription.allCases.first { erreurs[$0] != nil }
    }

    /// Intention de l'inscription soignant (l.46-52) : `{type, profession, nom, cgu, cgv}` ; `nom` vide et
    /// `cgv` faux pour un soignant (formulaire web l.32-39).
    public static func intention(profession: String, cgu: Bool) -> IntentionInscription {
        IntentionInscription(typeCompte: UserRole.soignant.rawValue, profession: profession, nom: "", cgu: cgu, cgv: false)
    }

    /// `user_metadata.inscription_progressive` posé par `signUp` (l.74) : mêmes clés et valeurs que le web.
    public static func metadonnees(_ intention: IntentionInscription) -> ValeurJSON {
        .objet([
            "type": .chaine(intention.typeCompte),
            "profession": .chaine(intention.profession ?? ""),
            "nom": .chaine(intention.nom ?? ""),
            "cgu": .booleen(intention.cgu),
            "cgv": .booleen(intention.cgv),
        ])
    }

    /// Paramètre texte de `fn_demarrer_inscription` : `input.profession || null`, `input.nom || null` (l.31-32).
    public static func parametreTexte(_ valeur: String?) -> String? {
        guard let valeur, !valeur.isEmpty else { return nil }
        return valeur
    }

    /// Compte existant signalé par GoTrue : `/already.*registered|user.*registered/i` (`inscriptionProgressive.ts`
    /// l.78-80) ; l'app propose alors la connexion (`ResultatCompte.connexionRequise`).
    public static func estCompteExistant(messageServeur: String) -> Bool {
        let texte = messageServeur.lowercased()
        return texte.range(of: "already.*registered", options: .regularExpression) != nil
            || texte.range(of: "user.*registered", options: .regularExpression) != nil
    }

    /// Refus GoTrue d'un `signUp` traduit comme `mapperErreurInscription` (cas 2, `src/lib/erreurs.ts` l.79-138),
    /// textes web verbatim. Écart assumé (blueprint §3 T7) : un refus captcha rend le message générique du web
    /// (l.178) et non « Rafraîchissez la page… », sans objet dans l'app ; son code `CAPTCHA_FAILED` permet le renvoi
    /// web de l'inscription quand le présentateur `.safari` existe (D25).
    public static func refusCreation(messageServeur: String, codeServeur: String?) -> RefusInscription {
        let texte = messageServeur.lowercased()
        if codeServeur == "weak_password"
            || texte.range(of: "password is known to be weak|password.*easy to guess|password.*leaked", options: .regularExpression) != nil {
            return RefusInscription(code: "WEAK_PASSWORD", message: InscriptionTextes.motDePasseDivulgue)
        }
        if texte.contains("email rate limit") || texte.contains("only request this once every") {
            return RefusInscription(code: "EMAIL_RATE_LIMIT", message: InscriptionTextes.tropDeTentatives)
        }
        if texte.contains("invalid email") || texte.contains("email_address_invalid") {
            return RefusInscription(code: "INVALID_EMAIL", message: InscriptionTextes.emailInvalide)
        }
        if let minimum = longueurMinimaleAnnoncee(messageServeur) {
            return RefusInscription(code: "WEAK_PASSWORD", message: InscriptionTextes.motDePasseLongueur(minimum))
        }
        if texte.contains("weak_password") || texte.contains("password is too short") || texte.contains("password should") {
            return RefusInscription(code: "WEAK_PASSWORD", message: InscriptionTextes.motDePasseFaible)
        }
        if texte.contains("captcha") || codeServeur == "captcha_failed" {
            return RefusInscription(code: RefusInscription.codeCaptcha, message: InscriptionTextes.erreurInattendue)
        }
        return RefusInscription(code: "UNKNOWN", message: InscriptionTextes.erreurInattendue)
    }

    /// `Password should be at least (\d+) characters?` (insensible à la casse, l.115).
    private static func longueurMinimaleAnnoncee(_ message: String) -> String? {
        let motif = try! NSRegularExpression(pattern: #"Password should be at least (\d+) characters?"#, options: [.caseInsensitive])
        let plage = NSRange(message.startIndex..., in: message)
        guard let trouve = motif.firstMatch(in: message, range: plage), trouve.numberOfRanges > 1,
              let chiffres = Range(trouve.range(at: 1), in: message) else { return nil }
        return String(message[chiffres])
    }

    /// Codes de réservation qui signalent un espace déjà existant (`InscriptionRapide.tsx` l.98-100).
    public static let codesEspaceExistant: Set<String> = [
        "ACCOUNT_ALREADY_REGISTERED", "ACCOUNT_TYPE_MISMATCH", "ACCOUNT_REGISTRATION_INCOMPLETE",
    ]

    /// Exception métier de `fn_demarrer_inscription` restituée avant `SupabaseErrorMapping` (correction 12) :
    /// 22023 → message serveur verbatim (`public.sql` l.30163, l.30167) ; 23505 → le message est le code de réservation
    /// (`RAISE EXCEPTION '%', v_reservation ->> 'code'`, l.30176) : « Ce compte possède déjà un espace Jolene… »
    /// pour les trois codes du web, sinon le message générique du web (`mapperErreurInscription`).
    public static func refusDemarrage(sqlstate: String, messageServeur: String) -> RefusInscription {
        let message = messageServeur.trimmingCharacters(in: .whitespacesAndNewlines)
        switch sqlstate {
        case "22023":
            return RefusInscription(code: "SQLSTATE_22023", message: message.isEmpty ? InscriptionTextes.erreurInattendue : message)
        case "23505":
            let espaceExistant = codesEspaceExistant.contains { message.contains($0) }
            return RefusInscription(code: "SQLSTATE_23505",
                                    message: espaceExistant ? InscriptionTextes.compteDejaEspace : InscriptionTextes.erreurInattendue)
        default:
            return RefusInscription(code: "SQLSTATE_\(sqlstate)", message: InscriptionTextes.erreurInattendue)
        }
    }

    /// Message d'une erreur de transport pendant la création ou le démarrage (`mapperErreurInscription` cas 3-5) :
    /// réseau ou délai → texte réseau du web, session expirée → message de session natif, sinon générique.
    public static func messageErreur(_ erreur: Error) -> String {
        if let refus = erreur as? RefusInscription { return refus.message }
        guard let jolene = erreur as? JoleneError else { return InscriptionTextes.erreurInattendue }
        switch jolene.kind {
        case .network: return InscriptionTextes.connexionInstable
        case .unauthorized, .demoOnly: return jolene.message
        default: return InscriptionTextes.erreurInattendue
        }
    }
}
