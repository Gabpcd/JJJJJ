import SwiftUI
import JoleneCore
import JoleneDesign

/// « Mon profil » (lot 3, T9), ouvert depuis le hub `ProfileScreen` (entrée `profil-ouvrir`). Nom
/// distinct du hub (`Screens/ProfileScreen.swift`, onglet Profil) : jamais deux surfaces pour la même
/// route (CLAUDE.md, « livré ≠ mergé »). Lecture en liste blanche et édition relue
/// (`ProfilEditionModel`) ; textes du web verbatim (`ProfilEdition.Textes`). Type d'exercice et
/// attestation de cumul (L1222-5) non portés : encart `profil-exercice-web`, bouton de renvoi web
/// seulement si un présentateur `.safari` est injecté (jamais un bouton sans effet).
///
/// Identifiants : `profil-screen`, `profil-chargement`, `profil-erreur-chargement`, `profil-reessayer`,
/// `profil-nom-complet`, `profil-prenom`, `profil-nom`, `profil-telephone`, `profil-date-naissance`,
/// `profil-date-naissance-renseigner`, `profil-email`, `profil-profession`, `profil-rpps`,
/// `profil-rpps-verifie`, `profil-ville-recherche`, `profil-bio`, `profil-experience`, `profil-mode-*`,
/// `profil-taux-min`, `profil-taux-min-valeur`, `profil-rayon`, `profil-rayon-valeur`,
/// `profil-exercice-web`, `profil-exercice-web-action`, `profil-enregistre`, `profil-erreur`,
/// `profil-enregistrer`.
struct ProfilEditionScreen: View {
    @StateObject private var model: ProfilEditionModel
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    private typealias Textes = ProfilEdition.Textes

