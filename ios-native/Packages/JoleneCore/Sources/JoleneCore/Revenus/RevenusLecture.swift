import Foundation

// Lecture des revenus (lot 3, T12, B9 ; blueprint `docs/mobile-swift/LOT3_PLAN.md` §2.4, D4, D5) : formes de réponse
// de `fn_mes_revenus_connect` et `fn_mes_paiements_escrow` (définitions live relues en lecture seule le 09/11/2026,
// identiques au dump `supabase/schema/public.sql` l.42233 et l.42396) et lignes PostgREST de `MesGains.tsx` (colonnes
// l.95 pour les missions, l.102 pour les déclarations). Mêmes décodeurs pour le monde Supabase et le monde démo. Aucun
// montant n'est calculé ici : chaque valeur est celle du serveur.

// MARK: - Totaux (`fn_mes_revenus_connect`)

extension TotauxRevenus {
    /// Contrôle du web (`PageStripeConnect.tsx` l.74-76) : `mois_en_cours`, `total` et `en_attente` sont des nombres JSON
    /// finis (jamais une chaîne ni un booléen), sinon `nil` (section « indisponible »). `stripe_connect_actif` n'est lu
    /// que s'il est booléen.
    public static func lire(_ corps: ValeurJSON) -> TotauxRevenus? {
        guard case .objet(let objet) = corps else { return nil }
        func nombre(_ cle: String) -> Double? {
            guard case .nombre(let valeur)? = objet[cle], valeur.isFinite else { return nil }
            return valeur
        }
        guard let mois = nombre("mois_en_cours"), let total = nombre("total"), let attente = nombre("en_attente") else { return nil }
        var actif: Bool?
        if case .booleen(let valeur)? = objet["stripe_connect_actif"] { actif = valeur }
        return TotauxRevenus(moisEnCours: mois, total: total, enAttente: attente, stripeConnectActif: actif)
    }

    /// Totaux à afficher, comme les cartes du web (`PageStripeConnect.tsx` l.367-417, revue B8 de T12, M1) : rendues
    /// seulement si `statut === 'COMPLET'` (l.367). Le natif ne lit pas l'edge `stripe-connect-status` (T14a) : il prend
    /// `stripe_connect_actif` de la même réponse (`fn_soignant_stripe_connect_actif` : ligne `stripe_connect_onboarding`
    /// COMPLET avec `onboarding_complete`, `charges_enabled` et `payouts_enabled`, celle que l'edge relit et réécrit).
    /// - `stripe_connect_actif = false` → `nil` (section absente), même sans les trois nombres : le web ne rend ni les
    ///   cartes ni « Tes revenus sont temporairement indisponibles » hors COMPLET ;
    /// - trois nombres finis absents → « indisponible » (l.387-391, `erreurRevenus` dans la branche COMPLET) ;
    /// - drapeau absent ou non booléen → `nil` : statut inconnu, aucune carte (le web les masque sur `erreurStatut`).
    public static func visibles(_ corps: ValeurJSON) throws -> TotauxRevenus? {
        if case .objet(let objet) = corps, case .booleen(false)? = objet["stripe_connect_actif"] { return nil }
        guard let totaux = lire(corps) else { throw JoleneError(.unknown, RevenusTextes.totauxIndisponibles) }
        return totaux.stripeConnectActif == true ? totaux : nil
    }
}

/// Exercice du soignant lu avant les totaux (`soignants.type_exercice, est_compte_test`, sous-ensemble des colonnes de
/// `PageStripeConnect.tsx` l.95). Sert uniquement à décider si la section des totaux existe ; jamais à afficher le
/// régime d'une ligne financière (règle Lot 14 de `CLAUDE.md` : `missions.type_contrat_applique`).
///
/// Revue B8 de T12, M1 : la condition de l.106 (`… || sg.statut_liberal === 'ACTIF'`) n'est que celle du CHARGEMENT ;
/// les cartes ne sont RENDUES que pour `isLiberal` (l.178, appliqué l.300 ; `statut_liberal` n'y entre pas) hors
/// compte de test (`!estCompteTest`, l.302 et l.367). `statut_liberal` n'est donc pas lu : un salarié
/// `statut_liberal = ACTIF` verrait sinon ses réceptions de salaire (`paiements_soignant` CONFIRME hors Connect,
/// additionnés par `fn_mes_revenus_connect`) présentées comme « Total réglé ».
public struct ExerciceRevenus: Equatable, Sendable, Decodable {
    public var typeExercice: String?
    /// `soignants.est_compte_test` (boolean NOT NULL) ; absent vaut faux, comme `!!sg.est_compte_test` (l.103).
    public var estCompteTest: Bool?

