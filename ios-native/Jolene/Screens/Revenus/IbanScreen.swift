import SwiftUI
import JoleneCore
import JoleneDesign

/// Route de l'écran « Coordonnées bancaires », empilée sur l'onglet Profil depuis l'entrée du hub (`iban-ouvrir`) ;
/// destination enregistrée par `ProfileScreen`, sur la liste et non dans ses lignes (comme `MotDePasseRoute`). Aucune
/// route web (DECISIONS_LOT3 : l'IBAN est une sous-ligne de `/soignant/mon-compte`, sans lien universel).
struct IbanRoute: Hashable {}

/// Section « Paiements & facturation » du hub (`MonCompteSoignant.tsx` l.64-77), entrée « Coordonnées bancaires »
/// (l.73) : le web fait défiler jusqu'à `SectionPaiements` (l.160-169), le natif empile l'écran. Les entrées Stripe et
/// mandat de la même section web (l.67-70, libéral seulement) relèvent de T14a.
struct IbanEntreeSection: View {
    var body: some View {
        Section(IbanTextes.sectionHub) {
            NavigationLink(value: IbanRoute()) {
                Label(IbanTextes.entreeHub, systemImage: "building.columns")
            }
            .accessibilityIdentifier("iban-ouvrir")
        }
    }
}

/// « Coordonnées bancaires » (lot 3, T14b, B9 ; D20, TJ6), port de `SectionIbanPrime` (`SectionPaiements.tsx`
/// l.227-376) : état relu (`fn_consulter_mon_iban`), IBAN masqué (quatre derniers caractères), saisie contrôlée (mod 97
/// du web), titulaire, enregistrement confirmé par relecture. Clavier ASCII en majuscules, sans autocorrection ni
/// suggestion ; champ marqué `privacySensitive` (masqué sous la rédaction `.privacy` : widgets, écran verrouillé ; pas
/// dans l'instantané du sélecteur d'apps ni dans les captures d'écran) ; IBAN vidé dès l'envoi. Les toasts du web
/// deviennent des encarts annoncés. Identifiants : `iban-screen`, `iban-actuel`, `iban-actuel-titulaire`,
/// `iban-rib-requis`, `iban-rib-requis-documents`, `iban-input`, `iban-valide`, `iban-invalide`, `iban-titulaire`,
/// `iban-enregistrer`, `iban-succes`, `iban-erreur`, `iban-refus-documents`, `iban-session-verifier`, `iban-reessayer`.
struct IbanScreen: View {
    @StateObject private var model: IbanModel

    private typealias Textes = IbanTextes

    init(session: SessionStore, snapshot: SessionSnapshot) {
        _model = StateObject(wrappedValue: IbanModel(session: session, snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                switch model.etat {
                case .chargement:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, JoleneSpacing.lg)
                        .accessibilityIdentifier("iban-chargement")
                case .echec(let message):
                    // Session expirée : titre « Session à vérifier » du lot 1 (TJ6, règle 2 ; `ProfilEditionScreen`).
                    InlineNotice(message, title: model.sessionExpiree ? ProfilEdition.Textes.sessionAVerifier : nil,
                                 tone: .error, identifier: "iban-erreur", announcesOnAppear: true,
                                 announcementID: model.annonces)
                    if model.sessionExpiree {
                        verifierSession
                    } else {
                        JoleneButton(RevenusTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                            .accessibilityIdentifier("iban-reessayer")
                    }
                case .pret:
                    etatActuel
                    issue
                    formulaire
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("iban-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(Textes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.enCours)
        .task { await model.charger() }
    }

    /// « IBAN enregistré » + IBAN masqué + titulaire (l.287-300) ; « RIB vérifié requis » + « Téléverser mon RIB »
    /// (l.302-320 ; texte de l.308 non porté, DECISIONS_LOT3 section T14b).
    @ViewBuilder private var etatActuel: some View {
        if model.afficheEnregistre, let masque = model.masque {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                InlineNotice(masque, title: Textes.ibanEnregistre, tone: .success, identifier: "iban-actuel")
                if let titulaire = model.ligneTitulaire {
                    Text(verbatim: titulaire)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityIdentifier("iban-actuel-titulaire")
                }
            }
        }
        if model.afficheRibRequis {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                Text(Textes.ribVerifieRequis)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityIdentifier("iban-rib-requis")
                lienDocuments(.televerserRib, identifiant: "iban-rib-requis-documents")
            }
            .padding(JoleneSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.butter100)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        }
    }

    @ViewBuilder private var issue: some View {
        switch model.issue {
        case .enregistre?:
            InlineNotice(Textes.ibanEnregistre, tone: .success, identifier: "iban-succes", announcesOnAppear: true,
                         announcementID: model.annonces)
        case .refus(let refus)?:
            InlineNotice(refus.message, title: refus.titre, tone: .error, identifier: "iban-erreur", announcesOnAppear: true,
                         announcementID: model.annonces)
            if let action = refus.action { lienDocuments(action, identifiant: "iban-refus-documents") }
        case .erreur(let message)?:
            InlineNotice(message, title: model.sessionExpiree ? ProfilEdition.Textes.sessionAVerifier : nil, tone: .error,
                         identifier: "iban-erreur", announcesOnAppear: true, announcementID: model.annonces)
            if model.sessionExpiree { verifierSession }
        case nil:
            EmptyView()
        }
    }

    private var formulaire: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                JoleneTextField(model.libelleChamp, text: $model.iban, kind: .iban, placeholder: Textes.placeholderIban,
                                identifier: "iban-input")
                    .privacySensitive()
                if model.afficheInvalide {
                    Label(Textes.ibanInvalide, systemImage: "exclamationmark.circle")
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.rose700)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Textes.ibanInvalide)
                        .accessibilityIdentifier("iban-invalide")
                }
                if model.afficheValide {
                    Label(Textes.ibanValide, systemImage: "checkmark.circle.fill")
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.cyan900)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Textes.ibanValide)
                        .accessibilityIdentifier("iban-valide")
                }
            }
            JoleneTextField(Textes.libelleTitulaire, text: $model.titulaire, kind: .nomComplet,
                            placeholder: Textes.placeholderTitulaire, identifier: "iban-titulaire")
            JoleneButton(model.libelleBouton, isLoading: model.enCours) { Task { await model.enregistrer() } }
                .disabled(!model.peutEnregistrer)
                .accessibilityIdentifier("iban-enregistrer")
        }
    }

    private var verifierSession: some View {
        JoleneButton(ProfilEdition.Textes.verifierSession, style: .secondary) { Task { await model.verifierSession() } }
            .accessibilityIdentifier("iban-session-verifier")
    }

    /// « Téléverser mon RIB » (l.316) ou « Mes documents » : documents du lot 2 sur la même pile (`MonEspaceRoute`).
    /// Un identifiant par surface (état non vérifié, refus) : les deux peuvent être affichées ensemble (PRINCIPES §6).
    private func lienDocuments(_ action: RefusIbanAffiche.Action, identifiant: String) -> some View {
        NavigationLink(value: MonEspaceRoute.documents(onglet: .justificatifs)) {
            Text(action == .televerserRib ? Textes.televerserRib : Textes.mesDocuments)
                .font(JoleneFont.button)
                .foregroundStyle(JoleneColor.rose700)
                .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier(identifiant)
    }
}
