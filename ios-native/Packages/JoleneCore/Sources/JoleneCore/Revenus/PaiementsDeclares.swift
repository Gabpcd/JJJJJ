import Foundation

// Paiements déclarés (lot 3, T13, B9 ; HARD STOP n°4 délégué, TJ7 de `DECISIONS_LOT3.md`) : port du bandeau web
// `src/components/BandeauPaiementDeclare.tsx` (monté par l'aperçu de `/soignant/mes-gains`, `MesGains.tsx` l.382-384).
// Lecture (lignes `DECLARE` du soignant, mission, présences et créneaux de l.95-153), règle de relecture après
// `fn_confirmer_paiement_soignant` et `fn_contester_paiement_soignant` (contrat d'après B3, #1118), et présentation de la
// carte. Mêmes décodeurs et mêmes règles pour le monde Supabase et le monde démo. Aucun montant n'est calculé : chaque
// valeur affichée est celle du serveur ; le seul choix fait ici est celui du web (taux retenu : taux Rist plafonné s'il
// est appliqué, sinon taux de base, l.236-238).

// MARK: - Textes

/// Textes du bandeau, verbatim web (`// source: fichier:ligne`, garde `PaiementsDeclaresTests`) ; les deux textes
/// tutoyés, non juridiques, passent au vouvoiement (TJ7 ; décision 9 du lot 1). Aucun texte nouveau, aucun texte sur la
/// portée juridique d'une confirmation ou d'une contestation (TJ7).
public enum PaiementsDeclaresTextes {
    // source: src/components/BandeauPaiementDeclare.tsx:51
    public static let motifTitre = "Motif de contestation :"
    /// Adapté au vouvoiement (TJ7) de src/components/BandeauPaiementDeclare.tsx:55 (« Décris pourquoi tu contestes ce
    /// paiement... »).
    public static let motifPlaceholder = "Décrivez pourquoi vous contestez ce paiement..."
    // source: src/components/BandeauPaiementDeclare.tsx:62
    public static let envoyerContestation = "Envoyer la contestation"
    // source: src/components/BandeauPaiementDeclare.tsx:64
    public static let annuler = "Annuler"
    // source: src/components/BandeauPaiementDeclare.tsx:397
    public static let confirmerReception = "Confirmer la réception"
    // source: src/components/BandeauPaiementDeclare.tsx:407
    public static let contester = "Contester"
    // source: src/components/BandeauPaiementDeclare.tsx:195 (toast, ici encart après relecture du statut)
    public static let paiementConfirme = "Paiement confirmé ✅"
    // source: src/components/BandeauPaiementDeclare.tsx:195 (toast, ici encart après relecture du statut)
    public static let contestationEnvoyee = "Contestation envoyée"
    // source: src/components/BandeauPaiementDeclare.tsx:200 (repli quand le serveur n'a pas de message)
    public static let erreurTraitement = "Erreur lors du traitement"
    // source: src/components/BandeauPaiementDeclare.tsx:208
    public static let indisponibles = "Paiements à confirmer indisponibles"
    // source: src/components/BandeauPaiementDeclare.tsx:170
    public static let erreurChargement = "Impossible de charger les paiements à confirmer."
    // source: src/components/BandeauPaiementDeclare.tsx:211
    public static let reessayer = "Réessayer"
    // source: src/components/BandeauPaiementDeclare.tsx:161
    public static let etablissementDefaut = "Établissement"
    /// Adapté au vouvoiement (TJ7) de src/components/BandeauPaiementDeclare.tsx:259 (« déclare t'avoir payé »).
    public static let declareVousAvoirPaye = "déclare vous avoir payé"
    // source: src/components/BandeauPaiementDeclare.tsx:264
    public static let mission = "Mission :"
    // source: src/components/BandeauPaiementDeclare.tsx:268
    public static let indication = "Touchez pour voir le détail · Confirmez ou contestez"
    // source: src/components/BandeauPaiementDeclare.tsx:282
    public static let methode = "Méthode :"
    // source: src/components/BandeauPaiementDeclare.tsx:288
    public static let date = "Date :"
    // source: src/components/BandeauPaiementDeclare.tsx:295
    public static let reference = "Référence :"
    // source: src/components/BandeauPaiementDeclare.tsx:324
    public static let tauxRetenu = "Taux retenu :"
    // source: src/components/BandeauPaiementDeclare.tsx:326
    public static let demande = "demandé :"
    // source: src/components/BandeauPaiementDeclare.tsx:330
    public static let heuresRetenues = "Heures retenues après litige :"
    // source: src/components/BandeauPaiementDeclare.tsx:332
    public static let brut = "Brut :"
    // source: src/components/BandeauPaiementDeclare.tsx:333
    public static let montantDeclare = "Montant déclaré :"
    // source: src/components/BandeauPaiementDeclare.tsx:363 (et l.342, suivi du nombre de segments)
    public static let pointagesEnregistres = "Pointages enregistrés"
    // source: src/components/BandeauPaiementDeclare.tsx:352
    public static let pausePrecedente = "Pause précédente :"
    // source: src/components/BandeauPaiementDeclare.tsx:354
    public static let segment = "Segment"
    // source: src/components/BandeauPaiementDeclare.tsx:371
    public static let arrivee = "Arrivée :"
    // source: src/components/BandeauPaiementDeclare.tsx:374
    public static let depart = "Départ :"
    // source: src/components/BandeauPaiementDeclare.tsx:318
    public static let planifiees = "planifiées"
}

