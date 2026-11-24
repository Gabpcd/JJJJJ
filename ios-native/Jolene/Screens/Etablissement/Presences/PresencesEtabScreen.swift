import SwiftUI
import JoleneCore
import JoleneDesign

/// Présences de l'établissement (lot 5, T8, **B9 paiements/escrow**) : vue de `PresencesEtabModel` (JoleneCore), port de
/// `PresencesEtablissement.tsx` et de `CarteValidation.tsx`. Onglets à valider / en cours / validées / alertes dérivés
/// des créneaux relus et de l'horloge, cartes (prévu, réel, alertes, litige), validation avec note
/// (`ValidationPresenceSheet`), validation en lot, contestation (`ContestationEtabSheet`), clôture d'un segment ouvert
/// (`ClotureSegmentSheet`), missions terminées sans pointage. Avec `missionId` (destination `.presencesMission` du
/// registre), seules les présences de cette mission sont listées, sans onglets ni lot.
///
/// La vue n'ajoute aucune règle : onglets, textes et actions viennent du modèle (`PresencesEtabModelTests`,
/// `PresencesEtabRulesTests`). « Validée » n'est jamais affichée avant la relecture ; aucun montant, aucune durée
/// facturée. Les actions n'existent qu'avec la permission `pointage` servie par le serveur.
///
/// Identifiants : `etab-presences-screen`, `etab-presences-scroll`, `etab-presences-tabs`,
/// `etab-presences-tab-{a_valider|en_cours|validees|alertes}`, `etab-presences-loading`, `-error` (+ `-retry`), `-empty`,
/// `-refresh-error`, `-succes`, `-avertissement`, `-erreur`, `etab-presences-lot` (+ `-resume`, `-confirmer`, `-annuler`,
/// `-resultat`), `etab-presences-sans-pointage`, `etab-presence-sans-pointage-{missionId}`, `etab-presence-{id}`,
/// `etab-presence-statut-{id}`, `etab-presence-alerte-{id}-{teleportation|hors_zone|gps_truque}`,
/// `etab-presence-litige-{id}`, `etab-presence-valider-{id}`, `etab-presence-contester-{id}`,
/// `etab-presence-cloturer-{missionId}`, `etab-presence-note-refus`.
struct PresencesEtabScreen: View {
    @StateObject private var model: PresencesEtabModel
    private let snapshot: EtablissementSessionSnapshot
    /// Onglet demandé par un lien (`?tab=`, T2b) ; chaque nouveau jeton sélectionne l'onglet.
    private let demande: DemandeOngletPresences

    init(missionId: String? = nil, session: SessionStore, snapshot: EtablissementSessionSnapshot,
         demande: DemandeOngletPresences = DemandeOngletPresences()) {
        self.snapshot = snapshot
        self.demande = demande
        _model = StateObject(wrappedValue: PresencesEtabModel(
            missionId: missionId, onglet: demande.onglet, controller: session.controller, snapshot: snapshot,
            relirePerimetre: { [weak session] in await session?.refreshEtablissementScope() }))
    }

    private typealias P = PresencesEtabPresentation
    /// Cadence du web (`PresencesEtablissement.tsx` l.186) : les onglets suivent l'heure sans relecture.
    private static let cadenceHorloge: UInt64 = 30_000_000_000

