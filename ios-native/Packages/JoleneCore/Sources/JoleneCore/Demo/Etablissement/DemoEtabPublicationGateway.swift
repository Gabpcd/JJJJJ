import Foundation

/// Missions publiées pendant la session démo (lot 5, T9), partagées par les gateways démo de la publication et des
/// missions : une seule source pour la mission créée et sa relecture (état dérivé). Journal des charges reçues, dans
/// l'ordre. Remis à zéro à chaque lancement (aucun stockage).
public actor DemoEtabEtatPublication {
    /// Lignes créées par la session : missions (sans montant, comme la fixture) et leurs créneaux PREVISIONNEL.
    public struct Surcouche: Equatable, Sendable {
        public var missions: [EtabMissionResume] = []
        public var creneaux: [MissionSlot] = []
    }

    private var surcoucheCourante = Surcouche()
    private var chargesRecues: [PublicationPayload] = []

    public init() {}

    public func surcouche() -> Surcouche { surcoucheCourante }

    /// Charges reçues par la gateway démo, refusées comprises.
    public func journal() -> [PublicationPayload] { chargesRecues }

    func journaliser(_ charge: PublicationPayload) {
        chargesRecues.append(charge)
    }

    /// Insère la mission et ses créneaux ; rend l'identifiant attribué (`demo-etab-publiee-<n>`).
    func creer(_ brouillon: PublicationMission, etablissementId: String, creeLe: String) -> String {
        let id = "demo-etab-publiee-\(surcoucheCourante.missions.count + 1)"
        let description = PublicationPayload.description(brouillon.description)
        surcoucheCourante.missions.append(EtabMissionResume(
            id: id, intitule: brouillon.intitule.trimmingCharacters(in: .whitespacesAndNewlines),
            statut: PublicationRelecture.statutOuverte, debutLe: brouillon.creneaux.map(\.debut).min(),
            finLe: brouillon.creneaux.map(\.fin).max(), nbCreneaux: brouillon.creneaux.count,
            professionRequise: brouillon.professionRequise, typeContratRecherche: PublicationPayload.typeContratRecherche,
            estUrgente: brouillon.estUrgente, etablissementId: etablissementId, description: description,
            service: brouillon.service, niveauUrgence: brouillon.estUrgente ? brouillon.niveauUrgence : 0,
            soignantAssigneId: nil, modeAttribution: brouillon.modeAttribution.rawValue, creeLe: creeLe))
        for (rang, creneau) in brouillon.creneaux.enumerated() {
            surcoucheCourante.creneaux.append(MissionSlot(id: "\(id)-c\(rang + 1)", missionId: id, debut: creneau.debut,
                                                          fin: creneau.fin, estPause: false, typeCreneau: "PREVISIONNEL"))
        }
        return id
    }

    /// Mission créée et ses créneaux, relus dans l'état de la session.
    func relire(_ id: String) -> EtabMissionDetail? {
        guard let mission = surcoucheCourante.missions.first(where: { $0.id == id }) else { return nil }
        return EtabMissionDetail(mission: mission, creneaux: surcoucheCourante.creneaux.filter { $0.missionId == id },
                                 soignantAssigneId: nil)
    }
}

/// `EtabPublicationPort` du monde démo (lot 5, T9), aucun réseau. Mêmes règles que la gateway Supabase : contexte
/// cohérent et compte fictif seulement (`.demoOnly`), brouillon structurellement valide exigé avant tout traitement,
/// charge de seize paramètres journalisée, refus au texte du serveur, « publiée » seulement après relecture de la
/// mission insérée dans l'état de la session (que la gateway démo des missions relit aussi : la mission apparaît dans
/// la liste, « Ouverte »). Aucune règle du temps de travail n'est rejouée ici (D9) : seuls les refus structurels du
/// serveur le sont.
public struct DemoEtabPublicationGateway: EtabPublicationPort {
    /// `fn_blocage_publication_etab` (`supabase/schema/public.sql` l.21209-21210), code et texte serveur.
    static let codeSuspendue = "PUBLICATION_SUSPENDUE"
    static let messageSuspendue = "Publication suspendue en raison d obligations de paiement à régulariser."
    /// `fn_creer_mission_multi_jours` (l.27579-27580), texte serveur d'une création impossible (droit d'écriture refusé).
    static let codeIndisponible = "CREATION_MISSION_INDISPONIBLE"
    static let messageIndisponible = "La création de la mission est temporairement indisponible."
    /// `fn_creer_mission_multi_jours` (l.27462), texte serveur.
    static let messagePasse = "La mission ne peut pas commencer dans le passé."
    /// `fn_valider_creneaux_mission_json` (l.65723), texte serveur.
    static let messageAucunCreneau = "Ajoutez au moins un créneau travaillé."

    private let etat: DemoEtabEtatPublication
    private let blocage: Bool
    private let horloge: ClockPort

    /// `blocage` : établissement bloqué automatiquement (`-JOLENE_DEMO_BLOCAGE 1`).
    public init(etat: DemoEtabEtatPublication, blocage: Bool = false, horloge: ClockPort = FixedClock(DemoWorld.fixedNow)) {
        self.etat = etat
        self.blocage = blocage
        self.horloge = horloge
    }

    /// Plancher du monde démo : la constante (aucun réseau), après le même contrôle de contexte que l'envoi.
    public func tauxMinimumSalarie(context: EtablissementReadContext) async -> Double? {
        guard (try? DemoEtablissementWorld.verifier(context)) != nil else { return nil }
        return PublicationRules.tauxMinimum
    }

    public func publier(_ brouillon: PublicationMission, context: EtablissementReadContext) async throws -> PublicationOutcome {
        try DemoEtablissementWorld.verifier(context)
        guard PublicationRules.champsInvalides(brouillon).isEmpty else {
            throw JoleneError(.contract, "Brouillon de mission invalide.")
        }
        await etat.journaliser(PublicationPayload(brouillon))
        // Ordre du serveur : blocage de l'établissement, planning, début dans le passé, puis écriture (droit `missions`).
        if blocage { return .blocageEtablissement(code: Self.codeSuspendue, message: Self.messageSuspendue) }
        guard !brouillon.creneaux.isEmpty else { return .refusee(code: nil, message: Self.messageAucunCreneau) }
        let maintenant = horloge.now()
        let debuts = brouillon.creneaux.compactMap { try? DateHeureParis.instantJolene($0.debut) }
        guard debuts.count == brouillon.creneaux.count, let premier = debuts.min() else {
            throw JoleneError(.contract, "Créneau de mission illisible.")
        }
        guard premier >= maintenant else { return .refusee(code: nil, message: Self.messagePasse) }
        guard context.permissions.missions else { return .refusee(code: Self.codeIndisponible, message: Self.messageIndisponible) }
        let id = await etat.creer(brouillon, etablissementId: context.etablissementId, creeLe: DateHeureParis.isoUTC(maintenant))
        guard let relue = await etat.relire(id), PublicationRelecture.confirme(relue, envoi: brouillon.creneaux) else {
            return .nonConfirmee(missionId: id)
        }
        return .publiee(missionId: id)
    }
}
