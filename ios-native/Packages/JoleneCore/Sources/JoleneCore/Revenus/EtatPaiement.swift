import Foundation

/// Répartition d'un règlement confirmé (`RepartitionPaiementConfirme`).
public struct RepartitionPaiementConfirme: Equatable, Sendable {
    public var montantPaye: Double
    public var montantRestant: Double
    public var estPartiel: Bool

    public init(montantPaye: Double, montantRestant: Double, estPartiel: Bool) {
        self.montantPaye = montantPaye; self.montantRestant = montantRestant; self.estPartiel = estPartiel
    }
}

/// Ligne de paiement horodatée, indexable par mission (`PaiementSoignantPourUi`).
public protocol PaiementHorodate {
    var id: String { get }
    var missionId: String? { get }
    var datePaiement: String? { get }
    var modifieLe: String? { get }
    var creeLe: String? { get }
}

/// `PaiementSoignantPourUi` : colonnes `paiements_soignant` lues pour l'indexation, clés PostgREST.
public struct PaiementSoignantPourUi: PaiementHorodate, Equatable, Sendable, Decodable {
    public var id: String
    public var missionId: String?
    public var datePaiement: String?
    public var modifieLe: String?
    public var creeLe: String?

    public init(id: String, missionId: String? = nil, datePaiement: String? = nil, modifieLe: String? = nil, creeLe: String? = nil) {
        self.id = id; self.missionId = missionId; self.datePaiement = datePaiement
        self.modifieLe = modifieLe; self.creeLe = creeLe
    }

    enum CodingKeys: String, CodingKey {
        case id
        case missionId = "mission_id"
        case datePaiement = "date_paiement"
        case modifieLe = "modifie_le"
        case creeLe = "cree_le"
    }
}

/// `PaiementSalairePourUi` : dernière déclaration d'un versement salarial. Les montants sont
/// `unknown` côté web (nombre ou texte décimal PostgREST) : valeur JSON brute.
public struct PaiementSalairePourUi: Equatable, Sendable, Decodable {
    public var statut: String?
    public var montantNet: ValeurJSON?
    public var confirmeParSoignant: Bool?
    public var conteste: Bool?
    public var montantDuReference: ValeurJSON?
    public var sourceMontantDu: String?

    public init(statut: String? = nil, montantNet: ValeurJSON? = nil, confirmeParSoignant: Bool? = nil, conteste: Bool? = nil,
                montantDuReference: ValeurJSON? = nil, sourceMontantDu: String? = nil) {
        self.statut = statut; self.montantNet = montantNet; self.confirmeParSoignant = confirmeParSoignant
        self.conteste = conteste; self.montantDuReference = montantDuReference; self.sourceMontantDu = sourceMontantDu
    }

    enum CodingKeys: String, CodingKey {
        case statut
        case montantNet = "montant_net"
        case confirmeParSoignant = "confirme_par_soignant"
        case conteste
        case montantDuReference = "montant_du_reference"
        case sourceMontantDu = "source_montant_du"
    }
}

/// État d'une déclaration (`EtatPaiementSalaire['etat']`).
public enum EtatPaiementSalaireCode: String, CaseIterable, Sendable {
    case absent, declare, confirme, conteste, resolu
    case aVerifier = "a_verifier"
}

/// `EtatPaiementSalaire` : état, libellé verbatim et montants déclarés (jamais un solde déduit).
public struct EtatPaiementSalaire: Equatable, Sendable {
    public var etat: EtatPaiementSalaireCode
    public var libelle: String
    public var montantDeclare: Double?
    public var montantReferenceEmployeur: Double?

    public init(etat: EtatPaiementSalaireCode, libelle: String, montantDeclare: Double?, montantReferenceEmployeur: Double?) {
        self.etat = etat; self.libelle = libelle
        self.montantDeclare = montantDeclare; self.montantReferenceEmployeur = montantReferenceEmployeur
    }
}

/// Port de `src/lib/paiementSoignantUi.ts` : état d'un paiement déclaré à partir de la seule dernière
/// déclaration de chaque mission (état dérivé, jamais un total de virements).
public enum EtatPaiement {
    /// `repartirPaiementConfirme` : un règlement partiel reste visible dans « Payé » et dans
    /// « En attente ». `Number()` sur chaque valeur, négatif ramené à 0, centimes de `toFixed(2)`.
    public static func repartirPaiementConfirme(montantDu: ValeurJSON?, montantRegle: ValeurJSON?) -> RepartitionPaiementConfirme {
        let du = positifOuZero(PrimitivesJS.nombre(montantDu))
        let paye = positifOuZero(PrimitivesJS.nombre(montantRegle))
        let restant = max0(PrimitivesJS.arrondiCentimes(du - paye))
        return RepartitionPaiementConfirme(montantPaye: PrimitivesJS.arrondiCentimes(paye), montantRestant: restant,
                                           estPartiel: paye > 0 && restant > 0)
    }

