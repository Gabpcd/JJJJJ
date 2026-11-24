import SwiftUI
import JoleneCore
import JoleneDesign

/// Pool urgence (`/soignant/pool-urgence`, L4-T11), port de `PoolUrgenceSoignant.tsx` et `PoolUrgenceToggle.tsx`, empilé
/// par `SecondaryRouter` une fois son coupe-circuit `ios_natif_pool_urgence_actif` lu (fail-open). Vue de
/// `PoolUrgenceModel` (JoleneCore), qui porte les règles (relecture qui confirme, refus verbatim, planning exact, délai,
/// second appui, session, epoch) ; la vue n'ajoute aucune logique.
///
/// - Carte « Disponibilité urgence » : interrupteur (état relu : un refus le laisse à l'état serveur), puis, pool actif,
///   curseur 5-50 km (envoi à la fin du geste, ou 0,6 s après le dernier pas VoiceOver), SMS, badge, avantages et texte
///   d'engagement, verbatim (`TextesWeb.PoolUrgence`, HARD STOP n°4). Refus « documents » : lien vers les documents.
///   La zone « Ville spécifique » du web n'est pas portée : la ville saisie n'y est enregistrée par aucun appel.
/// - Missions urgentes (ordre serveur) : « J'accepte » ouvre le récapitulatif du planning exact (désactivé sinon) ;
///   statut relu après l'acceptation ; « Voir détail » / « Voir mission » ouvrent le détail de mission du lot 1, seul
///   lieu du choix de contrat quand l'acceptation rapide le demande.
///
/// Identifiants : `pool-screen`, `pool-toggle`, `pool-rayon` (+ `-valeur`), `pool-sms`, `pool-consentement`,
/// `pool-mission-<id>`, `pool-accepter-<id>`, `pool-detail-<id>`, `pool-statut-<id>`, `pool-choix-<id>` ;
/// `pool-chargement`, `pool-erreur` (+ `-reessayer`), `pool-inactif`, `pool-vide`, `pool-compteur`, `pool-avis-erreur`,
/// `pool-confirmation`, `pool-documents`, `pool-session-check` ; récapitulatif `pool-recap` (`-confirm`, `-cancel`).
struct PoolUrgenceScreen: View {
    let contexte: ContexteSecondaire
    @StateObject private var model: PoolUrgenceModel
    @ObservedObject private var session: SessionStore
    @State private var rayon: Double = Double(PoolUrgenceRegles.rayonParDefaut)
    @State private var envoiRayon: Task<Void, Never>?
    @State private var aConfirmer: MissionUrgente?

