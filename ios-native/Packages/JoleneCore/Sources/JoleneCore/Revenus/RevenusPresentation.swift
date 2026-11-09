import Foundation

// Présentation de l'onglet Revenus (lot 3, T12, B9 ; HARD STOP n°4 délégué, règle 6 de la tranche) : textes et mise en
// forme de l'aperçu `MesGainsApercuContent` (`src/pages/MesGains.tsx`, route `/soignant/mes-gains`, onglet par défaut),
// du bloc « Paiement rapide » (`src/components/gains/PaiementsEscrowAVenir.tsx`, monté par l'aperçu l.427) et des
// totaux serveur (`src/pages/PageStripeConnect.tsx` l.392-417). Libellés escrow et notes « net estimé » verbatim web
// (tutoiement compris, décision du 09/11/2026) ; textes non juridiques au vouvoiement (décision 9 du lot 1), adaptations
// et textes sans équivalent web listés dans `DECISIONS_LOT3.md` (section T12). Montants : valeurs serveur formatées
// comme `Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' })` (`MissionPresentation.euros`).

// MARK: - Textes

public enum RevenusTextes {
    // source: src/pages/MesGains.tsx:837 (`usePageTitle('Revenus')`, libellé de l'onglet)
    public static let titre = "Revenus"
    /// Adapté au vouvoiement (non juridique) de src/pages/MesGains.tsx:918 (« Tes gains, factures et documents de paie au
    /// même endroit », variante sans avance de trésorerie : drapeau `affacturage_actif` non lu, défaut `false`).
    public static let sousTitre = "Vos gains, factures et documents de paie au même endroit"
    // source: src/pages/MesGains.tsx:367
    public static let erreurTitre = "Impossible de charger tous les revenus"
    // source: src/pages/MesGains.tsx:156
    public static let erreurDefaut = "Impossible de charger les revenus."
    // source: src/pages/MesGains.tsx:370 ; src/components/gains/PaiementsEscrowAVenir.tsx:120
    public static let reessayer = "Réessayer"
    // source: src/pages/MesGains.tsx:804
    public static let videTitre = "Pas encore de gains"
    /// Adapté au vouvoiement de src/pages/MesGains.tsx:804 (« Tes gains apparaîtront ici après ta première mission terminée. »).
    public static let videDescription = "Vos gains apparaîtront ici après votre première mission terminée."
    // source: src/pages/MesGains.tsx:804
    public static let videAction = "Trouver une mission"
    // source: src/pages/MesGains.tsx:799
    public static let chargerPlus = "Charger plus de missions"
    // source: src/pages/MesGains.tsx:799
    public static let chargementSuite = "Chargement…"
    // source: src/pages/MesGains.tsx:764
    public static let regimeAVerifier = "Régime à vérifier"
    // source: src/pages/MesGains.tsx:751
    public static let honorairesPrevisionnels = "Honoraires prévisionnels du planning"
    // source: src/pages/MesGains.tsx:756
    public static let brutDuPlanning = "brut du planning"
    // source: src/pages/MesGains.tsx:756
    public static let brut = "brut"
    // source: src/pages/MesGains.tsx:703 (`aria-label={`Voir mission ${m.intitule || ''}`}`)
    public static let voirMission = "Voir mission"
    // source: src/pages/MesGains.tsx:937 (onglet « Factures »)
    public static let factures = "Factures"
    // source: src/pages/MesGains.tsx:943 (onglet « Paie »)
    public static let paie = "Paie"
    // source: src/pages/MesGains.tsx:664
    public static let noteSalariee = "* Net salarié estimé après cotisations salariales (~22 %). "
    // source: src/pages/MesGains.tsx:665
    public static let noteLiberale = "* Honoraires libéraux hors charges URSSAF et de retraite (annualisées). "
    // source: src/pages/MesGains.tsx:666
    public static let noteCommune = "Les simulations salariales sont indicatives ; le net exact figure sur le bulletin officiel fourni par l’employeur. Les honoraires libéraux sont détaillés sur la facture."
    /// `NoteNetEstime` (src/components/NoteNetEstime.tsx:13-16), source unique partagée avec l'Accueil.
    public static let noteNetEstime = AccueilPresentation.noteNetEstime
    /// Sans équivalent web (non juridique) : en-tête de la liste, le web la pose sous ses KPI sans titre.
    public static let missionsTerminees = "Missions terminées"
    /// Sans équivalent web (non juridique) : état d'une mission libérale. Le web le déduit des factures d'honoraires
    /// (`resumerFacturesMission`, l.766-786, lot 4) ; le natif n'en déduit rien et renvoie à l'onglet « Factures ».
    public static let paiementSuiviDansFactures = "Paiement suivi dans Factures"

