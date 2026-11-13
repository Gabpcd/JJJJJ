import SwiftUI
import JoleneCore
import JoleneDesign

/// Détail des présences d'une mission (lot 2, T5a) : vue de `DetailPresencesModel` (JoleneCore), port de
/// `DetailPresencesMission.tsx` pour le soignant. Dérivations et textes testés dans JoleneCore
/// (`PresentationDetailPresencesTests`, `DetailPresencesModelTests`) ; la vue n'ajoute aucune règle.
///
/// Sections dans l'ordre du web : en-tête, synthèse (masquée sur refus serveur), créneaux travaillés par jour, contrôles
/// du pointage, relance de l'établissement (titre et explication verbatim de `TextesWeb.Presences`, HARD STOP n°4 de TL),
/// puis le récapitulatif financier en renvoi web (montants calculés côté client, non portés : LOT2_PLAN §1.2), route
/// forcée web (`PresencesRenvois.recapitulatifFinancier`), rendu seulement avec le présentateur de T10 (jamais un bouton
/// sans effet). Échec de lecture : titres du lot 1 et repli lisible (`LibellesDetailPresences.Echec`).
///
/// Point d'extension T5b : le panneau de contestation d'une présence validée se monte sous la section des contrôles
/// (`ContestationSheet`), après le go HARD STOP n°4 (Q9) ; rien n'est rendu ici d'ici là.
struct DetailPresencesScreen: View {
    @StateObject private var model: DetailPresencesModel
    @ObservedObject private var session: SessionStore
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @Environment(\.scenePhase) private var scenePhase

