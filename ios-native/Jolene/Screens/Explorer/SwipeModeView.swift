import SwiftUI
import JoleneCore
import JoleneDesign

extension View {
    /// Vue Swipe de l'onglet Explorer (L4-T1c, `LOT4_PLAN.md` §1.1 et §2.5), posée une fois sur le contenu de
    /// `MissionsListScreen`.
    func vueSwipe(model: MissionsListModel) -> some View {
        modifier(VueSwipeExplorer(model: model))
    }
}

/// Vue Swipe d'Explorer (L4-T3b, `/soignant/swipe-missions`), sans retoucher `MissionsListScreen.swift` : port de la
/// bascule de `RechercheMissions.tsx` (l.288-300) et de `VueSwipeMissions.tsx`.
///
/// - **Commande segmentée « Swipe · Liste »** (`explorer-vue`, segments `explorer-vue-swipe` et `explorer-vue-liste`)
///   au-dessus du contenu d'Explorer, affichée seulement une fois le coupe-circuit `ios_natif_swipe_actif` lu vrai,
///   absent ou illisible (fail-open, D18) ; lu faux : ni commande ni vue Swipe, Explorer reste la liste. Rien du swipe
///   n'est construit avant la réponse du coupe-circuit. Le web a une troisième vue, « Carte » : Explorer natif n'a pas
///   de carte de la liste des missions, la commande n'en propose donc que deux (écart consigné, `LOT4_PLAN.md`).
/// - **Vue affichée** : celle que le soignant a choisie en dernier (`SwipeMarqueurs.vue`, par compte), la liste sans
///   préférence (écart assumé avec le web, qui ouvre sur Swipe : `SwipeMarqueurs.vueParDefaut`). Un lien
///   `/soignant/swipe-missions` ou `/soignant/recherche-missions?vue=swipe`, un tap push ou une ligne du centre
///   (cible `.secondaire(.swipe)`) fait avancer `contexte.demandesVueSwipe` : la vue Swipe est affichée, sans changer la
///   préférence mémorisée (le web ne mémorise pas `?vue=`).
/// - En vue Swipe, le contenu de la liste est remplacé par `SwipePaquetView` ; la barre d'Explorer (« Filtres »,
///   « Mes favoris », alerte rapide), sa feuille de filtres et ses destinations restent celles de `MissionsListScreen`.
struct VueSwipeExplorer: ViewModifier {
    @ObservedObject var model: MissionsListModel
    @Environment(\.contexteSecondaire) private var contexte

    func body(content: Content) -> some View {
        if let contexte {
            content.modifier(VueSwipeActive(missions: model, contexte: contexte))
        } else {
            content
        }
    }
}

private struct VueSwipeActive: ViewModifier {
    @ObservedObject var missions: MissionsListModel
    let contexte: ContexteSecondaire
    private let marqueurs: SwipeMarqueurs
    @StateObject private var parcours: ParcoursCandidatureSwipe
    @State private var porte = PorteEcranNatif(drapeau: nil)
    @State private var vue: VueExplorer
    /// Dernière demande de la vue Swipe prise en compte (`contexte.demandesVueSwipe`).
    @State private var demandesTraitees: Int

    private static let options = [
        SegmentedChoice.Option(id: VueExplorer.swipe.rawValue, title: SwipeTextes.vueSwipe, systemImage: "sparkles"),
        SegmentedChoice.Option(id: VueExplorer.liste.rawValue, title: SwipeTextes.vueListe, systemImage: "list.bullet"),
    ]

