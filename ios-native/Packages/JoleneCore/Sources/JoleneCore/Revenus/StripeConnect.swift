import Foundation

// Stripe Connect (lot 3, T14a, B9 ; blueprint `docs/mobile-swift/LOT3_PLAN.md` §3 T14a, D6, D7, corrections 1, 6 et 17) :
// exercice lu avant tout appel d'edge, règle de lecture de `stripe-connect-status`, textes de `/soignant/stripe-connect`.
// Mêmes règles pour le monde Supabase et le monde démo. Aucun état Connect n'est déduit côté client : il vient du
// serveur (`stripe-connect-status`), relu après chaque issue du flux hébergé, jamais supposé.

// MARK: - Exercice (`soignants`)

/// `soignants.type_exercice, statut_liberal, est_compte_test` (colonnes de `PageStripeConnect.tsx` l.95, sans prénom ni
/// nom), lus **avant** tout appel d'edge (l.94-111) : un salarié ou un compte de test ne déclenche aucun appel Stripe.
/// Sert seulement à choisir l'écran ; jamais à afficher le régime d'une ligne financière (règle Lot 14 de `CLAUDE.md`).
public struct ExerciceConnect: Equatable, Sendable, Decodable {
    public var typeExercice: String?
    public var statutLiberal: String?
    /// `soignants.est_compte_test` (boolean NOT NULL) ; absent vaut faux, comme `!!sg.est_compte_test` (l.103).
    public var estCompteTest: Bool?

    public init(typeExercice: String?, statutLiberal: String? = nil, estCompteTest: Bool? = false) {
        self.typeExercice = typeExercice; self.statutLiberal = statutLiberal; self.estCompteTest = estCompteTest
    }

    /// `isLiberal` du web (l.178, après `type_exercice || 'SALARIE'`, l.101) : la section Stripe n'est rendue que pour
    /// `LIBERAL` ou `MIXTE` ; `statut_liberal` n'y entre pas (il ne conditionne que le chargement, l.106).
    public var estLiberal: Bool { typeExercice == "LIBERAL" || typeExercice == "MIXTE" }

    public var compteTest: Bool { estCompteTest == true }

    /// Entrée « Compte de paiement (Stripe) » du hub web (`estLiberal`, `MonCompteSoignant.tsx` l.45-48, l.68) :
    /// `statut_liberal = 'ACTIF'` compris (l'écran montre alors le mode salarié, comme le web).
    public var entreeHub: Bool { estLiberal || statutLiberal == "ACTIF" }

    enum CodingKeys: String, CodingKey {
        case typeExercice = "type_exercice"
        case statutLiberal = "statut_liberal"
        case estCompteTest = "est_compte_test"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Valeur d'un autre type que celle attendue → nil, jamais un échec de décodage de toute la ligne.
        typeExercice = (try? c.decodeIfPresent(String.self, forKey: .typeExercice)) ?? nil
        statutLiberal = (try? c.decodeIfPresent(String.self, forKey: .statutLiberal)) ?? nil
        estCompteTest = (try? c.decodeIfPresent(Bool.self, forKey: .estCompteTest)) ?? nil
    }
}

// MARK: - Statut (`stripe-connect-status`)

extension StatutConnect {
    /// Corps 200 de `stripe-connect-status`, contrôlé comme le web (`PageStripeConnect.tsx` l.53-60) : `statut` parmi les
    /// six valeurs de `stripe_connect_onboarding_statut_check` ; `COMPLET` admis seulement si `onboarding_complete`,
    /// `charges_enabled` et `payouts_enabled` valent `true` (booléens JSON) ; sinon nil, « Statut de paiement
    /// indisponible » (l.55, l.65), jamais un défaut. Écart au blueprint (§3 T14a : « `COMPLET` sans les trois drapeaux →
    /// `EN_COURS` ») : le web live lève une erreur, le natif le suit. Motif affiché pour `REJETE` (l.60) :
    /// `disabled_reason`, sinon la première exigence (`requirements[0]`) ; `iban_last4` vide → nil (`|| null`, l.58).
    public static func lire(statut: String?, onboardingComplete: Bool?, chargesEnabled: Bool?, payoutsEnabled: Bool?,
                            ibanLast4: String? = nil, disabledReason: String? = nil, premiereExigence: String? = nil,
                            message: String? = nil) -> StatutConnect? {
        guard let brut = statut, let valeur = StatutOnboardingConnect(rawValue: brut) else { return nil }
        let complet = onboardingComplete == true && chargesEnabled == true && payoutsEnabled == true
        if valeur == .complet, !complet { return nil }
        func nonVide(_ texte: String?) -> String? {
            guard let texte, !texte.isEmpty else { return nil }
            return texte
        }
        return StatutConnect(statut: valeur, onboardingComplete: onboardingComplete == true,
                             chargesEnabled: chargesEnabled == true, payoutsEnabled: payoutsEnabled == true,
                             ibanLast4: nonVide(ibanLast4), disabledReason: nonVide(disabledReason) ?? nonVide(premiereExigence),
                             message: nonVide(message))
    }
}

