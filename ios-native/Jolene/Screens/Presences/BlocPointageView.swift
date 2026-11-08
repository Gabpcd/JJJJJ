import SwiftUI
import JoleneCore
import JoleneDesign

/// Point d'extension « zone de pointage » (blueprint lot 2 §3 T4b) : saisie des six chiffres, QR, consentement GPS,
/// position, hors ligne. T4b le câble en injectant sa fabrique dans l'environnement
/// (`.environment(\.fabriqueZonePointage, …)`) au-dessus des onglets, avec l'`Appareil` réel ou démo d'`AppContainer`.
/// La vue rendue possède le `PointageModel` de la mission (`@StateObject`, cycle de vie de la consigne T4b de
/// `DECISIONS_LOT2.md` : `.task { await model.charger(); await model.suivre() }`, `desactiver()` à la disparition,
/// `reconcilier()` au retour au premier plan) et traduit chaque `PointageModel.Issue` en libellé web.
///
/// Tant qu'aucune fabrique n'est injectée, un bloc pointable n'affiche qu'un encart provisoire
/// (`pointage-zone-provisoire-<mission>`, `LibellesPresences.Provisoire.pointage`) : jamais un bouton sans effet
/// (CLAUDE.md, « un gap connu reste verrouillé »). Verrou du gap : `DemoPresencesTests` affirme aujourd'hui cet encart ;
/// T4b le remplace par sa zone et migre ces assertions vers ses identifiants (`pointage-code-<mission>`…).
@MainActor
protocol FabriqueZonePointage: AnyObject, Sendable {
    func zone(pour contexte: ZonePointageContexte) -> AnyView
}

/// Ce que la zone reçoit du bloc : la mission (identifiant et fin prévue, pour `PointageModel` et la notation), l'action
/// que la fenêtre ouvre, et la session de l'écran.
struct ZonePointageContexte {
    let missionId: String
    let finLe: String
    let action: EtatDisponibilitePointage.Action?
    let session: SessionStore
    let snapshot: SessionSnapshot
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
/// d'entrée entre présences et détail de mission sont la tranche T5a. « Voir le contrat » ouvre le contrat natif à
/// T9a ; d'ici là, le renvoi web `/contrat/:id`, rendu seulement avec le présentateur de T10.
struct BlocPointageView: View {
    let mission: MissionPresenceEnrichie<MissionPresenceLue, EtablissementSummary>
    let contrat: ContratPointage?
    let horloge: any ClockPort
    let session: SessionStore
    let snapshot: SessionSnapshot
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @Environment(\.fabriqueZonePointage) private var fabriqueZonePointage

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
                                                                session: session, snapshot: snapshot))
        } else {
            InlineNotice(LibellesPresences.Provisoire.pointage, title: LibellesPresences.Provisoire.etat, tone: .info,
                         identifier: "pointage-zone-provisoire-\(missionId)")
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

    /// « Voir le contrat » (l.90-99) : seulement quand un contrat est retenu et qu'un renvoi peut être présenté.
    @ViewBuilder
    private func voirLeContrat(_ affichage: BlocPointageAffichage) -> some View {
        if case let .contratNonSigne(contratId?, _) = affichage, let presentateurRenvoiWeb,
           let route = PresencesRenvois.contrat(id: contratId) {
            JoleneButton(LibellesWeb.BlocPointage.voirLeContrat, style: .secondary) { presentateurRenvoiWeb.presenter(route) }
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
