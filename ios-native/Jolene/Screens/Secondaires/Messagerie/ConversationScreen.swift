import SwiftUI
import JoleneCore
import JoleneDesign

/// Fil d'une conversation (L4-T7b), port du panneau de détail de `src/pages/PageMessagerie.tsx` (l.660-800) et
/// d'`InputMessage.tsx`. Vue de `FilModel` (JoleneCore, T7a), qui porte toutes les règles : flux déclarés avant la
/// lecture, fusion par id, accusé de lecture, relecture après « rejoint », envoi par l'edge puis relecture de la ligne,
/// issue non confirmée relue **sans renvoi**, saisie et présence. La vue n'ajoute aucune règle et ne journalise aucun
/// contenu.
///
/// - En-tête : nom, « Mission · … », présence ou « Est en train d'écrire… » (interlocuteur non plateforme), puis blocage
///   et signalement (Apple 1.2 : `BlocageControle`, `SignalementSheet`), absents pour une conversation Jolene.
/// - Un message n'apparaît « envoyé » qu'une fois relu ; une issue non confirmée affiche « Envoi non confirmé », le
///   texte reste dans le composeur, rien n'est renvoyé.
/// - Conversation archivée (ou `CONVERSATION_ARCHIVEE` de l'edge) : composeur remplacé par la mention verbatim.
/// - Anti-fuite : feuille éducative verbatim (`AntiFuiteSheet`), texte saisi conservé.
///
/// Identifiants : `chat-screen`, `chat-message-<id>`, `chat-input`, `chat-envoyer`, `chat-archivee`, `chat-non-confirme`,
/// `chat-typing`, `chat-presence`, `chat-bloquer`, `chat-signaler`, `chat-antifuite`, `chat-refus`, `chat-vide`,
/// `chat-chargement`, `chat-erreur` (+ `-reessayer`), `chat-message-erreur`, `chat-moderation-confirmation`.
struct ConversationScreen: View {
    let conversation: ConversationAffichee
    let contexte: ContexteEcranMessagerie
    @ObservedObject var cycle: CycleRealtime
    /// La conversation n'est plus accessible (`42501 Accès refusé`) : l'écran se referme sur la liste.
    let surIndisponible: () -> Void

    @StateObject private var fil: FilModel
    @StateObject private var blocage: BlocageModel
    @State private var texte = ""
    @State private var envoiLocal = false
    @State private var signalementOuvert = false
    @State private var confirmationSignalement: String?
    /// Défilement vers la fin du fil en attente (un seul à la fois : le plus récent remplace le précédent).
    @State private var defilementFin: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    /// Position du repère de fin, hauteur visible et dernier envoi : décident du suivi de la fin quand la hauteur change
    /// (`SuiviFinDuFil`, JoleneCore). Le dernier envoi est daté sur l'horloge d'interface, jamais sur l'horloge métier
    /// (figée en démo).
    /// Boîte non observée : la position du repère change à chaque image d'un défilement, sans rendre l'écran.
    @State private var boiteSuivi = BoiteSuiviFinDuFil()
    private let horlogeInterface: HorlogeInterface
    /// Dernier type détecté : la feuille garde son texte pendant sa fermeture.
    @State private var typeAntiFuite: DetectedType?
    private let moderation: ModerationConversation

    init(conversation: ConversationAffichee, contexte: ContexteEcranMessagerie, cycle: CycleRealtime,
         horlogeInterface: HorlogeInterface = .systeme, surIndisponible: @escaping () -> Void) {
        self.conversation = conversation
        self.horlogeInterface = horlogeInterface
        self.contexte = contexte
        self.cycle = cycle
        self.surIndisponible = surIndisponible
        // Lot 5 (T11) : cibles du blocage et du signalement propres à l'établissement (`ModerationConversation.pour`).
        let moderation = ModerationConversation.pour(conversation, etablissement: contexte.contexte.estEtablissement)
        self.moderation = moderation
        // Présence et saisie suivies pour l'interlocuteur seulement, jamais pour la plateforme (web `realtimeAutreId`).
        let autre = conversation.estJolene ? nil : conversation.apercu.autreId
        _fil = StateObject(wrappedValue: FilModel(controller: contexte.controller, contexte: contexte.contexte,
                                                  conversationId: conversation.id, autreId: autre,
                                                  archivee: conversation.apercu.archivee, cycle: cycle))
        _blocage = StateObject(wrappedValue: BlocageModel(controller: contexte.controller, contexte: contexte.contexte,
                                                          cibleId: moderation.blocage ?? "", libelleCible: moderation.libelleCible))
    }

