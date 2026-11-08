import SwiftUI
import JoleneCore
import JoleneDesign

/// Route du centre de notifications dans la pile de l'onglet Accueil (lot 3, T5 ; `/soignant/notifications`).
struct CentreNotificationsRoute: Hashable {}

/// Centre de notifications (lot 3, T5 ; D23), vue de `CentreNotificationsModel` (JoleneCore,
/// `CentreNotificationsTests`), port de `NotificationsContent` (`src/pages/PageNotifications.tsx` l.37-171) :
/// 200 dernières notifications, non lues signalées (pastille et « Non lue » vocalisé), date relative comme le web
/// (`DistanceRelative`, port de `formatDistanceToNow`), tap = marquer lue (relue) puis ouvrir le lien.
/// Textes verbatim web (`CentreNotificationsTextes`, HARD STOP n°4).
///
/// Écarts consignés : ni « Supprimer les lues » (la base refuse DELETE au soignant, correction 9), ni Realtime
/// (lot 4 ; relecture au tirer-pour-rafraîchir et à chaque notification reçue au premier plan), ni filtres par
/// famille (hors périmètre du blueprint §1.1). Un renvoi web passe par le présentateur `.safari` injecté par
/// L1-T10 ; sans lui, « Voir » n'est pas affiché et une ligne déjà lue sans destination présentable n'est pas un
/// bouton (jamais un bouton sans effet).
///
/// Identifiants (blueprint §3 T5) : `notifications-screen`, `notification-<id>`, `notification-non-lue-<id>`,
/// `notifications-empty`, `notifications-error`, `notifications-retry` ; en plus `notifications-loading`,
/// `notification-voir-<id>`, `notifications-action-erreur`.
struct NotificationsScreen: View {
    @StateObject private var model: CentreNotificationsModel
    @ObservedObject private var taps: BoiteTapsPush
    private let ouvrir: (CibleNotification) -> Void
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(session: SessionStore, snapshot: SessionSnapshot, taps: BoiteTapsPush, ouvrir: @escaping (CibleNotification) -> Void) {
        self.taps = taps
        self.ouvrir = ouvrir
        _model = StateObject(wrappedValue: CentreNotificationsModel(controller: session.controller, snapshot: snapshot))
    }

    private var renvoiWebDisponible: Bool { presentateurRenvoiWeb != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                if let message = model.messageAction {
                    InlineNotice(message, tone: .error, identifier: "notifications-action-erreur", announcesOnAppear: true,
                                 announcementID: model.numeroMessage)
                        .onTapGesture { model.effacerMessage() }
                        .task(id: model.numeroMessage) {
                            do { try await Task.sleep(nanoseconds: IssuePrePromptPush.duree) } catch { return }
                            model.effacerMessage()
                        }
                }
                switch model.etat {
                case .chargement:
                    ProgressView()
                        .tint(JoleneColor.rose700)
                        .frame(maxWidth: .infinity)
                        .padding(JoleneSpacing.xxl)
                        .accessibilityIdentifier("notifications-loading")
                case .echec:
                    erreur
                case .charge(let liste) where liste.isEmpty:
                    EmptyState(systemImage: "bell", title: CentreNotificationsTextes.videTitre,
                               message: CentreNotificationsTextes.videDescription, identifier: "notifications-empty")
                case .charge(let liste):
                    LazyVStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                        ForEach(liste) { notification in
                            ligne(notification)
                        }
                    }
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger(silencieux: true) }
        .accessibilityIdentifier("notifications-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(CentreNotificationsTextes.titre)
        .task { if case .chargement = model.etat { await model.charger() } }
        // Notification reçue au premier plan : la liste visible se relit (pas de Realtime avant le lot 4).
        .onChange(of: taps.premiersPlans) { _ in Task { await model.charger(silencieux: true) } }
    }

    // MARK: - États

    private var erreur: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            Text(CentreNotificationsTextes.erreurChargement)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
            JoleneButton(CentreNotificationsTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                .accessibilityIdentifier("notifications-retry")
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notifications-error")
    }

    // MARK: - Lignes

    @ViewBuilder
    private func ligne(_ notification: NotificationJolene) -> some View {
        HStack(alignment: .top, spacing: JoleneSpacing.sm) {
            if !notification.lue {
                // Pastille des non lues (web `bg-destructive`) et texte « Non lue » des lecteurs d'écran
                // (`PanneauNotifications.tsx` l.160), avant le contenu de la ligne.
                Circle()
                    .fill(JoleneColor.rose700)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityElement()
                    .accessibilityLabel(CentreNotificationsTextes.nonLue)
                    .accessibilityIdentifier("notification-non-lue-\(notification.id)")
            }
            if CentreNotificationsModel.estActionnable(notification, renvoiWebDisponible: renvoiWebDisponible) {
                Button {
                    Task {
                        if let cible = await model.ouvrir(notification, renvoiWebDisponible: renvoiWebDisponible) {
                            ouvrir(cible)
                        }
                    }
                } label: {
                    contenu(notification)
                }
                .buttonStyle(.plain)
                .disabled(model.ouvertureEnCours != nil)
                .accessibilityIdentifier("notification-\(notification.id)")
            } else {
                contenu(notification)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("notification-\(notification.id)")
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notification.lue ? JoleneColor.cloud : JoleneColor.rose100)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    private func contenu(_ notification: NotificationJolene) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
                Text(notification.titre)
                    .font(JoleneFont.callout.weight(notification.lue ? .regular : .semibold))
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let date = dateRelative(notification) {
                    Text(date)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
            }
            Text(notification.corps)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            if CentreNotificationsModel.afficheVoir(notification, renvoiWebDisponible: renvoiWebDisponible) {
                HStack(spacing: JoleneSpacing.xs) {
                    Text(CentreNotificationsTextes.voir)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.rose800)
                .accessibilityIdentifier("notification-voir-\(notification.id)")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// `formatDistanceToNow(new Date(n.cree_le), { addSuffix: true, locale: fr })` ; rien si la date est illisible
    /// (le web lèverait une `RangeError`).
    private func dateRelative(_ notification: NotificationJolene) -> String? {
        guard let brut = notification.creeLe, let date = try? DateHeureParis.instantJolene(brut) else { return nil }
        return DistanceRelative.depuis(date, maintenant: model.horloge.now())
    }
}