    // Totaux serveur (`fn_mes_revenus_connect`).
    // source: src/pages/PageStripeConnect.tsx:397
    public static let kpiMois = "Ce mois"
    // source: src/pages/PageStripeConnect.tsx:404
    public static let kpiTotal = "Total réglé"
    // source: src/pages/PageStripeConnect.tsx:411
    public static let kpiAttente = "Autres paiements en attente"
    // source: src/pages/PageStripeConnect.tsx:417
    public static let noteTotaux = "Ces montants incluent les transferts vers le solde Stripe et les règlements directs. Ils ne confirment pas à eux seuls une arrivée en banque."
    /// Adapté au vouvoiement de src/pages/PageStripeConnect.tsx:389 (« Tes revenus sont temporairement indisponibles.
    /// Utilise « Actualiser » pour réessayer. ») ; la seconde phrase devient le bouton « Réessayer » de la section.
    public static let totauxIndisponibles = "Vos revenus sont temporairement indisponibles."

    // Paiement rapide (escrow), HARD STOP n°4 : verbatim web.
    // source: src/components/gains/PaiementsEscrowAVenir.tsx:163
    public static let paiementRapide = "Paiement rapide"
    // source: src/components/gains/PaiementsEscrowAVenir.tsx:168
    public static let aVenir = "À venir"
    // source: src/components/gains/PaiementsEscrowAVenir.tsx:175
    public static let recemmentVerse = "Récemment versé"
    // source: src/components/gains/PaiementsEscrowAVenir.tsx:181
    public static let annules = "Annulés"
    // source: src/components/gains/PaiementsEscrowAVenir.tsx:117
    public static let escrowIndisponible = "Paiements rapides indisponibles"
    // source: src/components/gains/PaiementsEscrowAVenir.tsx:103
    public static let escrowErreurDefaut = "Impossible de charger les paiements rapides."
    // source: src/components/gains/PaiementsEscrowAVenir.tsx:145
    public static let mission = "Mission"
}

/// Ton d'un état affiché (couleur sémantique du web), traduit en `StatusPill.Tone` par l'app ; jamais porté seul : le
/// libellé est toujours affiché et vocalisé.
public enum TonRevenus: Equatable, Sendable { case info, succes, alerte, neutre, erreur }

// MARK: - Paiement rapide

/// Les sept états de `fn_mes_paiements_escrow` (`public.sql` l.42272-42283), configuration `CONFIG` du web
/// (`PaiementsEscrowAVenir.tsx` l.42-80).
public enum EtatEscrow: String, CaseIterable, Sendable {
    case reserve = "RESERVE"
    case attenteValidation = "ATTENTE_VALIDATION"
    case versementEnCours = "VERSEMENT_EN_COURS"
    case retarde = "RETARDE"
    case litige = "LITIGE"
    case verse = "VERSE"
    case annule = "ANNULE"

    /// Fait partie du bloc « À venir » (`aVenir`).
    public var aVenir: Bool { self != .verse && self != .annule }

    /// `tone` du web : info, success, warning, neutral.
    public var ton: TonRevenus {
        switch self {
        case .reserve, .attenteValidation, .versementEnCours: return .info
        case .retarde, .litige: return .alerte
        case .verse: return .succes
        case .annule: return .neutre
        }
    }
}

/// Ligne affichée du paiement rapide : libellé, ligne d'explication (`nom · aide`) et part soignant (I3).
public struct LigneEscrowAffichee: Equatable, Sendable, Identifiable {
    public var missionId: String
    public var etat: EtatEscrow
    public var libelle: String
    public var detail: String
    public var montant: String
    /// Litige : la ligne mène au détail de la mission (web l.152-155, `Link` vers `/soignant/missions/:id`).
    public var ouvreMission: Bool { etat == .litige }
    public var ton: TonRevenus { etat.ton }

