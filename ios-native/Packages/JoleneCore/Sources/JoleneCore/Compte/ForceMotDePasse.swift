import Foundation

/// Force d'un nouveau mot de passe (lot 3, T11), port à l'identique de `calculerForce`
/// (`src/components/soignant/ChangementMotDePasse.tsx` l.198-208) : cinq critères, score = nombre de critères
/// remplis (`Object.values(criteres).filter(Boolean).length`). Sémantique JavaScript conservée :
/// - `mdp.length >= 12` compte des unités UTF-16 (un emoji en vaut deux) ;
/// - `/[A-Z]/`, `/[a-z]/`, `/[0-9]/` sans drapeau `u` : plages ASCII seulement ;
/// - `/[^A-Za-z0-9]/` : toute unité UTF-16 hors de ces plages (lettre accentuée, espace, demi-emoji).
/// Les libellés et tons de la jauge vivent dans `PasswordCriteriaList` (JoleneDesign) ; aucune règle là-bas.
public struct ForceMotDePasse: Equatable, Sendable {
    /// `longueur: mdp.length >= 12` (l.200).
    public static let longueurMinimale = 12

    public var longueur: Bool
    public var majuscule: Bool
    public var minuscule: Bool
    public var chiffre: Bool
    public var special: Bool

    public init(longueur: Bool, majuscule: Bool, minuscule: Bool, chiffre: Bool, special: Bool) {
        self.longueur = longueur; self.majuscule = majuscule; self.minuscule = minuscule
        self.chiffre = chiffre; self.special = special
    }

    /// Nombre de critères remplis (l.206).
    public var score: Int { [longueur, majuscule, minuscule, chiffre, special].filter { $0 }.count }

    /// `motDePasseValide = force.score === 5` (l.38).
    public var estValide: Bool { score == 5 }

    public static func calculer(_ motDePasse: String) -> ForceMotDePasse {
        let unites = Array(motDePasse.utf16)
        let majuscules: ClosedRange<UInt16> = 0x41...0x5A
        let minuscules: ClosedRange<UInt16> = 0x61...0x7A
        let chiffres: ClosedRange<UInt16> = 0x30...0x39
        return ForceMotDePasse(
            longueur: unites.count >= longueurMinimale,
            majuscule: unites.contains(where: majuscules.contains),
            minuscule: unites.contains(where: minuscules.contains),
            chiffre: unites.contains(where: chiffres.contains),
            special: unites.contains { !majuscules.contains($0) && !minuscules.contains($0) && !chiffres.contains($0) }
        )
    }
}

/// Règles et textes du changement de mot de passe (lot 3, T11, D13), port de `ChangementMotDePasse.tsx`
/// l.37-110 et, pour les refus GoTrue, du sous-ensemble d'`extraireMessageErreur` (`src/lib/erreurs.ts`
/// l.479-532) qu'une erreur d'authentification peut atteindre : table `traductions`, puis code
/// `weak_password` / `invalid_password`, puis message générique. Les branches de paiement, de trigger
/// PostgreSQL et de contrainte ne concernent pas GoTrue ; les erreurs réseau et de session ont leurs
/// messages natifs (`JoleneError`). Aucun mot de passe n'est conservé ni journalisé.
public enum MotDePasse {
    /// `correspond = nouveauMdp.length > 0 && nouveauMdp === confirmationMdp` (l.39) : égalité JavaScript,
    /// unité UTF-16 par unité, sans normalisation Unicode (l'égalité Swift en ferait une).
    public static func correspond(nouveau: String, confirmation: String) -> Bool {
        !nouveau.utf16.isEmpty && nouveau.utf16.elementsEqual(confirmation.utf16)
    }

    /// `formValide = ancienMdp.length > 0 && motDePasseValide && correspond` (l.40). Rien n'est rogné.
    public static func formValide(ancien: String, nouveau: String, confirmation: String) -> Bool {
        !ancien.utf16.isEmpty && ForceMotDePasse.calculer(nouveau).estValide && correspond(nouveau: nouveau, confirmation: confirmation)
    }