// MARK: - Textes de `/soignant/stripe-connect`

/// Textes de l'écran (HARD STOP n°4, TJ8 ; `DECISIONS_LOT3.md`, « T14a-J1 »). Règle **par carte** : une carte qui porte un
/// texte à portée contractuelle (qui verse, quand, quels frais, droit de recevoir des paiements, mode d'exercice) est
/// reprise **verbatim**, tutoiement compris, en entier ; les autres textes (en-tête, chargement en échec, étapes de
/// l'inscription Stripe, raccourcis) passent au vouvoiement (décision 9 du lot 1). Chaque texte verbatim est épinglé à
/// sa ligne web par `StripeConnectTests.testTextesVerbatimASaLigneWeb`.
public enum StripeConnectTextes {
    // En-tête et chargement (non juridiques, vouvoyés).
    public static let titre = "Paiements"                                                       // source: l.185
    public static let sousTitre = "Gérez la réception de vos paiements"                         // vouvoyé de l.187
    public static let profilIndisponible = "Profil de paiement indisponible"                    // source: l.171
    public static let profilIndisponibleDetail =
        "Votre mode d’exercice ne peut pas être vérifié pour le moment. Réessayez dans quelques instants." // vouvoyé de l.172
    public static let reessayer = "Réessayer"                                                   // source: l.173, l.320
    public static let statutIndisponible = "Statut de paiement indisponible"                    // source: l.317
    public static let statutIndisponibleDetail =
        "Le statut de votre compte de paiement ne peut pas être vérifié pour le moment. Réessayez dans quelques instants." // vouvoyé de l.65

    // Mode salarié (verbatim : qui verse le salaire, rôle du bulletin, restriction du mode d'exercice).
    public static let salarieTitre = "Mode salarié"                                             // source: l.208
    public static let salarieTexte = "En tant que salarié(e), ton salaire est versé directement par l'établissement employeur. Le bulletin de paie détaille le montant dû ; il ne prouve pas que le virement a été reçu." // source: l.210
    public static let salarieEtapesTitre = "Comment ça fonctionne :"                            // source: l.216
    public static let salarieEtapes = [
        "Tu effectues ta mission et pointes tes présences",                                     // source: l.220
        "L'établissement valide tes heures et déclare le paiement",                             // source: l.224
        "Tu confirmes la réception dans Mes gains",                                             // source: l.228
        "Le bulletin de paie est généré par l'établissement",                                   // source: l.232
    ]
    public static let salarieInfoTitre = "Paiement direct via Stripe Connect"                   // source: l.289
    public static let salarieInfoTexte = "Les soignants en exercice libéral peuvent recevoir leurs honoraires directement sur leur compte bancaire via Stripe Connect. Passe en libéral pour débloquer cette fonctionnalité." // source: l.291-292

    // Compte de test (verbatim, sans tutoiement).
    public static let compteTestTitre = "Stripe désactivé sur ce compte de test"                // source: l.307
    public static let compteTestTexte = "Aucun compte bancaire ni paiement réel ne sera créé depuis les données de démonstration. Le parcours Stripe se vérifie en environnement de recette avec Stripe en mode test." // source: l.309

    // NON_DEMANDE (verbatim : cycle de règlement, sécurité, frais).
    public static let nonDemandeTitre = "Reçois tes honoraires directement"                     // source: l.328
    public static let nonDemandeTexte = "Connecte ton compte bancaire via Stripe pour recevoir les règlements de tes missions selon le cycle indiqué sur chacune d'elles." // source: l.330
    public static let nonDemandeAvantages = [
        "Virements automatiques pour les périodes facturées",                                   // source: l.333
        "Sécurisé par Stripe (certifié PCI DSS)",                                               // source: l.334
        "Aucun frais pour le soignant",                                                         // source: l.335
    ]
    public static let connecter = "Connecter mon compte bancaire"                               // source: l.339

    // EN_COURS (étape de l'inscription Stripe, vouvoyée).
    public static let enCoursTitre = "Inscription en cours"                                     // source: l.350
    public static let enCoursTexte = "Complétez votre profil Stripe pour activer les paiements directs. C'est rapide et sécurisé." // vouvoyé de l.352
    public static let reprendreInscription = "Reprendre l'inscription Stripe"                   // source: l.358
    public static let actualiserStatut = "Actualiser le statut"                                 // source: l.361

    // COMPLET.
    public static let completTitre = "Compte connecté"                                          // source: l.374
    public static func iban(_ last4: String) -> String { "IBAN ****\(last4)" }                  // source: l.376
    public static let actualiser = "Actualiser"                                                 // source: l.382

    // SUSPENDU (étape de l'inscription Stripe, vouvoyée).
    public static let suspenduTitre = "Compte suspendu"                                         // source: l.448
    public static let suspenduTexte = "Des informations sont requises pour réactiver votre compte. Complétez votre profil Stripe ci-dessous." // vouvoyé de l.450
    public static let completerProfil = "Compléter mon profil Stripe"                           // source: l.455