    public var id: String { missionId }
}

/// Bloc « Paiement rapide » : présent dès qu'une ligne existe (I5 : absent sinon, web l.127), groupes du web.
public struct EscrowAffiche: Equatable, Sendable {
    public var afficheSection: Bool
    public var aVenir: [LigneEscrowAffichee]
    /// « Récemment versé » : trois au plus (`verses.slice(0, 3)`).
    public var verses: [LigneEscrowAffichee]
    public var annules: [LigneEscrowAffichee]

    public static let vide = EscrowAffiche(afficheSection: false, aVenir: [], verses: [], annules: [])
}

// MARK: - Mission terminée

/// État affiché d'une mission terminée.
public struct EtatLigneRevenus: Equatable, Sendable {
    public var texte: String
    public var ton: TonRevenus

    public init(texte: String, ton: TonRevenus) { self.texte = texte; self.ton = ton }
}

/// Ligne affichée d'une mission terminée (`MesGains.tsx` l.698-786) : chaînes prêtes pour `AmountRow` (montant serveur
/// formaté, nature verbatim, lignes secondaires), sans aucun calcul dans la vue.
public struct LigneMissionAffichee: Equatable, Sendable, Identifiable {
    public var id: String
    public var jour: AccueilPresentation.Jour?
    public var titre: String
    public var sousTitre: String
    public var horaires: String?
    /// Montant formaté, nil si le serveur n'en fournit pas (tiret « — » du web).
    public var montant: String?
    public var approximatif: Bool
    public var nature: String?
    public var details: [String]
    public var etat: EtatLigneRevenus
    /// Action vocale de la ligne (`aria-label` du web, l.703).
    public var actionAccessible: String
}

// MARK: - Règles de présentation

public enum RevenusPresentation {
    /// Factures d'honoraires (lot 4) : renvoi web assumé (D4).
    public static let lienFactures = "/soignant/mes-gains?tab=factures"
    /// Documents de paie (lot 4) : renvoi web assumé (D4).
    public static let lienBulletins = "/soignant/mes-gains?tab=bulletins"

    /// Détail des présences d'une mission (`navigate(`/soignant/presences/mission/${m.id}`)`, l.705) : écran du lot 2,
    /// renvoi web tant qu'il n'est pas livré.
    public static func lienPresences(missionId: String) -> String { "/soignant/presences/mission/\(missionId)" }

    /// Route d'un renvoi web (résolue par `LinkRouter` puis `DestinationLien`, jamais une URL écrite en dur) ; nil si le
    /// lien n'est pas un lien Jolene ou si son écran natif est livré.
    public static func renvoiWeb(_ lien: String) -> JoleneRoute? { AccueilPresentation.renvoiWeb(lien) }

    /// `fmt` du web : `Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' })`.
    public static func euros(_ valeur: Double) -> String { MissionPresentation.euros(valeur) }

    // MARK: Paiement rapide

    /// `jour(iso)` du web : `toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' })`, ici à l'heure de Paris
    /// (le web : heure locale de l'appareil, identique sur un appareil réglé sur la France) ; nil si illisible.
    public static func jourMois(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty, let date = try? DateHeureParis.instantJolene(iso) else { return nil }
        return DateHeureParis.format(date, "dd/MM")
    }