    // MARK: - Audit (l.82-91)

    /// `p_type_ressource: 'utilisateur'` (l.86) ; action `DONNEES_PERSO_MODIFICATION` (l.85).
    public static let auditTypeRessource = "utilisateur"

    /// `p_details: { champ: 'mot_de_passe', horodatage: new Date().toISOString() }` (l.88).
    public static func auditDetails(horodatage: Date) -> [String: String] {
        ["champ": "mot_de_passe", "horodatage": horodatageISO(horodatage)]
    }

    /// `Date.prototype.toISOString` : UTC, millisecondes, suffixe `Z`.
    public static func horodatageISO(_ date: Date) -> String {
        let formateur = ISO8601DateFormatter()
        formateur.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formateur.timeZone = TimeZone(secondsFromGMT: 0)
        return formateur.string(from: date)
    }

    // MARK: - Refus GoTrue (`extraireMessageErreur`)

    /// Paire de la table `traductions` (erreurs.ts l.480-493), dans l'ordre du web.
    public struct Traduction: Equatable, Sendable {
        public let anglais: String
        public let francais: String
    }

    // source: src/lib/erreurs.ts:480-493
    public static let traductionsWeb: [Traduction] = [
        Traduction(anglais: "Invalid login credentials", francais: "Email ou mot de passe incorrect."),
        Traduction(anglais: "Email not confirmed", francais: "Veuillez confirmer votre adresse email avant de vous connecter."),
        Traduction(anglais: "User already registered", francais: "Un compte existe déjà avec cette adresse email."),
        Traduction(anglais: "Signup requires a valid password", francais: "Le mot de passe n'est pas valide."),
        Traduction(anglais: "Password should be at least", francais: "Mot de passe trop court : il doit contenir au moins 8 caractères."),
        Traduction(anglais: "Password is too short", francais: "Mot de passe trop court : il doit contenir au moins 8 caractères."),
        Traduction(anglais: "weak_password", francais: Textes.motDePasseTropFaible),
        Traduction(anglais: "Password should contain",
                   francais: "Mot de passe trop faible : ajoutez majuscules, minuscules, chiffres et caractères spéciaux (8+ caractères)."),
        Traduction(anglais: "Password should be one of the following",
                   francais: "Mot de passe trop faible : ajoutez majuscules, minuscules, chiffres et caractères spéciaux (8+ caractères)."),
        Traduction(anglais: "pwned", francais: "Ce mot de passe a été compromis dans une fuite de données connue. Choisissez-en un autre."),
        Traduction(anglais: "Email rate limit exceeded", francais: "Trop de tentatives. Veuillez patienter quelques minutes."),
        Traduction(anglais: "For security purposes, you can only request this once every 60 seconds",
                   francais: "Pour des raisons de sécurité, veuillez patienter 60 secondes."),
        Traduction(anglais: "captcha verification process failed",
                   francais: "La vérification anti-bot a échoué. Rafraîchissez la page et réessayez."),
        Traduction(anglais: "captcha protection: request disallowed",
                   francais: "La vérification anti-bot a échoué. Rafraîchissez la page et réessayez."),
    ]

    /// Message affiché pour un refus GoTrue (`code` = `error_code`, `message` = message serveur anglais) :
    /// `msg.toLowerCase().includes(en.toLowerCase())` sur la table (l.496-498), puis `weak_password` /
    /// `invalid_password` (l.501-504), sinon le message générique (l.532). Jamais le message anglais brut.
    public static func messageRefus(code: String?, message: String) -> String {
        let minuscule = message.lowercased()
        if let traduction = traductionsWeb.first(where: { minuscule.contains($0.anglais.lowercased()) }) {
            return traduction.francais
        }
        if code == "weak_password" || code == "invalid_password" { return Textes.motDePasseTropFaible }
        return Textes.erreurGenerique
    }

    // MARK: - Issues GoTrue sans équivalent web (revue B8, m1 et m2)

    /// Octets que bcrypt (hachage des mots de passe GoTrue) prend en compte : les 72 premiers.
    public static let octetsBcrypt = 72