    // SUPPRIME (verbatim : droit de recevoir des paiements Connect).
    public static let supprimeTitre = "Compte Stripe supprimé"                                  // source: l.466
    public static let supprimeTexte = "Ton compte Stripe Connect a été supprimé (clôture manuelle, fraude détectée par Stripe, ou décision admin plateforme). Tu ne peux plus recevoir de paiements Connect jusqu'à la création d'un nouveau compte." // source: l.468-470
    public static let recommencer = "Recommencer l'onboarding"                                  // source: l.476

    // REJETE (étape de la vérification Stripe, vouvoyée ; « Contacter le support » non porté : modale web sans équivalent).
    public static let rejeteTitre = "Compte non validé"                                         // source: l.497
    public static let rejeteTexte = "Stripe n'a pas pu valider votre compte de paiement. Vous pouvez reprendre votre vérification pour corriger les informations manquantes ou erronées, ou contacter le support si le problème persiste." // vouvoyé de l.499-501
    public static func motif(_ motif: String) -> String { "Motif : \(motif)" }                  // source: l.504
    public static let reprendreVerification = "Reprendre ma vérification"                       // source: l.510

    // Avis (toasts du web).
    public static let avisCompteTest = "Compte de test : Stripe réel est désactivé pour éviter tout paiement réel." // source: l.125, l.138
    public static let avisNonLiberal = "Stripe Connect est disponible pour les soignants en exercice libéral." // source: l.129
    public static let avisPasserEnLiberal = "Passez en exercice libéral pour activer Stripe Connect."           // source: l.143
    public static let erreurConnexionStripe = "Erreur lors de la connexion à Stripe. Veuillez réessayer."       // source: l.146

    // Raccourcis (titres verbatim, sous-titres vouvoyés ; liens de l.240-283 et l.422-437).
    public static let lienMesGains = "Mes gains"                                                // source: l.246, l.425
    public static let lienMesGainsSalarie = "Voir le détail de vos revenus"                     // vouvoyé de l.247
    public static let lienMesGainsLiberal = "Détail des revenus"                                // source: l.426
    public static let lienPresences = "Mes présences"                                           // source: l.257
    public static let lienPresencesDetail = "Pointages et validations"                          // source: l.258
    public static let lienContrats = "Mes contrats"                                             // source: l.268
    public static let lienContratsDetail = "CDD et contrats de mission"                         // source: l.269
    public static let lienPasserEnLiberal = "Passer en libéral"                                 // source: l.279
    public static let lienPasserEnLiberalDetail = "Recevez vos paiements directement"           // vouvoyé de l.280
    public static let lienCharges = "Mes charges"                                               // source: l.433
    public static let lienChargesDetail = "Cotisations sociales et obligations fiscales"        // source: l.434

    /// Entrée du hub (`MonCompteSoignant.tsx` l.68) et titre de sa section (l.65).
    public static let entreeHub = "Compte de paiement (Stripe)"
    public static let sectionHub = "Paiements & facturation"
}

/// Raccourci de l'écran : un lien interne du web, présenté par la cible de l'espace (`DestinationLien` puis
/// `CibleNotification`) — écran natif s'il est livré, renvoi web sinon.
public struct RaccourciConnect: Equatable, Sendable, Identifiable {
    public var id: String { identifiant }
    public let titre: String
    public let detail: String
    public let lien: String
    public let identifiant: String

    /// Raccourcis du mode salarié (`PageStripeConnect.tsx` l.240-283).
    public static let salarie = [
        RaccourciConnect(titre: StripeConnectTextes.lienMesGains, detail: StripeConnectTextes.lienMesGainsSalarie,
                         lien: "/soignant/mes-gains", identifiant: "stripe-lien-mes-gains"),
        RaccourciConnect(titre: StripeConnectTextes.lienPresences, detail: StripeConnectTextes.lienPresencesDetail,
                         lien: "/soignant/presences", identifiant: "stripe-lien-presences"),
        RaccourciConnect(titre: StripeConnectTextes.lienContrats, detail: StripeConnectTextes.lienContratsDetail,
                         lien: "/soignant/contrats", identifiant: "stripe-lien-contrats"),
        RaccourciConnect(titre: StripeConnectTextes.lienPasserEnLiberal, detail: StripeConnectTextes.lienPasserEnLiberalDetail,
                         lien: "/soignant/passer-en-liberal", identifiant: "stripe-lien-passer-en-liberal"),
    ]

    /// Raccourcis d'un compte connecté (l.421-437).
    public static let complet = [
        RaccourciConnect(titre: StripeConnectTextes.lienMesGains, detail: StripeConnectTextes.lienMesGainsLiberal,
                         lien: "/soignant/mes-gains", identifiant: "stripe-lien-mes-gains"),
        RaccourciConnect(titre: StripeConnectTextes.lienCharges, detail: StripeConnectTextes.lienChargesDetail,
                         lien: "/soignant/charges", identifiant: "stripe-lien-charges"),
    ]
}
