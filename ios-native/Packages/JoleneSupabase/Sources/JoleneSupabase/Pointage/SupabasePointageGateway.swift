import Foundation
import JoleneCore
import Supabase

/// `PointagePort` sur Supabase (blueprint lot 2 §2.3-§2.5, §3 T3), avec le JWT du soignant ; la RLS reste seule juge.
///
/// - Présences : quatre lectures en parallèle comme le `Promise.all` du web (`PresencesSoignant.tsx` l.110-152), puis
///   créneaux (tous types, paginés), contrats et `fn_etablissements_safe` (`PointageQuery` : projections imposées) ;
///   noms d'établissement en lecture tolérante, comme le web (revue fraîche de T3, m5).
/// - État : `fn_etat_pointage_mission` ; `{error}` HTTP 200 (« Mission introuvable », « Accès interdit ») lu AVANT le
///   décodage et levé en `JoleneError(.unknown, <message serveur verbatim>)` (« Non authentifié » → `.unauthorized`) ;
///   décodeur `EtatPointage` en liste blanche (`code_pointage_actif`, `est_etab` jamais lus).
/// - Scan : une seule requête par `RPCResponse.appelerMutation(…, exceptionsMetier: ExceptionsMetierLot2.scannerCodePointage)`.
///   Réponse décodée en liste blanche (`ScanEnregistre`) : la forme d'après la PR B1 (sans code suivant) comme celle
///   d'avant (code suivant et sa signature encore présents) donnent le même résultat ; ces clés ne sont ni lues, ni
///   conservées, ni journalisées (la réponse brute ne sort jamais de cette méthode). Un HTTP 200 prouve le COMMIT
///   (PostgREST construit la réponse après lui) : succès annoncé après relecture de l'état (`PointageRules.etatConfirme`)
///   ET d'une preuve `scans_pointage` hors base du reçu (`RecuScan.reconcilier`) ; sinon ligne du scan relue SANS filtre
///   de mission (le code désigne la mission, revue fraîche de T3, M-A) → `.enregistreSurAutreMission` ; sinon
///   `.accepteSansPreuve`, jamais `.incertain`. Rollback prouvé → `.refuse` (SQLSTATE si c'en est un) ; transport ou
///   passerelle → `.incertain`, jamais un renvoi ; JWT refusé ou session absente → `.unauthorized` levée (m1).
/// - Réconciliation : relecture de `scans_pointage` de la mission du reçu, verdict de `RecuScan.reconcilier`.
/// - Consentement : `soignants.consentement_gps`, puis `fn_consentir_gps` relu.
/// - Détail : créneaux de la mission et `fn_presences_detail_mission` (carte masquée sur `{error}`).
/// - Relance : `fn_relancer_validation_presence`, message serveur verbatim ; `NON_AUTHENTIFIE` → `.unauthorized`.
///
/// Les lectures GET peuvent être rejouées par le SDK (`PostgrestBuilder`, correction 19) ; les RPC partent en POST et ne
/// le sont jamais.
public struct SupabasePointageGateway: PointagePort {
    private let client: SupabaseClient
    private let clock: any ClockPort
    private let missions: SupabaseMissionsGateway

    public init(client: SupabaseClient, clock: any ClockPort = SystemClock()) {
        self.client = client
        self.clock = clock
        self.missions = SupabaseMissionsGateway(client: client, clock: clock)
    }

    // MARK: - Présences

