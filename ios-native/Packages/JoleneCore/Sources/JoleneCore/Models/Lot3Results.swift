import Foundation

// Contrats d'échange des ports du lot 3 (`Ports/Lot3Ports.swift`, blueprint
// `docs/mobile-swift/LOT3_PLAN.md` §2.3-§2.4). Posés par T1 pour que les tranches suivantes ne
// modifient ni `Gateways` ni les protocoles : chaque tranche complète ici le contrat de son domaine
// (champs optionnels, conformité `Decodable` et décodage tolérant, règles d'écran) ou le déplace
// dans son fichier de modèle (`Profil/ProfilComplet.swift` en T9, etc.), comme au lot 1. Les types
// ci-dessous ne portent que les clés citées par les fiches de `CONTRATS_RPC_SOIGNANT.md` ; aucun
// n'est `Codable` à ce stade : la tolérance de décodage (clé absente, type inattendu) est une règle
// de la tranche qui câble la gateway. `JoleneError.Kind` n'est pas étendu : les refus métier
// structurés sont des issues, les erreurs de transport des `JoleneError`.

// MARK: - Push (T4, T5)

/// État d'autorisation des notifications de l'appareil (`UNAuthorizationStatus` réduit, §2.3).
public enum AutorisationPush: String, CaseIterable, Sendable {
    case nonDemandee, accordee, refusee, provisoire

    /// Seuls `accordee` et `provisoire` autorisent l'enregistrement du token (§2.5) : jamais de prompt implicite.
    public var permetEnregistrement: Bool { self == .accordee || self == .provisoire }
}

/// Issue de `fn_desactiver_mon_token_push` : `{success:true, tokens_desactives}` ou refus
/// `{success:false, error}` — jamais bloquant pour la déconnexion (D2, D3).
public enum IssueDesactivationPush: Equatable, Sendable {
    case desactive(tokensDesactives: Int)
    case nonDesactive
}

// MARK: - Centre de notifications (T5)

/// Ligne `notifications` lue sous RLS (`destinataire_id = auth.uid()`).
public struct NotificationJolene: Equatable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var titre: String
    public var corps: String
    public var lien: String?
    public var lue: Bool
    public var lueLe: String?
    public var creeLe: String?

    public init(id: String, type: String, titre: String, corps: String, lien: String? = nil, lue: Bool = false,
                lueLe: String? = nil, creeLe: String? = nil) {
        self.id = id; self.type = type; self.titre = titre; self.corps = corps; self.lien = lien
        self.lue = lue; self.lueLe = lueLe; self.creeLe = creeLe
    }
}

// MARK: - Préférences de notifications (T6)

// `CanalNotification`, `PreferenceEvenement` et `PreferencesNotifications` vivent depuis T6 dans
// `Notifications/PreferencesNotifications.swift`, avec le catalogue `EVENTS_SOIGNANT` et leurs règles.

// MARK: - Inscription (T7, T8)

/// Intention d'inscription (`user_metadata.inscription_progressive`, paramètres de
/// `fn_demarrer_inscription` : web `inscriptionProgressive.ts` l.26-39). Le natif ne sert que le
/// parcours soignant : `typeCompte` vaut `SOIGNANT`, `cgv` `false`.
public struct IntentionInscription: Equatable, Sendable {
    public var typeCompte: String
    public var profession: String?
    public var nom: String?
    public var cgu: Bool
    public var cgv: Bool

    public init(typeCompte: String = UserRole.soignant.rawValue, profession: String?, nom: String? = nil,
                cgu: Bool, cgv: Bool = false) {
        self.typeCompte = typeCompte; self.profession = profession; self.nom = nom; self.cgu = cgu; self.cgv = cgv
    }
}