// MARK: - Lecture

/// Ligne `paiements_soignant` de la liste (colonnes de `BandeauPaiementDeclare.tsx` l.97) ou d'une relecture (mêmes
/// colonnes, plus `statut`, `confirme_par_soignant` et `conteste`). `montant_net` est `numeric NOT NULL` (CHECK > 0) :
/// un montant illisible est un décalage de contrat, jamais un zéro affiché.
public struct LignePaiementDeclare: Equatable, Sendable, Decodable {
    public var id: String
    public var montantNet: Double
    public var missionId: String
    public var etablissementId: String
    public var referenceVirement: String?
    public var methode: String?
    public var datePaiement: String?
    public var statut: String?
    public var confirmeParSoignant: Bool?
    public var conteste: Bool?

    public init(id: String, montantNet: Double, missionId: String, etablissementId: String, referenceVirement: String? = nil,
                methode: String? = nil, datePaiement: String? = nil, statut: String? = nil, confirmeParSoignant: Bool? = nil,
                conteste: Bool? = nil) {
        self.id = id; self.montantNet = montantNet; self.missionId = missionId; self.etablissementId = etablissementId
        self.referenceVirement = referenceVirement; self.methode = methode; self.datePaiement = datePaiement
        self.statut = statut; self.confirmeParSoignant = confirmeParSoignant; self.conteste = conteste
    }

    enum CodingKeys: String, CodingKey {
        case id, methode, statut, conteste
        case montantNet = "montant_net"
        case missionId = "mission_id"
        case etablissementId = "etablissement_id"
        case referenceVirement = "reference_virement"
        case datePaiement = "date_paiement"
        case confirmeParSoignant = "confirme_par_soignant"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texte(.id), !id.isEmpty, let montant = c.nombre(.montantNet),
              let mission = c.texte(.missionId), let etablissement = c.texte(.etablissementId) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "paiement déclaré incomplet"))
        }
        self.init(id: id, montantNet: montant, missionId: mission, etablissementId: etablissement,
                  referenceVirement: c.texte(.referenceVirement), methode: c.texte(.methode),
                  datePaiement: c.texte(.datePaiement), statut: c.texte(.statut),
                  confirmeParSoignant: c.booleen(.confirmeParSoignant), conteste: c.booleen(.conteste))
    }
}