    public init(typeExercice: String?, estCompteTest: Bool?) {
        self.typeExercice = typeExercice; self.estCompteTest = estCompteTest
    }

    /// `isLiberal` du web : `typeExercice === 'LIBERAL' || typeExercice === 'MIXTE'` (l.178).
    public var estLiberal: Bool { typeExercice == "LIBERAL" || typeExercice == "MIXTE" }

    /// Totaux lus (et la RPC appelée) seulement pour un libéral hors compte de test (l.300, l.302, l.367).
    public var afficheTotaux: Bool { estLiberal && estCompteTest != true }

    enum CodingKeys: String, CodingKey {
        case typeExercice = "type_exercice"
        case estCompteTest = "est_compte_test"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        typeExercice = c.texteBrut(.typeExercice)
        estCompteTest = c.booleenBrut(.estCompteTest)
    }
}

// MARK: - Paiements rapides (`fn_mes_paiements_escrow`)

extension PaiementRapide {
    /// Tableau de la RPC, ordre serveur conservé (`ORDER BY` de l'état puis `mission_date DESC`). La RPC rend toujours
    /// un tableau (`COALESCE(jsonb_agg(…), '[]')`) : tout autre corps est un décalage de contrat, jamais une liste vide
    /// plausible. Une ligne sans `mission_id` n'a pas d'identifiant d'affichage et est ignorée ; `honoraires_cents`
    /// absent vaut 0 (`eur((cents ?? 0) / 100)` du web) ; l'état est conservé tel quel (présentation : sept états).
    public static func lireListe(_ corps: ValeurJSON) throws -> [PaiementRapide] {
        guard case .tableau(let elements) = corps else {
            throw JoleneError(.contract, RevenusLecture.contratMessage)
        }
        return elements.compactMap { element -> PaiementRapide? in
            guard case .objet(let o) = element, case .chaine(let missionId)? = o["mission_id"], !missionId.isEmpty else { return nil }
            func texte(_ cle: String) -> String? {
                if case .chaine(let valeur)? = o[cle] { return valeur }
                return nil
            }
            var cents = 0
            if case .nombre(let valeur)? = o["honoraires_cents"], valeur.isFinite, abs(valeur) < 9_007_199_254_740_992 {
                cents = Int(valeur.rounded())
            }
            var litige = false
            if case .booleen(let valeur)? = o["a_litige"] { litige = valeur }
            return PaiementRapide(missionId: missionId, missionIntitule: texte("mission_intitule"),
                                  etablissementNom: texte("etablissement_nom"), honorairesCents: cents, etat: texte("etat") ?? "",
                                  dateAffichee: texte("date_affichee"), missionDate: texte("mission_date"), aLitige: litige)
        }
    }
}

// MARK: - Missions terminées (`MesGains.tsx` l.95)

extension MissionTerminee: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, intitule, service, statut
        case debutLe = "debut_le"
        case finLe = "fin_le"
        case etablissementId = "etablissement_id"
        case typeContratApplique = "type_contrat_applique"
        case typeContratRecherche = "type_contrat_recherche"
        case netAPayer = "net_a_payer"
        case netEstime = "net_estime"
        case totalBrut = "total_brut"
        case dureeHeures = "duree_heures"
        case tauxHoraireBase = "taux_horaire_base"
    }

    /// Ligne PostgREST des colonnes de `MesGains.tsx` l.95. Seules ces colonnes sont lues : une colonne Rist présente dans
    /// la ligne (fixture démo complète) est ignorée, si bien que la correction de l'ancien plafond reste inactive comme
    /// sur le web (décision 5, correction 19). `numeric` accepté en nombre JSON ou en texte décimal ; `id` exigé.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texteBrut(.id), !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "mission sans id"))
        }
        self.init(id: id, intitule: c.texteBrut(.intitule), debutLe: c.texteBrut(.debutLe), finLe: c.texteBrut(.finLe),
                  etablissementId: c.texteBrut(.etablissementId), typeContratApplique: c.texteBrut(.typeContratApplique),
                  typeContratRecherche: c.texteBrut(.typeContratRecherche), netAPayer: c.nombreSQL(.netAPayer),
                  netEstime: c.nombreSQL(.netEstime), totalBrut: c.nombreSQL(.totalBrut), dureeHeures: c.nombreSQL(.dureeHeures),
                  tauxHoraireBase: c.nombreSQL(.tauxHoraireBase), service: c.texteBrut(.service), statut: c.texteBrut(.statut))
    }
}