    public func presences(context: MissionReadContext) async throws -> InstantanePresences {
        try MissionQuery.validate(context: context)
        let maintenant = clock.now()
        let il7jours = MissionQuery.isoTimestamp(DateHeureParis.ajouterJoursCivils(maintenant, -7))
        let soignant = context.userId
        async let actives: [LigneTolerante<MissionPresenceLue>] = lire {
            try await client.from("missions").select(PointageQuery.missionsSelect)
                .eq("soignant_assigne_id", value: soignant)
                .in("statut", values: PointageQuery.statutsActifs)
                .order("debut_le", ascending: true)
                .execute().value
        }
        async let validees: [LigneTolerante<PresenceLue>] = lire {
            try await client.from("presences").select(PointageQuery.presencesValideesSelect)
                .eq("soignant_id", value: soignant)
                .eq("valide_par_etablissement", value: true)
                .gte("valide_le", value: il7jours)
                .order("valide_le", ascending: false)
                .execute().value
        }
        async let historique: [LigneTolerante<PresenceLue>] = lire {
            try await client.from("presences").select(PointageQuery.historiqueSelect)
                .eq("soignant_id", value: soignant)
                .order("cree_le", ascending: false)
                .limit(PointageQuery.limiteHistorique)
                .execute().value
        }
        async let terminees: [LigneTolerante<MissionPresenceLue>] = lire {
            try await client.from("missions").select(PointageQuery.missionsSelect)
                .eq("soignant_assigne_id", value: soignant)
                .in("statut", values: PointageQuery.statutsHistorique)
                .order("fin_le", ascending: false)
                .limit(PointageQuery.limiteHistorique)
                .execute().value
        }
        // Lecture tolérante par ligne : une ligne sans ses clés obligatoires est écartée, jamais toute la page.
        let (lignesActives, lignesValidees, lignesHistorique, lignesTerminees) = try await (actives, validees, historique, terminees)
        let missionsActives = LigneTolerante.valeurs(lignesActives)
        let presencesValidees = LigneTolerante.valeurs(lignesValidees)
        let presences = LigneTolerante.valeurs(lignesHistorique)
        let missionsTerminees = LigneTolerante.valeurs(lignesTerminees)

        let idsMissions = InstantanePresences.identifiantsMissions(missions: missionsActives, presencesValidees: presencesValidees,
                                                                   historique: presences, missionsHistorique: missionsTerminees)
        let idsEtablissements = InstantanePresences.identifiantsEtablissements(
            missions: missionsActives, presencesValidees: presencesValidees, historique: presences, missionsHistorique: missionsTerminees)
        async let creneaux = lireCreneaux(missionIds: idsMissions)
        async let contrats = lireContrats(missionIds: missionsActives.map(\.id))
        async let etablissements = lireEtablissements(ids: idsEtablissements)
        return try await InstantanePresences(missions: missionsActives, presencesValidees: presencesValidees, historique: presences,
                                             missionsHistorique: missionsTerminees, creneaux: creneaux, contrats: contrats,
                                             etablissements: etablissements, chargeLe: maintenant)
    }

    // MARK: - État

