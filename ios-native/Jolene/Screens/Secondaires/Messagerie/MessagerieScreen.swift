import SwiftUI
import JoleneCore
import JoleneDesign

/// Messagerie (`/soignant/messagerie?conv=`, L4-T7b), port de la liste de `src/pages/PageMessagerie.tsx` (rôle SOIGNANT),
/// empilée sur le Profil par `SecondaryRouter` une fois son coupe-circuit `ios_natif_messagerie_actif` lu (fail-open).
/// Vue de `ConversationsModel` (JoleneCore, T7a), qui porte les règles (pagination keyset, interlocuteurs, Realtime,
/// epoch) ; la vue n'ajoute aucune logique. Textes : `MessagerieTextes` (verbatim du web).
///
/// - Onglets « Actives » / « Archivées (n) » dérivés de `archived_at`, recherche locale comme le web.
/// - Ligne : avatar (bouclier pour la plateforme), nom, horodatage, « Mission · … », aperçu, pastille de non-lus,
///   « Archivée — lecture seule ».
/// - Une conversation demandée (`?conv=`, « Écrire à l'établissement ») est ouverte dès que la liste la contient ;
///   absente ou refusée : « Cette conversation n'est plus accessible. ».
/// - Suivi Realtime relancé à chaque `CycleRealtime.generation` (premier plan, nouvelle identité).
///
/// Identifiants : `messagerie-screen`, `messagerie-onglet-actives`, `messagerie-onglet-archivees`, `messagerie-recherche`,
/// `conversation-<id>`, `conversation-nonlus-<id>`, `messagerie-chargement`, `messagerie-erreur` (+ `-reessayer`),
/// `messagerie-vide`, `messagerie-message`, `messagerie-indisponible`.
struct MessagerieScreen: View {
    let conversationId: String?
    let contexte: ContexteSecondaire
    @StateObject private var model: ConversationsModel
    @ObservedObject private var cycle: CycleRealtime
    @State private var onglet = Onglet.actives
    @State private var terme = ""
    @State private var ouverte: ConversationAffichee?
    @State private var demandeTraitee = false
    @State private var indisponible = false

    private enum Onglet { case actives, archivees }

