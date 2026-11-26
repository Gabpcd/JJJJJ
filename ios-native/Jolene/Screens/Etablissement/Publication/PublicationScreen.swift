import SwiftUI
import JoleneCore
import JoleneDesign

/// Publication d'une mission simple ou urgente (lot 5, T9) : vue de `PublicationModel` (JoleneCore), port de
/// `FormulaireMission.tsx` réduit au périmètre natif (D8). Sections : annonce (refus serveur mot pour mot, blocage de
/// publication avec renvoi web, issue non confirmée), intitulé, description, profession (liste du web sans celle
/// renvoyée au web), service, planning (`PlanningJoursEditor` : période → jours → créneaux), taux horaire, urgence,
/// mode de sélection, options renvoyées au web (texte neutre D8), bouton qui ouvre le récapitulatif
/// (`RecapPublicationSheet`). « Mission publiée » n'apparaît qu'après la relecture de la mission créée (port).
///
/// L'écran n'affiche ni ne propose aucun type de contrat ni mode d'exercice ; il ne calcule aucun montant (seul le taux
/// saisi est repris au récapitulatif) et aucune règle du temps de travail. Les règles d'état sont testées dans
/// `PublicationModelTests`, la charge dans `PublicationPayloadTests` ; la vue n'ajoute aucune logique.
///
/// Identifiants : `publier-screen`, `publier-intitule`, `publier-description`, `publier-profession`, `publier-service`
/// (+ `-suggestions`), `publier-taux`, `publier-urgente`, `publier-niveau-{1|2|3}`,
/// `publier-mode-{PREMIER_ARRIVE|CANDIDATURE}`, `publier-mode-aide`, `publier-renvoi-web-{liberal|medecin|recurrence|dupliquer}`
/// (valeur : URL du renvoi), `publier-taux-minimum`, `publier-ouvrir-recap`, `publier-erreur` (+ `-missions`), `publier-blocage` (+ `-ouvrir`),
/// `publier-succes` (+ `-mission`, `-missions`, `-nouvelle`) ; planning : voir `PlanningJoursEditor` ; récapitulatif :
/// voir `RecapPublicationSheet`.
struct PublicationScreen: View {
    @StateObject private var model: PublicationModel
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @Environment(\.dismiss) private var dismiss
    @FocusState private var descriptionFocus: Bool

    init(session: SessionStore, snapshot: EtablissementSessionSnapshot) {
        _model = StateObject(wrappedValue: PublicationModel(controller: session.controller, snapshot: snapshot))
    }

