import SwiftUI
import JoleneCore
import JoleneDesign

/// Point d'extension « zone de pointage » (blueprint lot 2 §3 T4b) : saisie des six chiffres, QR, consentement GPS,
/// position, hors ligne. Câblé par T4b (`FabriqueZonePointageNative`, `PointageCodeView.swift`), injecté dans
/// l'environnement (`.environment(\.fabriqueZonePointage, …)`) au-dessus des onglets par `MainTabView`, avec l'`Appareil`
/// réel ou démo d'`AppContainer`. La vue rendue possède le `PointageModel` de la mission (`@StateObject`, cycle de vie de
/// la consigne T4b de `DECISIONS_LOT2.md`) et traduit chaque `PointageModel.Issue` en libellé web.
///
/// Sans fabrique ni services de la page (`ServicesPointage`), un bloc pointable n'affiche aucune zone : jamais un bouton
/// sans effet (CLAUDE.md, « un gap connu reste verrouillé ») ; l'encart provisoire de T4a est retiré.
@MainActor
protocol FabriqueZonePointage: AnyObject, Sendable {
    func zone(pour contexte: ZonePointageContexte) -> AnyView
}

/// Ce que la zone reçoit du bloc : la mission (identifiant et fin prévue, pour `PointageModel` et la notation), l'action
/// que la fenêtre ouvre, la session de l'écran ; T4b : l'horloge des blocs (libellé de l'action, décision 25 ; fixée en
/// démo) et les services de la page (`ServicesPointage` : consentement, réseau, relecture des présences, m1).
struct ZonePointageContexte {
    let missionId: String
    let finLe: String
    let action: EtatDisponibilitePointage.Action?
    let session: SessionStore
    let snapshot: SessionSnapshot
    let horloge: any ClockPort
    let services: ServicesPointage?
}

private struct FabriqueZonePointageKey: EnvironmentKey {
    static let defaultValue: (any FabriqueZonePointage)? = nil
}

extension EnvironmentValues {
    /// Fabrique de la zone de pointage, `nil` tant que T4b ne l'a pas câblée.
    var fabriqueZonePointage: (any FabriqueZonePointage)? {
        get { self[FabriqueZonePointageKey.self] }
        set { self[FabriqueZonePointageKey.self] = newValue }
    }
}

/// Bloc de pointage d'une mission des onglets Aujourd'hui et Actives (port de `BlocPointageMission.tsx`) : carte de la
/// mission, puis la zone de pointage quand la fenêtre est ouverte, sinon le motif du web. État dérivé de
/// `BlocPointageAffichage` (JoleneCore, `PresencesAffichageTests`), réévalué toutes les 30 s sur l'horloge de l'appareil
/// (l.38-42, décision 25 ; horloge fixée en démo). Textes : `LibellesWeb.BlocPointage`, `LibellesPresences.Bloc`.
///
/// La carte n'ouvre pas le détail de la mission (le web navigue vers `/soignant/missions/:id`, l.57) : les points
/// d'entrée entre présences et détail de mission sont la tranche T5a. « Voir le contrat » ouvre le contrat natif
/// (`ContratsDestination.contrat`, T9a ; bascule par T4b, le contrat démo de la mission c étant désormais dans
/// `demo-contrats.json`).
struct BlocPointageView: View {
    let mission: MissionPresenceEnrichie<MissionPresenceLue, EtablissementSummary>
    let contrat: ContratPointage?
    let horloge: any ClockPort
    let session: SessionStore
    let snapshot: SessionSnapshot
    @Environment(\.fabriqueZonePointage) private var fabriqueZonePointage
    @Environment(\.servicesPointage) private var servicesPointage

    private var missionId: String { mission.mission.id }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let affichage = BlocPointageAffichage.evaluer(mission, contrat: contrat, maintenant: horloge.now())
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                carte
                if case let .pointable(action) = affichage {
                    zone(action)
                } else if let textes = LibellesPresences.Bloc.textes(affichage) {
                    motif(textes, affichage: affichage)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pointage-bloc-\(missionId)")
    }

    private var carte: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            if let intitule = mission.mission.intitule {
                Text(intitule)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LigneEtablissement(texte: LibellesPresences.Liste.etablissement(mission.etablissement))
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    @ViewBuilder
    private func zone(_ action: EtatDisponibilitePointage.Action?) -> some View {
        if let fabriqueZonePointage {
            fabriqueZonePointage.zone(pour: ZonePointageContexte(missionId: missionId, finLe: mission.mission.finLe, action: action,
                                                                session: session, snapshot: snapshot, horloge: horloge,
                                                                services: servicesPointage))
        }
    }

    private func motif(_ textes: LibellesPresences.Bloc.Textes, affichage: BlocPointageAffichage) -> some View {
        HStack(alignment: .top, spacing: JoleneSpacing.md) {
            Image(systemName: estContrat(affichage) ? "exclamationmark.triangle" : "calendar.badge.clock")
                .font(JoleneFont.headline)
                .foregroundStyle(estContrat(affichage) ? JoleneColor.butter700 : JoleneColor.rose700)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Text(textes.titre)
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(textes.details.enumerated()), id: \.offset) { _, detail in
                    Text(detail)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                }
                voirLeContrat(affichage)
            }
            Spacer(minLength: 0)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.card)
            .strokeBorder(JoleneColor.rose100, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pointage-indisponible-\(missionId)")
    }

    /// « Voir le contrat » (l.90-99) : seulement quand un contrat est retenu par `choisirContratPointage` ; ouvre le contrat
    /// natif (`navigate(`/contrat/${contrat.id}`)` du web, l.95).
    @ViewBuilder
    private func voirLeContrat(_ affichage: BlocPointageAffichage) -> some View {
        if case let .contratNonSigne(contratId?, _) = affichage {
            NavigationLink {
                ContratsDestination.contrat(session: session, snapshot: snapshot, contratId: contratId)
            } label: {
                Text(LibellesWeb.BlocPointage.voirLeContrat)
                    .font(JoleneFont.button)
                    .foregroundStyle(JoleneColor.rose700)
                    .padding(.horizontal, JoleneSpacing.md)
                    .frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.rose700, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pointage-voir-contrat-\(missionId)")
            .padding(.top, JoleneSpacing.xs)
        }
    }

    private func estContrat(_ affichage: BlocPointageAffichage) -> Bool {
        if case .contratNonSigne = affichage { return true }
        return false
    }
}

/// Établissement d'une ligne (« 🏥 » du web rendu par un symbole, masqué à VoiceOver).
struct LigneEtablissement: View {
    let texte: String

    var body: some View {
        HStack(spacing: JoleneSpacing.xs) {
            Image(systemName: "building.2")
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityHidden(true)
            Text(texte)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