    /// `indexerDernierPaiementParMission` : dernier état par mission selon `modifie_le ?? cree_le ??
    /// date_paiement` (texte vide ou date illisible = instant 0), égalité départagée par identifiant.
    /// L'ordre de réception n'est jamais utilisé. Identifiants : uuid (minuscules ASCII, chiffres,
    /// tirets), domaine où `localeCompare` suit l'ordre des points de code.
    public static func indexerDernierPaiementParMission<P: PaiementHorodate>(_ paiements: [P]) -> [String: P] {
        var resultat: [String: P] = [:]
        for paiement in paiements {
            guard let missionId = paiement.missionId, !missionId.isEmpty else { continue }
            guard let courant = resultat[missionId] else {
                resultat[missionId] = paiement
                continue
            }
            let instant = instantPaiement(paiement), instantCourant = instantPaiement(courant)
            if instant > instantCourant || (instant == instantCourant && paiement.id > courant.id) {
                resultat[missionId] = paiement
            }
        }
        return resultat
    }

    /// `classerPaiementSalaire` : la contestation prime sur une ancienne confirmation, une résolution
    /// de litige ne vaut pas réception, la confirmation exige l'accord explicite du soignant et un
    /// montant déclaré. Libellés verbatim de `paiementSoignantUi.ts` l.103-114.
    public static func classerPaiementSalaire(_ paiement: PaiementSalairePourUi?) -> EtatPaiementSalaire {
        let montantDeclare = montantPositifFini(paiement?.montantNet)
        // Source déclarée par l'employeur : ce n'est pas une vérification du bulletin.
        let reference = paiement?.sourceMontantDu == "BULLETIN_OFFICIEL_ETABLISSEMENT"
            ? montantPositifFini(paiement?.montantDuReference) : nil
        func etat(_ code: EtatPaiementSalaireCode, _ libelle: String) -> EtatPaiementSalaire {
            EtatPaiementSalaire(etat: code, libelle: libelle, montantDeclare: montantDeclare, montantReferenceEmployeur: reference)
        }
        guard let paiement else { return etat(.absent, "Aucun versement déclaré") }
        if paiement.conteste == true || paiement.statut == "CONTESTE" { return etat(.conteste, "Paiement contesté") }
        if paiement.statut == "RESOLU" { return etat(.resolu, "Litige résolu · réception à vérifier") }
        if paiement.statut == "CONFIRME", paiement.confirmeParSoignant == true, montantDeclare != nil {
            return etat(.confirme, "Réception confirmée")
        }
        if paiement.statut == "DECLARE" { return etat(.declare, "Réception à confirmer") }
        return etat(.aVerifier, "Réception à vérifier")
    }

    // MARK: - Outils

    /// `instantPaiement` : `new Date(valeur).getTime()` sur les formats ISO PostgREST (date seule en UTC,
    /// offset ou Z, ISO sans offset en heure de Paris hors changement d'heure), 0 sinon.
    static func instantPaiement<P: PaiementHorodate>(_ paiement: P) -> Double {
        // `??` JavaScript : seul `null` cède la place, un texte vide vaut instant 0.
        guard let valeur = paiement.modifieLe ?? paiement.creeLe ?? paiement.datePaiement, !valeur.isEmpty,
              let date = try? DateHeureParis.instantJolene(valeur) else { return 0 }
        return Double(DateHeureParis.millisecondes(date))
    }

    /// `montantPositifFini` : nombre ou texte non blanc seulement, `Number()` fini et strictement positif.
    static func montantPositifFini(_ valeur: ValeurJSON?) -> Double? {
        switch valeur {
        case .nombre?:
            break
        case .chaine(let texte)?:
            if PrimitivesJS.trim(texte).isEmpty { return nil }
        default:
            return nil
        }
        let montant = PrimitivesJS.nombre(valeur)
        return montant.isFinite && montant > 0 ? montant : nil
    }

    /// `Number.isFinite(x) ? Math.max(0, x) : 0`.
    private static func positifOuZero(_ valeur: Double) -> Double {
        valeur.isFinite ? max0(valeur) : 0
    }

    /// `Math.max(0, x)` pour x fini (−0 rendu +0).
    private static func max0(_ valeur: Double) -> Double {
        valeur > 0 ? valeur : 0
    }
}