    var body: some View {
        VStack(spacing: 0) {
            if model.missionId == nil { onglets }
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                    contenu
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.charger() }
            .accessibilityIdentifier("etab-presences-scroll")
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-presences-screen")
        .navigationTitle(P.titreEcran)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.charger() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.cadenceHorloge)
                model.actualiserHorloge()
            }
        }
        // Permissions relues à epoch constant (refus de droit) : les actions sont re-filtrées sans reconstruire l'écran.
        .onAppear { model.adopter(snapshot.context) }
        .onChange(of: snapshot.context) { contexte in model.adopter(contexte) }
        .onChange(of: demande.jeton) { _ in model.selectionner(OngletPresencesEtab(parametre: demande.onglet)) }
        .sheet(isPresented: validationPresentee) { ValidationPresenceSheet(model: model) }
        .sheet(isPresented: contestationPresentee) { ContestationEtabSheet(model: model) }
        .sheet(isPresented: cloturePresentee) { ClotureSegmentSheet(model: model) }
        .sheet(isPresented: lotPresente) { LotPresencesSheet(model: model) }
    }

    private var validationPresentee: Binding<Bool> {
        Binding(get: { model.validation != nil }, set: { presentee in if !presentee { model.annulerValidation() } })
    }

    private var contestationPresentee: Binding<Bool> {
        Binding(get: { model.contestation != nil }, set: { presentee in if !presentee { model.annulerContestation() } })
    }

    private var cloturePresentee: Binding<Bool> {
        Binding(get: { model.cloture != nil }, set: { presentee in if !presentee { model.annulerCloture() } })
    }

    private var lotPresente: Binding<Bool> {
        Binding(get: { model.lotOuvert }, set: { presente in if !presente { model.annulerLot() } })
    }

    // MARK: - Onglets

    private var onglets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JoleneSpacing.sm) {
                ForEach(OngletPresencesEtab.allCases) { onglet in
                    FilterChip(P.libelle(onglet, nombre: model.nombre(onglet)), isSelected: model.onglet == onglet,
                               identifier: "etab-presences-tab-\(onglet.rawValue)") {
                        model.selectionner(onglet)
                    }
                }
            }
            .padding(.horizontal, JoleneSpacing.lg)
            .padding(.vertical, JoleneSpacing.sm)
        }
        .background(JoleneColor.cloud)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-presences-tabs")
    }

    // MARK: - États

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .chargement:
            ProgressView(P.chargement)
                .tint(JoleneColor.rose700)
                .frame(maxWidth: .infinity)
                .padding(JoleneSpacing.xxl)
                .accessibilityIdentifier("etab-presences-loading")
        case let .echec(message):
            EmptyState(systemImage: "wifi.exclamationmark", title: P.titreErreur, message: message,
                       identifier: "etab-presences-error", actionTitle: P.reessayer,
                       actionIdentifier: "etab-presences-retry") { Task { await model.charger() } }
        case .chargee:
            liste
        }
    }

    @ViewBuilder private var liste: some View {
        let repartition = model.repartition
        let visibles = model.missionId == nil ? repartition.presences(model.onglet) : model.presences
        if let erreur = model.erreurRafraichissement {
            InlineNotice(erreur, tone: .error, identifier: "etab-presences-refresh-error", announcesOnAppear: true)
        }
        annonce
        if model.missionId == nil, model.onglet == .aValider, model.peutAgir, !repartition.aValider.isEmpty {
            blocLot(aValider: repartition.aValider.count, eligibles: repartition.sansAlerte.count)
        }
        if !model.missionsSansPointage.isEmpty, model.missionId != nil || model.onglet == .alertes {
            sansPointage
        }
        if visibles.isEmpty {
            let vide = P.etatVide(model.onglet, sansPointage: !model.missionsSansPointage.isEmpty)
            EmptyState(systemImage: "checkmark.seal", title: vide.titre, message: vide.message, identifier: "etab-presences-empty")
        } else {
            ForEach(visibles) { presence in carte(model.carte(presence)) }
        }
    }

    @ViewBuilder private var annonce: some View {
        switch model.annonce {
        case nil:
            EmptyView()
        case let .succes(message):
            InlineNotice(message, tone: .success, identifier: "etab-presences-succes", announcesOnAppear: true)
        case let .avertissement(message):
            InlineNotice(message, tone: .warning, identifier: "etab-presences-avertissement", announcesOnAppear: true)
        case let .erreur(message):
            InlineNotice(message, tone: .error, identifier: "etab-presences-erreur", announcesOnAppear: true)
        case let .lot(message, complet):
            InlineNotice(message, tone: complet ? .success : .warning, identifier: "etab-presences-lot-resultat", announcesOnAppear: true)
        }
        if let avis = model.avisNote {
            InlineNotice(avis, tone: .warning, identifier: "etab-presence-note-refus", announcesOnAppear: true)
        }
    }

    // MARK: - Lot et missions sans pointage

    private func blocLot(aValider: Int, eligibles: Int) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(P.lotResume(aValider))
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityIdentifier("etab-presences-lot-resume")
            JoleneButton(P.lotBouton(eligibles), style: .primary, isLoading: model.enCours == PresencesEtabModel.jetonLot) {
                model.ouvrirLot()
            }
            .disabled(eligibles == 0 || model.enCours != nil)
            .accessibilityIdentifier("etab-presences-lot")
            Text(P.lotNote)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JoleneSpacing.md)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    private var sansPointage: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            InlineNotice(P.sansPointageMessage, title: P.sansPointageTitre, tone: .error, identifier: "etab-presences-sans-pointage")
            // Depuis l'onglet seulement : la destination `.presencesMission` est déjà empilée sur le détail de sa mission.
            if model.missionId == nil {
                ForEach(model.missionsSansPointage) { mission in
                    NavigationLink(value: EtabDestination.detailMission(id: mission.id)) {
                        HStack(spacing: JoleneSpacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mission.intitule)
                                    .font(JoleneFont.callout.weight(.semibold))
                                    .foregroundStyle(JoleneColor.midnight)
                                    .multilineTextAlignment(.leading)
                                Text(P.periodeSansPointage(mission))
                                    .font(JoleneFont.caption)
                                    .foregroundStyle(JoleneColor.bubblegum)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(JoleneFont.caption)
                                .foregroundStyle(JoleneColor.bubblegum)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(JoleneSpacing.md)
                        .background(JoleneColor.cloud)
                        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("etab-presence-sans-pointage-\(mission.id)")
                }
            }
        }
    }

    // MARK: - Carte

    private func carte(_ carte: PresencesEtabPresentation.Carte) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(carte.titre)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                    if !carte.sousTitre.isEmpty {
                        Text(carte.sousTitre)
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                JoleneBadge(carte.statut.texte, tone: MesMissionLigneVue.ton(carte.statut.ton))
                    .accessibilityIdentifier("etab-presence-statut-\(carte.id)")
            }
            if !carte.alertes.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: JoleneSpacing.xs) { pastilles(carte) }
                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) { pastilles(carte) }
                }
            }
            ligne(carte.prevu, carte.prevuDetail)
            if let reel = carte.reel, let detail = carte.reelDetail {
                ligne(reel, detail)
                if let periode = carte.reelPeriode { texteSecondaire(periode) }
            }
            ForEach(carte.detailsAlertes, id: \.self) { detail in
                Label(detail, systemImage: "exclamationmark.triangle")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.butter800)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let litige = carte.litige {
                InlineNotice(litige, tone: .warning, identifier: "etab-presence-litige-\(carte.id)")
            }
            if let explication = carte.explication { texteSecondaire(explication) }
            if model.peutAgir { actions(carte) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JoleneSpacing.md)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-presence-\(carte.id)")
    }

    private func ligne(_ titre: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
            Text(detail)
                .font(JoleneFont.callout.weight(.medium))
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func texteSecondaire(_ texte: String) -> some View {
        Text(texte)
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func pastilles(_ carte: PresencesEtabPresentation.Carte) -> some View {
        ForEach(carte.alertes) { alerte in
            JoleneBadge(alerte.badge.texte, tone: MesMissionLigneVue.ton(alerte.badge.ton))
                .accessibilityIdentifier("etab-presence-alerte-\(carte.id)-\(alerte.cle.rawValue)")
        }
    }

    @ViewBuilder private func actions(_ carte: PresencesEtabPresentation.Carte) -> some View {
        if carte.aValider {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: JoleneSpacing.sm) { boutons(carte) }
                VStack(spacing: JoleneSpacing.sm) { boutons(carte) }
            }
        }
        if carte.segmentOuvert {
            Button { model.ouvrirCloture(missionId: carte.missionId) } label: {
                Text(P.clotureProposer)
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose700)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(model.enCours != nil)
            .accessibilityIdentifier("etab-presence-cloturer-\(carte.missionId)")
        }
    }

    @ViewBuilder private func boutons(_ carte: PresencesEtabPresentation.Carte) -> some View {
        JoleneButton(P.valider, style: .primary) { model.ouvrirValidation(presenceId: carte.id) }
            .disabled(model.enCours != nil)
            .accessibilityIdentifier("etab-presence-valider-\(carte.id)")
        JoleneButton(P.contester, style: .destructive) { model.ouvrirContestation(presenceId: carte.id) }
            .disabled(model.enCours != nil)
            .accessibilityIdentifier("etab-presence-contester-\(carte.id)")
    }
}