/// Issue de « Créer un compte » (`signUp`, §2.5).
public enum ResultatCompte: Equatable, Sendable {
    /// Email de confirmation envoyé : message verbatim web (`InscriptionRapide.tsx` l.320-326).
    case confirmationEnvoyee
    /// `signUp` a ouvert une session : `demarrer(intention:)` puis `SessionStore.start()`.
    case sessionOuverte
    /// Email déjà inscrit ou `identities` vide (`inscriptionProgressive.ts` l.78-94) : écran de connexion.
    case connexionRequise
}

/// Issue du lien `/inscription/confirmer` (`token_hash`, implicit, `code` tenté une fois — D10).
public enum ResultatConfirmation: Equatable, Sendable {
    case sessionOuverte
    /// Échec : texte verbatim web (`ConfirmationInscription.tsx` l.75-78) et « Se connecter ».
    case lienRefuse(message: String)
}

/// Brouillon serveur et formulaire de complétion soignant : seules les clés de la liste blanche
/// de `fn_enregistrer_parcours_inscription` (l.32436-32441) envoyées par le natif — jamais email,
/// mot de passe, jeton ni coordonnées. Un champ nil n'est pas transmis.
public struct FormulaireInscription: Equatable, Sendable {
    public var prenom: String?
    public var nom: String?
    public var telephone: String?
    /// `AAAA-MM-JJ`.
    public var dateNaissance: String?
    /// Profession du parcours (`parcours.donnees.profession`), en lecture seule à la complétion.
    public var profession: String?
    public var typesContrat: [String]
    public var rpps: String?
    public var rayon: Int?

    public init(prenom: String? = nil, nom: String? = nil, telephone: String? = nil, dateNaissance: String? = nil,
                profession: String? = nil, typesContrat: [String] = [], rpps: String? = nil, rayon: Int? = nil) {
        self.prenom = prenom; self.nom = nom; self.telephone = telephone; self.dateNaissance = dateNaissance
        self.profession = profession; self.typesContrat = typesContrat; self.rpps = rpps; self.rayon = rayon
    }
}

/// Ligne `parcours_inscription` (l.70967) : `donnees` restituée en brouillon (liste blanche).
public struct ParcoursInscription: Equatable, Sendable {
    public var userId: String
    public var typeCompte: String
    public var brouillon: FormulaireInscription
    /// Preuve serveur du consentement CGU (défaut de colonne à l'INSERT).
    public var consentementCguLe: String?
    public var modifieLe: String?

    public init(userId: String, typeCompte: String, brouillon: FormulaireInscription,
                consentementCguLe: String? = nil, modifieLe: String? = nil) {
        self.userId = userId; self.typeCompte = typeCompte; self.brouillon = brouillon
        self.consentementCguLe = consentementCguLe; self.modifieLe = modifieLe
    }
}

/// Utilisateur Auth courant vu par l'aiguillage d'onboarding (rôle `INCONNU`, §2.5).
public struct ContexteOnboarding: Equatable, Sendable {
    public var userId: String
    public var email: String?
    public var emailConfirme: Bool
    /// `user_metadata.inscription_progressive`, si présente et lisible.
    public var intention: IntentionInscription?

    public init(userId: String, email: String?, emailConfirme: Bool, intention: IntentionInscription?) {
        self.userId = userId; self.email = email; self.emailConfirme = emailConfirme; self.intention = intention
    }
}

/// Issue de `register-soignant` (§2.4) ; le succès n'est prouvé que par `.ready` relu ensuite.
public enum ResultatFinalisation: Equatable, Sendable {
    /// HTTP 200 `{ok:true, success:true, soignant_id}` : `refreshSession()` puis `SessionStore.start()`.
    case finalisee(soignantId: String)
    /// Refus serveur, `message` verbatim (`code` machine de `_shared/errors.ts`).
    case refusee(code: String?, message: String)
    /// 503 `ACCOUNT_FINALIZATION_PENDING` : déconnexion locale puis message serveur verbatim.
    case finalisationEnAttente(message: String)
}

// MARK: - Profil (T9, T10)