    /// Ligne d'un paiement rapide ; nil pour un état hors des sept (`if (!c) return null`, l.135).
    public static func ligneEscrow(_ ligne: PaiementRapide) -> LigneEscrowAffichee? {
        guard let etat = EtatEscrow(rawValue: ligne.etat) else { return nil }
        let jour = jourMois(ligne.dateAffichee)
        let libelle: String
        let aide: String
        switch etat {
        case .reserve:
            libelle = "Réservé"                                           // source: PaiementsEscrowAVenir.tsx:51
            aide = "le montant de ta confirmation, mis de côté"           // source: PaiementsEscrowAVenir.tsx:52
        case .attenteValidation:
            libelle = "En attente de validation des heures"               // source: PaiementsEscrowAVenir.tsx:55
            aide = "l'établissement valide tes heures (automatique sous 72 h)" // source: PaiementsEscrowAVenir.tsx:56
        case .versementEnCours:
            libelle = jour.map { "Versement en cours — estimé le \($0)" } ?? "Versement en cours" // source: :59
            aide = "ton virement est en route"                            // source: PaiementsEscrowAVenir.tsx:61
        case .retarde:
            libelle = "Paiement retardé"                                  // source: PaiementsEscrowAVenir.tsx:64
            aide = jour.map { "nouvelle tentative le \($0)" } ?? "nous relançons le règlement" // source: :65
        case .litige:
            libelle = "Paiement en litige"                                // source: PaiementsEscrowAVenir.tsx:68
            aide = "voir le litige de la mission"                         // source: PaiementsEscrowAVenir.tsx:69
        case .verse:
            libelle = jour.map { "Versé le \($0)" } ?? "Versé"           // source: PaiementsEscrowAVenir.tsx:72
            aide = ""                                                     // source: PaiementsEscrowAVenir.tsx:74
        case .annule:
            libelle = "Paiement annulé"                                   // source: PaiementsEscrowAVenir.tsx:77
            aide = "contacte le support si besoin"                        // source: PaiementsEscrowAVenir.tsx:78
        }
        // `{l.etablissement_nom || l.mission_intitule || 'Mission'}{c.aide(l) ? ` · ${c.aide(l)}` : ''}` (l.145-146).
        let nom = nonVide(ligne.etablissementNom) ?? nonVide(ligne.missionIntitule) ?? RevenusTextes.mission
        let detail = aide.isEmpty ? nom : "\(nom) · \(aide)"
        // `eur((cents ?? 0) / 100)` : part soignant seule (I3), `honoraires_cents` figé à la confirmation (règle #11).
        return LigneEscrowAffichee(missionId: ligne.missionId, etat: etat, libelle: libelle, detail: detail,
                                   montant: euros(Double(ligne.honorairesCents) / 100))
    }

    /// Groupes du web : « À venir » (états `aVenir`), « Récemment versé » (trois premiers `VERSE`), « Annulés ».
    public static func escrow(_ lignes: [PaiementRapide]) -> EscrowAffiche {
        let affichees = lignes.compactMap(ligneEscrow)
        return EscrowAffiche(afficheSection: !lignes.isEmpty,
                             aVenir: affichees.filter { $0.etat.aVenir },
                             verses: Array(affichees.filter { $0.etat == .verse }.prefix(3)),
                             annules: affichees.filter { $0.etat == .annule })
    }

    // MARK: Missions terminées

    /// Ligne d'une mission terminée, portée de `MesGains.tsx` l.698-786 (hors facturation, lot 4).
    public static func mission(_ mission: MissionTerminee) -> LigneMissionAffichee {
        let finance = MontantMission.montantAffiche(mission.finance)
        let debut = mission.debutLe.flatMap { try? DateHeureParis.instantJolene($0) }
        let fin = mission.finLe.flatMap { try? DateHeureParis.instantJolene($0) }
        let jour = debut.map {
            AccueilPresentation.Jour(semaine: DateHeureParis.format($0, "EEE"), jour: DateHeureParis.format($0, "d"),
                                     mois: DateHeureParis.format($0, "MMM"))
        }
        // `🏥 {m.etablissements?.nom || '—'}{m.service && ` · ${m.service}`}` (l.719-720).
        var sousTitre = "🏥 \(nonVide(mission.etablissementNom) ?? "—")"
        if let service = nonVide(mission.service) { sousTitre += " · \(service)" }
        let nature: String? = finance.map {
            $0.nature == .honorairesLiberaux ? RevenusTextes.honorairesPrevisionnels : $0.libelle
        }
        // `{regimeMission(m) === 'LIBERAL' ? 'brut du planning' : 'brut'} : {fmt(m.total_brut)}` (l.756).
        let details = mission.totalBrut.map {
            ["\(mission.regime == "LIBERAL" ? RevenusTextes.brutDuPlanning : RevenusTextes.brut) : \(euros($0))"]
        } ?? []
        return LigneMissionAffichee(
            id: mission.id, jour: jour, titre: mission.intitule ?? "", sousTitre: sousTitre,
            horaires: horaires(mission, debut: debut, fin: fin), montant: finance.map { euros($0.montant) },
            approximatif: finance?.approximatif ?? false, nature: nature, details: details, etat: etat(mission),
            actionAccessible: "\(RevenusTextes.voirMission) \(mission.intitule ?? "")")
    }