    init(missions: MissionsListModel, contexte: ContexteSecondaire) {
        self.missions = missions
        self.contexte = contexte
        let marqueurs = contexte.container.swipe.marqueurs(userId: contexte.snapshot.user.id)
        self.marqueurs = marqueurs
        _parcours = StateObject(wrappedValue: ParcoursCandidatureSwipe(
            model: SwipeModel(controller: contexte.session.controller, snapshot: contexte.snapshot), marqueurs: marqueurs))
        // Une demande antérieure au montage d'Explorer (lien reçu sur un autre onglet) l'emporte sur la préférence.
        _vue = State(initialValue: contexte.demandesVueSwipe > 0 ? .swipe : marqueurs.vue)
        _demandesTraitees = State(initialValue: contexte.demandesVueSwipe)
    }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if porte == .natif { commande }
            if porte == .natif, vue == .swipe {
                SwipePaquetView(model: parcours.model, parcours: parcours, missions: missions, contexte: contexte,
                                marqueurs: marqueurs) { basculer(.liste) }
            } else {
                content
            }
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .task { porte = await lirePorte() }
        .onChange(of: contexte.demandesVueSwipe) { demandes in
            guard demandes != demandesTraitees else { return }
            demandesTraitees = demandes
            vue = .swipe
        }
    }

    private var commande: some View {
        SegmentedChoice(SwipeTextes.commande, options: Self.options, selection: selection, identifier: "explorer-vue")
            .frame(maxWidth: 420)
            .padding(.horizontal, JoleneSpacing.lg)
            .padding(.top, JoleneSpacing.xs)
    }

    private var selection: Binding<String> {
        Binding(get: { vue.rawValue }, set: { nouvelle in
            if let choisie = VueExplorer(rawValue: nouvelle) { basculer(choisie) }
        })
    }

    /// Choix du soignant : affiché et mémorisé pour ce compte.
    private func basculer(_ nouvelle: VueExplorer) {
        vue = nouvelle
        marqueurs.memoriser(nouvelle)
    }

    private func lirePorte() async -> PorteEcranNatif {
        await PorteEcranNatif.lire(EcranSecondaire.swipe,
                                   flags: contexte.session.controller.gateways(for: contexte.snapshot.epoch)?.flags)
    }
}

// MARK: - Paquet

/// Feuilles de la vue Swipe : une seule présentation à la fois, portée par un seul `.sheet(item:)`. Le parcours du ❤️
/// (récapitulatif, feuille « première candidature », choix du contrat) tient dans **une** feuille dont le contenu suit
/// `ParcoursCandidatureSwipe.etape` : aucune feuille n'est refermée pour en ouvrir une autre pendant ce parcours.
private enum FeuilleSwipe: Identifiable, Equatable {
    case quiz
    case detail(String)
    case candidature(String)
    case alerte

    var id: String {
        switch self {
        case .quiz: return "quiz"
        case .detail(let missionId): return "detail-\(missionId)"
        case .candidature(let missionId): return "candidature-\(missionId)"
        case .alerte: return "alerte"
        }
    }
}

/// Paquet de cartes de la vue Swipe (L4-T3b). Vue de `SwipeModel` et de `ParcoursCandidatureSwipe` (JoleneCore), qui
/// portent les règles : carte retirée seulement après la réponse du serveur, refus et délai → message et carte remise en
/// tête sans renvoi, ❤️ par le récapitulatif exact puis la feuille « première candidature » la première fois, choix de
/// contrat rejoué, retrait sans retour de la carte (D4), fin de paquet, epoch. La vue n'ajoute aucune logique.
///
/// - Chips rapides d'Explorer au-dessus du paquet comme de la liste (`explorer-chips`, mêmes critères
///   `MissionsListModel.filtres` : le paquet est filtré par `FiltrePaquetSwipe(explorer:)`, source unique).
/// - `swipe-restantes` : nombre de cartes à parcourir ; `swipe-deck` (`SwipeCardStack`, geste) et boutons équivalents
///   `swipe-passer`, `swipe-sauvegarder`, `swipe-candidater` (`SwipeActionBar`, seule voie du favori).
/// - Annonces : `swipe-toast` (candidature envoyée avec `swipe-toast-annuler` pendant `ReglagesSwipe.dureeAnnulation`,
///   mission sauvegardée, candidature retirée avec `swipe-toast-mission`), `swipe-erreur` (refus ou erreur, verbatim),
///   `swipe-avertissement` (avertissement de planning du serveur) et `swipe-documents` (documents à compléter), qui ne
///   disparaissent jamais sur minuterie.
/// - Fin de paquet (`swipe-fin-paquet`) : état vide du web, alerte en un toucher (`swipe-fin-alerte`), rayon élargi ou
///   retour à la liste (`swipe-fin-secondaire`), missions sauvegardées re-proposées (`swipe-favoris`,
///   `swipe-favori-<missionId>`).
/// - Quiz du premier contact (`swipe-quiz`), une fois par compte.
private struct SwipePaquetView: View {
    /// Feuilles locales (hors parcours du ❤️).
    private enum FeuilleLocale: Equatable {
        case quiz
        case detail(String)
        case alerte
    }