    /// `same_password` reçu sur la mise à jour, l'ancien mot de passe venant d'être vérifié : si le nouveau en
    /// diffère pour GoTrue (octet par octet en UTF-8, sur les 72 octets que lit bcrypt), le mot de passe vaut DÉJÀ
    /// le nouveau — rejeu par le SDK d'un PUT abouti dont la réponse a été perdue, ou changement concurrent vers
    /// la même valeur. Sinon (nouveau égal à l'ancien pour bcrypt), c'est le vrai refus du web.
    public static func memeMotDePasseProuveLaModification(ancien: String, nouveau: String) -> Bool {
        Array(ancien.utf8.prefix(octetsBcrypt)) != Array(nouveau.utf8.prefix(octetsBcrypt))
    }

    /// Identité de l'écran partie entre la vérification de l'ancien mot de passe et la mise à jour (garde du
    /// port) : aucune mise à jour. Jamais affiché (réponse d'un epoch périmé, ignorée par le modèle).
    public static let identitePartie = JoleneError(.cancelled, "Chargement annulé.")

    /// Textes de l'écran. Repris mot pour mot du web (gardés par `CompteVerbatimTests`), sauf les deux
    /// textes natifs sans équivalent web listés dans `DECISIONS_LOT3.md` (à relire par Gabrielle).
    public enum Textes {
        // source: src/pages/MonCompteSoignant.tsx:206
        public static let titre = "Changer mon mot de passe"
        // source: src/pages/MonCompteSoignant.tsx:178
        public static let sectionHub = "Connexion & sécurité"
        // source: src/components/soignant/ChangementMotDePasse.tsx:115
        public static let ancien = "Mot de passe actuel"
        // source: src/components/soignant/ChangementMotDePasse.tsx:137
        public static let nouveau = "Nouveau mot de passe"
        // source: src/components/soignant/ChangementMotDePasse.tsx:160
        public static let confirmation = "Confirmer le nouveau mot de passe"
        // source: src/components/soignant/ChangementMotDePasse.tsx:171
        public static let nonCorrespondance = "Les mots de passe ne correspondent pas."
        // source: src/components/soignant/ChangementMotDePasse.tsx:176
        public static let correspondance = "Mots de passe identiques."
        // source: src/components/soignant/ChangementMotDePasse.tsx:187
        public static let soumettre = "Modifier mon mot de passe"
        // source: src/components/soignant/ChangementMotDePasse.tsx:58
        public static let ancienIncorrect = "Ancien mot de passe incorrect."
        // source: src/components/soignant/ChangementMotDePasse.tsx:96
        public static let succes = "Mot de passe modifié avec succès."
        // source: src/lib/erreurs.ts:503
        public static let motDePasseTropFaible =
            "Mot de passe trop faible. Utilisez au moins 8 caractères avec majuscules, minuscules, chiffres et caractères spéciaux."
        // source: src/lib/erreurs.ts:532
        public static let erreurGenerique = "Une erreur est survenue. Veuillez réessayer."

        /// Natif, sans équivalent web (D13) : le serveur exige une réauthentification (« secure password
        /// change », nonce) ; aucun flux OTP au lot 3, renvoi vers « Mot de passe oublié ? ». Ce lien de l'écran de
        /// connexion (`login-forgot`) arrive avec L1-T10, et ne s'atteint qu'après une déconnexion : dépendance
        /// consignée dans les manques de T11 (`DECISIONS_LOT3.md`), texte à relire par Gabrielle.
        public static let reauthentificationRequise =
            "Ce changement exige une nouvelle vérification de votre identité. Utilisez « Mot de passe oublié ? » pour choisir un nouveau mot de passe."
        /// Natif, sans équivalent web : délai dépassé ou coupure pendant le changement, le serveur a pu
        /// l'enregistrer (issue inconnue, PRINCIPES §3-§4) ; rien n'est annoncé ni renvoyé.
        public static let confirmationIndisponible =
            "Le changement de votre mot de passe n'a pas pu être confirmé. Vérifiez votre connexion puis réessayez."
    }
}