    init(missionId: String, session: SessionStore, snapshot: SessionSnapshot) {
        self.session = session
        _model = StateObject(wrappedValue: DetailPresencesModel(missionId: missionId, controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                switch model.etat {
                case .chargement:
                    chargement
                case .introuvable:
                    EmptyState(systemImage: "questionmark.circle", title: LibellesWeb.DetailPresences.introuvableTitre,
                               message: LibellesWeb.DetailPresences.introuvableMessage, identifier: "presence-detail-introuvable")
                case let .echec(message) where model.sessionExpired:
                    EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: LibellesDetailPresences.Echec.sessionAVerifier,
                               message: LibellesDetailPresences.Echec.message(message, sessionExpiree: true),
                               identifier: "presence-detail-session-expired",
                               actionTitle: LibellesDetailPresences.Echec.verifierMaSession,
                               actionIdentifier: "presence-detail-session-check") {
                        Task { await model.verifierSession(session) }
                    }
                case let .echec(message):
                    EmptyState(systemImage: "exclamationmark.triangle", title: LibellesPresences.Liste.erreurTitre,
                               message: LibellesDetailPresences.Echec.message(message, sessionExpiree: false),
                               identifier: "presence-detail-error",
                               actionTitle: LibellesWeb.ListePresences.reessayer, actionIdentifier: "presence-detail-retry") {
                        Task { await model.charger() }
                    }
                case let .pret(presentation):
                    contenu(presentation)
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .accessibilityIdentifier("presence-detail-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(LibellesWeb.DetailPresences.syntheseTitre)
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.presentation == nil { await model.charger() } }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.charger() } }
        }
    }

    private var chargement: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            SkeletonBlock(size: .lg, width: 240)
            SkeletonCard()
            SkeletonCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presence-detail-loading")
    }

    @ViewBuilder
    private func contenu(_ p: PresentationDetailPresences) -> some View {
        entete(p.entete)
        if let synthese = p.synthese { carteSynthese(synthese) }
        segments(p)
        if let controles = p.controles { carteControles(controles) }
        if p.relanceProposee { relance }
        recapitulatifFinancier
    }

    // MARK: - En-tête

    private func entete(_ entete: PresentationDetailPresences.Entete) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            if let intitule = entete.intitule {
                Text(intitule)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let service = entete.service {
                Text(service).font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
            }
            Text(entete.periode).font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            if let heures = entete.heures {
                Text(heures).font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
            }
            Text(entete.progression).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, JoleneSpacing.xs)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presence-detail-entete")
    }

    // MARK: - Synthèse

    private func carteSynthese(_ synthese: PresentationDetailPresences.Synthese) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            titreSection(LibellesWeb.DetailPresences.syntheseTitre, symbole: "clock")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .topLeading)], alignment: .leading,
                      spacing: JoleneSpacing.sm) {
                ForEach(synthese.valeurs) { valeur in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(valeur.titre).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                        Text(valeur.valeur).font(JoleneFont.callout.weight(.semibold)).foregroundStyle(Self.couleur(valeur.ton))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("presence-detail-synthese-\(valeur.id)")
                }
            }
            if let bilan = synthese.bilan { note(bilan) }
            if let cloture = synthese.cloture { note(cloture) }
            ForEach(synthese.alertes, id: \.self) { alerte in
                Text(alerte).font(JoleneFont.callout.weight(.medium)).foregroundStyle(JoleneColor.rose800)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.card)
            .strokeBorder(synthese.alertes.isEmpty ? Color.clear : JoleneColor.rose700, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presence-detail-synthese")
    }

    // MARK: - Créneaux travaillés

    @ViewBuilder
    private func segments(_ p: PresentationDetailPresences) -> some View {
        titreSection(p.titreSegments, symbole: "clock")
            .accessibilityIdentifier("presence-detail-segments-titre")
        if p.jours.isEmpty {
            Text(LibellesWeb.DetailPresences.aucunSegment)
                .font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
                .frame(maxWidth: .infinity)
                .padding(JoleneSpacing.lg)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                .accessibilityIdentifier("presence-detail-aucun-segment")
        } else {
            let numeros = Self.numeros(p.jours)
            ForEach(p.jours) { jour in
                VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                    Text(jour.titre).font(JoleneFont.callout.weight(.semibold)).foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(jour.segments) { segment in
                        carteSegment(segment, numero: numeros[segment.id] ?? 0)
                    }
                }
                .padding(JoleneSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            }
        }
    }

    private func carteSegment(_ segment: PresentationDetailPresences.Segment, numero: Int) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            if let etiquette = segment.etiquette {
                Text(etiquette).font(JoleneFont.caption.weight(.semibold)).foregroundStyle(JoleneColor.bubblegum)
                    .textCase(.uppercase)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let interruption = segment.interruption { note(interruption) }
            if let horaire = segment.horairePrevu {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LibellesWeb.DetailPresences.horairePrevu).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                    Text(horaire).font(JoleneFont.caption.weight(.medium)).foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(segment.ecarts, id: \.texte) { ecart in
                        Text(ecart.texte).font(JoleneFont.caption).foregroundStyle(Self.couleur(ecart.ton))
                    }
                }
                .padding(JoleneSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JoleneColor.lavender)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
            } else if let sansHoraire = segment.sansHoraire {
                note(sansHoraire)
            }
            Text(segment.arrivee).font(JoleneFont.callout.weight(.semibold)).foregroundStyle(JoleneColor.midnight)
            Text(segment.depart).font(segment.departPointe ? JoleneFont.callout.weight(.semibold) : JoleneFont.caption)
                .foregroundStyle(segment.departPointe ? JoleneColor.midnight : JoleneColor.butter800)
            if let duree = segment.duree {
                Text(duree).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            }
            Divider()
            Text(segment.validation).font(JoleneFont.caption.weight(.medium)).foregroundStyle(Self.couleur(segment.tonValidation))
        }
        .padding(JoleneSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(Self.bordure(segment.ton), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presence-detail-segment-\(numero)")
    }

    // MARK: - Contrôles, relance, récapitulatif

    private func carteControles(_ controles: PresentationDetailPresences.Controles) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            titreSection(LibellesWeb.DetailPresences.controlesTitre, symbole: nil)
            ForEach(controles.lignes) { ligne in
                HStack(spacing: JoleneSpacing.xs) {
                    Image(systemName: ligne.id == "distance" ? "mappin.and.ellipse" : "dot.radiowaves.left.and.right")
                        .accessibilityHidden(true)
                    Text(ligne.texte)
                    if let perimetre = ligne.perimetre {
                        Image(systemName: perimetre ? "checkmark.circle" : "xmark.circle").accessibilityHidden(true)
                    }
                }
                .font(JoleneFont.caption)
                .foregroundStyle(Self.couleur(ligne.ton))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("presence-detail-controle-\(ligne.id)")
            }
            if controles.alerteTeleportation {
                Label(LibellesWeb.DetailPresences.alerteTeleportationControle, systemImage: "exclamationmark.triangle")
                    .font(JoleneFont.caption.weight(.medium))
                    .foregroundStyle(JoleneColor.rose800)
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presence-detail-controles")
    }

    private var relance: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(TextesWeb.Presences.relanceTitre).font(JoleneFont.callout.weight(.medium)).foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
            Text(TextesWeb.Presences.relanceExplication).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            if let retour = model.retourRelance {
                InlineNotice(retour.message, tone: retour.succes ? .success : .error, identifier: "presence-relance-retour",
                             announcesOnAppear: true)
            }
            JoleneButton(model.relanceEnCours ? LibellesWeb.Presences.relanceEnvoi : LibellesWeb.Presences.relancer,
                         style: .secondary, isLoading: model.relanceEnCours) {
                Task { await model.relancer() }
            }
            .disabled(model.relanceEnCours)
            .accessibilityIdentifier("presence-relancer")
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.butter100)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presence-relance")
    }

    @ViewBuilder
    private var recapitulatifFinancier: some View {
        // Route forcée web (`PresencesRenvois.recapitulatifFinancier`) : elle ne disparaît pas quand T10 rend native la
        // route de cet écran ; le bouton n'apparaît qu'avec le présentateur `.safari` (jamais un bouton sans effet).
        if let presentateurRenvoiWeb, let route = PresencesRenvois.recapitulatifFinancier(missionId: model.missionId) {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                titreSection(LibellesWeb.DetailPresences.recapitulatifFinancier, symbole: nil)
                JoleneButton(LibellesDetailPresences.voirSurLeWeb, style: .secondary) { presentateurRenvoiWeb.presenter(route) }
                    .accessibilityIdentifier("presence-revenus-web")
            }
            .padding(JoleneSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        }
    }

    // MARK: - Outils

    private func titreSection(_ texte: String, symbole: String?) -> some View {
        HStack(spacing: JoleneSpacing.xs) {
            if let symbole {
                Image(systemName: symbole).foregroundStyle(JoleneColor.rose700).accessibilityHidden(true)
            }
            Text(texte).font(JoleneFont.headline).foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func note(_ texte: String) -> some View {
        Text(texte).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum).fixedSize(horizontal: false, vertical: true)
    }

    /// Numéro d'ordre (1…n) de chaque segment, tous jours confondus (identifiants `presence-detail-segment-<n>`).
    private static func numeros(_ jours: [PresentationDetailPresences.Jour]) -> [String: Int] {
        var numeros: [String: Int] = [:]
        for (index, segment) in jours.flatMap(\.segments).enumerated() { numeros[segment.id] = index + 1 }
        return numeros
    }

    private static func couleur(_ ton: PresentationDetailPresences.Ton) -> Color {
        switch ton {
        case .neutre: return JoleneColor.midnight
        case .succes: return JoleneColor.cyan900
        case .attention: return JoleneColor.butter800
        case .alerte: return JoleneColor.rose800
        case .accent: return JoleneColor.mauve800
        }
    }

    private static func bordure(_ ton: PresentationDetailPresences.Ton) -> Color {
        switch ton {
        case .neutre: return JoleneColor.rose100
        case .succes: return JoleneColor.cyan700
        case .attention: return JoleneColor.butter700
        case .alerte: return JoleneColor.rose700
        case .accent: return JoleneColor.mauve700
        }
    }
}