    init(conversationId: String?, contexte: ContexteSecondaire) {
        self.conversationId = conversationId
        self.contexte = contexte
        let cycle = contexte.container.cycleMessagerie
        self.cycle = cycle ?? CycleRealtime(session: contexte.session)
        _model = StateObject(wrappedValue: ConversationsModel(controller: contexte.session.controller,
                                                              snapshot: contexte.snapshot, cycle: cycle))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                if indisponible {
                    InlineNotice(MessagerieTextes.conversationIndisponible, tone: .error, identifier: "messagerie-indisponible")
                }
                if let message = model.message {
                    InlineNotice(message, tone: .error, identifier: "messagerie-message")
                }
                JoleneTextField(MessagerieTextes.recherche, text: $terme, kind: .recherche,
                                placeholder: MessagerieTextes.recherche, identifier: "messagerie-recherche")
                onglets
                contenu
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(MessagerieTextes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("messagerie-screen")
        // Liste lue puis suivie ; relancée à chaque ouverture des canaux (premier plan, identité).
        .task(id: cycle.generation) { await model.suivre() }
        .onChange(of: model.etat) { _ in ouvrirDemandee() }
        .onChange(of: model.conversations) { _ in ouvrirDemandee() }
        .navigationDestination(isPresented: filPresente) {
            if let ouverte {
                ConversationScreen(conversation: ouverte, contexte: contexte, cycle: cycle) {
                    indisponible = true
                    self.ouverte = nil
                }
                .id(ouverte.id)
            }
        }
    }

    // MARK: - Onglets

    private var onglets: some View {
        HStack(spacing: JoleneSpacing.sm) {
            FilterChip(MessagerieTextes.ongletActives, isSelected: onglet == .actives, identifier: "messagerie-onglet-actives") {
                onglet = .actives
            }
            let archivees = model.archivees.count
            FilterChip(archivees > 0 ? "\(MessagerieTextes.ongletArchivees) (\(archivees))" : MessagerieTextes.ongletArchivees,
                       isSelected: onglet == .archivees, identifier: "messagerie-onglet-archivees") {
                onglet = .archivees
            }
        }
    }

    // MARK: - Contenu

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .chargement:
            SkeletonCard(identifier: "messagerie-chargement")
        case .echec:
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(MessagerieTextes.echecListe, tone: .error, identifier: "messagerie-erreur")
                JoleneButton(MessagerieTextes.reessayerListe, style: .secondary) { Task { await model.charger() } }
                    .accessibilityIdentifier("messagerie-erreur-reessayer")
            }
        case .pret:
            let liste = MessageriePresentation.filtrer(onglet == .actives ? model.actives : model.archivees, terme: terme)
            if liste.isEmpty {
                vide
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(liste) { ligne($0) }
                }
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            }
        }
    }

    private var vide: some View {
        VStack(spacing: JoleneSpacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityHidden(true)
            Text(onglet == .archivees ? MessagerieTextes.videArchivees : MessagerieTextes.videActives)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
            Text(!terme.isEmpty ? MessagerieTextes.videRecherche
                 : onglet == .archivees ? MessagerieTextes.videArchiveesDetail : MessagerieTextes.videActivesDetail)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .multilineTextAlignment(.center)
        }
        .padding(JoleneSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("messagerie-vide")
    }

    private func ligne(_ conversation: ConversationAffichee) -> some View {
        let nonLus = conversation.apercu.nonLus
        return Button {
            indisponible = false
            ouverte = conversation
        } label: {
            HStack(alignment: .top, spacing: JoleneSpacing.md) {
                avatar(conversation, taille: 48)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(MessageriePresentation.nom(conversation))
                            .font(nonLus > 0 ? JoleneFont.headline : JoleneFont.headline.weight(.semibold))
                            .foregroundStyle(JoleneColor.midnight)
                            .lineLimit(1)
                        Spacer(minLength: JoleneSpacing.sm)
                        if let quand = MessageriePresentation.horodatage(conversation.apercu.dernierMessageLe,
                                                                        maintenant: contexte.container.clock.now()) {
                            Text(quand)
                                .font(JoleneFont.caption)
                                .foregroundStyle(nonLus > 0 ? JoleneColor.rose800 : JoleneColor.bubblegum)
                        }
                    }
                    if let intitule = conversation.apercu.missionIntitule, !intitule.isEmpty {
                        Text(MessagerieTextes.prefixeMission + intitule)
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.mauve700)
                            .lineLimit(1)
                    }
                    Text(MessageriePresentation.apercu(conversation))
                        .font(JoleneFont.callout)
                        .foregroundStyle(nonLus > 0 ? JoleneColor.midnight : JoleneColor.bubblegum)
                        .lineLimit(1)
                    if conversation.apercu.archivee {
                        Text(MessagerieTextes.archiveeLectureSeule)
                            .font(JoleneFont.caption.italic())
                            .foregroundStyle(JoleneColor.bubblegum)
                    }
                }
                if let pastille = MessageriePresentation.pastille(nonLus) {
                    Text(pastille)
                        .font(JoleneFont.caption.weight(.bold))
                        .foregroundStyle(JoleneColor.onGradient)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(JoleneColor.heroGradient)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("conversation-nonlus-\(conversation.id)")
                }
            }
            .padding(JoleneSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("conversation-\(conversation.id)")
    }

    // MARK: - Ouverture

    private var filPresente: Binding<Bool> {
        Binding(get: { ouverte != nil }, set: { if !$0 { ouverte = nil } })
    }

    /// Conversation demandée par le lien (`?conv=`) : ouverte une fois, dès que la liste lue la contient.
    private func ouvrirDemandee() {
        guard let conversationId, !demandeTraitee, model.etat == .pret else { return }
        demandeTraitee = true
        if let cible = model.conversation(conversationId) {
            onglet = cible.apercu.archivee ? .archivees : .actives
            ouverte = cible
        } else {
            indisponible = true
        }
    }
}

/// Avatar d'une conversation : bouclier pour la plateforme (web `Shield`), initiales sinon (aucune image distante).
@MainActor @ViewBuilder
func avatar(_ conversation: ConversationAffichee, taille: CGFloat) -> some View {
    if conversation.estJolene {
        Image(systemName: "shield")
            .font(.system(size: taille * 0.4))
            .foregroundStyle(JoleneColor.rose800)
            .frame(width: taille, height: taille)
            .background(JoleneColor.mauve100)
            .clipShape(Circle())
            .accessibilityHidden(true)
    } else {
        AvatarView(prenom: conversation.interlocuteur?.prenom, nom: conversation.interlocuteur?.nom, size: taille)
            .accessibilityHidden(true)
    }
}
