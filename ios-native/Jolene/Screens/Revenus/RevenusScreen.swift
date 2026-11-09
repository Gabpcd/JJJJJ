import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet Revenus (lot 3, T12, B9 ; lecture seule) : vue de `RevenusModel` (JoleneCore), port de l'aperçu de
/// `/soignant/mes-gains` (`MesGainsApercuContent`, `src/pages/MesGains.tsx`) restreint au lot 3 (D4). Remplace le
/// placeholder du lot 0 (`placeholder-revenus` → `revenus-screen`, identifiants des XCUITest migrés, règle 8).
///
/// Sections, dans l'ordre : en-tête ; renvois web « Factures » et « Paie » (onglets du web, D4 : lot 4) ; totaux serveur
/// (`fn_mes_revenus_connect`, seulement là où le web rend ses cartes : profil libéral ou mixte, hors compte de test,
/// compte Connect complet, `PageStripeConnect.tsx` l.178, l.300, l.302, l.367) ; « Paiement
/// rapide » (`fn_mes_paiements_escrow`, sept états, libellés verbatim) ; missions terminées (montant de
/// `montantFinanceAfficheMission`, état de la dernière déclaration), pages de 50, notes « net estimé » verbatim.
/// Les règles (états, montants, epoch, audit, pagination) sont dans JoleneCore et testées là ; la vue n'ajoute aucune
/// logique ni aucun calcul de montant.
///
/// Navigation, par la cible de l'espace (`CibleNotification`, `MainTabView.presenter`) : le litige d'un paiement rapide
/// ouvre la page web de la mission (`/soignant/missions/:id`, comme le `Link` du web l.152-155 ; revue B8 n°2 de T12,
/// M1 : le détail natif ne porte pas le bloc litige du web, l'empiler serait une impasse), une ligne de mission ouvre
/// ses présences (`/soignant/presences/mission/:id`, lot 2 : renvoi web aujourd'hui) et l'état vide ouvre Explorer. Un
/// renvoi web n'est proposé qu'avec le présentateur `.safari` du coordinateur des liens (jamais `openURL`, jamais un
/// bouton sans effet).
///
/// Fraîcheur (revue B8 de T12, m1) : relecture à l'apparition et au retour au premier plan des sections lues il y a
/// plus de 60 s, et immédiate quand `peremption` avance (lien universel ou tap qui présente l'onglet, `MainTabView`).
struct RevenusScreen: View {
    @StateObject private var model: RevenusModel
    @ObservedObject private var session: SessionStore
    private let peremption: Int
    private let ouvrir: (CibleNotification) -> Void
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @Environment(\.scenePhase) private var scenePhase
    /// Onglet affiché : le retour au premier plan ne relit que l'onglet visible.
    @State private var affiche = false

    init(session: SessionStore, snapshot: SessionSnapshot, peremption: Int = 0,
         ouvrir: @escaping (CibleNotification) -> Void) {
        self.session = session
        self.peremption = peremption
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
        // Premier affichage, relance après une tâche annulée, relecture au-delà de 60 s ou dès que le jeton avance.
        .task(id: peremption) { await model.chargerSiNecessaire(peremption: peremption) }
        .onAppear { affiche = true }
        .onDisappear { affiche = false }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, affiche else { return }
            Task { await model.chargerSiNecessaire(peremption: peremption) }
        }
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
                    // Revue B8 n°2 de T12, M1 : le litige ouvre la page web de la mission (bloc litige du web, absent du
                    // détail natif), par le présentateur `.safari` seulement (jamais un bouton sans effet).
                    if let route = ligne.renvoiLitige, presentateurRenvoiWeb != nil {
                        Button { ouvrir(.web(route)) } label: {
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
                // Masqué tant que le bandeau d'erreur propose « Réessayer » (revue B8 de T12, m3 : jamais une page sautée).
                if model.afficheChargerPlus {
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
/// par élément (`contain`, identifiants internes inchangés). L'ouverture des présences : tap de la ligne, et (revue B8
/// de T12, m5) un vrai bouton dans la ligne, chevron nommé comme le `aria-label` du web (`Voir mission …`, l.703 ; le
/// web : `role="button"`, `tabIndex`, Entrée/Espace, l.701-706), atteignable par VoiceOver, le Contrôle vocal et le
/// clavier — un conteneur `contain` ne reçoit pas le focus et une action nommée qu'il porterait resterait inatteignable.
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
            HStack(alignment: .center, spacing: JoleneSpacing.sm) {
                StatusPill(ligne.etat.texte, tone: RevenusTon.pastille(ligne.etat.ton), size: .sm,
                           identifier: "revenus-mission-etat-\(ligne.id)")
                Spacer(minLength: JoleneSpacing.sm)
                if let ouvrir {
                    Button(action: ouvrir) {
                        Image(systemName: "chevron.right")
                            .font(JoleneFont.callout.weight(.semibold))
                            .foregroundStyle(JoleneColor.rose800)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ligne.actionAccessible)
                    .accessibilityIdentifier("revenus-mission-ouvrir-\(ligne.id)")
                }
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("revenus-mission-\(ligne.id)")

        if let ouvrir {
            contenu.onTapGesture { ouvrir() }
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
