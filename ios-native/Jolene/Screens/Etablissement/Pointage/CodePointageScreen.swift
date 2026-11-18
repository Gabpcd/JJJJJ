import SwiftUI
import JoleneCore
import JoleneDesign

/// Code de pointage rotatif d'une mission, côté établissement (lot 5, T7) : vue de `CodeRotatifModel`, port de
/// `AffichageCodeRotatifEtab.tsx` (rendu par la page web des présences d'une mission). L'établissement montre le code ou
/// le QR au soignant, qui le scanne ou le saisit depuis son app ; le code est relu au serveur toutes les 5 s (D23),
/// seulement écran visible et scène active, et change à chaque scan. « Afficher en plein écran » présente le code en
/// grand et le QR au plus grand (`FullScreenCodeView`) ; l'écran reste allumé tant qu'un code est affiché
/// (`VeilleEcran.controleur`), et la veille est rétablie à la disparition, en arrière-plan et dès que le code est masqué.
/// La clôture d'un segment par l'établissement (fin rétroactive) relève des présences (T8, B9) : non portée ici.
///
/// Identifiants : `etab-pointage-screen`, `-scroll`, `-loading`, `-reserve`, `-indisponible` (+ `-reessayer`), `-aucun`,
/// `-masque` (+ `-titre`, `-motif`), `-momentanement`, `-creneau`, `-prochain`, `-rotation`, `-code`, `-qr`,
/// `-segment-en-cours`, `-plein-ecran` (bouton), `-plein-ecran-vue` (+ `-code`, `-qr`), `-fermer`, `-segments`,
/// `etab-pointage-segment-{index}`.
struct CodePointageScreen: View {
    @StateObject private var model: CodeRotatifModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var pleinEcran = false
    @State private var visible = false
    /// Demandeur de la veille propre à cet écran (une demande par écran affiché).
    @State private var demandeurVeille = "etab-pointage-\(UUID().uuidString)"

    init(missionId: String, session: SessionStore, snapshot: EtablissementSessionSnapshot) {
        _model = StateObject(wrappedValue: CodeRotatifModel(missionId: missionId, controller: session.controller, snapshot: snapshot))
    }

    private typealias R = CodeRotatifRules
    static let libellePleinEcran = "Afficher en plein écran"
    static let libelleFermer = "Fermer"
    static let libelleQR = "QR du code de pointage"
    static let messageAucun = "Aucun code de pointage n’est à présenter pour cette mission."

    private var sceneActive: Bool { scenePhase == .active }
    /// L'écran reste allumé tant qu'un code est présenté sur un écran visible d'une scène active.
    private var veilleDesactivee: Bool { visible && sceneActive && model.codePresente != nil }