    init(contexte: ContexteSecondaire) {
        self.contexte = contexte
        self.session = contexte.session
        _model = StateObject(wrappedValue: PoolUrgenceModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(PoolUrgenceTextes.sousTitre)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                if aConfirmer == nil { avis }
                if model.sessionExpiree {
                    JoleneButton("Vérifier ma session", style: .secondary) { Task { await model.verifierSession(session) } }
                        .accessibilityIdentifier("pool-session-check")
                }
                contenu
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(PoolUrgenceTextes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("pool-screen")
        .task { await model.charger() }
        .onChange(of: model.ecran.etat?.rayonKm) { relu in
            rayon = Double(PoolUrgenceRegles.rayonCurseur(relu))
        }
        .confirmationSheet(isPresented: recapPresente, configurationRecap, isLoading: aConfirmer.map { model.occupe($0.id) } ?? false,
                           isConfirmEnabled: aConfirmer?.mission.planningExact ?? false, onConfirm: confirmerAcceptation) {
            if let mission = aConfirmer {
                SlotList(planning: PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(mission: mission.mission)),
                         identifier: "pool-recap-planning", libelle: MissionPresentation.creneau)
                if mission.mission.planningExact {
                    Text(TextesWeb.Candidature.engagementCandidature)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let erreur = model.erreur {
                    InlineNotice(erreur, tone: .error, identifier: "pool-recap-erreur", announcementID: model.jeton)
                }
            }
        }
    }

    // MARK: - Avis

    @ViewBuilder private var avis: some View {
        if let erreur = model.erreur {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(erreur, tone: .error, identifier: "pool-avis-erreur", announcementID: model.jeton)
                if model.documentsManquants {
                    JoleneButton(LibellesCandidature.validerDocuments, style: .secondary) {
                        contexte.ouvrir(.documents(onglet: .justificatifs))
                    }
                    .accessibilityIdentifier("pool-documents")
                }
            }
        } else if let confirmation = model.confirmation {
            InlineNotice(confirmation, tone: .success, identifier: "pool-confirmation", announcementID: model.jeton)
        }
    }

    // MARK: - Contenu

    @ViewBuilder private var contenu: some View {
        switch model.ecran {
        case .chargement:
            SkeletonCard(identifier: "pool-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: "pool-erreur")
                if !model.sessionExpiree {
                    JoleneButton(PoolUrgenceTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                        .accessibilityIdentifier("pool-erreur-reessayer")
                }
            }
        case let .pret(etat):
            carteReglages(etat)
            missions(etat)
        }
    }

    private func carteReglages(_ etat: EtatPool) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            Label(PoolUrgenceTextes.carteTitre, systemImage: "flame.fill")
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            ToggleRow(TextesWeb.PoolUrgence.disponible, description: TextesWeb.PoolUrgence.disponibleDescription,
                      isOn: Binding(get: { model.ecran.etat?.actif ?? false },
                                    set: { valeur in Task { await model.basculer(actif: valeur) } }),
                      isDisabled: model.occupe(PoolUrgenceModel.clePool), identifier: "pool-toggle")
            if etat.actif {
                rayonCurseur
                ToggleRow(TextesWeb.PoolUrgence.smsTitre, description: TextesWeb.PoolUrgence.smsDescription,
                          systemImage: "message",
                          isOn: Binding(get: { model.ecran.etat?.smsOptIn ?? false },
                                        set: { valeur in Task { await model.basculerSMS(valeur) } }),
                          isDisabled: model.occupe(PoolUrgenceModel.cleSMS), identifier: "pool-sms")
                HStack(spacing: JoleneSpacing.sm) {
                    StatusBadge(PoolUrgenceTextes.badge, tone: .error)
                    Text(PoolUrgenceTextes.badgeVisible).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                }
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(PoolUrgenceTextes.avantages).font(JoleneFont.caption.weight(.semibold)).foregroundStyle(JoleneColor.midnight)
                    avantage("star", TextesWeb.PoolUrgence.avantageFiabilite)
                    avantage("shield", PoolUrgenceTextes.avantagePrioritaire)
                    avantage("eye", PoolUrgenceTextes.avantageBadge)
                }
                // Texte d'engagement verbatim (HARD STOP n°4), « +10 points de fiabilité » en gras comme le web.
                (Text(TextesWeb.PoolUrgence.engagementDebut + " ")
                    + Text(TextesWeb.PoolUrgence.engagementPoints).bold()
                    + Text(TextesWeb.PoolUrgence.engagementFin))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(JoleneSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JoleneColor.lavender)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(TextesWeb.PoolUrgence.engagement)
                    .accessibilityIdentifier("pool-consentement")
            }
        }
        .padding(JoleneSpacing.lg)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    private var rayonCurseur: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            (Text(PoolUrgenceTextes.rayonLibelle + " ") + Text(PoolUrgenceTextes.km(Int(rayon))).bold())
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityIdentifier("pool-rayon-valeur")
            Slider(value: $rayon, in: Double(PoolUrgenceRegles.rayonMin)...Double(PoolUrgenceRegles.rayonMax), step: 1)
                .tint(JoleneColor.mauve700)
                .disabled(model.occupe(PoolUrgenceModel.clePool))
                .accessibilityLabel(PoolUrgenceTextes.rayonAccessibilite)
                .accessibilityValue(PoolUrgenceTextes.km(Int(rayon)))
                .accessibilityIdentifier("pool-rayon")
                .onChange(of: rayon) { valeur in
                    // Fin du geste (`onValueCommit` du web) : envoi après 0,6 s sans nouveau pas, geste ou VoiceOver.
                    envoiRayon?.cancel()
                    let cible = Int(valeur)
                    envoiRayon = Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        guard !Task.isCancelled else { return }
                        await model.validerRayon(cible)
                    }
                }
            HStack {
                Text(PoolUrgenceTextes.km(PoolUrgenceRegles.rayonMin))
                Spacer()
                Text(PoolUrgenceTextes.km(PoolUrgenceRegles.rayonMax))
            }
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .accessibilityHidden(true)
        }
    }

    private func avantage(_ icone: String, _ texte: String) -> some View {
        Label(texte, systemImage: icone)
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func missions(_ etat: EtatPool) -> some View {
        if !etat.actif {
            EmptyState(systemImage: "exclamationmark.circle", title: PoolUrgenceTextes.inactifTitre,
                       message: PoolUrgenceTextes.inactifTexte, identifier: "pool-inactif")
        } else if etat.missions.isEmpty {
            EmptyState(systemImage: "checkmark.circle", title: PoolUrgenceTextes.videTitre,
                       message: PoolUrgenceTextes.videTexte(rayon: etat.rayonKm ?? 30), identifier: "pool-vide")
        } else {
            Text(PoolUrgenceTextes.compteur(etat.missions.count))
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("pool-compteur")
            ForEach(etat.missions) { carte($0) }
        }
    }

    private func carte(_ urgente: MissionUrgente) -> some View {
        let mission = urgente.mission
        let occupe = model.occupe(urgente.id)
        return VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(mission.record.intitule)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    Text([mission.etablissement?.nom, mission.record.service].compactMap { $0 }.filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
                Spacer(minLength: 0)
                StatusBadge(PoolUrgenceTextes.urgent, tone: .error)
            }
            SlotList(planning: PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(mission: mission)),
                     identifier: "pool-planning-\(urgente.id)", libelle: MissionPresentation.creneau, limit: 3)
            Text([PoolUrgenceTextes.taux(mission.record.tauxHoraireBase),
                  PoolUrgenceTextes.lieu(ville: mission.etablissement?.adresseVille, distanceKm: mission.distanceKm),
                  MissionPresentation.professionLabel(mission.record.professionRequise)]
                .joined(separator: " · "))
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
            Divider()
            if let statut = PoolUrgenceRegles.libelleStatut(urgente) {
                HStack {
                    Text(statut)
                        .font(JoleneFont.caption.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityIdentifier("pool-statut-\(urgente.id)")
                    Spacer()
                    lienDetail(urgente, titre: PoolUrgenceTextes.voirMission)
                }
            } else {
                if model.choixRequis.contains(urgente.id) {
                    InlineNotice(PoolUrgenceTextes.choixContratRequis, tone: .warning, identifier: "pool-choix-\(urgente.id)")
                }
                HStack {
                    lienDetail(urgente, titre: PoolUrgenceTextes.voirDetail)
                    Spacer()
                    if !model.choixRequis.contains(urgente.id) {
                        JoleneButton(occupe ? PoolUrgenceTextes.acceptationEnCours : PoolUrgenceTextes.accepter, isLoading: occupe) {
                            model.effacerMessages()
                            aConfirmer = urgente
                        }
                        .disabled(occupe || !PoolUrgenceRegles.acceptable(urgente))
                        .fixedSize()
                        .accessibilityIdentifier("pool-accepter-\(urgente.id)")
                    }
                }
            }
        }
        .padding(JoleneSpacing.lg)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pool-mission-\(urgente.id)")
    }

    private func lienDetail(_ urgente: MissionUrgente, titre: String) -> some View {
        Button(titre) { contexte.ouvrir(.mission(id: urgente.id)) }
            .font(JoleneFont.caption.weight(.semibold))
            .foregroundStyle(JoleneColor.mauve700)
            .frame(minHeight: 44)
            .accessibilityIdentifier("pool-detail-\(urgente.id)")
    }

    // MARK: - Récapitulatif

    private var recapPresente: Binding<Bool> {
        Binding(get: { aConfirmer != nil }, set: { if !$0 { aConfirmer = nil } })
    }

    private var configurationRecap: ConfirmationSheet.Configuration {
        ConfirmationSheet.Configuration(
            title: LibellesCandidature.recapTitre,
            message: LibellesCandidature.recapDescription(intitule: aConfirmer?.mission.record.intitule),
            confirmTitle: PoolUrgenceTextes.confirmerAcceptation,
            cancelTitle: LibellesCandidature.recapAnnuler,
            identifier: "pool-recap")
    }

    private func confirmerAcceptation() {
        guard let cible = aConfirmer else { return }
        Task {
            await model.accepter(cible)
            // Le récapitulatif se referme sur toute issue : le résultat (statut relu, refus verbatim) s'affiche sur l'écran.
            aConfirmer = nil
        }
    }
}