extension MissionTerminee {
    /// Colonnes financières passées à `MontantMission` (`montantFinanceAfficheMission(m)` du web, sur la ligne lue) :
    /// les colonnes Rist, `soignant_assigne_id` et `profession_requise` ne sont pas lues (D5) et restent nulles.
    public var finance: MissionFinanceAffichee {
        MissionFinanceAffichee(typeContratRecherche: typeContratRecherche, typeContratApplique: typeContratApplique,
                               tauxHoraireBase: tauxHoraireBase, netEstime: netEstime, netAPayer: netAPayer, totalBrut: totalBrut)
    }

    /// `regimeMission` du web (`MesGains.tsx` l.56-59) : `type_contrat_applique ?? type_contrat_recherche`, seulement
    /// `SALARIE` ou `LIBERAL`. Jamais `soignants.type_exercice` (règle Lot 14 de `CLAUDE.md`, garde `test:guards` 7).
    public var regime: String? {
        let regime = typeContratApplique ?? typeContratRecherche
        return regime == "SALARIE" || regime == "LIBERAL" ? regime : nil
    }
}

// MARK: - Déclarations de paiement (`MesGains.tsx` l.102)

/// Ligne `paiements_soignant` lue sous RLS (`pol_paie_soig_select` : soignant de la ligne), colonnes de `MesGains.tsx`
/// l.102. Seule la dernière déclaration d'une mission compte (`EtatPaiement.indexerDernierPaiementParMission`) ; son
/// état est celui de `classerPaiementSalaire` (golden T2), jamais un total de virements. Lecture seule : la
/// confirmation et la contestation sont T13.
public struct PaiementSoignantLu: PaiementHorodate, Equatable, Sendable, Decodable {
    public var id: String
    public var missionId: String?
    public var factureHonoraireId: String?
    public var statut: String?
    public var montantNet: ValeurJSON?
    public var confirmeParSoignant: Bool?
    public var conteste: Bool?
    public var montantDuReference: ValeurJSON?
    public var sourceMontantDu: String?
    public var methode: String?
    public var referenceVirement: String?
    public var datePaiement: String?
    public var modifieLe: String?
    public var creeLe: String?

    public init(id: String, missionId: String? = nil, factureHonoraireId: String? = nil, statut: String? = nil,
                montantNet: ValeurJSON? = nil, confirmeParSoignant: Bool? = nil, conteste: Bool? = nil,
                montantDuReference: ValeurJSON? = nil, sourceMontantDu: String? = nil, methode: String? = nil,
                referenceVirement: String? = nil, datePaiement: String? = nil, modifieLe: String? = nil, creeLe: String? = nil) {
        self.id = id; self.missionId = missionId; self.factureHonoraireId = factureHonoraireId; self.statut = statut
        self.montantNet = montantNet; self.confirmeParSoignant = confirmeParSoignant; self.conteste = conteste
        self.montantDuReference = montantDuReference; self.sourceMontantDu = sourceMontantDu; self.methode = methode
        self.referenceVirement = referenceVirement; self.datePaiement = datePaiement; self.modifieLe = modifieLe
        self.creeLe = creeLe
    }

    /// Valeurs lues par `classerPaiementSalaire` (montants en valeur JSON brute, comme le `unknown` du web).
    public var salaire: PaiementSalairePourUi {
        PaiementSalairePourUi(statut: statut, montantNet: montantNet, confirmeParSoignant: confirmeParSoignant, conteste: conteste,
                              montantDuReference: montantDuReference, sourceMontantDu: sourceMontantDu)
    }

