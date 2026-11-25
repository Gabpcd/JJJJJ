import SwiftUI
import JoleneCore
import JoleneDesign

/// « Mes disponibilités » (`/soignant/disponibilites`, L4-T5), port de `src/pages/MesDisponibilites.tsx`, empilé sur le
/// Profil par `SecondaryRouter` une fois son coupe-circuit `ios_natif_disponibilites_actif` lu (fail-open). Vue de
/// `DisponibilitesModel` (JoleneCore), qui porte les règles (grille dérivée de l'horloge, aucune bascule optimiste,
/// relecture qui confirme, refus verbatim, jour passé jamais envoyé, session, epoch) ; la vue n'ajoute aucune logique.
///
/// - Quatre semaines depuis le lundi courant (`AvailabilityWeekGrid`, JoleneDesign) : pour chaque jour, « Jour » et
///   « Nuit » ; jours passés inertes ; seule la case en cours d'appel est occupée.
/// - Aide tant qu'aucun créneau n'est déclaré ; compteur et mention du web en pied de page.
/// - Lecture en échec : « Disponibilités indisponibles », le texte du web et « Réessayer » ; la grille n'est plus
///   affichée (« Réessayez avant de les modifier. »).
///
/// Point d'entrée : lien universel, tap push ou ligne du centre (`CibleNotification.secondaire`). Le web y mène aussi
/// par l'icône calendrier d'Explorer (`RechercheMissions.tsx` l.309-316) ; cet emplacement reste à poser dans Explorer
/// (`LOT4_PLAN.md`, écart n°12 : laissé à l'intégration).
///
/// Identifiants : `dispos-screen` ; `dispos-semaine-<1…4>` (+ `-title`), `dispo-<yyyy-MM-dd>` (ligne),
/// `dispo-<yyyy-MM-dd>-JOURNEE`, `dispo-<yyyy-MM-dd>-NUIT` ; `dispos-introduction`, `dispos-aide`, `dispos-compteur` ;
/// `dispos-chargement`, `dispos-erreur` (+ `dispos-indisponibles`, `dispos-reessayer`), `dispos-action-erreur`,
/// `dispos-session-check`.
struct DisponibilitesScreen: View {
    let contexte: ContexteSecondaire
    @StateObject private var model: DisponibilitesModel
    @ObservedObject private var session: SessionStore

    init(contexte: ContexteSecondaire) {
        self.contexte = contexte
        self.session = contexte.session
        _model = StateObject(wrappedValue: DisponibilitesModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(DisponibilitesTextes.introduction)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dispos-introduction")
                if model.sessionExpiree {
                    JoleneButton("Vérifier ma session", style: .secondary) { Task { await model.verifierSession(session) } }
                        .accessibilityIdentifier("dispos-session-check")
                }
                contenu
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(DisponibilitesTextes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("dispos-screen")
        // À chaque apparition, comme le web au montage : la grille est re-dérivée de l'horloge et les créneaux relus.
        .task { await model.charger() }
    }

    // MARK: - Contenu

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .chargement:
            SkeletonCard(identifier: "dispos-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                Text(DisponibilitesTextes.echecTitre)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("dispos-indisponibles")
                InlineNotice(message, tone: .error, identifier: "dispos-erreur")
                if !model.sessionExpiree {
                    JoleneButton(DisponibilitesTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                        .accessibilityIdentifier("dispos-reessayer")
                }
            }
        case .prete:
            if let erreur = model.erreur {
                InlineNotice(erreur, tone: .error, identifier: "dispos-action-erreur", announcementID: model.jeton)
            }
            if model.nombre == 0 { aide }
            ForEach(model.semaines) { semaine in
                AvailabilityWeekGrid(title: semaine.entete, days: semaine.jours.map { Self.jour($0) },
                                     identifier: semaine.id) { jour, creneau in
                    let cible = Self.creneau(creneau)
                    Task { await model.basculer(jour: JourParis(iso: jour.id), creneau: cible) }
                }
            }
            pied
        }
    }

    /// Aide du web (l.137-145), affichée seulement sans créneau déclaré ; « Jour » et « Nuit » en gras.
    private var aide: some View {
        HStack(alignment: .top, spacing: JoleneSpacing.sm) {
            Image(systemName: "info.circle")
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityHidden(true)
            DisponibilitesTextes.aide
                .reduce(Text("")) { texte, segment in texte + (segment.gras ? Text(segment.texte).bold() : Text(segment.texte)) }
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DisponibilitesTextes.aideTexte)
        .accessibilityIdentifier("dispos-aide")
    }

    /// Pied du web (l.206-211) : compteur (rien à zéro), puis la mention, toujours affichée.
    private var pied: some View {
        let phrases: [String?] = [AvailabilityWeekGrid.resume(count: model.nombre), DisponibilitesTextes.mention]
        return Text(phrases.compactMap { $0 }.joined(separator: " "))
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("dispos-compteur")
    }

    // MARK: - Correspondances avec la grille de JoleneDesign

    nonisolated private static func jour(_ jour: JourDisponibilitesAffiche) -> AvailabilityWeekGrid.Day {
        AvailabilityWeekGrid.Day(id: jour.id, label: jour.libelle, isToday: jour.estAujourdhui, isPast: jour.passe,
                                 journee: .init(isAvailable: jour.journee.declaree, isPending: jour.journee.enCours),
                                 nuit: .init(isAvailable: jour.nuit.declaree, isPending: jour.nuit.enCours))
    }

    nonisolated private static func creneau(_ creneau: AvailabilityWeekGrid.Creneau) -> CreneauDispo {
        switch creneau {
        case .journee: return .journee
        case .nuit: return .nuit
        }
    }
}
