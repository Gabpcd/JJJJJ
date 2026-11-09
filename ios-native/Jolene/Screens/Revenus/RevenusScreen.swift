import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet Revenus (lot 3, T12, B9 ; lecture seule) : vue de `RevenusModel` (JoleneCore), port de l'aperçu de
/// `/soignant/mes-gains` (`MesGainsApercuContent`, `src/pages/MesGains.tsx`) restreint au lot 3 (D4). Remplace le
/// placeholder du lot 0 (`placeholder-revenus` → `revenus-screen`, identifiants des XCUITest migrés, règle 8).
///
/// Sections, dans l'ordre : en-tête ; renvois web « Factures » et « Paie » (onglets du web, D4 : lot 4) ; totaux serveur
/// (`fn_mes_revenus_connect`, profil libéral ou mixte seulement, comme `PageStripeConnect.tsx` l.104) ; « Paiement
/// rapide » (`fn_mes_paiements_escrow`, sept états, libellés verbatim) ; missions terminées (montant de
/// `montantFinanceAfficheMission`, état de la dernière déclaration), pages de 50, notes « net estimé » verbatim.
/// Les règles (états, montants, epoch, audit, pagination) sont dans JoleneCore et testées là ; la vue n'ajoute aucune
/// logique ni aucun calcul de montant.
///
/// Navigation : le litige d'un paiement rapide empile le détail natif de la mission sur la pile de l'onglet
/// (`MissionRoute`, comme le `Link` du web l.152-155) ; une ligne de mission ouvre ses présences
/// (`/soignant/presences/mission/:id`, lot 2 : renvoi web aujourd'hui) et l'état vide ouvre Explorer, par la cible de
/// l'espace (`CibleNotification`, `MainTabView.presenter`). Un renvoi web n'est proposé qu'avec le présentateur
/// `.safari` du coordinateur des liens (jamais `openURL`, jamais un bouton sans effet).
struct RevenusScreen: View {
    @StateObject private var model: RevenusModel
    @ObservedObject private var session: SessionStore
    private let snapshot: SessionSnapshot
    private let ouvrir: (CibleNotification) -> Void
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(session: SessionStore, snapshot: SessionSnapshot, ouvrir: @escaping (CibleNotification) -> Void) {
        self.session = session
        self.snapshot = snapshot
        self.ouvrir = ouvrir
        _model = StateObject(wrappedValue: RevenusModel(controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                entete
                totaux
                paiementsRapides
                missions
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .accessibilityIdentifier("revenus-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(RevenusTextes.titre)
        .navigationDestination(for: MissionRoute.self) { route in
            MissionDetailScreen(route: route, initial: nil, session: session, snapshot: snapshot)
        }
        .task { await model.chargerSiNecessaire() }
    }

    // MARK: - En-tête et renvois web

    private var entete: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            Text(RevenusTextes.sousTitre)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("revenus-sous-titre")
            if presentateurRenvoiWeb != nil {
                HStack(spacing: JoleneSpacing.sm) {
                    renvoi(RevenusTextes.factures, lien: RevenusPresentation.lienFactures, identifiant: "revenus-factures-web")
                    renvoi(RevenusTextes.paie, lien: RevenusPresentation.lienBulletins, identifiant: "revenus-bulletins-web")
                }
            }
        }
    }

    @ViewBuilder
    private func renvoi(_ titre: String, lien: String, identifiant: String) -> some View {
        if let cible = cible(lien) {
            JoleneButton(titre, style: .secondary) { ouvrir(cible) }
                .accessibilityIdentifier(identifiant)
        }
    }

    /// Cible présentable d'un lien de l'onglet (renvoi web seulement avec le présentateur `.safari`), nil sinon.
    private func cible(_ lien: String) -> CibleNotification? {
        guard let destination = DestinationLien(link: lien) else { return nil }
        let cible = CibleNotification(destination)
        return cible.estPresentable(renvoiWebDisponible: presentateurRenvoiWeb != nil) ? cible : nil
    }

    // MARK: - Totaux serveur

    @ViewBuilder
    private var totaux: some View {
        switch model.totaux {
        case .chargement, .masques:
            EmptyView()
        case let .pret(totaux):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: JoleneSpacing.md) { cartes(totaux) }
                    VStack(alignment: .leading, spacing: JoleneSpacing.md) { cartes(totaux) }
                }
                Text(RevenusTextes.noteTotaux)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("revenus-kpi-note")
            }
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .warning, identifier: "revenus-kpi-erreur")
                JoleneButton(RevenusTextes.reessayer, style: .secondary) { Task { await model.rechargerTotaux() } }
                    .accessibilityIdentifier("revenus-kpi-reessayer")
            }
        }
    }

    @ViewBuilder
    private func cartes(_ totaux: TotauxRevenus) -> some View {
        RevenusCarteTotal(titre: RevenusTextes.kpiMois, valeur: RevenusPresentation.euros(totaux.moisEnCours),
                          image: "banknote", identifiant: "revenus-kpi-mois")
        RevenusCarteTotal(titre: RevenusTextes.kpiTotal, valeur: RevenusPresentation.euros(totaux.total),
                          image: "banknote", identifiant: "revenus-kpi-total")
        RevenusCarteTotal(titre: RevenusTextes.kpiAttente, valeur: RevenusPresentation.euros(totaux.enAttente),
                          image: "clock", identifiant: "revenus-kpi-attente")
    }

    // MARK: - Paiement rapide

    @ViewBuilder
    private var paiementsRapides: some View {
        switch model.paiementsRapides {
        case .chargement:
            // Le web n'affiche rien pendant le chargement (`if (loading) return null`, l.112).
            EmptyView()
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, title: RevenusTextes.escrowIndisponible, tone: .error, identifier: "revenus-escrow-erreur")
                JoleneButton(RevenusTextes.reessayer, style: .secondary) { Task { await model.rechargerPaiementsRapides() } }
                    .accessibilityIdentifier("revenus-escrow-reessayer")
            }
        case .pret:
            let affiche = model.escrowAffiche
            if affiche.afficheSection {
                VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                    Label(RevenusTextes.paiementRapide, systemImage: "bolt.fill")
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("revenus-escrow")
                    groupe(RevenusTextes.aVenir, affiche.aVenir, identifiant: "revenus-escrow-a-venir")
                    groupe(RevenusTextes.recemmentVerse, affiche.verses, identifiant: "revenus-escrow-verses")
                    groupe(RevenusTextes.annules, affiche.annules, identifiant: "revenus-escrow-annules")
                }
            }
        }
    }

    @ViewBuilder
    private func groupe(_ titre: String, _ lignes: [LigneEscrowAffichee], identifiant: String) -> some View {
        if !lignes.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                Text(titre)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(identifiant)
                ForEach(lignes) { ligne in
                    if ligne.ouvreMission {
                        NavigationLink(value: MissionRoute(id: ligne.missionId)) {
                            RevenusLigneEscrow(ligne: ligne, cliquable: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(RevenusLigneEscrow.libelleAccessible(ligne))
                        .accessibilityIdentifier("revenus-escrow-\(ligne.missionId)")
                    } else {
                        RevenusLigneEscrow(ligne: ligne, cliquable: false)
                            .accessibilityIdentifier("revenus-escrow-\(ligne.missionId)")
                    }
                }
            }
        }
    }

    // MARK: - Missions terminées

    @ViewBuilder
    private var missions: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            if let erreur = model.erreur {
                bandeauErreur(erreur)
            }
            if !model.missions.isEmpty {
                SectionHeader(RevenusTextes.missionsTerminees, identifier: "revenus-section-missions")
                ForEach(model.lignes) { ligne in
                    RevenusLigneMission(ligne: ligne, ouvrir: actionPresences(ligne.id))
                }
                if model.aSuivre {
                    JoleneButton(model.chargementMissions ? RevenusTextes.chargementSuite : RevenusTextes.chargerPlus,
                                 style: .secondary, isLoading: model.chargementMissions) {
                        Task { await model.chargerPlus() }
                    }
                    .disabled(model.chargementMissions)
                    .accessibilityIdentifier("revenus-load-more")
                }
                if model.afficheNoteNetEstime {
                    note(RevenusTextes.noteNetEstime, identifiant: "revenus-note-net-estime")
                }
                note(model.noteBasDePage, identifiant: "revenus-note-bas")
            } else if model.afficheVide {
                EmptyState(systemImage: "banknote", title: RevenusTextes.videTitre, message: RevenusTextes.videDescription,
                           identifier: "revenus-empty", actionTitle: RevenusTextes.videAction,
                           actionIdentifier: "revenus-empty-action") { ouvrir(.explorer) }
            } else if model.erreur == nil {
                chargement
            }
        }
    }

    private func bandeauErreur(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            InlineNotice(message, title: RevenusTextes.erreurTitre, tone: .error, identifier: "revenus-error", announcesOnAppear: true)
            if model.sessionExpiree {
                // Libellé natif du lot 1, repris tel quel (`ProfilEdition.Textes.verifierSession`).
                JoleneButton(ProfilEdition.Textes.verifierSession, style: .secondary) {
                    Task { await model.verifierSession(session) }
                }
                .accessibilityIdentifier("revenus-session-check")
            } else {
                JoleneButton(RevenusTextes.reessayer, style: .secondary, isLoading: model.chargementMissions) {
                    Task { await model.reessayer() }
                }
                .disabled(model.chargementMissions)
                .accessibilityIdentifier("revenus-retry")
            }
        }
    }

    /// Ouverture des présences de la mission (`navigate(`/soignant/presences/mission/${m.id}`)`, l.705) ; nil sans
    /// cible présentable (aucune action sans effet).
    private func actionPresences(_ missionId: String) -> (() -> Void)? {
        guard let cible = cible(RevenusPresentation.lienPresences(missionId: missionId)) else { return nil }
        return { ouvrir(cible) }
    }

    private func note(_ texte: String, identifiant: String) -> some View {
        Text(texte)
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifiant)
    }

    private var chargement: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            SkeletonBlock(size: .lg, width: 200)
            SkeletonCard()
            SkeletonCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("revenus-loading")
    }
}