    public func etat(missionId: String, context: MissionReadContext) async throws -> EtatPointage {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, PointageQuery.rpcEtat, params: ["p_mission_id": .string(missionId)],
                                                    fallback: PointageQuery.fallbackEtat)
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
            throw JoleneError(.unknown, erreur)
        }
        guard !reponse.estRefus, reponse.raw.objectValue != nil,
              let etat = PointageQuery.decoder(EtatPointage.self, reponse) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return etat
    }

    // MARK: - Consentement GPS

    private struct LigneConsentement: Decodable {
        let consentementGps: Bool?
        enum CodingKeys: String, CodingKey { case consentementGps = "consentement_gps" }
        init(from decoder: Decoder) throws {
            consentementGps = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Bool.self, forKey: .consentementGps)
        }
    }

    public func consentementGps(context: MissionReadContext) async throws -> Bool? {
        try MissionQuery.validate(context: context)
        let soignant = context.userId
        let ligne: LigneConsentement? = try await lire(fallback: PointageQuery.fallbackLocalisation) {
            try await client.from("soignants").select(PointageQuery.consentementSelect)
                .eq("id", value: soignant)
                .maybeSingle()
                .execute().value
        }
        return ligne?.consentementGps
    }

    public func enregistrerConsentementGps(_ accepte: Bool, context: MissionReadContext) async throws -> Bool {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, PointageQuery.rpcConsentement, params: ["p_accepte": .bool(accepte)],
                                                    fallback: PointageQuery.fallbackLocalisation)
        try reponse.leverSiErreur(fallback: PointageQuery.fallbackLocalisation)
        guard reponse.estSucces else { throw JoleneError(.unknown, reponse.erreur ?? PointageQuery.fallbackLocalisation) }
        // Relecture : la valeur rendue est celle du serveur, jamais l'hypothèse locale.
        guard let relu = try await consentementGps(context: context) else {
            throw JoleneError(.unknown, PointageQuery.fallbackLocalisation)
        }
        return relu
    }

    // MARK: - Scan

    public func scanner(code: String, metadonnees: MetadonneesScan, recu: RecuScan,
                        context: MissionReadContext) async throws -> IssueScan {
        try MissionQuery.validate(context: context)
        guard recu.phase == .started, recu.userId == context.userId, recu.terminalId == metadonnees.idTerminal,
              PointageRules.codeSaisi(code) == code else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let params = try PointageQuery.parametresScan(code: code, metadonnees: metadonnees)
        switch await RPCResponse.appelerMutation(client, PointageQuery.rpcScanner, params: params, fallback: PointageQuery.fallbackScan,
                                                 exceptionsMetier: ExceptionsMetierLot2.scannerCodePointage) {
        case let .reponse(reponse):
            if reponse.estRefus {
                return .refuse(sqlstate: reponse.sqlstate, message: reponse.erreur ?? PointageQuery.fallbackScan)
            }
            // HTTP 200 : la fonction a rendu, le COMMIT est fait. Corps hors contrat (sans numéro de scan, `{error}`
            // inattendu) : relu sans réponse décodée, jamais « non reçu » (revue fraîche de T3, M-A).
            let scan = reponse.erreur == nil ? PointageQuery.decoder(ScanEnregistre.self, reponse) : nil
            return await relire(scan, recu: recu, context: context)
        case let .refusDefinitif(code, erreur):
            // JWT refusé (`PGRST301`-`PGRST303`) : session expirée, jamais un refus métier (m1).
            if erreur.kind == .unauthorized { throw erreur }
            return .refuse(sqlstate: RecuScan.sqlstateValide(code) ? code : nil, message: erreur.message)
        case let .incertain(erreur):
            // Session absente (levée avant l'envoi) ou 401/403 hors PostgREST : `.unauthorized` remonte (m1) ; l'appelant
            // garde le reçu `started` et le réconcilie au retour de l'utilisateur.
            if erreur.kind == .unauthorized { throw erreur }
            return .incertain
        }
    }

    /// Relecture d'un HTTP 200 (§2.3 ; revue fraîche de T3, M-A). `fn_scanner_code_pointage` trouve la mission par le
    /// seul code (`public.sql` l.55639-55644) : le scan validé peut appartenir à une autre mission du soignant que celle
    /// du reçu. (1) Mission du reçu : preuve hors base ET état confirmé → `.enregistre`. (2) Sinon, ligne du scan relue
    /// sans filtre de mission (`localiser`) puis état de sa mission confirmé → `.enregistreSurAutreMission`. (3) Sinon
    /// `.accepteSansPreuve` : jamais `.incertain`, car la réconciliation du reçu, filtrée sur sa mission, conclurait
    /// « non reçu » et inviterait à pointer une seconde fois (décision 2, PRINCIPES §4).
    private func relire(_ scan: ScanEnregistre?, recu: RecuScan, context: MissionReadContext) async -> IssueScan {
        if let confirme = try? await confirmerSurLaMissionDuRecu(scan, recu: recu, context: context) { return confirme }
        guard let scan, let creneau = scan.creneauEffectifId, !creneau.isEmpty,
              let preuve = try? await localiser(scan, creneau: creneau, recu: recu, context: context),
              let mission = preuve.missionId, mission != recu.missionId,
              let relu = try? await etat(missionId: mission, context: context),
              PointageRules.etatConfirme(relu, scan: scan) else { return .accepteSansPreuve }
        return .enregistreSurAutreMission(missionId: mission, typeScan: scan.typeScanEffectue ?? preuve.typeScan,
                                          numeroScan: scan.numeroScan)
    }

    /// (1) de `relire` : nil si la mission du reçu ne confirme pas le scan. Sans réponse décodée, la preuve hors base de
    /// ce terminal est celle de l'essai (un seul essai en vol par utilisateur, `ReceiptJournal`), si l'état la compte.
    private func confirmerSurLaMissionDuRecu(_ scan: ScanEnregistre?, recu: RecuScan,
                                             context: MissionReadContext) async throws -> IssueScan? {
        async let etatRelu = self.etat(missionId: recu.missionId, context: context)
        async let preuvesRelues = self.preuvesScan(missionId: recu.missionId, context: context)
        let (relu, lignes) = try await (etatRelu, preuvesRelues)
        guard case let .recu(preuve) = try recu.reconcilier(scans: lignes, relueLe: clock.now()),
              let numero = preuve.numeroScan else { return nil }
        guard let scan else {
            return (relu.nbScans ?? 0) >= numero ? .enregistre(typeScan: preuve.typeScan, numeroScan: numero) : nil
        }
        guard numero == scan.numeroScan, PointageRules.etatConfirme(relu, scan: scan) else { return nil }
        return .enregistre(typeScan: scan.typeScanEffectue ?? preuve.typeScan, numeroScan: scan.numeroScan)
    }

    /// Ligne `scans_pointage` d'un scan validé, SANS filtre de mission (revue fraîche de T3, M-A) : le créneau EFFECTIF
    /// et le numéro rendus par la réponse la désignent seule (un créneau appartient à une mission, où le numéro est
    /// unique : `numero_scan = COALESCE(nb_scans, 0) + 1`, `public.sql` l.55667), lisible par le soignant (`sp_select`
    /// l.79931). Projection `PreuveScan.colonnes` (jamais `code_saisi`, `ip_address`, `latitude`, `longitude`). Nil si
    /// aucune ligne, ou plusieurs, ne conviennent (même terminal, même numéro, même type, mission connue).
    private func localiser(_ scan: ScanEnregistre, creneau: String, recu: RecuScan,
                           context: MissionReadContext) async throws -> PreuveScan? {
        try MissionQuery.validate(context: context)
        let soignant = context.userId, terminal = recu.terminalId, numero = String(scan.numeroScan)
        let lignes: [LigneTolerante<PreuveScan>] = try await lire {
            try await client.from("scans_pointage").select(PointageQuery.preuvesSelect)
                .eq("soignant_id", value: soignant)
                .eq("creneau_effectif_id", value: creneau)
                .eq("numero_scan", value: numero)
                .eq("id_terminal", value: terminal)
                .limit(PointageQuery.limiteLocalisation)
                .execute().value
        }
        let candidates = LigneTolerante.valeurs(lignes).filter { ligne in
            guard ligne.numeroScan == scan.numeroScan, ligne.idTerminal == terminal,
                  let mission = ligne.missionId, !mission.isEmpty else { return false }
            guard let attendu = scan.typeScanEffectue, let lu = ligne.typeScan else { return true }
            return attendu == lu
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    // MARK: - Réconciliation

    public func reconcilier(recu: RecuScan, context: MissionReadContext) async throws -> IssueScan {
        try MissionQuery.validate(context: context)
        guard recu.userId == context.userId else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let lignes = try await preuvesScan(missionId: recu.missionId, context: context)
        return IssueScan(reconciliation: try recu.reconcilier(scans: lignes, relueLe: clock.now()))
    }

    public func preuvesScan(missionId: String, context: MissionReadContext) async throws -> [PreuveScan] {
        try MissionQuery.validate(context: context)
        let lignes: [LigneTolerante<PreuveScan>] = try await lire {
            try await client.from("scans_pointage").select(PointageQuery.preuvesSelect)
                .eq("mission_id", value: missionId)
                .order("numero_scan", ascending: false)
                .limit(RecuScan.maxPreuves)
                .execute().value
        }
        return LigneTolerante.valeurs(lignes).filter { $0.missionId == missionId }
    }

    // MARK: - Détail et relance

    public func detail(missionId: String, context: MissionReadContext) async throws -> DetailPresences {
        try MissionQuery.validate(context: context)
        async let creneaux = lireCreneaux(missionIds: [missionId])
        async let resume = lireResume(missionId: missionId)
        return try await DetailPresences(missionId: missionId, creneaux: creneaux, resume: resume)
    }

    /// Synthèse serveur, lecture tolérante : `{error}`, forme inattendue ou panne → nil (carte masquée, §2.4) ; une
    /// session expirée et l'annulation remontent.
    private func lireResume(missionId: String) async throws -> ResumePresencesServeur? {
        let reponse: RPCResponse
        do {
            reponse = try await RPCResponse.appeler(client, PointageQuery.rpcDetail, params: ["p_mission_id": .string(missionId)],
                                                    fallback: PointageQuery.fallbackDetail)
        } catch let erreur as JoleneError where erreur.kind == .unauthorized || erreur.kind == .cancelled {
            throw erreur
        } catch {
            if error is CancellationError { throw error }
            return nil
        }
        if let erreur = reponse.erreur, RPCResponse.estNonAuthentifie(erreur) {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        guard reponse.erreur == nil, !reponse.estRefus else { return nil }
        return PointageQuery.decoder(ResumePresencesServeur.self, reponse)
    }

    public func relancerValidation(missionId: String, context: MissionReadContext) async throws -> IssueRelance {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, PointageQuery.rpcRelance, params: ["p_mission_id": .string(missionId)],
                                                    fallback: PointageQuery.fallbackRelance)
        if reponse.success == true, reponse.erreur == nil { return .envoyee(message: reponse.string("message")) }
        // Session expirée (`auth.uid()` nul, `public.sql` l.53023) : jamais « Relance impossible. » (m1).
        if reponse.erreur == PointageQuery.erreurRelanceNonAuthentifie {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        return .refusee(message: reponse.string("message") ?? PointageQuery.fallbackRelance)
    }

    // MARK: - Lectures

    /// Lecture PostgREST traduite par `SupabaseErrorMapping` (aucune interception : lecture seule).
    private func lire<T>(fallback: String = PointageQuery.fallbackPresences,
                         _ requete: () async throws -> T) async throws -> T {
        do {
            return try await requete()
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallback)
        }
    }

    /// Noms des établissements en lecture tolérante, comme le web (`fetchEtablissementsSafe`,
    /// `src/lib/etablissements.ts` l.31-38 : erreur ignorée, repli « Établissement » à l'affichage) : un échec de
    /// `fn_etablissements_safe` donne `[:]`, jamais l'échec de l'instantané ; une session expirée et l'annulation
    /// remontent (revue fraîche de T3, m5).
    private func lireEtablissements(ids: [String]) async throws -> [String: EtablissementSummary] {
        do {
            return try await missions.etablissements(ids: ids)
        } catch let erreur as JoleneError where erreur.kind == .unauthorized || erreur.kind == .cancelled {
            throw erreur
        } catch {
            if error is CancellationError { throw error }
            return [:]
        }
    }

    private func lireContrats(missionIds: [String]) async throws -> [ContratPointage] {
        guard !missionIds.isEmpty else { return [] }
        let lignes: [LigneTolerante<ContratPointage>] = try await lire {
            try await client.from("contrats_mission").select(PointageQuery.contratsSelect)
                .in("mission_id", values: missionIds)
                .execute().value
        }
        let demandes = Set(missionIds)
        return LigneTolerante.valeurs(lignes).filter { $0.missionId.map(demandes.contains) ?? false }
    }

    /// Créneaux de tous types (PREVISIONNEL, EFFECTIF, pauses) par lots de 50 missions et pages de 500, compte exact
    /// obligatoire et stable (mêmes erreurs d'intégrité que `MissionSlotPager`) ; ordre final par début (l.177).
    func lireCreneaux(missionIds: [String]) async throws -> [MissionSlot] {
        var resultat: [MissionSlot] = []
        var vus = Set<String>()
        for lot in MissionSlotPager.batches(missionIds) {
            var attendu: Int?
            var position = 0
            while attendu.map({ position < $0 }) ?? true {
                try Task.checkCancellation()
                let page: PostgrestResponse<[MissionSlot]> = try await lire {
                    try await client.from("mission_creneaux")
                        .select(MissionQuery.slotSelect, count: .exact)
                        .in("mission_id", values: lot)
                        .order("debut", ascending: true)
                        .order("id", ascending: true)
                        .range(from: position, to: position + MissionQuery.slotPageSize - 1)
                        .execute()
                }
                guard let compte = page.count, compte >= 0 else { throw MissionSlotPager.countUnavailable }
                if let attendu, attendu != compte { throw MissionSlotPager.planningChanged }
                attendu = compte
                if page.value.isEmpty, position < compte { throw MissionSlotPager.planningIncomplete }
                for creneau in page.value {
                    guard let id = creneau.id, !id.isEmpty, let mission = creneau.missionId, lot.contains(mission),
                          vus.insert(id).inserted else { throw MissionSlotPager.planningInconsistent }
                    resultat.append(creneau)
                }
                position += page.value.count
                if position > compte { throw MissionSlotPager.planningInconsistent }
            }
        }
        return TriCreneauxPointage.parDebut(resultat)
    }
}

/// Tri stable des créneaux par début (plusieurs lots se concatènent dans l'ordre des lots).
enum TriCreneauxPointage {
    static func parDebut(_ creneaux: [MissionSlot]) -> [MissionSlot] {
        creneaux.enumerated().sorted { a, b in
            let ta = (try? DateHeureParis.instantJolene(a.element.debut))?.timeIntervalSince1970 ?? .infinity
            let tb = (try? DateHeureParis.instantJolene(b.element.debut))?.timeIntervalSince1970 ?? .infinity
            if ta != tb { return ta < tb }
            return a.offset < b.offset
        }.map(\.element)
    }
}