// `ProfilComplet` et `ModificationProfil` : déplacés par T9 dans `Profil/ProfilComplet.swift` et
// `Profil/ModificationProfil.swift` (décodage en liste blanche, différence de saisie).

/// Résultat du géocodage inverse (`api-adresse.data.gouv.fr/reverse`, D15), best-effort.
public struct AdresseGeocodee: Equatable, Sendable {
    public var libelle: String
    public var ville: String?
    public var codePostal: String?

    public init(libelle: String, ville: String? = nil, codePostal: String? = nil) {
        self.libelle = libelle; self.ville = ville; self.codePostal = codePostal
    }
}

// MARK: - Compte (T11)

/// Issue du changement de mot de passe (ancien vérifié par `signIn` du même utilisateur, D13).
public enum ResultatMotDePasse: Equatable, Sendable {
    case modifie
    case ancienIncorrect
    /// Le serveur exige un nonce (« secure password change ») : refus verrouillé vers « Mot de passe oublié ? ».
    case reauthentificationRequise
    /// Refus serveur, message verbatim.
    case refuse(message: String)
}

/// Export RGPD (`fn_rgpd_exporter_rate_limited`) : corps JSON brut, jamais persisté hors du fichier
/// temporaire de la feuille de partage (§2.6) ; l'aplatissement CSV est une règle de T11.
public struct ExportDonneesRGPD: Equatable, Sendable {
    public var json: Data

    public init(json: Data) { self.json = json }
}

// MARK: - Revenus (T12)

/// `fn_mes_revenus_connect` : trois nombres finis exigés (web `PageStripeConnect.tsx` l.73-76).
public struct TotauxRevenus: Equatable, Sendable {
    public var moisEnCours: Double
    public var total: Double
    public var enAttente: Double
    public var stripeConnectActif: Bool?

    public init(moisEnCours: Double, total: Double, enAttente: Double, stripeConnectActif: Bool? = nil) {
        self.moisEnCours = moisEnCours; self.total = total; self.enAttente = enAttente; self.stripeConnectActif = stripeConnectActif
    }
}

/// Élément de `fn_mes_paiements_escrow` (`etat` ∈ sept valeurs serveur, libellés verbatim en T12).
public struct PaiementRapide: Equatable, Sendable, Identifiable {
    public var missionId: String
    public var missionIntitule: String?
    public var etablissementNom: String?
    public var honorairesCents: Int
    public var etat: String
    public var dateAffichee: String?
    public var missionDate: String?
    public var aLitige: Bool

    public var id: String { missionId }

    public init(missionId: String, missionIntitule: String? = nil, etablissementNom: String? = nil, honorairesCents: Int,
                etat: String, dateAffichee: String? = nil, missionDate: String? = nil, aLitige: Bool = false) {
        self.missionId = missionId; self.missionIntitule = missionIntitule; self.etablissementNom = etablissementNom
        self.honorairesCents = honorairesCents; self.etat = etat; self.dateAffichee = dateAffichee
        self.missionDate = missionDate; self.aLitige = aLitige
    }
}

/// Mission TERMINEE de l'onglet Revenus, colonnes de `MesGains.tsx` l.95 (sans colonnes Rist, D5), complétée à
/// l'assemblage (`RevenusAssemblage`, T12) par le nom d'établissement (`fn_etablissements_safe` seul) et la dernière
/// déclaration de paiement de la mission (`paiements_soignant`, l.102). Montant affiché = règle web portée
/// (`MontantMission`, golden T2) sur ces valeurs serveur, jamais recalculé ; régime = contrat de LA mission.
public struct MissionTerminee: Equatable, Sendable, Identifiable {
    public var id: String
    public var intitule: String?
    public var debutLe: String?
    public var finLe: String?
    public var etablissementId: String?
    public var typeContratApplique: String?
    public var typeContratRecherche: String?
    public var netAPayer: Double?
    public var netEstime: Double?
    public var totalBrut: Double?
    public var dureeHeures: Double?
    public var tauxHoraireBase: Double?
    public var service: String?
    public var statut: String?
    /// Nom relu par `fn_etablissements_safe` (lot 0) ; nil si la lecture n'a pas abouti (le web affiche « — »).
    public var etablissementNom: String?
    /// Dernière déclaration de la mission (`EtatPaiement.indexerDernierPaiementParMission`), nil si aucune.
    public var dernierPaiement: PaiementSoignantLu?