// MARK: - Lignes

/// Carte d'un total serveur (`CarteKPIY2K` du web) : libellé verbatim et montant formaté, un seul élément vocalisé.
private struct RevenusCarteTotal: View {
    let titre: String
    let valeur: String
    let image: String
    let identifiant: String

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Label(titre, systemImage: image)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            Text(valeur)
                .font(JoleneFont.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(JoleneColor.rose800)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titre), \(valeur)")
        .accessibilityIdentifier(identifiant)
    }
}

/// Ligne du paiement rapide (`Ligne` de `PaiementsEscrowAVenir.tsx` l.133-157) : icône du ton, libellé, explication,
/// part soignant. Texte jamais tronqué (le web tronque, le natif passe à la ligne).
struct RevenusLigneEscrow: View {
    let ligne: LigneEscrowAffichee
    let cliquable: Bool

    static func libelleAccessible(_ ligne: LigneEscrowAffichee) -> String {
        "\(ligne.libelle), \(ligne.detail), \(ligne.montant)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: JoleneSpacing.md) {
            Image(systemName: Self.symbole(ligne.etat))
                .font(JoleneFont.callout)
                .foregroundStyle(RevenusTon.encre(ligne.ton))
                .frame(width: 36, height: 36)
                .background(Circle().fill(RevenusTon.fond(ligne.ton)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ligne.libelle)
                    .font(JoleneFont.callout.weight(.medium))
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ligne.detail)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: JoleneSpacing.sm)
            Text(ligne.montant)
                .font(JoleneFont.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(JoleneColor.midnight)
            if cliquable {
                Image(systemName: "chevron.right")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityHidden(true)
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.libelleAccessible(ligne))
    }