extension MissionPaiementDeclare: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, intitule
        case debutLe = "debut_le"
        case finLe = "fin_le"
        case dureeHeures = "duree_heures"
        case tauxHoraireBase = "taux_horaire_base"
        case tauxRistPlafonne = "taux_rist_plafonne"
        case ristPlafondApplique = "rist_plafond_applique"
        case totalBrut = "total_brut"
        case netAPayer = "net_a_payer"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texte(.id), !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "mission sans id"))
        }
        self.init(id: id, intitule: c.texte(.intitule), debutLe: c.texte(.debutLe), finLe: c.texte(.finLe),
                  dureeHeures: c.nombre(.dureeHeures), tauxHoraireBase: c.nombre(.tauxHoraireBase),
                  tauxRistPlafonne: c.nombre(.tauxRistPlafonne), ristPlafondApplique: c.booleen(.ristPlafondApplique),
                  totalBrut: c.nombre(.totalBrut), netAPayer: c.nombre(.netAPayer))
    }
}

extension PresencePaiementDeclare: Decodable {
    enum CodingKeys: String, CodingKey {
        case missionId = "mission_id"
        case pointageArriveeLe = "pointage_arrivee_le"
        case pointageDepartLe = "pointage_depart_le"
        case methodePointageArrivee = "methode_pointage_arrivee"
        case heuresAjusteesLitige = "heures_ajustees_litige"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let mission = c.texte(.missionId) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "présence sans mission"))
        }
        self.init(missionId: mission, pointageArriveeLe: c.texte(.pointageArriveeLe), pointageDepartLe: c.texte(.pointageDepartLe),
                  methodePointageArrivee: c.texte(.methodePointageArrivee), heuresAjusteesLitige: c.nombre(.heuresAjusteesLitige))
    }
}

extension CreneauPaiementDeclare: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, debut, fin
        case missionId = "mission_id"
        case estPause = "est_pause"
        case typeCreneau = "type_creneau"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texte(.id), let mission = c.texte(.missionId), let debut = c.texte(.debut) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "créneau incomplet"))
        }
        self.init(id: id, missionId: mission, debut: debut, fin: c.texte(.fin), estPause: c.booleen(.estPause),
                  typeCreneau: c.texte(.typeCreneau))
    }
}

/// Assemblage du bandeau (`BandeauPaiementDeclare.tsx` l.107-168), partagé par les mondes Supabase et démo : ordre
/// serveur des lignes, nom d'établissement par `fn_etablissements_safe` seul (repli « Établissement », l.161), mission,
/// présences et créneaux de la mission dans l'ordre de leurs requêtes (`pointage_arrivee_le` puis `debut` croissants).
public enum PaiementsDeclaresAssemblage {
    /// Statut des lignes listées (`.eq('statut', 'DECLARE')`, l.99).
    public static let statutDeclare = "DECLARE"
    /// Statuts relus après une mutation réussie (`fn_confirmer_paiement_soignant` l.24581, `fn_contester_paiement_soignant`
    /// l.25796 du dump).
    public static let statutConfirme = "CONFIRME"
    public static let statutConteste = "CONTESTE"

    public static func assembler(_ lignes: [LignePaiementDeclare], etablissements: [String: String],
                                 missions: [MissionPaiementDeclare], presences: [PresencePaiementDeclare],
                                 creneaux: [CreneauPaiementDeclare]) -> [PaiementDeclare] {
        let parMission = Dictionary(missions.map { ($0.id, $0) }, uniquingKeysWith: { premiere, _ in premiere })
        return lignes.map { ligne in
            var paiement = paiement(ligne, statutParDefaut: statutDeclare)
            paiement.etablissementNom = etablissements[ligne.etablissementId]
            paiement.mission = parMission[ligne.missionId]
            paiement.presences = presences.filter { $0.missionId == ligne.missionId }
            paiement.creneaux = creneaux.filter { $0.missionId == ligne.missionId }
            return paiement
        }
    }

    /// Ligne relue (sans détail) ; `statutParDefaut` sert à la liste, filtrée sur `DECLARE` côté serveur.
    public static func paiement(_ ligne: LignePaiementDeclare, statutParDefaut: String = "") -> PaiementDeclare {
        PaiementDeclare(id: ligne.id, missionId: ligne.missionId, etablissementId: ligne.etablissementId,
                        montantNet: ligne.montantNet, methode: ligne.methode ?? "", referenceVirement: ligne.referenceVirement,
                        datePaiement: ligne.datePaiement, statut: ligne.statut ?? statutParDefaut,
                        confirmeParSoignant: ligne.confirmeParSoignant ?? false, conteste: ligne.conteste ?? false)
    }