    public init(id: String, intitule: String? = nil, debutLe: String? = nil, finLe: String? = nil,
                etablissementId: String? = nil, typeContratApplique: String? = nil, typeContratRecherche: String? = nil,
                netAPayer: Double? = nil, netEstime: Double? = nil, totalBrut: Double? = nil, dureeHeures: Double? = nil,
                tauxHoraireBase: Double? = nil, service: String? = nil, statut: String? = nil, etablissementNom: String? = nil,
                dernierPaiement: PaiementSoignantLu? = nil) {
        self.id = id; self.intitule = intitule; self.debutLe = debutLe; self.finLe = finLe
        self.etablissementId = etablissementId; self.typeContratApplique = typeContratApplique
        self.typeContratRecherche = typeContratRecherche; self.netAPayer = netAPayer; self.netEstime = netEstime
        self.totalBrut = totalBrut; self.dureeHeures = dureeHeures; self.tauxHoraireBase = tauxHoraireBase
        self.service = service; self.statut = statut; self.etablissementNom = etablissementNom
        self.dernierPaiement = dernierPaiement
    }
}

public struct PageMissionsTerminees: Equatable, Sendable {
    public var missions: [MissionTerminee]
    public var page: Int
    public var aSuivre: Bool

    public init(missions: [MissionTerminee], page: Int, aSuivre: Bool) {
        self.missions = missions; self.page = page; self.aSuivre = aSuivre
    }
}

// MARK: - Paiements déclarés (T13)

/// Ligne `paiements_soignant` (l.70881) lue sous RLS ; nom d'établissement via `fn_etablissements_safe` seul.
public struct PaiementDeclare: Equatable, Sendable, Identifiable {
    public var id: String
    public var missionId: String
    public var etablissementId: String
    public var montantNet: Double
    public var methode: String
    public var referenceVirement: String?
    public var datePaiement: String?
    public var statut: String
    public var confirmeParSoignant: Bool
    public var conteste: Bool
    public var etablissementNom: String?

    public init(id: String, missionId: String, etablissementId: String, montantNet: Double, methode: String,
                referenceVirement: String? = nil, datePaiement: String? = nil, statut: String,
                confirmeParSoignant: Bool = false, conteste: Bool = false, etablissementNom: String? = nil) {
        self.id = id; self.missionId = missionId; self.etablissementId = etablissementId; self.montantNet = montantNet
        self.methode = methode; self.referenceVirement = referenceVirement; self.datePaiement = datePaiement
        self.statut = statut; self.confirmeParSoignant = confirmeParSoignant; self.conteste = conteste
        self.etablissementNom = etablissementNom
    }
}

/// Issue d'une confirmation ou d'une contestation, toujours après relecture de la ligne.
public enum IssuePaiement: Equatable, Sendable {
    /// Relu `statut = CONFIRME` et `confirme_par_soignant`.
    case confirme(PaiementDeclare)
    /// Relu `statut = CONTESTE` ; `litige_id` renvoyé par la RPC.
    case conteste(PaiementDeclare, litigeId: String?)
    /// Refus serveur `{error}`, message verbatim.
    case refuse(message: String)
}

// MARK: - IBAN (T14b)

/// `fn_consulter_mon_iban` (l.25576-25582) : affichage `•••• {last4}` seulement.
public struct ConsultationIban: Equatable, Sendable {
    public var ibanRenseigne: Bool
    public var ibanVerifie: Bool
    public var verificationRequise: Bool
    public var ibanLast4: String?
    public var ibanTitulaire: String?