    /// État de la mission (l.758-786) : salariée → dernière déclaration (`classerPaiementSalaire`, golden T2) ; régime non
    /// arrêté → « Régime à vérifier » ; libérale → renvoi à l'onglet Factures (états des factures : lot 4).
    public static func etat(_ mission: MissionTerminee) -> EtatLigneRevenus {
        switch mission.regime {
        case "SALARIE"?:
            let salaire = EtatPaiement.classerPaiementSalaire(mission.dernierPaiement?.salaire)
            let ton: TonRevenus = salaire.etat == .confirme ? .succes : salaire.etat == .conteste ? .erreur : .neutre
            return EtatLigneRevenus(texte: salaire.libelle, ton: ton)
        case "LIBERAL"?:
            return EtatLigneRevenus(texte: RevenusTextes.paiementSuiviDansFactures, ton: .neutre)
        default:
            return EtatLigneRevenus(texte: RevenusTextes.regimeAVerifier, ton: .neutre)
        }
    }

    /// Note de bas de page (l.663-667) : `salMissions` et `libMissions` filtrent `type_contrat_applique` seul (l.249-250).
    public static func noteBasDePage(_ missions: [MissionTerminee]) -> String {
        let salariee = missions.contains { $0.typeContratApplique == "SALARIE" }
        let liberale = missions.contains { $0.typeContratApplique == "LIBERAL" }
        return (salariee ? RevenusTextes.noteSalariee : "") + (liberale ? RevenusTextes.noteLiberale : "") + RevenusTextes.noteCommune
    }

    /// `NoteNetEstime` accompagne une mission salariée (`salMissions.length > 0`, l.632-633).
    public static func afficheNoteNetEstime(_ missions: [MissionTerminee]) -> Bool {
        missions.contains { $0.typeContratApplique == "SALARIE" }
    }

    // MARK: Interne

    /// `{formatParis(debut, "HH'h'mm")} → {formatParis(fin, "HH'h'mm")}`, `{Math.round(duree * 10) / 10}h`,
    /// `{m.taux_horaire_base} €/h` (l.730-733), joints par « · » ; une partie illisible est omise.
    static func horaires(_ mission: MissionTerminee, debut: Date?, fin: Date?) -> String? {
        var parties: [String] = []
        if let debut, let fin {
            parties.append("\(DateHeureParis.format(debut, "HH'h'mm")) → \(DateHeureParis.format(fin, "HH'h'mm"))")
        }
        // `m.duree_heures ?? (fin - début) / 3 600 000`.
        let duree = mission.dureeHeures ?? {
            guard let debut, let fin else { return nil }
            return fin.timeIntervalSince(debut) / 3600
        }()
        if let duree, duree.isFinite {
            parties.append("\(nombreJS(CalendrierCivil.arrondiJS(duree * 10) / 10))h")
        }
        if let taux = mission.tauxHoraireBase, taux.isFinite {
            parties.append("\(nombreJS(taux)) €/h")
        }
        return parties.isEmpty ? nil : parties.joined(separator: " · ")
    }

    /// `String(n)` d'un nombre JavaScript fini dans le domaine des durées et des taux (entier sans décimale, sinon la plus
    /// courte écriture décimale avec un point, comme le web).
    static func nombreJS(_ valeur: Double) -> String {
        if valeur == valeur.rounded(), abs(valeur) < 1e15 { return String(Int(valeur)) }
        return String(valeur)
    }

    /// `||` JavaScript sur un texte : vide ou absent cède la place.
    private static func nonVide(_ texte: String?) -> String? {
        guard let texte, !texte.isEmpty else { return nil }
        return texte
    }
}
