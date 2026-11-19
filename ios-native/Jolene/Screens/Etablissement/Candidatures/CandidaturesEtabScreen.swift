import SwiftUI
import JoleneCore
import JoleneDesign

/// Candidatures d'une mission de l'établissement (lot 5, T6) : vue de `CandidaturesEtabModel`, port de
/// `ListeCandidatures.tsx` (rendue par `DetailMission.tsx`) sur la lecture habilitée. Sections : annonce (succès relu,
/// refus serveur verbatim, paiement, renvoi web), en attente (bandeau de planning bloquant, lien neutre vers les CGV,
/// cartes avec « Accepter » / « Refuser », ou « Accepter sur jolene.app » hors périmètre natif, D10 et D25), traitées.
/// « Accepter » ouvre le récapitulatif (`RecapAcceptationSheet`). Aucun montant, aucune note, aucun statut d'internat,
/// aucune case juridique ; la mention CGV art. 8 verbatim attend la validation HARD STOP n°4 (lien neutre d'ici là).
///
/// Identifiants : `etab-candidatures-screen`, `-loading`, `-error` (+ `-retry`), `-acces-refuse`, `-introuvable`,
/// `-empty`, `-titre`, `-en-attente`, `-planning-bloquant`, `-cgv-lien`, `-traitees`, `-succes`, `-erreur`, `-renvoi`
/// (+ `-renvoi-ouvrir`), `-refresh-error` ; `etab-candidature-{id}`, `etab-candidature-accepter-{id}`,
/// `etab-candidature-refuser-{id}`, `etab-candidature-web-{id}`, `etab-candidature-statut-{id}`,
/// `etab-candidature-paiement` (+ `-ouvrir`).
struct CandidaturesEtabScreen: View {
    @StateObject private var model: CandidaturesEtabModel
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(missionId: String, session: SessionStore, snapshot: EtablissementSessionSnapshot) {
        _model = StateObject(wrappedValue: CandidaturesEtabModel(
            missionId: missionId, controller: session.controller, snapshot: snapshot,
            relirePerimetre: { [weak session] in await session?.refreshEtablissementScope() }))
    }

    private typealias P = CandidaturesEtabPresentation

    var body: some View {
        ScrollView {
            switch model.etat {
            case .chargement:
                ProgressView(P.chargement)
                    .tint(JoleneColor.rose700)
                    .padding(JoleneSpacing.xxl)
                    .accessibilityIdentifier("etab-candidatures-loading")
            case let .echec(message):
                EmptyState(systemImage: "wifi.exclamationmark", title: P.titreErreur, message: message,
                           identifier: "etab-candidatures-error", actionTitle: P.reessayer,
                           actionIdentifier: "etab-candidatures-retry") { Task { await model.charger() } }
            case let .accesRefuse(message):
                EmptyState(systemImage: "lock.shield", title: "Accès non autorisé", message: message,
                           identifier: "etab-candidatures-acces-refuse")
            case .introuvable:
                EmptyState(systemImage: "questionmark.circle", title: EtabMissionsPresentation.introuvableTitre,
                           message: EtabMissionsPresentation.introuvableMessage, identifier: "etab-candidatures-introuvable")
            case .chargee:
                contenu
            }
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-candidatures-screen")
        .navigationTitle(P.titreEcran)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.charger() }
        .sheet(isPresented: recapPresente) {
            if let recap = model.recap {
                RecapAcceptationSheet(recap: recap, intitule: model.lecture?.intitule, enCours: model.enCours != nil,
                                      onCancel: { model.annulerRecapitulatif() },
                                      onConfirm: { Task { await model.confirmerAcceptation() } })
            }
        }
    }

    private var recapPresente: Binding<Bool> {
        Binding(get: { model.recap != nil }, set: { presente in if !presente { model.annulerRecapitulatif() } })
    }

    // MARK: - Contenu

    @ViewBuilder private var contenu: some View {
        let lecture = model.lecture
        VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
            if let erreur = model.erreurRafraichissement {
                InlineNotice(erreur, tone: .error, identifier: "etab-candidatures-refresh-error", announcesOnAppear: true)
            }
            if let intitule = lecture?.intitule, !intitule.isEmpty {
                Text(intitule)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("etab-candidatures-titre")
            }
            annonce
            if (lecture?.candidatures ?? []).isEmpty {
                EmptyState(systemImage: "clock", title: P.videTitre, message: P.videMessage, identifier: "etab-candidatures-empty")
            } else {
                enAttente
                traitees
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var annonce: some View {
        switch model.annonce {
        case nil:
            EmptyView()
        case let .succes(message):
            InlineNotice(message, tone: .success, identifier: "etab-candidatures-succes", announcesOnAppear: true)
        case let .erreur(message):
            InlineNotice(message, tone: .error, identifier: "etab-candidatures-erreur", announcesOnAppear: true)
        case let .paiement(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .warning, identifier: "etab-candidature-paiement", announcesOnAppear: true)
                if let presentateurRenvoiWeb {
                    JoleneButton(P.voirFacturation, style: .secondary) { presentateurRenvoiWeb.presenter(.etablissement(P.urlFacturation)) }
                        .accessibilityIdentifier("etab-candidature-paiement-ouvrir")
                        .accessibilityValue(P.urlFacturation.absoluteString)
                }
            }
        case let .renvoiWeb(_, message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message ?? P.renvoiWebAcceptation, tone: .info, identifier: "etab-candidatures-renvoi", announcesOnAppear: true)
                if let presentateurRenvoiWeb {
                    let url = P.urlAcceptationWeb(missionId: model.missionId)
                    JoleneButton(P.accepterSurWeb, style: .secondary) { presentateurRenvoiWeb.presenter(.etablissement(url)) }
                        .accessibilityIdentifier("etab-candidatures-renvoi-ouvrir")
                        .accessibilityValue(url.absoluteString)
                }
            }
        }
    }