    /// Identifiants dédoublonnés dans l'ordre de première apparition (`[...new Set(…)]`, l.108 et l.114).
    public static func identifiants(_ valeurs: [String]) -> [String] {
        var vus = Set<String>()
        return valeurs.filter { !$0.isEmpty && vus.insert($0).inserted }
    }
}

// MARK: - Relecture après mutation (PRINCIPES §3)

/// Règle unique des deux mondes : un succès annoncé par la RPC n'est un succès qu'après relecture de la ligne
/// (`CONFIRME` et `confirme_par_soignant`, ou `CONTESTE` et `conteste`). Sans relecture probante, l'issue est une erreur
/// (« Erreur lors du traitement », texte web l.200), jamais un succès. B3 écrit le paiement et le litige dans un même
/// sous-bloc (l.25791-25824 du dump) : une ligne relue `CONTESTE` prouve aussi le litige.
public enum PaiementsDeclaresRelecture {
    public static func confirmation(relue: PaiementDeclare?) throws -> IssuePaiement {
        guard let relue, relue.statut == PaiementsDeclaresAssemblage.statutConfirme, relue.confirmeParSoignant else {
            throw JoleneError(.unknown, PaiementsDeclaresTextes.erreurTraitement)
        }
        return .confirme(relue)
    }

    public static func contestation(relue: PaiementDeclare?, litigeId: String?) throws -> IssuePaiement {
        guard let relue, relue.statut == PaiementsDeclaresAssemblage.statutConteste, relue.conteste else {
            throw JoleneError(.unknown, PaiementsDeclaresTextes.erreurTraitement)
        }
        return .conteste(relue, litigeId: litigeId)
    }
}

// MARK: - Présentation

/// Carte d'un paiement déclaré, chaînes prêtes pour la vue (aucun calcul dans la vue).
public struct CartePaiementDeclare: Equatable, Sendable, Identifiable {
    public var id: String
    /// « 💰 {nom} déclare vous avoir payé {montant} » (l.259-260).
    public var titre: String
    public var nom: String
    public var montant: String
    /// « Mission : {intitulé} » (l.262-266), nil sans intitulé.
    public var mission: String?
    public var indication: String
    /// Méthode, date et référence (l.279-299) : libellé et valeur.
    public var infos: [InfoPaiementDeclare]
    /// Bloc mission (l.302-336), nil sans mission lue.
    public var blocMission: BlocMissionPaiementDeclare?
    /// Pointages (l.339-385), nil sans segment ni présence.
    public var pointages: BlocPointagesPaiementDeclare?
}

public struct InfoPaiementDeclare: Equatable, Sendable {
    /// Clé stable de l'information (`methode`, `date`, `reference`), pour les identifiants d'accessibilité.
    public var cle: String
    public var libelle: String
    public var valeur: String
}

public struct BlocMissionPaiementDeclare: Equatable, Sendable {
    public var intitule: String
    public var periode: String
    public var horaires: String
    public var taux: String
    public var heuresRetenues: String?
    public var brut: String?
    public var montantDeclare: String
}

public struct BlocPointagesPaiementDeclare: Equatable, Sendable {
    public var titre: String
    public var lignes: [String]
}

public enum PaiementsDeclaresPresentation {
    /// `fmt` du web (l.218-219) : `Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' })`, « — » sans valeur.
    public static func euros(_ valeur: Double?) -> String {
        guard let valeur, valeur.isFinite else { return "—" }
        return MissionPresentation.euros(valeur)
    }

    /// `formatMethode` (l.70-78) : libellés et emojis du web, valeur brute sinon, « — » sans méthode.
    public static func methode(_ methode: String) -> String {
        switch methode {
        case "": return "—"                                  // source: BandeauPaiementDeclare.tsx:71
        case "VIREMENT": return "🏦 Virement"                // source: BandeauPaiementDeclare.tsx:72
        case "CHEQUE": return "📝 Chèque"                    // source: BandeauPaiementDeclare.tsx:73
        case "NOTE_HONORAIRES": return "📄 Note d'honoraires" // source: BandeauPaiementDeclare.tsx:74
        case "STRIPE_CONNECT": return "💳 Stripe Connect"     // source: BandeauPaiementDeclare.tsx:75
        case "ESPECES": return "💵 Espèces"                   // source: BandeauPaiementDeclare.tsx:76
        default: return methode                               // source: BandeauPaiementDeclare.tsx:77
        }
    }