    /// Action différée jusqu'à la fermeture complète de la feuille locale : jamais deux présentations enchaînées dans
    /// le même tour (détail → récapitulatif, quiz → Pool urgence).
    private enum ApresFermeture {
        case recapitulatif(String)
        case ouvrir(CibleNotification)
    }

    @ObservedObject var model: SwipeModel
    @ObservedObject var parcours: ParcoursCandidatureSwipe
    @ObservedObject var missions: MissionsListModel
    let contexte: ContexteSecondaire
    let marqueurs: SwipeMarqueurs
    let versLaListe: () -> Void

    @ObservedObject private var session: SessionStore
    @StateObject private var alerte: AlerteRapideModel
    @State private var feuilleLocale: FeuilleLocale?
    @State private var apresFermeture: ApresFermeture?
    @State private var quizEnCours = false
    @State private var quizVerifie = false
    /// Avis refermables de la vue (quiz appliqué, alerte confirmée).
    @State private var avisLocal: String?
    /// L'alerte en un toucher suit le coupe-circuit des recherches sauvegardées (T4).
    @State private var porteAlerte = PorteEcranNatif(drapeau: nil)
    @Environment(\.scenePhase) private var scenePhase
    /// Largeur régulière : « Mes favoris » en tête de la rangée de chips, comme dans la liste.
    @Environment(\.horizontalSizeClass) private var classeLargeur
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(model: SwipeModel, parcours: ParcoursCandidatureSwipe, missions: MissionsListModel, contexte: ContexteSecondaire,
         marqueurs: SwipeMarqueurs, versLaListe: @escaping () -> Void) {
        self.model = model
        self.parcours = parcours
        self.missions = missions
        self.contexte = contexte
        self.marqueurs = marqueurs
        self.versLaListe = versLaListe
        self.session = contexte.session
        _alerte = StateObject(wrappedValue: AlerteRapideModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
    }

    var body: some View {
        VStack(spacing: 0) {
            chipsRapides
            annonces
            contenu
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("swipe-vue")
        .sheet(item: feuillePresentee, onDismiss: executerApresFermeture) { feuille in
            contenuFeuille(feuille)
        }
        // Apparition : filtre du paquet dérivé des critères d'Explorer, lecture (ou relecture après 60 s), quiz.
        .task {
            await model.appliquerFiltre(FiltrePaquetSwipe(explorer: missions.filtres))
            await model.reprendre()
            await proposerQuiz()
            porteAlerte = await lirePorteAlerte()
        }
        .onChange(of: missions.filtres) { filtres in
            Task { await model.appliquerFiltre(FiltrePaquetSwipe(explorer: filtres)) }
        }
        // Retour au premier plan : relu si la dernière lecture date de plus de 60 s (`staleTime` du web).
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.reprendre() } }
        }
        // Toast de l'annonce : la candidature se retire depuis le paquet pendant `dureeAnnulation` (D4) ; l'annonce
        // « Candidature retirée » reste jusqu'à sa fermeture (accès au détail).
        .task(id: model.annonce) {
            guard let annonce = model.annonce, annonce.expire else { return }
            let duree = UInt64(max(1, contexte.container.swipe.dureeAnnulation) * 1_000_000_000)
            guard (try? await Task.sleep(nanoseconds: duree)) != nil, model.annonce == annonce else { return }
            model.fermerAnnonce()
        }
    }

    // MARK: Chips

    /// Chips rapides d'Explorer (les mêmes critères que la liste) : le paquet les respecte comme le web (6c.1). En
    /// largeur régulière (iPad), « Mes favoris » est en tête de la rangée comme dans la liste (`ExplorerActions` : la
    /// barre de navigation n'y tient pas) ; en largeur compacte, il reste dans la barre de `MissionsListScreen`.
    private var chipsRapides: some View {
        HStack(spacing: 0) {
            if ExplorerActions.dansLaRangeeDeChips(classeLargeur) {
                NavigationLink(value: FavorisRoute()) {
                    Image(systemName: "star")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .tint(JoleneColor.rose700)
                .accessibilityLabel(FavorisPresentation.titreEcran)
                .accessibilityIdentifier("explorer-favoris-ouvrir")
                .modifier(ExplorerActions.Pastille())
                .padding(.leading, JoleneSpacing.lg)
                // Messages hors de la barre en largeur régulière, comme dans la liste (`boutonMessages(explorer:)`).
                BoutonMessagesRangee()
            }
            FilterChipRow(identifier: "explorer-chips") {
                ForEach(ExplorerFiltres.chipsRapides) { chip in
                    FilterChip(chip.titre, isSelected: missions.filtres.estActif(chip), identifier: chip.identifiant) {
                        Task { await missions.basculer(chip) }
                    }
                }
            }
        }
        .padding(.vertical, JoleneSpacing.xs)
    }

    // MARK: Annonces

    @ViewBuilder private var annonces: some View {
        VStack(spacing: JoleneSpacing.xs) {
            if model.sessionExpiree {
                JoleneButton("Vérifier ma session", style: .secondary) { Task { await verifierSession() } }
                    .accessibilityIdentifier("swipe-session-check")
            }
            if let message = model.message, model.etat == .pret {
                avisRefermable(identifiantFermeture: "swipe-erreur-fermer", fermer: { model.effacerMessage() }) {
                    InlineNotice(message, tone: .error, identifier: "swipe-erreur", announcesOnAppear: true)
                }
            }
            if let annonce = model.annonce { toast(annonce) }
            if let recu = model.avisCandidature { avisCandidature(recu) }
            if let avisLocal {
                avisRefermable(identifiantFermeture: "swipe-avis-fermer", fermer: { self.avisLocal = nil }) {
                    InlineNotice(avisLocal, tone: .success, identifier: "swipe-avis", announcesOnAppear: true)
                }
            }
        }
        .padding(.horizontal, JoleneSpacing.lg)
        .frame(maxWidth: 640)
    }

    /// Annonce d'une action confirmée par le serveur (toast du web).
    @ViewBuilder
    private func toast(_ annonce: SwipeModel.Annonce) -> some View {
        switch annonce {
        case .candidatureEnvoyee:
            HStack(alignment: .center, spacing: JoleneSpacing.sm) {
                InlineNotice(SwipeTextes.candidatureEnvoyee, tone: .success, identifier: "swipe-toast", announcesOnAppear: true)
                if model.candidatureAnnulable != nil {
                    Button(SwipeTextes.annuler) { Task { await model.retirerCandidature() } }
                        .font(JoleneFont.callout.weight(.semibold))
                        .tint(JoleneColor.rose800)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(model.actionEnCours != nil)
                        .accessibilityIdentifier("swipe-toast-annuler")
                }
            }
        case .favoriSauvegarde:
            InlineNotice(SwipeTextes.favoriSauvegardeDetail, title: SwipeTextes.favoriSauvegarde, tone: .success,
                         identifier: "swipe-toast", announcesOnAppear: true)
        case let .candidatureRetiree(missionId):
            avisRefermable(identifiantFermeture: "swipe-toast-fermer", fermer: { model.fermerAnnonce() }) {
                HStack(alignment: .center, spacing: JoleneSpacing.sm) {
                    InlineNotice(SwipeTextes.candidatureRetiree, tone: .info, identifier: "swipe-toast", announcesOnAppear: true)
                    NavigationLink(value: MissionRoute(id: missionId)) {
                        Text(SwipeTextes.voirMission)
                            .font(JoleneFont.callout.weight(.semibold))
                            .foregroundStyle(JoleneColor.rose800)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityIdentifier("swipe-toast-mission")
                }
            }
        }
    }

    /// Avis du ❤️ confirmé : avertissement de planning du serveur (verbatim), documents à compléter (lot 1 : même texte
    /// et même bouton que le détail de mission, vers « Mes documents » natif).
    private func avisCandidature(_ avisRecu: AvisSwipeLike) -> some View {
        avisRefermable(identifiantFermeture: "swipe-avis-candidature-fermer", fermer: { model.fermerAvis() }) {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                if let avertissement = avisRecu.avertissement {
                    InlineNotice(avertissement, tone: .warning, identifier: "swipe-avertissement", announcesOnAppear: true)
                }
                if avisRecu.documentsACompleter {
                    InlineNotice(LibellesCandidature.envoyeeDocuments, tone: .info, identifier: "swipe-documents")
                    Button(LibellesCandidature.validerDocuments) { contexte.ouvrir(.documents(onglet: OngletDocuments(parametre: nil))) }
                        .font(JoleneFont.callout.weight(.semibold))
                        .tint(JoleneColor.rose800)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("swipe-documents-ouvrir")
                }
            }
        }
    }

    /// Avis refermable : contenu, puis « Fermer ».
    private func avisRefermable<Contenu: View>(identifiantFermeture: String, fermer: @escaping () -> Void,
                                               @ViewBuilder _ contenu: () -> Contenu) -> some View {
        HStack(alignment: .top, spacing: JoleneSpacing.sm) {
            contenu()
            Button(action: fermer) {
                Image(systemName: "xmark")
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SwipeTextes.fermer)
            .accessibilityIdentifier(identifiantFermeture)
        }
    }

    // MARK: États

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .chargement:
            ProgressView(SwipeTextes.chargement)
                .tint(JoleneColor.rose700)
                .accessibilityIdentifier("swipe-chargement")
        case let .echec(message):
            // Titre et explication du web ; le message de l'erreur (réseau, session) est affiché en dessous, tel quel.
            ScrollView {
                VStack(spacing: JoleneSpacing.md) {
                    EmptyState(systemImage: "exclamationmark.triangle", title: SwipeTextes.echecTitre,
                               message: SwipeTextes.echecDescription, identifier: "swipe-echec",
                               actionTitle: SwipeTextes.reessayer, actionIdentifier: "swipe-reessayer") {
                        Task { await model.charger() }
                    }
                    InlineNotice(message, tone: .error, identifier: "swipe-echec-message")
                        .padding(.horizontal, JoleneSpacing.lg)
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        case .pret:
            if model.cartesAffichees.isEmpty { finDePaquet } else { paquet }
        }
    }

    private var paquet: some View {
        let cartes = model.cartesAffichees
        let occupe = model.actionEnCours != nil || parcours.envoiEnCours
        return VStack(spacing: JoleneSpacing.sm) {
            // Conteneur `swipe-deck` posé ici, autour du compteur ET des cartes : jamais la carte du dessus seule, que le
            // conteneur absorberait (identifiant `swipe-card-<id>` perdu sur la dernière carte, `SwipeCardStack`).
            VStack(spacing: JoleneSpacing.sm) {
                Text(SwipeTextes.restantes(cartes.count))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("swipe-restantes")
                SwipeCardStack(cartes, identifier: "", cardAccessibility: .contain, isBusy: occupe, onAction: { action, carte in
                    agir(action, sur: carte.id)
                }, card: { carte in
                    SwipeCarteView(carte: carte) { ouvrirDetail(carte.id) }
                })
                .frame(maxWidth: 440)
                .padding(.horizontal, JoleneSpacing.lg)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(SwipeDeckIdentifiers.deck)
            SwipeActionBar(isDisabled: occupe) { action in
                if let premiere = cartes.first { agir(action, sur: premiere.id) }
            }
        }
        .padding(.top, JoleneSpacing.xs)
    }

    /// Point unique des gestes et des boutons : ✕ et ⭐ posent le verrou du modèle dans l'appel (la carte reste
    /// décalée pendant l'envoi), ❤️ ouvre le récapitulatif.
    private func agir(_ action: SwipeCardAction, sur missionId: String) {
        switch action {
        case .passer: model.lancer(.passer, missionId)
        case .sauvegarder: model.lancer(.favori, missionId)
        case .candidater: parcours.demander(missionId)
        }
    }

    private func ouvrirDetail(_ missionId: String) {
        guard parcours.etape == .aucune, model.actionEnCours == nil else { return }
        feuilleLocale = .detail(missionId)
    }

    // MARK: Fin de paquet

    private var finDePaquet: some View {
        let etat = SwipePresentation.finDePaquet(paquetLuNonVide: model.paquetLuNonVide)
        return ScrollView {
            VStack(spacing: JoleneSpacing.lg) {
                VStack(spacing: JoleneSpacing.lg) {
                    Image(systemName: model.paquetLuNonVide ? "sparkles" : "magnifyingglass")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(JoleneColor.heroGradient)
                        .accessibilityHidden(true)
                    Text(etat.titre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("swipe-fin-titre")
                    Text(etat.description)
                        .font(JoleneFont.body)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .multilineTextAlignment(.center)
                    VStack(spacing: JoleneSpacing.md) {
                        if porteAlerte == .natif {
                            JoleneButton(etat.alerte, style: .secondary) {
                                alerte.effacerIssue()
                                feuilleLocale = .alerte
                            }
                            .accessibilityIdentifier("swipe-fin-alerte")
                        }
                        JoleneButton(etat.secondaire, style: .secondary) {
                            if etat.elargirLeRayon {
                                Task {
                                    await missions.appliquer(missions.filtres.elargissantRayon())
                                    versLaListe()
                                }
                            } else {
                                versLaListe()
                            }
                        }
                        .accessibilityIdentifier("swipe-fin-secondaire")
                    }
                    .frame(maxWidth: 320)
                }
                .padding(JoleneSpacing.xl)
                .frame(maxWidth: .infinity)
                favorisReproposes
            }
            .padding(.horizontal, JoleneSpacing.lg)
            .padding(.bottom, JoleneSpacing.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .accessibilityIdentifier("swipe-fin-paquet")
    }

    /// Missions sauvegardées `OUVERTE` à venir, re-proposées en fin de paquet (anti-fuite du favori) : cinq au plus,
    /// le titre annonce le total lu ; chacune ouvre son détail.
    @ViewBuilder private var favorisReproposes: some View {
        let favoris = model.favorisFinDePaquet
        if !favoris.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                SectionHeader(SwipeTextes.favorisTitre(favoris.count), identifier: "swipe-favoris")
                ForEach(Array(favoris.prefix(SwipePresentation.favorisAffiches))) { ligne in
                    if let mission = ligne.mission {
                        NavigationLink(value: MissionRoute(id: mission.id)) {
                            HStack(spacing: JoleneSpacing.sm) {
                                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                                    Text(FavorisPresentation.titreMission(mission))
                                        .font(JoleneFont.headline)
                                        .foregroundStyle(JoleneColor.midnight)
                                        .multilineTextAlignment(.leading)
                                    Text(FavorisPresentation.detailMission(mission))
                                        .font(JoleneFont.caption)
                                        .foregroundStyle(JoleneColor.bubblegum)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(JoleneFont.caption.weight(.semibold))
                                    .foregroundStyle(JoleneColor.rose700)
                                    .accessibilityHidden(true)
                            }
                            .padding(JoleneSpacing.md)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(JoleneColor.cloud)
                            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(FavorisPresentation.titreMission(mission)), \(FavorisPresentation.detailMission(mission))")
                        .accessibilityIdentifier("swipe-favori-\(mission.id)")
                    }
                }
            }
        }
    }

    // MARK: Feuilles

    private var feuille: FeuilleSwipe? {
        if let missionId = parcours.etape.missionId { return .candidature(missionId) }
        switch feuilleLocale {
        case .quiz?: return .quiz
        case .detail(let missionId)?: return .detail(missionId)
        case .alerte?: return .alerte
        case nil: return nil
        }
    }

    /// Fermeture par le geste : même effet que le bouton d'annulation de la feuille affichée.
    private var feuillePresentee: Binding<FeuilleSwipe?> {
        Binding(get: { feuille }, set: { nouvelle in
            guard nouvelle == nil else { return }
            if parcours.etape != .aucune { parcours.abandonner() } else { fermerFeuilleLocale() }
        })
    }

    /// Le quiz refermé, de quelque façon que ce soit, ne revient plus.
    private func fermerFeuilleLocale() {
        if feuilleLocale == .quiz { marqueurs.marquerQuizVu() }
        feuilleLocale = nil
    }

    private func executerApresFermeture() {
        guard let action = apresFermeture else { return }
        apresFermeture = nil
        switch action {
        case .recapitulatif(let missionId): parcours.demander(missionId)
        case .ouvrir(let cible): contexte.ouvrir(cible)
        }
    }

    @ViewBuilder
    private func contenuFeuille(_ feuille: FeuilleSwipe) -> some View {
        switch feuille {
        case .candidature(let missionId):
            FeuilleCandidatureSwipe(parcours: parcours, model: model, missionId: missionId)
        case .detail(let missionId):
            if let carte = model.carteDuPaquet(missionId) {
                SwipeDetailSheet(carte: carte, occupe: model.actionEnCours != nil, onSuivant: {
                    fermerFeuilleLocale()
                    model.lancer(.passer, missionId)
                }, onPostuler: {
                    // Le récapitulatif s'ouvre une fois le détail refermé.
                    apresFermeture = .recapitulatif(missionId)
                    fermerFeuilleLocale()
                })
            }
        case .quiz:
            QuizPreferencesSheet(envoiEnCours: quizEnCours, ouvrirPoolUrgence: ouverturePoolUrgence, onValider: validerQuiz,
                                 onPlusTard: fermerFeuilleLocale)
        case .alerte:
            ConfirmationSheet(configurationAlerte, isLoading: alerte.enCours,
                              onCancel: { if !alerte.enCours { fermerFeuilleLocale() } },
                              onConfirm: activerAlerte) {
                if case let .echec(message)? = alerte.issue {
                    InlineNotice(message, tone: .error, identifier: "swipe-alerte-erreur", announcementID: alerte.jeton)
                }
            }
        }
    }

    // MARK: Quiz

    /// Premier contact avec le paquet : quiz proposé une fois par compte, jamais deux fois par montage de la vue.
    private func proposerQuiz() async {
        guard !quizVerifie else { return }
        quizVerifie = true
        switch await model.quizPremierContact(dejaVu: marqueurs.quizVu) {
        case .proposer:
            if feuille == nil { feuilleLocale = .quiz }
        case .dejaFait:
            marqueurs.marquerQuizVu()
        case .indetermine:
            quizVerifie = false
        }
    }

    /// « C'est parti 🚀 » : préférences amorcées côté serveur (au mieux, comme le web), critères appliqués à Explorer.
    /// La confirmation n'est affichée que si le serveur a répondu (aucun succès fabriqué).
    private func validerQuiz(_ reponses: ReponsesQuizSwipe) {
        guard !quizEnCours else { return }
        quizEnCours = true
        Task {
            let applique = await model.appliquerQuiz(reponses.preferences)
            await missions.appliquer(reponses.appliquees(a: missions.filtres))
            quizEnCours = false
            if applique { avisLocal = QuizSwipe.confirmation }
            fermerFeuilleLocale()
        }
    }

    /// Renvoi vers l'écran Pool urgence (web tant que T11 n'a pas livré l'écran natif) ; `nil` si la cible n'est pas
    /// présentable. Présenté une fois le quiz refermé.
    private var ouverturePoolUrgence: (() -> Void)? {
        guard let destination = DestinationLien(link: EcranSecondaire.poolUrgence.lienWeb) else { return nil }
        let cible = CibleNotification(destination)
        guard cible.estPresentable(renvoiWebDisponible: presentateurRenvoiWeb != nil) else { return nil }
        return {
            apresFermeture = .ouvrir(cible)
            fermerFeuilleLocale()
        }
    }

    // MARK: Alerte en un toucher (fin de paquet)

    /// Confirmation de T4 (`AlerteRapideExplorer`), mêmes textes et même modèle : aucune alerte existante n'est réécrite.
    private var configurationAlerte: ConfirmationSheet.Configuration {
        ConfirmationSheet.Configuration(
            title: FiltresTextes.alerteRapideTitre,
            message: FiltresTextes.alerteRapideDescription(
                profession: FiltresPresentation.professionAlerte(filtres: missions.filtres, profile: missions.profile),
                rayonKm: missions.filtres.rayonKm,
                filtreEtablissement: missions.filtres.etablissementId != nil),
            confirmTitle: FiltresTextes.alerteRapideActiver,
            cancelTitle: FiltresTextes.alerteRapideAnnuler,
            identifier: "swipe-alerte")
    }

    private func activerAlerte() {
        let filtres = missions.filtres
        let profil = missions.profile
        Task {
            guard await alerte.activer(filtres: filtres, profile: profil), case let .confirmee(message)? = alerte.issue else { return }
            avisLocal = message
            fermerFeuilleLocale()
        }
    }

    private func lirePorteAlerte() async -> PorteEcranNatif {
        await PorteEcranNatif.lire(EcranSecondaire.recherches,
                                   flags: contexte.session.controller.gateways(for: contexte.snapshot.epoch)?.flags)
    }

    // MARK: Session

    /// « Vérifier ma session » : revalide la session, puis relit si elle est toujours prête pour cet epoch.
    private func verifierSession() async {
        await session.start()
        guard session.state.snapshot?.epoch == contexte.snapshot.epoch else { return }
        await model.charger()
    }
}

private extension SwipeModel.Annonce {
    /// Annonces qui se referment seules après `ReglagesSwipe.dureeAnnulation` (toasts du web) ; « Candidature
    /// retirée » reste jusqu'à sa fermeture.
    var expire: Bool {
        switch self {
        case .candidatureEnvoyee, .favoriSauvegarde: return true
        case .candidatureRetiree: return false
        }
    }
}

// MARK: - Parcours du ❤️

/// Feuille unique du parcours du ❤️ : récapitulatif exact (lot 1 : mêmes textes, mêmes identifiants que le détail de
/// mission), feuille « première candidature » la première fois (HARD STOP n°4, `PremiereCandidatureSheet`), choix du
/// contrat quand le serveur le demande. Le contenu suit `ParcoursCandidatureSwipe.etape` ; la feuille ne se referme
/// pas pendant l'envoi. La carte et la dernière étape affichées sont gardées pendant la fermeture (la carte quitte le
/// paquet dès la candidature relue).
private struct FeuilleCandidatureSwipe: View {
    @ObservedObject var parcours: ParcoursCandidatureSwipe
    @ObservedObject var model: SwipeModel
    let missionId: String
    @State private var carte: CarteSwipe?
    @State private var etape: ParcoursCandidatureSwipe.Etape
    @State private var options: [ChoixContratOption]
    @State private var choixSelectionne: String?

    private typealias L = LibellesCandidature

    init(parcours: ParcoursCandidatureSwipe, model: SwipeModel, missionId: String) {
        self.parcours = parcours
        self.model = model
        self.missionId = missionId
        _carte = State(initialValue: model.carteDuPaquet(missionId))
        _etape = State(initialValue: parcours.etape)
        _options = State(initialValue: model.optionsContrat)
    }

    var body: some View {
        Group {
            switch etape {
            case .premiereCandidature:
                PremiereCandidatureSheet(envoiEnCours: parcours.envoiEnCours,
                                         onConfirmer: { Task { await parcours.confirmerPremiereCandidature() } },
                                         onPasMaintenant: { parcours.abandonner() })
            case .choixContrat:
                choixContrat
            case .recapitulatif, .aucune:
                recapitulatif
            }
        }
        .interactiveDismissDisabled(parcours.envoiEnCours)
        .onChange(of: parcours.etape) { nouvelle in
            if nouvelle != .aucune { etape = nouvelle }
        }
        .onChange(of: model.optionsContrat) { nouvelles in
            if !nouvelles.isEmpty { options = nouvelles }
        }
    }

    /// Récapitulatif exact (`RecapitulatifCandidatureDialog`) : planning candidat, phrase d'engagement du web (verbatim,
    /// `TextesWeb.Candidature`), confirmation désactivée tant que le planning n'est pas exact.
    private var recapitulatif: some View {
        let planning = carte.map { SwipePresentation.planning($0) }
        let configuration = ConfirmationSheet.Configuration(
            title: L.recapTitre, message: L.recapDescription(intitule: carte?.mission.record.intitule),
            confirmTitle: L.recapEnvoyer, cancelTitle: L.recapAnnuler, identifier: "candidature-recap")
        return ConfirmationSheet(configuration, isLoading: parcours.envoiEnCours, isConfirmEnabled: planning?.exact ?? false,
                                 onCancel: { parcours.abandonner() },
                                 onConfirm: { Task { await parcours.confirmerRecapitulatif() } }) {
            if let planning {
                SlotList(planning: planning, identifier: "candidature-recap-planning", libelle: MissionPresentation.creneauCandidat)
                if planning.exact {
                    Text(L.recapEngagement(.swipeLike))
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("candidature-recap-engagement")
                }
            }
        }
    }

    /// Choix du contrat (`ChoixContratDialog`, textes du lot 1) : options du serveur, ❤️ rejoué avec l'option choisie.
    /// La mémorisation du choix du web (écriture directe de `soignants.preference_contrat_mixte`) n'est pas portée.
    private var choixContrat: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(L.choixTitre)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(L.choixDescription)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(options, id: \.value) { option in
                    FilterChip(option.label, isSelected: choixSelectionne == option.value,
                               identifier: "choix-contrat-\(option.value)") { choixSelectionne = option.value }
                        .disabled(parcours.envoiEnCours)
                }
                JoleneButton(L.choixConfirmer, isLoading: parcours.envoiEnCours) {
                    guard let choix = choixSelectionne else { return }
                    Task { await parcours.choisirContrat(choix) }
                }
                .disabled(choixSelectionne == nil || parcours.envoiEnCours)
                .accessibilityIdentifier("choix-contrat-confirmer")
                JoleneButton(L.recapAnnuler, style: .secondary) { parcours.abandonner() }
                    .disabled(parcours.envoiEnCours)
                    .accessibilityIdentifier("choix-contrat-annuler")
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.cloud.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("choix-contrat")
    }
}