    init(session: SessionStore, snapshot: SessionSnapshot) {
        _model = StateObject(wrappedValue: ProfilEditionModel(session: session, snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                switch model.etat {
                case .chargement:
                    VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                        SkeletonBlock(size: .lg, width: 220)
                        SkeletonCard()
                        SkeletonCard()
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("profil-chargement")
                case let .echec(message):
                    EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: Textes.titre, message: message,
                               identifier: "profil-erreur-chargement", actionTitle: Textes.reessayer,
                               actionIdentifier: "profil-reessayer") { Task { await model.charger() } }
                case let .pret(profil):
                    contenu(profil)
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("profil-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(Textes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .task { if case .chargement = model.etat { await model.charger() } }
    }

    // MARK: - Contenu

    @ViewBuilder
    private func contenu(_ profil: ProfilComplet) -> some View {
        entete(profil)
        carte { informations(profil) }
        carte { villeRecherche }
        carte { presentation }
        carte {
            ChoixModesExerciceSection(choix: model.choixModes, prefixe: "profil",
                                      basculer: { model.basculerMode($0, selectionne: $1) },
                                      reessayer: { Task { await model.verifierModes() } })
        }
        carte { taux }
        carte { rayon }
        typeExercice
        enregistrement
    }

    private func entete(_ profil: ProfilComplet) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text("\(profil.prenom) \(profil.nom)")
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("profil-nom-complet")
            if let profession = profil.profession, !profession.isEmpty {
                Text(MissionPresentation.professionLabel(profession))
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("profil-profession")
            }
            if profil.identiteVerrouillee {
                StatusPill(Textes.rppsVerifie, tone: .success, identifier: "profil-rpps-verifie")
            }
        }
    }

    @ViewBuilder
    private func informations(_ profil: ProfilComplet) -> some View {
        titreCarte(Textes.sectionInformations)
        if profil.identiteVerrouillee {
            lectureSeule(Textes.prenom, valeur: model.formulaire.prenom, identifiant: "profil-prenom", verrou: true)
            lectureSeule(Textes.nom, valeur: model.formulaire.nom, identifiant: "profil-nom", verrou: true)
        } else {
            JoleneTextField(Textes.prenom, text: $model.formulaire.prenom, kind: .prenom, identifier: "profil-prenom")
            JoleneTextField(Textes.nom, text: $model.formulaire.nom, kind: .nom, identifier: "profil-nom")
        }
        JoleneTextField(Textes.telephone, text: $model.formulaire.telephone, kind: .telephone, identifier: "profil-telephone")
        dateNaissance(verrouillee: profil.identiteVerrouillee)
        lectureSeule(Textes.email, valeur: profil.email ?? "—", identifiant: "profil-email", verrou: false)
        if profil.rppsPropose { rpps(profil) }
    }

    @ViewBuilder
    private func dateNaissance(verrouillee: Bool) -> some View {
        if verrouillee {
            lectureSeule(Textes.dateNaissance, valeur: model.formulaire.dateNaissance.flatMap(DateNaissance.affichage) ?? "—",
                         identifiant: "profil-date-naissance", verrou: true)
        } else if model.formulaire.dateNaissance.flatMap(DateNaissance.date) != nil {
            DatePicker(Textes.dateNaissance, selection: DateNaissance.liaison($model.formulaire.dateNaissance),
                       in: ...Date(), displayedComponents: .date)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .frame(minHeight: 44)
                .accessibilityIdentifier("profil-date-naissance")
        } else {
            // Date absente : aucune date fictive affichée ; un appui ouvre le sélecteur.
            Button {
                model.formulaire.dateNaissance = DateNaissance.chaine(DateNaissance.parDefaut)
            } label: {
                Label(Textes.dateNaissance, systemImage: "calendar")
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose800)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("profil-date-naissance-renseigner")
        }
    }

    @ViewBuilder
    private func rpps(_ profil: ProfilComplet) -> some View {
        if profil.identiteVerrouillee {
            lectureSeule(Textes.rpps, valeur: model.formulaire.numeroRpps, identifiant: "profil-rpps", verrou: true)
        } else {
            let libelle = Textes.numeroRpps + (profil.rppsOptionnel ? Textes.suffixeOptionnel : Textes.suffixeRequis)
            ChampProfil(libelle, texte: Binding(get: { model.formulaire.numeroRpps },
                                                 set: { model.formulaire.numeroRpps = FormulaireProfil.filtrerRpps($0) }),
                        placeholder: Textes.rppsPlaceholder, clavier: .numberPad, identifiant: "profil-rpps")
            if let compteur = Textes.rppsCompteur(model.formulaire.numeroRpps.count) {
                legende(compteur).foregroundStyle(JoleneColor.butter800)
            }
            legende(Textes.rppsAide)
        }
    }

    @ViewBuilder
    private var villeRecherche: some View {
        ChampProfil(Textes.villeRecherche, texte: $model.formulaire.villeRecherche,
                    placeholder: Textes.villeRecherchePlaceholder, contenu: .addressCity, identifiant: "profil-ville-recherche")
        legende(Textes.villeRechercheAide)
    }

    @ViewBuilder
    private var presentation: some View {
        titreCarte(Textes.presentation)
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(Textes.bio).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            TextField(Textes.bioPlaceholder,
                      text: Binding(get: { model.formulaire.bio }, set: { model.formulaire.bio = FormulaireProfil.limiterBio($0) }),
                      axis: .vertical)
                .lineLimit(4...8)
                .font(.system(size: 16))
                .padding(JoleneSpacing.md)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .accessibilityLabel(Textes.bio)
                .accessibilityIdentifier("profil-bio")
            Text(Textes.bioCompteur(model.formulaire.bio.count))
                .font(JoleneFont.caption)
                .foregroundStyle(model.formulaire.bio.count >= 450 ? JoleneColor.butter800 : JoleneColor.bubblegum)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        Stepper(value: $model.formulaire.anneesExperience, in: FormulaireProfil.bornesExperience) {
            Text("\(Textes.anneesExperience) * : \(model.formulaire.anneesExperience)")
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("profil-experience")
    }

    @ViewBuilder
    private var taux: some View {
        titreCarte(Textes.tauxTitre)
        legende(Textes.tauxAide)
        let valeur = model.formulaire.tauxDefini ? Textes.taux(model.formulaire.tauxHoraireMinimum ?? 0) : Textes.tauxNonDefini
        Text(valeur)
            .font(JoleneFont.callout.weight(.semibold))
            .foregroundStyle(JoleneColor.midnight)
            .accessibilityIdentifier("profil-taux-min-valeur")
        Slider(value: Binding(get: { model.formulaire.tauxDefini ? model.formulaire.tauxHoraireMinimum ?? 10 : 10 },
                              set: { model.formulaire.tauxHoraireMinimum = $0.rounded() }),
               in: Double(FormulaireProfil.bornesTaux.lowerBound)...Double(FormulaireProfil.bornesTaux.upperBound), step: 1)
            .tint(JoleneColor.rose700)
            .frame(minHeight: 44)
            .accessibilityLabel(Textes.tauxTitre)
            .accessibilityValue(valeur)
            .accessibilityIdentifier("profil-taux-min")
        bornes(Textes.tauxMinimum, Textes.tauxMaximum)
    }

    @ViewBuilder
    private var rayon: some View {
        titreCarte(Textes.rayonTitre)
        legende(Textes.rayonAide)
        Text(Textes.rayon(model.formulaire.rayonDeplacementKm))
            .font(JoleneFont.callout.weight(.semibold))
            .foregroundStyle(JoleneColor.midnight)
            .accessibilityIdentifier("profil-rayon-valeur")
        Slider(value: Binding(get: { Double(model.formulaire.rayonDeplacementKm) },
                              set: { model.formulaire.rayonDeplacementKm = Int($0.rounded()) }),
               in: Double(FormulaireProfil.bornesRayon.lowerBound)...Double(FormulaireProfil.bornesRayon.upperBound), step: 1)
            .tint(JoleneColor.rose700)
            .frame(minHeight: 44)
            .accessibilityLabel(Textes.rayonTitre)
            .accessibilityValue("\(model.formulaire.rayonDeplacementKm) km")
            .accessibilityIdentifier("profil-rayon")
        bornes(Textes.rayonMinimum, Textes.rayonMaximum)
    }

    private var typeExercice: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            InlineNotice(Textes.typeExerciceWeb, title: Textes.typeExercice, tone: .info, identifier: "profil-exercice-web")
            if let presentateurRenvoiWeb, let route = ProfilEdition.renvoiTypeExercice {
                JoleneButton(Textes.voirSurLeWeb, style: .secondary) { presentateurRenvoiWeb.presenter(route) }
                    .accessibilityIdentifier("profil-exercice-web-action")
            }
        }
    }

