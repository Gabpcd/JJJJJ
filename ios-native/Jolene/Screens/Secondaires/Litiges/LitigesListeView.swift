import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet « Litiges mission » (L4-T8), port de `LitigesSoignantContent` (`LitigesSoignant.tsx`) : vue de `LitigesModel`
/// (JoleneCore), qui porte les règles (filtres, cible du lien, ouverture confirmée par relecture, refus mot pour mot).
///
/// - En-tête, « Ouvrir un litige », filtres par groupe de statut (groupes vides masqués), liste dans l'ordre serveur.
/// - Un litige déplié à la fois : son fil (`LitigeFilView`), le renvoi « Accord amiable sur jolene.app » tant que le web
///   propose un accord. Aucun texte de délai (`LitigesTextes`).
///
/// Identifiants : `litige-ouvrir`, `litiges-filtres`, `litiges-filtre-<groupe>`, `litige-<id>`, `litige-entete-<id>`,
/// `litige-statut-<id>`, `litiges-chargement`, `litiges-erreur` (+ `-reessayer`), `litiges-vide`, `litiges-action-erreur`,
/// `litiges-confirmation`, `litiges-session-check` ; feuille `litige-ouverture` (`LitigeOuvertureSheet`).
struct LitigesListeView: View {
    @ObservedObject var model: LitigesModel
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
            entete
            if !model.formulaire.estOuvert { avis }
            if model.sessionExpiree {
                JoleneButton(LitigesTextes.verifierSession, style: .secondary) { Task { await model.verifierSession(session) } }
                    .accessibilityIdentifier("litiges-session-check")
            }
            contenu
        }
        // À chaque apparition de l'onglet, comme le web au montage.
        .task { await model.charger() }
        .sheet(isPresented: Binding(get: { model.formulaire.estOuvert }, set: { if !$0 { model.fermerFormulaire() } })) {
            LitigeOuvertureSheet(model: model)
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(LitigesTextes.titre)
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            Text(LitigesTextes.sousTitre)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            JoleneButton(LitigesTextes.ouvrir, isLoading: model.formulaire == .chargement) {
                Task { await model.ouvrirFormulaire() }
            }
            .disabled(model.formulaire != .ferme)
            .accessibilityIdentifier("litige-ouvrir")
        }
    }

    @ViewBuilder private var avis: some View {
        if let erreur = model.erreur {
            InlineNotice(erreur, tone: .error, identifier: "litiges-action-erreur", announcementID: model.jeton)
        } else if let confirmation = model.confirmation {
            InlineNotice(confirmation, tone: .success, identifier: "litiges-confirmation", announcementID: model.jeton)
        }
    }

    // MARK: - Contenu

    @ViewBuilder private var contenu: some View {
        switch model.liste {
        case .chargement:
            SkeletonCard(identifier: "litiges-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: "litiges-erreur")
                if !model.sessionExpiree {
                    JoleneButton(LitigesTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                        .accessibilityIdentifier("litiges-erreur-reessayer")
                }
            }
        case .prete:
            filtres
            if model.litigesFiltres.isEmpty {
                EmptyState(systemImage: "scalemass", title: LitigesTextes.videTitre, message: LitigesTextes.videMessage,
                           identifier: "litiges-vide")
                    .background(JoleneColor.cloud)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            } else {
                ForEach(model.litigesFiltres) { carte($0) }
            }
        }
    }

    /// Pastilles de filtre (l.201-226) : libellé du web et nombre de litiges du groupe.
    @ViewBuilder private var filtres: some View {
        let visibles = model.filtresVisibles
        if !visibles.isEmpty {
            FilterChipRow(identifier: "litiges-filtres") {
                ForEach(visibles) { ligne in
                    FilterChip("\(ligne.filtre.libelle) \(ligne.nombre)", isSelected: model.filtre == ligne.filtre,
                               identifier: ligne.filtre.identifiant) {
                        model.choisir(ligne.filtre)
                    }
                }
            }
        }
    }

    private func carte(_ litige: Litige) -> some View {
        let deplie = model.deplie == litige.id
        let regle = StatutLitige.regle(litige.statut)
        return VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            // Pastille et date hors du bouton : un bouton fond ses enfants en un seul élément, la pastille y perdrait
            // son identifiant (`litige-statut-<id>`, lu par les XCUITest et par VoiceOver comme un état distinct).
            HStack(alignment: .center, spacing: JoleneSpacing.sm) {
                StatusPill(regle.libelle, tone: Self.ton(regle.groupe), systemImage: Self.symbole(regle.icone), size: .sm,
                           identifier: "litige-statut-\(litige.id)")
                if let date = LitigesPresentation.jour(litige.creeLe) {
                    Text(date)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
                Spacer(minLength: 0)
            }
            Button {
                model.basculer(litige.id)
            } label: {
                HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                        Text(LitigesPresentation.intitule(litige))
                            .font(JoleneFont.headline)
                            .foregroundStyle(JoleneColor.midnight)
                            .multilineTextAlignment(.leading)
                        Text(LitigesPresentation.etablissement(litige))
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                            .multilineTextAlignment(.leading)
                        Text(LitigesPresentation.motif(litige))
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                            .multilineTextAlignment(.leading)
                            .lineLimit(deplie ? nil : 2)
                        // Revue B8 des textes de la vague D (M3) : proposition d'accord en attente (web l.267-271), sans délai.
                        if LitigesPresentation.propositionEnAttente(litige) {
                            Label(LitigesTextes.propositionRecue, systemImage: "hand.raised")
                                .font(JoleneFont.caption.weight(.semibold))
                                .foregroundStyle(JoleneColor.midnight)
                                .multilineTextAlignment(.leading)
                                .accessibilityIdentifier("litige-proposition-liste-\(litige.id)")
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: deplie ? "chevron.down" : "chevron.right")
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.bubblegum)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(deplie ? .isSelected : [])
            .accessibilityIdentifier("litige-entete-\(litige.id)")
            if deplie {
                Divider()
                LitigeFilView(litige: litige, session: session, snapshot: snapshot) { await model.relire() }
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("litige-\(litige.id)")
    }

    /// Tons des pastilles, d'après les classes du web (`statut-litige-regles.ts`) : ouvert en avertissement, médiation en
    /// information, revue admin en erreur, résolutions en succès, fermé neutre.
    private static func ton(_ groupe: GroupeStatutLitige) -> StatusPill.Tone {
        switch groupe {
        case .ouvert: return .warning
        case .mediation: return .info
        case .actionAttendue: return .error
        case .resoluAccord, .resoluDecision: return .success
        case .ferme: return .neutral
        }
    }

    /// Symbole SF de l'icône nommée du web (lucide), décoratif : le libellé porte l'état.
    private static func symbole(_ icone: IconeStatutLitige) -> String {
        switch icone {
        case .scale: return "scalemass"
        case .messageSquare: return "text.bubble"
        case .alertTriangle: return "exclamationmark.triangle"
        case .users: return "person.2"
        case .gavel: return "hammer"
        case .checkCircle2: return "checkmark.circle"
        case .xCircle: return "xmark.circle"
        }
    }
}

/// « Ouvrir un nouveau litige » (`LitigesSoignant.tsx` l.306-348) : avertissement du web (mot pour mot), mission
/// concernée parmi les missions proposées, motif (1 000 caractères au plus, 10 au moins après `trim` pour activer
/// l'envoi). Le refus du serveur s'affiche tel quel ; la feuille ne se referme qu'après une relecture qui montre le
/// litige ouvert. Type `AUTRE` seulement : les litiges liés à une facture restent sur jolene.app (D9).
///
/// Identifiants : `litige-ouverture` (défilement), `litige-avertissement`, `litige-missions-vide`, `litige-mission-<id>`,
/// `litige-motif`, `litige-motif-compteur`, `litige-ouverture-erreur`, `litige-envoyer`, `litige-annuler`.
struct LitigeOuvertureSheet: View {
    @ObservedObject var model: LitigesModel
    @FocusState private var motifActif: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                    Text(LitigesTextes.ouvertureTitre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    InlineNotice(LitigesTextes.avertissementOuverture, tone: .warning, identifier: "litige-avertissement")
                    missions
                    motif
                    if let erreur = model.erreurFormulaire {
                        InlineNotice(erreur, tone: .error, identifier: "litige-ouverture-erreur", announcesOnAppear: true)
                    }
                    VStack(spacing: JoleneSpacing.sm) {
                        JoleneButton(model.envoiEnCours ? LitigesTextes.creation : LitigesTextes.ouvrirLeLitige,
                                     isLoading: model.envoiEnCours) {
                            motifActif = false
                            Task { await model.envoyer() }
                        }
                        .disabled(!model.peutEnvoyer)
                        .accessibilityIdentifier("litige-envoyer")
                        JoleneButton(LitigesTextes.annuler, style: .secondary) { model.fermerFormulaire() }
                            .disabled(model.envoiEnCours)
                            .accessibilityIdentifier("litige-annuler")
                    }
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(JoleneColor.lavender.ignoresSafeArea())
            .accessibilityIdentifier("litige-ouverture")
        }
        .interactiveDismissDisabled(model.envoiEnCours)
    }

    private var missions: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(LitigesTextes.missionConcernee)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
            if model.formulaire.missions.isEmpty {
                Text(LitigesTextes.aucuneMissionEligible)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("litige-missions-vide")
            } else {
                if model.missionChoisie.isEmpty {
                    Text(LitigesTextes.selectionnerMission)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
                ForEach(model.formulaire.missions) { mission in
                    let choisie = model.missionChoisie == mission.id
                    Button {
                        model.choisirMission(mission.id)
                    } label: {
                        HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                            Image(systemName: choisie ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(choisie ? JoleneColor.rose700 : JoleneColor.bubblegum)
                                .accessibilityHidden(true)
                            Text(LitigesPresentation.option(mission))
                                .font(JoleneFont.callout)
                                .foregroundStyle(JoleneColor.midnight)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(JoleneSpacing.md)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(JoleneColor.cloud)
                        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field)
                            .strokeBorder(choisie ? JoleneColor.rose700 : JoleneColor.rose100, lineWidth: choisie ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.envoiEnCours)
                    .accessibilityAddTraits(choisie ? .isSelected : [])
                    .accessibilityIdentifier("litige-mission-\(mission.id)")
                }
            }
        }
    }

    private var motif: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(LitigesTextes.motifDuLitige)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
            TextField(LitigesTextes.motifPlaceholder,
                      text: Binding(get: { model.motif }, set: { model.saisirMotif($0) }), axis: .vertical)
                .lineLimit(4...8)
                .font(.system(size: 16))
                .focused($motifActif)
                .boutonOKClavier($motifActif, actif: !model.envoiEnCours)
                .padding(JoleneSpacing.md)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .disabled(model.envoiEnCours)
                .accessibilityLabel(LitigesTextes.motifDuLitige)
                .accessibilityIdentifier("litige-motif")
            Text(LitigesPresentation.compteur(model.motif))
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("litige-motif-compteur")
        }
    }
}