    /// Icônes lucide du web (`ShieldCheck`, `Clock`, `Send`, `AlertTriangle`, `PauseCircle`, `CheckCircle2`, `XCircle`).
    static func symbole(_ etat: EtatEscrow) -> String {
        switch etat {
        case .reserve: return "checkmark.shield"
        case .attenteValidation: return "clock"
        case .versementEnCours: return "paperplane"
        case .retarde: return "exclamationmark.triangle"
        case .litige: return "pause.circle"
        case .verse: return "checkmark.circle"
        case .annule: return "xmark.circle"
        }
    }
}

/// Ligne d'une mission terminée (`MesGains.tsx` l.698-786) : pavé de date, `AmountRow` (intitulé, établissement,
/// montant serveur, nature verbatim, brut), horaires, état de la dernière déclaration. Le contenu reste lisible élément
/// par élément (`contain`) ; l'ouverture des présences est le tap de la ligne et l'action vocale « Voir mission … ».
struct RevenusLigneMission: View {
    let ligne: LigneMissionAffichee
    let ouvrir: (() -> Void)?

    var body: some View {
        let contenu = VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top, spacing: JoleneSpacing.md) {
                AccueilPaveDate(jour: ligne.jour)
                AmountRow(.init(title: ligne.titre, subtitle: ligne.sousTitre, montant: ligne.montant,
                                approximatif: ligne.approximatif, nature: ligne.nature, details: ligne.details,
                                identifier: "revenus-mission-montant-\(ligne.id)"))
            }
            if let horaires = ligne.horaires {
                Text(horaires)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("revenus-mission-horaires-\(ligne.id)")
            }
            StatusPill(ligne.etat.texte, tone: RevenusTon.pastille(ligne.etat.ton), size: .sm,
                       identifier: "revenus-mission-etat-\(ligne.id)")
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("revenus-mission-\(ligne.id)")

        if let ouvrir {
            contenu
                .onTapGesture { ouvrir() }
                .accessibilityAction(named: Text(ligne.actionAccessible)) { ouvrir() }
        } else {
            contenu
        }
    }
}

/// Couleurs sémantiques des tons (`TONE_CLASSES` du web, encres des pastilles de `StatusPill`).
enum RevenusTon {
    static func pastille(_ ton: TonRevenus) -> StatusPill.Tone {
        switch ton {
        case .info: return .info
        case .succes: return .success
        case .alerte: return .warning
        case .neutre: return .neutral
        case .erreur: return .error
        }
    }

    static func encre(_ ton: TonRevenus) -> Color { Color(pastille(ton).iconInkHSL) }
    static func fond(_ ton: TonRevenus) -> Color { Color(pastille(ton).backgroundHSL) }
}