    var body: some View {
        ZStack {
            if pleinEcran, let code = model.codePresente {
                FullScreenCodeView(
                    chiffres: code.chiffres, valeur: code.valeur, consigne: consigne(code), libelleQR: Self.libelleQR,
                    libelleFermer: Self.libelleFermer,
                    identifiants: .init(vue: "etab-pointage-plein-ecran-vue", code: "etab-pointage-plein-ecran-code",
                                        qr: "etab-pointage-plein-ecran-qr", fermer: "etab-pointage-fermer"),
                    onClose: { pleinEcran = false })
            } else {
                ScrollView { contenu }
                    .background(JoleneColor.lavender.ignoresSafeArea())
                    .accessibilityIdentifier("etab-pointage-scroll")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-pointage-screen")
        .navigationTitle(R.titreCodePointage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(pleinEcran ? .hidden : .automatic, for: .navigationBar)
        .toolbar(pleinEcran ? .hidden : .automatic, for: .tabBar)
        .statusBarHidden(pleinEcran)
        // Suivi seulement scène active : la tâche est relancée à chaque changement, annulée à la disparition.
        .task(id: sceneActive) {
            if sceneActive { await model.suivre() } else { model.desactiver() }
        }
        .onAppear {
            visible = true
            appliquerVeille()
        }
        .onDisappear {
            visible = false
            model.desactiver()
            appliquerVeille()
        }
        .onChange(of: veilleDesactivee) { _ in appliquerVeille() }
        .onChange(of: model.codePresente == nil) { masque in if masque { pleinEcran = false } }
    }

    private func appliquerVeille() {
        VeilleEcran.controleur.appliquer(veilleDesactivee: veilleDesactivee, demandeur: demandeurVeille)
    }

    private func consigne(_ code: CodeRotatifRules.CodeVisible) -> String {
        "\(R.consignePresentation) \(code.prochainPointage)."
    }

    // MARK: - Contenu

    @ViewBuilder private var contenu: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
            if model.chargement {
                ProgressView(R.messageChargement)
                    .tint(JoleneColor.rose700)
                    .frame(maxWidth: .infinity)
                    .padding(JoleneSpacing.xxl)
                    .accessibilityIdentifier("etab-pointage-loading")
            } else {
                bloc
                if !model.segments.isEmpty { segments }
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var bloc: some View {
        switch model.affichage.bloc {
        case .reservePointage:
            carte(identifiant: "etab-pointage-reserve") {
                titre(R.titreCodePointage, identifiant: nil)
                corps(R.messageReservePointage, identifiant: "etab-pointage-reserve-message")
            }
        case let .indisponible(message):
            carte(identifiant: "etab-pointage-indisponible") {
                titre(R.titreIndisponible, identifiant: "etab-pointage-indisponible-titre")
                corps(message, identifiant: "etab-pointage-indisponible-message")
                JoleneButton(R.libelleReessayer, style: .secondary) { Task { await model.reessayer() } }
                    .accessibilityIdentifier("etab-pointage-reessayer")
            }
        case .aucun:
            EmptyState(systemImage: "clock", title: R.titreCodePointage, message: Self.messageAucun, identifier: "etab-pointage-aucun")
        case let .planningInutilisable(message):
            masque(R.titreMasque, detail: message)
        case let .code(code):
            creneauActif
            codeVisible(code)
        case .momentanementIndisponible:
            creneauActif
            corps(R.messageMomentanementIndisponible, identifiant: "etab-pointage-momentanement")
        case let .masque(intitule, detail):
            creneauActif
            masque(intitule, detail: detail)
        }
    }

    @ViewBuilder private var creneauActif: some View {
        if let creneau = model.affichage.creneauActif {
            Text(creneau.libelle)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("etab-pointage-creneau")
        }
    }

    private func codeVisible(_ code: CodeRotatifRules.CodeVisible) -> some View {
        VStack(spacing: JoleneSpacing.md) {
            HStack(spacing: JoleneSpacing.xs) {
                Image(systemName: "arrow.triangle.2.circlepath").accessibilityHidden(true)
                Text(R.libelleChangeAChaqueScan)
            }
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("etab-pointage-rotation")
            Text(consigne(code))
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("etab-pointage-prochain")
            Text(code.chiffres)
                .font(.system(.largeTitle, design: .monospaced).weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityIdentifier("etab-pointage-code")
            QRCodeImage(code.valeur, side: 180, accessibilityLabel: Self.libelleQR, identifier: "etab-pointage-qr")
            if code.segmentEnCours {
                StatusPill(R.libelleSegmentEnCours, tone: .success, systemImage: "clock", identifier: "etab-pointage-segment-en-cours")
            }
            JoleneButton(Self.libellePleinEcran) { pleinEcran = true }
                .accessibilityIdentifier("etab-pointage-plein-ecran")
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: JoleneRadius.card).fill(JoleneColor.cloud))
        .accessibilityElement(children: .contain)
    }

    private func masque(_ intitule: String, detail: String) -> some View {
        carte(identifiant: "etab-pointage-masque") {
            titre(intitule, identifiant: "etab-pointage-masque-titre")
            corps(detail, identifiant: "etab-pointage-masque-motif")
        }
    }

    private var segments: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(R.titreSegments)
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(model.segments.enumerated()), id: \.element.id) { index, ligne in
                HStack {
                    Text(ligne.libelle)
                    Spacer(minLength: JoleneSpacing.sm)
                    Text(ligne.duree).fontWeight(.semibold)
                }
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.midnight)
                .padding(.horizontal, JoleneSpacing.md)
                .padding(.vertical, JoleneSpacing.sm)
                .background(RoundedRectangle(cornerRadius: JoleneRadius.field).fill(JoleneColor.cloud))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("etab-pointage-segment-\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-pointage-segments")
    }

    // MARK: - Briques

    private func carte<Contenu: View>(identifiant: String, @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) { contenu() }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: JoleneRadius.card).fill(JoleneColor.cloud))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifiant)
    }

    @ViewBuilder private func titre(_ texte: String, identifiant: String?) -> some View {
        let vue = Text(texte)
            .font(JoleneFont.headline)
            .foregroundStyle(JoleneColor.midnight)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        if let identifiant { vue.accessibilityIdentifier(identifiant) } else { vue }
    }

    private func corps(_ texte: String, identifiant: String) -> some View {
        Text(texte)
            .font(JoleneFont.callout)
            .foregroundStyle(JoleneColor.bubblegum)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifiant)
    }
}