    private typealias P = PublicationPresentation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                switch model.etat {
                case .saisie:
                    formulaire
                case let .publiee(missionId):
                    succes(missionId)
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publier-screen")
        .navigationTitle(P.titreEcran)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.chargerTauxMinimum() }
        .refreshable { await model.chargerTauxMinimum() }
        .sheet(isPresented: recapPresente) {
            if let recap = model.recap {
                RecapPublicationSheet(recap: recap, enCours: model.enCours,
                                      onCancel: { model.annulerRecapitulatif() },
                                      onConfirm: { Task { await model.confirmerPublication() } })
            }
        }
    }

    private var recapPresente: Binding<Bool> {
        Binding(get: { model.recap != nil }, set: { presente in if !presente { model.annulerRecapitulatif() } })
    }

    // MARK: - Formulaire

    @ViewBuilder private var formulaire: some View {
        annonce
        identite
        planning
        conditions
        renvoisWeb
        JoleneButton(P.boutonPublier(creneaux: model.creneaux.count)) { model.ouvrirRecapitulatif() }
            .disabled(!model.peutOuvrirRecap)
            .accessibilityIdentifier("publier-ouvrir-recap")
    }

    /// Intitulé, description, profession, service.
    @ViewBuilder private var identite: some View {
        champ(P.intitule) {
            TextField(P.intituleExemple, text: Binding(get: { model.saisie.intitule }, set: { model.definirIntitule($0) }))
                .submitLabel(.done)
                .accessibilityLabel(P.intitule)
                .accessibilityIdentifier("publier-intitule")
        }
        champ(P.description) {
            TextField(P.descriptionExemple, text: Binding(get: { model.saisie.description }, set: { model.definirDescription($0) }),
                      axis: .vertical)
                .lineLimit(3...6)
                .focused($descriptionFocus)
                .boutonOKClavier($descriptionFocus)
                .accessibilityLabel(P.description)
                .accessibilityIdentifier("publier-description")
        }
        profession
        service
    }

    /// Taux horaire, urgence, mode de sélection.
    @ViewBuilder private var conditions: some View {
        JoleneTextField(P.taux, text: Binding(get: { model.saisie.taux }, set: { model.definirTaux($0) }), kind: .montant,
                        placeholder: P.tauxExemple, identifier: "publier-taux")
        // Revue B8 des textes de la vague D (M4) : plancher du web (`min` du champ), le bouton restant désactivé dessous.
        if let avis = model.avisTauxSousLeMinimum {
            InlineNotice(avis, tone: .warning, identifier: "publier-taux-minimum")
        }
        urgence
        mode
    }

    @ViewBuilder private var annonce: some View {
        switch model.annonce {
        case nil:
            EmptyView()
        case let .erreur(message):
            InlineNotice(message, tone: .error, identifier: "publier-erreur", announcesOnAppear: true)
        case let .blocage(code, message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .warning, identifier: "publier-blocage", announcesOnAppear: true)
                if let presentateurRenvoiWeb {
                    let url = P.urlBlocage(code: code)
                    JoleneButton(P.blocageOuvrir, style: .secondary) { presentateurRenvoiWeb.presenter(.etablissement(url)) }
                        .accessibilityIdentifier("publier-blocage-ouvrir")
                        .accessibilityValue(url.absoluteString)
                }
            }
        case let .nonConfirmee(detail, _):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(P.texteNonConfirmee(detail: detail), tone: .error, identifier: "publier-erreur", announcesOnAppear: true)
                JoleneButton(P.voirMissions, style: .secondary) { dismiss() }
                    .accessibilityIdentifier("publier-erreur-missions")
            }
        }
    }

    /// Champ de texte libre au style de `JoleneTextField` (libellé, 16 pt, cadre arrondi).
    private func champ<Contenu: View>(_ titre: String, @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(titre).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            contenu()
                .font(.system(size: 16))
                .padding(.horizontal, JoleneSpacing.lg)
                .padding(.vertical, JoleneSpacing.sm)
                .frame(minHeight: 48)
                .background(JoleneColor.cloud)
                .overlay {
                    RoundedRectangle(cornerRadius: JoleneRadius.field)
                        .strokeBorder(JoleneColor.bubblegum.opacity(0.35), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        }
    }

    private var profession: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(P.profession).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            Picker(P.profession, selection: Binding(get: { model.saisie.profession }, set: { model.definirProfession($0) })) {
                Text(P.professionAChoisir).tag("")
                ForEach(PublicationRules.professions, id: \.valeur) { option in
                    Text(option.label).tag(option.valeur)
                }
            }
            .pickerStyle(.menu)
            .tint(JoleneColor.rose700)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityIdentifier("publier-profession")
        }
    }

    private var service: some View {
        HStack(alignment: .bottom, spacing: JoleneSpacing.sm) {
            champ(P.service) {
                TextField(P.serviceExemple, text: Binding(get: { model.saisie.service }, set: { model.definirService($0) }))
                    .submitLabel(.done)
                    .accessibilityLabel(P.service)
                    .accessibilityIdentifier("publier-service")
            }
            Menu {
                ForEach(PublicationRules.services, id: \.self) { suggestion in
                    Button(suggestion) { model.definirService(suggestion) }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(JoleneColor.rose700)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(P.serviceExemple)
            .accessibilityIdentifier("publier-service-suggestions")
        }
    }

    private var planning: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            SectionHeader(P.planningTitre, identifier: "publier-planning")
            Text(P.planningAide)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            PlanningJoursEditor(model: model)
        }
    }

    private var urgence: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            ToggleRow(P.urgente, description: P.urgenteAide,
                      isOn: Binding(get: { model.saisie.estUrgente }, set: { model.definirUrgente($0) }),
                      identifier: "publier-urgente")
            if model.saisie.estUrgente {
                SegmentedChoice(P.niveauUrgence,
                                options: P.niveaux.map { SegmentedChoice.Option(id: String($0.niveau), title: $0.libelle) },
                                selection: Binding(get: { String(model.saisie.niveauUrgence) },
                                                   set: { if let niveau = Int($0) { model.definirNiveauUrgence(niveau) } }),
                                identifier: "publier-niveau")
            }
        }
    }

    private var mode: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            SectionHeader(P.modeSelection, identifier: "publier-mode-titre")
            SegmentedChoice(P.modeSelection,
                            options: ModeAttributionPublication.allCases.map {
                                SegmentedChoice.Option(id: $0.rawValue, title: P.libelleMode($0))
                            },
                            selection: Binding(get: { model.saisie.modeAttribution.rawValue },
                                               set: { if let choix = ModeAttributionPublication(rawValue: $0) { model.definirModeAttribution(choix) } }),
                            identifier: "publier-mode")
            Text(P.aideMode(model.saisie.modeAttribution))
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("publier-mode-aide")
        }
    }

    /// Options qui restent sur le web (D8) : titre de l'option, texte neutre, sortie Safari. Sans présentateur de
    /// renvoi, aucun bouton (règle du lot 3 : jamais un bouton sans effet).
    @ViewBuilder private var renvoisWeb: some View {
        if let presentateurRenvoiWeb {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                SectionHeader(P.renvoiWebTitre, identifier: "publier-renvois-web")
                ForEach(P.RenvoiWeb.allCases) { renvoi in
                    Button { presentateurRenvoiWeb.presenter(.etablissement(renvoi.url)) } label: {
                        HStack(spacing: JoleneSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(renvoi.titre)
                                    .font(JoleneFont.callout.weight(.semibold))
                                    .foregroundStyle(JoleneColor.rose700)
                                    .multilineTextAlignment(.leading)
                                Text(P.renvoiWebMessage)
                                    .font(JoleneFont.caption)
                                    .foregroundStyle(JoleneColor.bubblegum)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "safari")
                                .font(JoleneFont.caption)
                                .foregroundStyle(JoleneColor.bubblegum)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(renvoi.titre). \(P.renvoiWebMessage)")
                    .accessibilityValue(renvoi.url.absoluteString)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier(renvoi.identifiant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JoleneSpacing.md)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        }
    }

    // MARK: - Succès relu

    @ViewBuilder private func succes(_ missionId: String) -> some View {
        InlineNotice(P.succes, tone: .success, identifier: "publier-succes", announcesOnAppear: true)
        NavigationLink(value: EtabDestination.detailMission(id: missionId)) {
            Label(P.voirMission, systemImage: "chevron.right")
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.rose700)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("publier-succes-mission")
        JoleneButton(P.voirMissions) { dismiss() }
            .accessibilityIdentifier("publier-succes-missions")
        JoleneButton(P.nouvellePublication, style: .secondary) { model.nouvellePublication() }
            .accessibilityIdentifier("publier-succes-nouvelle")
    }
}