    public init(ibanRenseigne: Bool, ibanVerifie: Bool, verificationRequise: Bool, ibanLast4: String? = nil,
                ibanTitulaire: String? = nil) {
        self.ibanRenseigne = ibanRenseigne; self.ibanVerifie = ibanVerifie; self.verificationRequise = verificationRequise
        self.ibanLast4 = ibanLast4; self.ibanTitulaire = ibanTitulaire
    }
}

/// Issue de `fn_enregistrer_mon_iban` : succès strict (`success == true` puis `consulter` relu, D20).
public enum ResultatIban: Equatable, Sendable {
    case enregistre(ConsultationIban)
    /// `error_code` serveur ; `message` = `error` verbatim s'il existe (deux codes sur neuf en portent un).
    case refuse(code: String?, message: String?)
}

// MARK: - Stripe Connect (T14a)

/// `stripe_connect_onboarding_statut_check` (`public.sql` l.72036) : statut hors de ces six valeurs →
/// erreur d'écran, jamais un défaut.
public enum StatutOnboardingConnect: String, CaseIterable, Sendable {
    case nonDemande = "NON_DEMANDE"
    case enCours = "EN_COURS"
    case complet = "COMPLET"
    case suspendu = "SUSPENDU"
    case rejete = "REJETE"
    case supprime = "SUPPRIME"
}

/// Réponse 200 de `stripe-connect-status` ; `COMPLET` n'est accepté que si les trois drapeaux sont
/// vrais (web l.53-54), règle de T14a.
public struct StatutConnect: Equatable, Sendable {
    public var statut: StatutOnboardingConnect
    public var onboardingComplete: Bool
    public var chargesEnabled: Bool
    public var payoutsEnabled: Bool
    public var ibanLast4: String?
    public var disabledReason: String?
    /// Message serveur verbatim (ex. compte `SUPPRIME`).
    public var message: String?

    public init(statut: StatutOnboardingConnect, onboardingComplete: Bool, chargesEnabled: Bool, payoutsEnabled: Bool,
                ibanLast4: String? = nil, disabledReason: String? = nil, message: String? = nil) {
        self.statut = statut; self.onboardingComplete = onboardingComplete; self.chargesEnabled = chargesEnabled
        self.payoutsEnabled = payoutsEnabled; self.ibanLast4 = ibanLast4; self.disabledReason = disabledReason
        self.message = message
    }
}

/// Issue de `stripe-connect-onboard` (avec `Origin: https://jolene.app`, D6).
public enum ResultatLienConnect: Equatable, Sendable {
    /// URL d'onboarding hébergé : ouverte par `ExternalFlowPort`, puis statut relu (`force`).
    case lien(URL)
    /// Compte de test (`TEST_ACCOUNT_PAYMENT_DISABLED`) : texte web verbatim, aucun appel Stripe.
    case compteTest
    /// Soignant non libéral : message web verbatim.
    case nonEligible(message: String)
    case refuse(code: String?, message: String)
}

// MARK: - Flux hébergés (T14a)

/// Retour attendu d'un flux hébergé : Universal Link `https://<hote><chemin>` (rappel `.https`, iOS ≥ 17.4).
public struct RetourAttendu: Equatable, Sendable {
    public var hote: String
    public var chemin: String

    public init(hote: String, chemin: String) { self.hote = hote; self.chemin = chemin }

    /// `return_url` et `refresh_url` de `stripe-connect-onboard` (l.200-205).
    public static let stripeConnect = RetourAttendu(hote: "jolene.app", chemin: "/soignant/stripe-connect")
}

/// Issue d'un flux hébergé : jamais un succès, elle déclenche une relecture (§2.3).
public enum IssueFlux: Equatable, Sendable {
    case retour(URL)
    case ferme
}