    public static func carte(_ p: PaiementDeclare) -> CartePaiementDeclare {
        typealias T = PaiementsDeclaresTextes
        let nom = nonVide(p.etablissementNom) ?? T.etablissementDefaut
        let montant = euros(p.montantNet)
        var infos = [InfoPaiementDeclare(cle: "methode", libelle: T.methode, valeur: methode(p.methode))]
        if let date = nonVide(p.datePaiement) {
            // `format(new Date(p.date_paiement), 'd MMM yyyy', { locale: fr })` : date seule lue à minuit UTC.
            infos.append(InfoPaiementDeclare(cle: "date", libelle: T.date, valeur: formater(date, "d MMM yyyy")))
        }
        if let reference = nonVide(p.referenceVirement) {
            infos.append(InfoPaiementDeclare(cle: "reference", libelle: T.reference, valeur: reference))
        }
        return CartePaiementDeclare(
            id: p.id, titre: "💰 \(nom) \(T.declareVousAvoirPaye) \(montant)", nom: nom, montant: montant,
            mission: nonVide(p.mission?.intitule).map { "\(T.mission) \($0)" }, indication: T.indication, infos: infos,
            blocMission: p.mission.map { blocMission($0, paiement: p) }, pointages: pointages(p))
    }

    // MARK: Interne

    /// Créneaux fermés hors pause d'un type (`creneauxPlanifies` / `creneauxEffectifs`, l.226-231), ordre de la requête.
    static func creneaux(_ p: PaiementDeclare, type: String) -> [CreneauPaiementDeclare] {
        p.creneaux.filter { $0.typeCreneau == type && $0.estPause != true && nonVide($0.fin) != nil }
    }

    static func blocMission(_ m: MissionPaiementDeclare, paiement p: PaiementDeclare) -> BlocMissionPaiementDeclare {
        typealias T = PaiementsDeclaresTextes
        let planifies = creneaux(p, type: "PREVISIONNEL")
        let periode: String
        if planifies.count > 1, let premier = planifies.first, let fin = planifies.last?.fin {
            periode = "\(formater(premier.debut, "d MMM yyyy")) → \(formater(fin, "d MMM yyyy"))"
        } else {
            periode = formater(m.debutLe, "EEE d MMM yyyy")
        }
        let horaires: String
        if planifies.isEmpty {
            horaires = "\(formater(m.debutLe, "HH'h'mm")) → \(formater(m.finLe, "HH'h'mm"))"
        } else {
            let minutes = planifies.reduce(0.0) { $0 + minutesEntre($1.debut, $1.fin) }
            horaires = "\(planifies.count) créneau\(planifies.count > 1 ? "x" : "") · "
                + "\(SynthesePresence.formatDureeMinutes(minutes)) \(T.planifiees)"
        }
        // Taux retenu : taux Rist plafonné s'il est appliqué et renseigné, sinon taux de base (l.236-238).
        let base = m.tauxHoraireBase ?? 0
        let retenu = m.ristPlafondApplique == true && m.tauxRistPlafonne != nil ? m.tauxRistPlafonne ?? base : base
        var taux = "\(T.tauxRetenu) \(euros(retenu))/h"
        if m.ristPlafondApplique == true, retenu != base {
            taux += " (\(T.demande) \(euros(base))/h)"
        }
        let heures = p.presences.first { $0.heuresAjusteesLitige != nil }?.heuresAjusteesLitige
        return BlocMissionPaiementDeclare(
            intitule: m.intitule ?? "", periode: periode, horaires: horaires, taux: taux,
            heuresRetenues: heures.map { "\(T.heuresRetenues) \(SynthesePresence.formatDureeMinutes($0 * 60))" },
            brut: m.totalBrut.map { "\(T.brut) \(euros($0))" }, montantDeclare: "\(T.montantDeclare) \(euros(p.montantNet))")
    }

