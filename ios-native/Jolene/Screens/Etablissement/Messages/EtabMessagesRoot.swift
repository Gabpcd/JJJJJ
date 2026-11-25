import SwiftUI
import JoleneCore
import JoleneDesign

/// Racine de l'onglet Messages de l'espace établissement (lot 5, T11) : l'écran de la messagerie du lot 4
/// (`MessagerieScreen`, port de `PageMessagerie.tsx` rôle `ADMIN_ETABLISSEMENT`) en contexte établissement — aucun
/// second écran. Accès : permission `lecture` et drapeau `ios_natif_etab_messages_actif`, lus par la coquille
/// (`ecranEtablissement(.messages, …)`) ; l'écriture reste jugée par le serveur (edge `messagerie-validate`).
struct EtabMessagesRoot: View {
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot
    @Environment(\.messagerieEtablissement) var environnement

    var body: some View {
        MessagerieScreen(conversationId: nil,
                         messagerie: ContexteEcranMessagerie(etablissement: snapshot, session: session, environnement: environnement))
    }
}

/// Fil d'une conversation poussé sur une pile établissement (`EtabDestination.conversation`, lot 5, T11) : lien
/// `/etablissement/messagerie?conv=<id>` ou « Contacter le soignant » du détail de mission. La conversation est relue
/// par le modèle de liste du lot 4 (`ConversationsModel.charger`), puis le fil du lot 4 (`ConversationScreen`) est
/// affiché ; absente ou refusée : « Cette conversation n'est plus accessible. » (web l.523), jamais un fil supposé.
///
/// Identifiants : `etab-conversation-chargement`, `etab-conversation-erreur` (+ `-reessayer`), `messagerie-indisponible`.
struct EtabConversationRoot: View {
    let conversationId: String
    private let messagerie: ContexteEcranMessagerie
    @StateObject private var liste: ConversationsModel
    @State private var indisponible = false

    init(conversationId: String, session: SessionStore, snapshot: EtablissementSessionSnapshot,
         environnement: MessagerieEtablissementEnvironnement?) {
        self.conversationId = conversationId
        let messagerie = ContexteEcranMessagerie(etablissement: snapshot, session: session, environnement: environnement)
        self.messagerie = messagerie
        // Lecture seule de la liste, sans s'attacher au cycle (la liste de l'onglet reste celle qu'il met à jour).
        _liste = StateObject(wrappedValue: ConversationsModel(controller: messagerie.controller, contexte: messagerie.contexte))
    }

    var body: some View {
        Group {
            if indisponible {
                ScrollView {
                    InlineNotice(MessagerieTextes.conversationIndisponible, tone: .error, identifier: "messagerie-indisponible")
                        .padding(JoleneSpacing.lg)
                }
                .background(JoleneColor.lavender.ignoresSafeArea())
                .navigationTitle(MessagerieTextes.titre)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                switch liste.etat {
                case .chargement:
                    SkeletonCard(identifier: "etab-conversation-chargement")
                        .padding(JoleneSpacing.lg)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(JoleneColor.lavender.ignoresSafeArea())
                case .echec:
                    VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                        InlineNotice(MessagerieTextes.echecListe, tone: .error, identifier: "etab-conversation-erreur")
                        JoleneButton(MessagerieTextes.reessayerListe, style: .secondary) { Task { await liste.charger() } }
                            .accessibilityIdentifier("etab-conversation-erreur-reessayer")
                    }
                    .padding(JoleneSpacing.lg)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(JoleneColor.lavender.ignoresSafeArea())
                case .pret:
                    if let conversation = liste.conversation(conversationId) {
                        ConversationScreen(conversation: conversation, contexte: messagerie, cycle: messagerie.cycle) {
                            indisponible = true
                        }
                        .id(conversation.id)
                    } else {
                        Color.clear.onAppear { indisponible = true }
                    }
                }
            }
        }
        .task { await liste.charger() }
    }
}