    private var enregistrement: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            if let succes = model.succes {
                InlineNotice(succes, tone: .success, identifier: "profil-enregistre", announcesOnAppear: true,
                             announcementID: model.annonces)
            }
            if let erreur = model.erreur {
                InlineNotice(erreur, tone: .error, identifier: "profil-erreur", announcesOnAppear: true,
                             announcementID: model.annonces)
            }
            JoleneButton(model.enregistrementEnCours ? Textes.enregistrement : Textes.enregistrer,
                         isLoading: model.enregistrementEnCours) {
                Task { await model.enregistrer() }
            }
            .disabled(!model.peutEnregistrer)
            .accessibilityIdentifier("profil-enregistrer")
        }
    }

    // MARK: - Briques

    private func carte<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) { contenu() }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    private func titreCarte(_ texte: String) -> some View {
        Text(texte)
            .font(JoleneFont.headline)
            .foregroundStyle(JoleneColor.midnight)
            .accessibilityAddTraits(.isHeader)
    }

    private func legende(_ texte: String) -> some View {
        Text(texte)
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bornes(_ minimum: String, _ maximum: String) -> some View {
        HStack {
            Text(minimum)
            Spacer()
            Text(maximum)
        }
        .font(JoleneFont.caption)
        .foregroundStyle(JoleneColor.bubblegum)
        .accessibilityHidden(true)
    }

    /// Valeur non modifiable : libellé, mention verbatim « (non modifiable après le contrôle RPPS) » pour
    /// l'identité figée, puis la valeur.
    private func lectureSeule(_ libelle: String, valeur: String, identifiant: String, verrou: Bool) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(verrou ? "\(libelle) \(Textes.nonModifiableApresRpps)" : libelle)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
            Text(valeur.isEmpty ? "—" : valeur)
                .font(JoleneFont.body)
                .foregroundStyle(JoleneColor.midnight)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier(identifiant)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Champ libre au style de `JoleneTextField` (ville, RPPS), sans nature de saisie de `JoleneInputKind`
/// (aucune n'a le clavier et l'autocomplétion attendus : ville, 11 chiffres).
private struct ChampProfil: View {
    let libelle: String
    @Binding var texte: String
    let placeholder: String
    var clavier: UIKeyboardType = .default
    var contenu: UITextContentType?
    let identifiant: String
    @FocusState private var focus: Bool

    init(_ libelle: String, texte: Binding<String>, placeholder: String, clavier: UIKeyboardType = .default,
         contenu: UITextContentType? = nil, identifiant: String) {
        self.libelle = libelle; self._texte = texte; self.placeholder = placeholder; self.clavier = clavier
        self.contenu = contenu; self.identifiant = identifiant
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(libelle).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            TextField(placeholder, text: $texte)
                .font(.system(size: 16))
                .keyboardType(clavier)
                .textContentType(contenu)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focus)
                .padding(.horizontal, JoleneSpacing.lg)
                .frame(minHeight: 48)
                .background(JoleneColor.cloud)
                .overlay(
                    RoundedRectangle(cornerRadius: JoleneRadius.field)
                        .strokeBorder(focus ? JoleneColor.rose : JoleneColor.bubblegum.opacity(0.35), lineWidth: focus ? 2 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .accessibilityLabel(libelle)
                .accessibilityIdentifier(identifiant)
        }
    }
}

/// Date de naissance `AAAA-MM-JJ` (colonne `date`) ↔ `Date` du sélecteur, calendrier grégorien en UTC
/// (aucun décalage de fuseau sur un jour civil).
enum DateNaissance {
    private static let calendrier: Calendar = {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendrier
    }()

    static func date(_ chaine: String) -> Date? {
        let parties = chaine.split(separator: "-").compactMap { Int($0) }
        guard parties.count == 3, chaine.count == 10 else { return nil }
        return calendrier.date(from: DateComponents(year: parties[0], month: parties[1], day: parties[2]))
    }

    static func chaine(_ date: Date) -> String {
        let composantes = calendrier.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", composantes.year ?? 0, composantes.month ?? 1, composantes.day ?? 1)
    }

    /// `14/05/1990`.
    static func affichage(_ chaine: String) -> String? {
        guard let date = date(chaine) else { return nil }
        let composantes = calendrier.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", composantes.day ?? 1, composantes.month ?? 1, composantes.year ?? 0)
    }

    /// Point de départ du sélecteur quand la date est absente (aucune valeur enregistrée sans appui).
    static var parDefaut: Date {
        calendrier.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    }

    static func liaison(_ source: Binding<String?>) -> Binding<Date> {
        Binding(get: { source.wrappedValue.flatMap(date) ?? parDefaut },
                set: { source.wrappedValue = chaine($0) })
    }
}