    enum CodingKeys: String, CodingKey {
        case id, statut, conteste, methode
        case missionId = "mission_id"
        case factureHonoraireId = "facture_honoraire_id"
        case montantNet = "montant_net"
        case confirmeParSoignant = "confirme_par_soignant"
        case montantDuReference = "montant_du_reference"
        case sourceMontantDu = "source_montant_du"
        case referenceVirement = "reference_virement"
        case datePaiement = "date_paiement"
        case modifieLe = "modifie_le"
        case creeLe = "cree_le"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texteBrut(.id), !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "paiement sans id"))
        }
        self.init(id: id, missionId: c.texteBrut(.missionId), factureHonoraireId: c.texteBrut(.factureHonoraireId),
                  statut: c.texteBrut(.statut), montantNet: c.valeurNonNulle(.montantNet),
                  confirmeParSoignant: c.booleenBrut(.confirmeParSoignant), conteste: c.booleenBrut(.conteste),
                  montantDuReference: c.valeurNonNulle(.montantDuReference), sourceMontantDu: c.texteBrut(.sourceMontantDu),
                  methode: c.texteBrut(.methode), referenceVirement: c.texteBrut(.referenceVirement),
                  datePaiement: c.texteBrut(.datePaiement), modifieLe: c.texteBrut(.modifieLe), creeLe: c.texteBrut(.creeLe))
    }
}

// MARK: - Assemblage d'une page

/// Assemblage d'une page de l'aperçu (`MesGainsApercuContent`) : missions dans l'ordre serveur, nom d'établissement
/// (`fn_etablissements_safe`, seule source, aucun nom deviné) et dernière déclaration de chaque mission. Partagé par le
/// monde Supabase et le monde démo.
public enum RevenusAssemblage {
    /// `PAGE_SIZE` de `MesGains.tsx` l.72.
    public static let taillePage = 50

    public static func page(_ missions: [MissionTerminee], paiements: [PaiementSoignantLu], etablissements: [String: String],
                            page: Int) -> PageMissionsTerminees {
        let derniers = EtatPaiement.indexerDernierPaiementParMission(paiements)
        let assemblees = missions.map { mission -> MissionTerminee in
            var complete = mission
            complete.etablissementNom = mission.etablissementId.flatMap { etablissements[$0] }
            complete.dernierPaiement = derniers[mission.id]
            return complete
        }
        // `setHasMore(pageMissions.length === PAGE_SIZE)` ; index complet des déclarations relues (revue B8 n°2, m2).
        return PageMissionsTerminees(missions: assemblees, page: page, aSuivre: missions.count == taillePage,
                                     derniersPaiements: derniers)
    }
}

/// Messages internes de la lecture (aucun n'est un texte d'écran).
enum RevenusLecture {
    /// Décalage de contrat : même message que `SupabaseErrorMapping.contractMessage` (lot 0).
    static let contratMessage = "Cette version de l'application n'est plus compatible avec le service. Mettez-la à jour."
}

// MARK: - Décodage tolérant (interne)

private extension KeyedDecodingContainer {
    /// Texte tel quel (le web affiche et compare la valeur brute) ; nil si absent, nul ou d'un autre type.
    func texteBrut(_ cle: Key) -> String? { (try? decodeIfPresent(String.self, forKey: cle)) ?? nil }

    func booleenBrut(_ cle: Key) -> Bool? { (try? decodeIfPresent(Bool.self, forKey: cle)) ?? nil }

    /// `numeric` PostgREST : nombre JSON fini ou texte décimal ; nil sinon.
    func nombreSQL(_ cle: Key) -> Double? {
        if let reel = (try? decodeIfPresent(Double.self, forKey: cle)) ?? nil, reel.isFinite { return reel }
        if let texte = (try? decodeIfPresent(String.self, forKey: cle)) ?? nil,
           let reel = Double(texte.trimmingCharacters(in: .whitespaces)), reel.isFinite { return reel }
        return nil
    }

    /// Valeur JSON brute (montants `unknown` du web) ; nil pour une clé absente ou nulle.
    func valeurNonNulle(_ cle: Key) -> ValeurJSON? {
        guard let valeur = (try? decodeIfPresent(ValeurJSON.self, forKey: cle)) ?? nil, valeur != .null else { return nil }
        return valeur
    }
}
