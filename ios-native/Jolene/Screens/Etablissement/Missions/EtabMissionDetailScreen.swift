import SwiftUI
import JoleneCore
import JoleneDesign

/// Détail d'une mission de l'établissement (lot 5, T5) : vue de `EtabMissionDetailModel`, port de la lecture de
/// `DetailMission.tsx` (écran réellement monté par `/etablissement/missions/:id`, correction 15) **sans montant**
/// (D15) ni note (D8). Sections : en-tête (statut, urgence, contrat recherché), informations, planning (exact, à
/// confirmer, ou indisponible), soignant assigné (`fn_soignant_pour_etablissement`), liens vers les écrans voisins
/// (registre T2a : écran natif livré, sinon page web équivalente, D16), actions de gestion du web (modifier,
/// dupliquer, annuler : permission `missions`), historique. Non repris, renvoyés au web avec la page détail : alerte
/// de requalification (D27), terminer la mission, litige, booster, garantie, recommandations, évaluation.
///
/// Identifiants : `etab-mission-detail`, `etab-mission-loading`, `etab-mission-error` (+ `-retry`),
/// `etab-mission-introuvable`, `etab-mission-titre`, `etab-mission-candidatures-attente`, `etab-mission-infos`,
/// `etab-mission-planning` (+ `-creneau-<n>`, `-summary`), `etab-mission-planning-incomplet`,
/// `etab-mission-planning-indisponible`, `etab-mission-soignant` (+ `-nom`, `-attente`, `-indisponible`,
/// `-error`, `-retry`), `etab-mission-lien-{candidatures|pointage|presences|contrat|message}`,
/// `etab-mission-web-{modifier|annuler|dupliquer}`, `etab-mission-historique`, `etab-mission-refresh-error`.
struct EtabMissionDetailScreen: View {
    @StateObject private var model: EtabMissionDetailModel
    private let snapshot: EtablissementSessionSnapshot
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(missionId: String, session: SessionStore, snapshot: EtablissementSessionSnapshot) {
        self.snapshot = snapshot
        _model = StateObject(wrappedValue: EtabMissionDetailModel(missionId: missionId, controller: session.controller,
                                                                  snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            switch model.etat {
            case .chargement:
                ProgressView("Ouverture de la mission")
                    .tint(JoleneColor.rose700)
                    .padding(JoleneSpacing.xxl)
                    .accessibilityIdentifier("etab-mission-loading")
            case let .echec(message):
                EmptyState(systemImage: "wifi.exclamationmark", title: EtabMissionsPresentation.titreErreurDetail, message: message,
                           identifier: "etab-mission-error", actionTitle: "Réessayer",
                           actionIdentifier: "etab-mission-retry") { Task { await model.charger() } }
            case .introuvable:
                EmptyState(systemImage: "questionmark.circle", title: EtabMissionsPresentation.introuvableTitre,
                           message: EtabMissionsPresentation.introuvableMessage, identifier: "etab-mission-introuvable")
            case let .chargee(detail):
                contenu(detail)
            }
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-mission-detail")
        .navigationTitle("Mission")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.charger() }
    }

    // MARK: - Contenu

    private func contenu(_ detail: EtabMissionDetail) -> some View {
        let mission = detail.mission
        let permissions = snapshot.context.permissions
        return VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
            if let erreur = model.erreurRafraichissement {
                InlineNotice(erreur, tone: .error, identifier: "etab-mission-refresh-error", announcesOnAppear: true)
            }
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                Text(mission.intitule)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("etab-mission-titre")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: JoleneSpacing.xs) { pastilles(mission) }
                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) { pastilles(mission) }
                }
            }
            if permissions.candidatures, let attente = EtabMissionsPresentation.candidaturesEnAttente(detail.candidaturesEnAttente) {
                InlineNotice(attente, tone: .warning, identifier: "etab-mission-candidatures-attente")
            }
            carteSection {
                VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                    let sousTitre = EtabMissionsPresentation.sousTitre(mission)
                    if !sousTitre.isEmpty {
                        Text(sousTitre).font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
                    }
                    if let description = mission.description, !description.isEmpty {
                        Text(description).font(JoleneFont.body).foregroundStyle(JoleneColor.midnight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Label(periode(detail), systemImage: "calendar")
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("etab-mission-infos")
            }
            planning(detail)
            soignant(detail)
            liens(detail, permissions: permissions)
            actionsWeb(mission, permissions: permissions)
            if let cree = EtabMissionsPresentation.creeLe(mission) {
                Text(cree)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("etab-mission-historique")
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    /// Période du détail (mois en toutes lettres), sur les créneaux d'un planning exact seulement.
    private func periode(_ detail: EtabMissionDetail) -> String {
        let planifies = CompletudePlanning.analyser(detail.mission.planningAttendu, creneaux: detail.creneaux).creneauxPlanifies
        return EtabMissionsPresentation.periode(detail.mission, creneaux: planifies, moisLong: true)
    }

    @ViewBuilder private func pastilles(_ mission: EtabMissionResume) -> some View {
        let badges = (mission.estUrgente == true ? [EtabMissionsPresentation.badgeUrgence(mission.niveauUrgence)] : [])
            + [MesMissionsPresentation.badgeStatut(mission.statut ?? ""), EtabMissionsPresentation.badgeContrat(mission.typeContratRecherche)]
        ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
            JoleneBadge(badge.texte, tone: MesMissionLigneVue.ton(badge.ton))
        }
    }

    // MARK: - Planning

    @ViewBuilder private func planning(_ detail: EtabMissionDetail) -> some View {
        carteSection {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                SectionHeader("Planning prévu", identifier: "etab-mission-planning-titre")
                switch EtabMissionsPresentation.planning(detail) {
                case let .indisponible(message):
                    InlineNotice(message, tone: .warning, identifier: "etab-mission-planning-indisponible")
                case let .exact(resume, lignes):
                    SlotList(presentation: SlotList.Presentation(items: items(lignes), resume: resume),
                             identifier: "etab-mission-planning")
                case let .aConfirmer(lignes):
                    if !lignes.isEmpty {
                        SlotList(items: items(lignes), identifier: "etab-mission-planning")
                    }
                    InlineNotice(EtabMissionsPresentation.planningAConfirmer + ".", tone: .warning,
                                 identifier: "etab-mission-planning-incomplet")
                }
            }
        }
    }

    private func items(_ lignes: [String]) -> [SlotList.Item] {
        lignes.enumerated().map { index, ligne in SlotList.Item(id: "creneau-\(index + 1)", label: ligne, isPause: false) }
    }

    // MARK: - Soignant

    @ViewBuilder private func soignant(_ detail: EtabMissionDetail) -> some View {
        carteSection {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                SectionHeader("Soignant assigné", identifier: "etab-mission-soignant-titre")
                switch model.soignant {
                case .aucun:
                    Text(EtabMissionsPresentation.enAttenteSoignantDetail)
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityIdentifier("etab-mission-soignant-attente")
                    Text(EtabMissionsPresentation.enAttenteSoignantAide)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                case .chargement:
                    Text("Chargement des informations du soignant…")
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                case .indisponible:
                    Text(EtabMissionsPresentation.soignantIndisponible)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityIdentifier("etab-mission-soignant-indisponible")
                case let .echec(message):
                    InlineNotice(message, tone: .error, identifier: "etab-mission-soignant-error")
                    JoleneButton("Réessayer", style: .secondary) { Task { await model.rechargerSoignant() } }
                        .accessibilityIdentifier("etab-mission-soignant-retry")
                case let .charge(soignant):
                    let fiche = EtabMissionsPresentation.fiche(soignant, statutMission: detail.mission.statut)
                    // Identifiant sur le nom seul : posé sur le `Label`, il est repris par l'icône ET le texte, et
                    // `etab-mission-soignant-nom` désignait d'abord l'image, libellée « person » (iPad portrait, iOS 18.6).
                    // L'icône, décorative, n'est pas annoncée : le nom qui la suit suffit.
                    Label {
                        Text(fiche.nom)
                            .accessibilityIdentifier("etab-mission-soignant-nom")
                    } icon: {
                        Image(systemName: "person")
                            .accessibilityHidden(true)
                    }
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    let ligne = [fiche.profession, fiche.fiabilite].compactMap { $0 }.joined(separator: " · ")
                    if !ligne.isEmpty {
                        Text(ligne).font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
                    }
                    Label(fiche.telephone, systemImage: "phone")
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                    if let rpps = fiche.rpps {
                        Text(rpps).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("etab-mission-soignant")
        }
    }

    // MARK: - Liens et renvois web

    @ViewBuilder private func liens(_ detail: EtabMissionDetail, permissions: PermissionsEtab) -> some View {
        let liens = EtabMissionsPresentation.liens(detail, permissions: permissions)
            .filter { !$0.estWeb || presentateurRenvoiWeb != nil }
        if !liens.isEmpty {
            carteSection {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    ForEach(liens) { lien in
                        switch lien.cible {
                        case let .ecran(destination):
                            NavigationLink(value: destination) { ligneLien(lien.titre, detail: lien.detail, web: false) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(lien.identifiant)
                        case let .web(url):
                            Button { presentateurRenvoiWeb?.presenter(.etablissement(url)) } label: {
                                ligneLien(lien.titre, detail: lien.detail, web: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(lien.identifiant)
                            .accessibilityValue(url.absoluteString)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func actionsWeb(_ mission: EtabMissionResume, permissions: PermissionsEtab) -> some View {
        let actions = EtabMissionsPresentation.actionsWeb(mission, permissions: permissions)
        if let presentateurRenvoiWeb, !actions.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                ForEach(actions) { action in
                    JoleneButton(action.titre, style: .secondary) {
                        presentateurRenvoiWeb.presenter(.etablissement(action.url))
                    }
                    .accessibilityIdentifier(action.identifiant)
                    .accessibilityValue(action.url.absoluteString)
                }
                Text(EtabMissionsPresentation.noteRenvoiWeb)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ligneLien(_ titre: String, detail: String?, web: Bool) -> some View {
        HStack(spacing: JoleneSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(JoleneFont.callout.weight(.semibold)).foregroundStyle(JoleneColor.rose700)
                if let detail { Text(detail).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum) }
            }
            Spacer(minLength: 0)
            Image(systemName: web ? "safari" : "chevron.right")
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func carteSection<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        contenu()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JoleneSpacing.md)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }
}