    // MARK: - En attente

    @ViewBuilder private var enAttente: some View {
        let candidatures = model.enAttente
        if !candidatures.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                SectionHeader(P.titreEnAttente(candidatures.count), identifier: "etab-candidatures-en-attente")
                let verification = model.verification
                if let erreur = verification.erreur {
                    InlineNotice(PlanningExactEtab.detailBandeauAConfirmer + "\n" + erreur,
                                 title: PlanningExactEtab.titreBandeauAConfirmer, tone: .warning,
                                 identifier: "etab-candidatures-planning-bloquant")
                }
                if let presentateurRenvoiWeb {
                    Button { presentateurRenvoiWeb.presenter(.etablissement(P.urlCgv)) } label: {
                        Label(P.cgvLienNeutre, systemImage: "safari")
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.rose700)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("etab-candidatures-cgv-lien")
                    .accessibilityValue(P.urlCgv.absoluteString)
                }
                ForEach(candidatures) { candidature in carte(candidature) }
            }
        }
    }

    private func carte(_ candidature: CandidatureHabilitee) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Label(P.nom(candidature.soignant), systemImage: "person")
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
            let badges = P.badges(candidature.soignant)
            if !badges.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: JoleneSpacing.xs) { pastilles(badges) }
                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) { pastilles(badges) }
                }
            }
            if let message = candidature.message, !message.isEmpty {
                Text("\u{201C}\(message)\u{201D}")
                    .font(JoleneFont.callout.italic())
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions(candidature)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JoleneSpacing.md)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-candidature-\(candidature.id)")
    }

    @ViewBuilder private func actions(_ candidature: CandidatureHabilitee) -> some View {
        let enCours = model.enCours == candidature.id
        ViewThatFits(in: .horizontal) {
            HStack(spacing: JoleneSpacing.sm) { boutons(candidature, enCours: enCours) }
            VStack(spacing: JoleneSpacing.sm) { boutons(candidature, enCours: enCours) }
        }
    }

    @ViewBuilder private func boutons(_ candidature: CandidatureHabilitee, enCours: Bool) -> some View {
        if model.motifRenvoiWeb(candidature) != nil {
            if let presentateurRenvoiWeb {
                let url = P.urlAcceptationWeb(missionId: model.missionId)
                JoleneButton(P.accepterSurWeb, style: .secondary) { presentateurRenvoiWeb.presenter(.etablissement(url)) }
                    .accessibilityIdentifier("etab-candidature-web-\(candidature.id)")
                    .accessibilityValue(url.absoluteString)
            }
        } else {
            JoleneButton(P.accepter, style: .primary, isLoading: enCours && model.recap == nil) {
                Task { await model.ouvrirAcceptation(candidatureId: candidature.id) }
            }
            .disabled(!model.peutAccepter(candidature))
            .accessibilityIdentifier("etab-candidature-accepter-\(candidature.id)")
        }
        JoleneButton(P.refuser, style: .destructive) {
            Task { await model.refuser(candidatureId: candidature.id) }
        }
        .disabled(!model.peutRefuser(candidature))
        .accessibilityIdentifier("etab-candidature-refuser-\(candidature.id)")
    }

    // MARK: - Traitées

    @ViewBuilder private var traitees: some View {
        let candidatures = model.traitees
        if !candidatures.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                SectionHeader(P.titreTraitees(candidatures.count), identifier: "etab-candidatures-traitees")
                ForEach(candidatures) { candidature in
                    let statut = P.statut(candidature)
                    HStack(spacing: JoleneSpacing.sm) {
                        Text(P.nom(candidature.soignant))
                            .font(JoleneFont.callout)
                            .foregroundStyle(JoleneColor.midnight)
                        Spacer(minLength: 0)
                        JoleneBadge(statut.texte, tone: MesMissionLigneVue.ton(statut.ton))
                            .accessibilityLabel(statut.texteAccessible)
                            .accessibilityIdentifier("etab-candidature-statut-\(candidature.id)")
                    }
                    .padding(JoleneSpacing.md)
                    .background(JoleneColor.cloud)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("etab-candidature-\(candidature.id)")
                }
            }
        }
    }

    @ViewBuilder private func pastilles(_ badges: [MesMissionsPresentation.Badge]) -> some View {
        ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
            JoleneBadge(badge.texte, tone: MesMissionLigneVue.ton(badge.ton))
                .accessibilityLabel(badge.texteAccessible)
        }
    }
}