/// Onglet demandé par un lien vers la page (`/etablissement/presences?tab=…`, `CibleEtablissement.ongletPresences`) :
/// `jeton` avance à chaque demande, même répétée, pour que l'écran déjà monté la rejoue.
struct DemandeOngletPresences: Equatable {
    var onglet: String?
    var jeton = 0
}

/// Confirmation de la validation en lot (`ModalConfirmation` du web, `PresencesEtablissement.tsx` l.608-615) : seules
/// les présences sans alerte sont concernées ; fermeture et second envoi interdits pendant l'appel.
struct LotPresencesSheet: View {
    @ObservedObject var model: PresencesEtabModel

    private typealias P = PresencesEtabPresentation

    var body: some View {
        let nombre = model.lotEligibles.count
        let enCours = model.enCours != nil
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(P.lotTitre(nombre))
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("etab-presences-lot-titre")
                Text(P.lotMessage)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                JoleneButton(P.lotConfirmer(nombre), style: .primary, isLoading: enCours) {
                    Task { await model.confirmerLot() }
                }
                .disabled(enCours || nombre == 0)
                .accessibilityIdentifier("etab-presences-lot-confirmer")
                JoleneButton(P.annuler, style: .secondary) { model.annulerLot() }
                    .disabled(enCours)
                    .accessibilityIdentifier("etab-presences-lot-annuler")
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.cloud.ignoresSafeArea())
        .interactiveDismissDisabled(enCours)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-presences-lot-feuille")
    }
}