    private var maintenant: Date { contexte.maintenant() }

    var body: some View {
        VStack(spacing: 0) {
            entete
            Divider()
            messages
            avis
            MessageComposer(text: $texte, isSending: envoiLocal || fil.envoiEnCours, isArchived: fil.archivee,
                            onActivity: activite, onSend: envoyer)
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(MessageriePresentation.nom(conversation))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-screen")
        // Suivi relancé à chaque ouverture des canaux (premier plan, identité) ; arrêté à la disparition.
        .task(id: cycle.generation) { await fil.suivre() }
        .task { if moderation.blocage != nil { await blocage.lire() } }
        .onChange(of: fil.accesRefuse) { refuse in if refuse { surIndisponible() } }
        .sheet(isPresented: antiFuitePresentee) {
            AntiFuiteSheet(type: fil.antiFuite ?? typeAntiFuite) { fil.fermerAntiFuite() }
        }
        .onChange(of: fil.antiFuite) { type in if let type { typeAntiFuite = type } }
        .sheet(isPresented: $signalementOuvert) {
            if let cible = moderation.signalement {
                SignalementSheet(cible: cible, messagerie: contexte) { transmis in
                    signalementOuvert = false
                    if transmis { confirmationSignalement = MessagerieTextes.Signalement.succes }
                }
            }
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            HStack(alignment: .center, spacing: JoleneSpacing.md) {
                avatar(conversation, taille: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MessageriePresentation.nom(conversation))
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if let intitule = conversation.apercu.missionIntitule, !intitule.isEmpty {
                        Text(MessagerieTextes.prefixeMission + intitule)
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.mauve700)
                            .lineLimit(1)
                            .accessibilityIdentifier("chat-mission")
                    }
                    if fil.autreId != nil {
                        if fil.saisieInterlocuteur {
                            Text(TypingIndicator.statusText)
                                .font(JoleneFont.caption.italic())
                                .foregroundStyle(JoleneColor.rose800)
                                .accessibilityIdentifier("chat-typing")
                        } else {
                            Text(MessageriePresentation.presence(fil.presence, maintenant: maintenant))
                                .font(JoleneFont.caption)
                                .foregroundStyle(JoleneColor.bubblegum)
                                .accessibilityIdentifier("chat-presence")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if moderation.blocage != nil || moderation.signalement != nil {
                HStack(spacing: JoleneSpacing.lg) {
                    if moderation.blocage != nil { BlocageControle(model: blocage) }
                    if moderation.signalement != nil {
                        Button {
                            confirmationSignalement = nil
                            signalementOuvert = true
                        } label: {
                            Label(MessagerieTextes.Signalement.signaler, systemImage: "flag")
                                .font(JoleneFont.caption)
                                .foregroundStyle(JoleneColor.bubblegum)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat-signaler")
                    }
                }
            }
            if let confirmationSignalement {
                InlineNotice(confirmationSignalement, tone: .success, identifier: "chat-moderation-confirmation")
            } else if let message = blocage.message {
                InlineNotice(message, tone: blocage.succes ? .success : .error, identifier: "chat-moderation-confirmation")
            }
        }
        .padding(.horizontal, JoleneSpacing.lg)
        .padding(.vertical, JoleneSpacing.sm)
        .background(JoleneColor.cloud)
    }

    // MARK: - Messages

    /// Repère de fin du fil, hors de la pile paresseuse : sa position est exacte dès la mise en page, contrairement à
    /// celle d'une ligne de `LazyVStack` qui vient d'arriver (position estimée).
    private static let finDuFil = "chat-fin-du-fil"

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: JoleneSpacing.sm) {
                        switch fil.etat {
                        case .chargement:
                            SkeletonCard(identifier: "chat-chargement")
                        case .echec:
                            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                                InlineNotice(MessagerieTextes.echecFil, tone: .error, identifier: "chat-erreur")
                                JoleneButton(MessagerieTextes.reessayerFil, style: .secondary) { Task { await fil.relire() } }
                                    .accessibilityIdentifier("chat-erreur-reessayer")
                            }
                        case .pret where fil.messages.isEmpty:
                            VStack(spacing: JoleneSpacing.sm) {
                                Image(systemName: "bubble.left").font(.system(size: 28)).foregroundStyle(JoleneColor.bubblegum)
                                    .accessibilityHidden(true)
                                Text(MessagerieTextes.filVide).font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, JoleneSpacing.xl)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("chat-vide")
                        case .pret:
                            ForEach(fil.messages) { message in
                                if equipe(message) {
                                    // Lot 5 (T11) : message d'un collègue de l'équipe, du côté de l'établissement (web l.763-767).
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(MessagerieTextes.equipeEtablissement)
                                            .font(JoleneFont.caption.weight(.semibold))
                                            .foregroundStyle(JoleneColor.bubblegum)
                                            .accessibilityIdentifier("chat-equipe-\(message.id)")
                                        bulle(message)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .id(message.id)
                                } else {
                                    bulle(message).id(message.id)
                                }
                            }
                        }
                        if fil.saisieInterlocuteur {
                            TypingIndicator(identifier: "chat-typing-bulle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("chat-typing-bulle")
                        }
                    }
                    .padding(JoleneSpacing.md)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    Color.clear
                        .frame(height: 1)
                        .id(Self.finDuFil)
                        .accessibilityHidden(true)
                        .background(GeometryReader { repere in
                            Color.clear
                                .onAppear { boiteSuivi.etat.repere(Double(repere.frame(in: .named(Self.finDuFil)).minY)) }
                                .onChange(of: repere.frame(in: .named(Self.finDuFil)).minY) { haut in boiteSuivi.etat.repere(Double(haut)) }
                        })
                }
            }
            .coordinateSpace(name: Self.finDuFil)
            .accessibilityIdentifier("chat-messages")
            // Fin du fil gardée visible à chaque message inséré (pas seulement quand le dernier change) et quand la hauteur
            // visible change (clavier), une fois l'animation du clavier finie. Run 45527404765 (`DemoMessagerieTests`,
            // `DemoEtabMessagerieTests`, iPad paysage ; reproduit et instrumenté sur iOS 18.6) : à l'envoi, le clavier se
            // ferme puis se rouvre (zone visible 83,5 → 480,5 → 83,5 pt en 0,1 s) ; le défilement demandé pendant cette
            // animation était écrasé par l'évitement du clavier, et la réponse démo, insérée par le flux avant la relecture
            // du message envoyé (dernier identifiant inchangé), restait sous le bas visible, jamais rendue par la pile
            // paresseuse. Le repère de fin, hors de la pile, a une position exacte. Un changement de hauteur ne ramène en
            // bas que si la fin était visible avant, ou juste après un envoi (`SuiviFinDuFil`) : l'historique relu garde
            // sa position (revue fraîche de la PR #1185, mineur 1).
            .onChange(of: Self.signature(fil.messages)) { _ in defilerEnBas(proxy, apres: Self.delaiApresMessage) }
            .background(GeometryReader { zone in
                Color.clear
                    .onAppear { boiteSuivi.etat.hauteurMesuree(Double(zone.size.height)) }
                    .onChange(of: zone.size.height) { hauteur in
                        if boiteSuivi.etat.hauteurChangee(Double(hauteur), a: horlogeInterface.maintenant()) {
                            defilerEnBas(proxy, apres: Self.delaiApresClavier)
                        }
                    }
            })
            // Ouverture : sans animation, au tour suivant de la boucle principale (mise en page faite). Un `scrollTo`
            // immédiat dans `onAppear` rendait le bouton « Confirmer » du blocage inopérant (iPhone, iOS 18.6, 3 sur 3).
            .onAppear { defilerEnBas(proxy, apres: Self.delaiApresMessage, anime: false) }
            .onDisappear { defilementFin?.cancel() }
        }
    }


    /// Nombre de messages et dernier identifiant : change à toute insertion, en fin de fil ou avant le dernier.
    private static func signature(_ messages: [MessageChat]) -> String {
        "\(messages.count)|\(messages.last?.id ?? "")"
    }

    /// Délai avant de défiler : un tour de boucle après un message (mise en page faite), la fin de l'animation du clavier
    /// (0,25 s chez UIKit, marge comprise) après un changement de hauteur visible.
    private static let delaiApresMessage: UInt64 = 0
    private static let delaiApresClavier: UInt64 = 400_000_000

    /// Amène la fin du fil en bas de la zone visible après `apres` nanosecondes ; une demande plus récente remplace celle
    /// en attente (la dernière mise en page l'emporte).
    private func defilerEnBas(_ proxy: ScrollViewProxy, apres delai: UInt64, anime: Bool = true) {
        defilementFin?.cancel()
        let animation: Animation? = anime && !reduireAnimations ? .easeOut(duration: 0.2) : nil
        defilementFin = Task { @MainActor in
            if delai > 0 { try? await Task.sleep(nanoseconds: delai) } else { await Task.yield() }
            guard !Task.isCancelled else { return }
            withAnimation(animation) { proxy.scrollTo(Self.finDuFil, anchor: .bottom) }
        }
    }

    private func bulle(_ message: MessageChat) -> ChatBubble {
        ChatBubble(message.contenu, kind: nature(message), heure: MessageriePresentation.heure(message),
                   auteur: MessageriePresentation.nom(conversation), identifier: "chat-message-\(message.id)")
    }

    /// Bulle d'un collègue (établissement seulement).
    private func equipe(_ message: MessageChat) -> Bool {
        fil.estEtablissement && MessageriePresentation.messageEquipe(message, moi: fil.moi, soignantId: conversation.apercu.soignantId)
    }

    private func nature(_ message: MessageChat) -> ChatBubble.Kind {
        let nature = fil.estEtablissement
            ? MessageriePresentation.natureEtablissement(message, moi: fil.moi, soignantId: conversation.apercu.soignantId)
            : MessageriePresentation.nature(message, moi: fil.moi)
        switch nature {
        case .moi: return .moi
        case .interlocuteur: return .interlocuteur
        case .jolene: return .jolene
        case .systeme: return .systeme
        }
    }

    // MARK: - Avis du composeur

    @ViewBuilder private var avis: some View {
        VStack(spacing: JoleneSpacing.xs) {
            if fil.envoiNonConfirme {
                InlineNotice(MessagerieTextes.envoiNonConfirme, tone: .warning, identifier: "chat-non-confirme")
            }
            if let refus = fil.refusEnvoi {
                InlineNotice(MessageriePresentation.libelleRefus(code: refus.code), tone: .error, identifier: "chat-refus")
            }
            if let message = fil.message {
                InlineNotice(message, tone: .error, identifier: "chat-message-erreur")
            }
        }
        .padding(.horizontal, JoleneSpacing.md)
    }

    // MARK: - Composeur

    private var antiFuitePresentee: Binding<Bool> {
        Binding(get: { fil.antiFuite != nil }, set: { if !$0 { fil.fermerAntiFuite() } })
    }

    /// Verrou posé avant toute suspension (exigence de `MessageComposer`) ; le champ n'est vidé que sur un envoi confirmé
    /// et relu, sinon le texte saisi reste.
    private func envoyer() {
        envoiLocal = true
        boiteSuivi.etat.envoi(a: horlogeInterface.maintenant())
        let contenu = MessageComposer.trimmed(texte)
        Task {
            let confirme = await fil.envoyer(contenu)
            if confirme { texte = "" }
            envoiLocal = false
        }
    }

    private func activite(_ activite: MessageComposer.Activity) {
        switch activite {
        case .focus, .change:
            if MessageComposer.trimmed(texte).isEmpty, activite == .change {
                Task { await fil.finSaisie() }
            } else {
                fil.frappe()
            }
        case .blur:
            Task { await fil.finSaisie() }
        }
    }
}

/// État du suivi de la fin du fil (`SuiviFinDuFil`) tenu par référence : ses mises à jour (à chaque image d'un
/// défilement) ne provoquent aucun rendu ; seules les décisions de défilement agissent.
@MainActor
private final class BoiteSuiviFinDuFil {
    var etat = SuiviFinDuFil()
}