    /// Segments effectifs (l.339-360), sinon présences (l.361-385), sinon rien.
    static func pointages(_ p: PaiementDeclare) -> BlocPointagesPaiementDeclare? {
        typealias T = PaiementsDeclaresTextes
        let effectifs = creneaux(p, type: "EFFECTIF")
        if !effectifs.isEmpty {
            var lignes: [String] = []
            for (index, creneau) in effectifs.enumerated() {
                if index > 0 {
                    let pause = max(0, SynthesePresence.arrondiJS(minutesSignees(effectifs[index - 1].fin, creneau.debut)))
                    if pause > 0 { lignes.append("\(T.pausePrecedente) \(SynthesePresence.formatDureeMinutes(pause))") }
                }
                let duree = SynthesePresence.formatDureeMinutes(minutesEntre(creneau.debut, creneau.fin))
                lignes.append("\(T.segment) \(index + 1) · \(formater(creneau.debut, "d MMM · HH'h'mm")) → "
                              + "\(formater(creneau.fin, "HH'h'mm")) · \(duree)")
            }
            let titre = "\(T.pointagesEnregistres) · \(effectifs.count) segment\(effectifs.count > 1 ? "s" : "")"
            return BlocPointagesPaiementDeclare(titre: titre, lignes: lignes)
        }
        guard !p.presences.isEmpty else { return nil }
        let lignes = p.presences.map { presence -> String in
            let jour = nonVide(presence.pointageArriveeLe).map { formater($0, "d MMM") } ?? "—"
            var ligne = "\(jour) · \(T.arrivee) \(nonVide(presence.pointageArriveeLe).map { formater($0, "HH'h'mm") } ?? "—")"
                + " · \(T.depart) \(nonVide(presence.pointageDepartLe).map { formater($0, "HH'h'mm") } ?? "—")"
            if let methode = nonVide(presence.methodePointageArrivee) {
                ligne += methode == "GPS" ? " · (📍 GPS)" : " · (🔢 Code)" // source: BandeauPaiementDeclare.tsx:378
            }
            return ligne
        }
        return BlocPointagesPaiementDeclare(titre: T.pointagesEnregistres, lignes: lignes)
    }

    /// `formatParis(valeur, masque)` ; « — » pour une valeur absente ou illisible (aucun « Invalid Date » affiché).
    static func formater(_ valeur: String?, _ masque: String) -> String {
        guard let valeur, let date = try? DateHeureParis.instantJolene(valeur) else { return "—" }
        return DateHeureParis.format(date, masque)
    }

    /// `Math.max(0, fin - début) / 60 000` (l.233, l.349) ; 0 si une borne manque ou est illisible.
    static func minutesEntre(_ debut: String, _ fin: String?) -> Double {
        max(0, minutesSignees(debut, fin))
    }

    private static func minutesSignees(_ debut: String?, _ fin: String?) -> Double {
        guard let debut, let fin, let d = try? DateHeureParis.instantJolene(debut),
              let f = try? DateHeureParis.instantJolene(fin) else { return 0 }
        return Double(DateHeureParis.millisecondes(f) - DateHeureParis.millisecondes(d)) / 60_000
    }

    private static func nonVide(_ texte: String?) -> String? {
        guard let texte, !texte.isEmpty else { return nil }
        return texte
    }
}

// MARK: - Décodage tolérant (interne)

private extension KeyedDecodingContainer {
    func texte(_ cle: Key) -> String? { (try? decodeIfPresent(String.self, forKey: cle)) ?? nil }

    func booleen(_ cle: Key) -> Bool? { (try? decodeIfPresent(Bool.self, forKey: cle)) ?? nil }

    /// `numeric` PostgREST : nombre JSON fini ou texte décimal ; nil sinon.
    func nombre(_ cle: Key) -> Double? {
        if let reel = (try? decodeIfPresent(Double.self, forKey: cle)) ?? nil, reel.isFinite { return reel }
        if let texte = (try? decodeIfPresent(String.self, forKey: cle)) ?? nil,
           let reel = Double(texte.trimmingCharacters(in: .whitespaces)), reel.isFinite { return reel }
        return nil
    }
}
