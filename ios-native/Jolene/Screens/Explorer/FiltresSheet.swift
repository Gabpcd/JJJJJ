import SwiftUI
import JoleneCore
import JoleneDesign

/// Feuille « Filtres » d'Explorer (lot 1, T4a), port de la feuille de `RechercheMissions.tsx`
/// (l.506-636) : ville ou code postal, profession, rayon 5 → 100 km par pas de 5, taux horaire
/// minimum, type de contrat, horaires, urgentes uniquement. Les critères sont édités sur un
/// brouillon (`ExplorerFiltres`) et appliqués par « Afficher les missions » ; « Réinitialiser »
/// remet le brouillon aux valeurs du web (`ExplorerFiltres.reinitialises(profile:)`), « Fermer »
/// abandonne le brouillon. Aucune règle ici : tout est porté et testé dans JoleneCore.
///
/// Identifiants : `explorer-filtres` (défilement), `filtre-ville`, `filtre-profession`,
/// `filtre-rayon`, `filtre-rayon-valeur`, `filtre-taux`, `filtre-contrat`, `filtre-horaire`,
/// `filtre-urgentes`, `filtres-reset`, `filtres-apply`, `filtres-fermer`.
struct FiltresSheet: View {
    let profile: SoignantProfile
    let appliquer: (ExplorerFiltres) -> Void

    @State private var brouillon: ExplorerFiltres
    @State private var tauxSaisi: String
    @Environment(\.dismiss) private var dismiss

    init(filtres: ExplorerFiltres, profile: SoignantProfile, appliquer: @escaping (ExplorerFiltres) -> Void) {
        self.profile = profile
        self.appliquer = appliquer
        _brouillon = State(initialValue: filtres)
        _tauxSaisi = State(initialValue: ExplorerFiltres.saisie(depuisTaux: filtres.tauxMin))
    }

    var body: some View {
        NavigationStack {
            // Barre d'actions SOUS le défilement (pas en `safeAreaInset`) : le cadre du défilement
            // s'arrête au-dessus des boutons, aucun champ n'est jamais masqué par eux.
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                        ville
                        profession
                        rayon
                        taux
                        selecteur("Type de contrat", identifier: "filtre-contrat", options: ExplorerFiltres.optionsContrat,
                                  selection: $brouillon.typeContrat)
                        selecteur("Horaires", identifier: "filtre-horaire", options: ExplorerFiltres.optionsHoraire,
                                  selection: $brouillon.horaire)
                        Toggle("Urgentes uniquement", isOn: $brouillon.urgentesOnly)
                            .font(JoleneFont.body)
                            .foregroundStyle(JoleneColor.midnight)
                            .tint(JoleneColor.rose700)
                            .accessibilityIdentifier("filtre-urgentes")
                    }
                    .padding(JoleneSpacing.lg)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("explorer-filtres")
                actions
            }
            .background(JoleneColor.lavender.ignoresSafeArea())
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(JoleneColor.rose700)
                        .accessibilityIdentifier("filtres-fermer")
                }
            }
        }
    }

    // MARK: Champs

    private var ville: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            JoleneTextField("Ville ou code postal", text: $brouillon.ville, kind: .recherche,
                            placeholder: "Ex : Paris, 75001…", identifier: "filtre-ville")
            Text("Laissez vide pour utiliser votre position.")
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
        }
    }

    private var profession: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text("Profession").font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            Picker("Profession", selection: $brouillon.profession) {
                ForEach(ExplorerFiltres.optionsProfession(profile: profile), id: \.valeur) { option in
                    Text(option.titre).tag(option.valeur)
                }
            }
            .pickerStyle(.menu)
            .tint(JoleneColor.rose700)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityIdentifier("filtre-profession")
        }
    }

    private var rayon: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(ExplorerFiltres.libelleRayon(brouillon.rayonKm))
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("filtre-rayon-valeur")
            // Curseur nu comme le web (ni libellé minimum ni maximum) : un seul élément « Rayon »
            // pour VoiceOver, sa valeur en kilomètres.
            Slider(value: $brouillon.rayonKm, in: ExplorerFiltres.rayonMinimumKm...ExplorerFiltres.rayonMaximumKm,
                   step: ExplorerFiltres.rayonPasKm)
            .tint(JoleneColor.rose700)
            .accessibilityLabel("Rayon")
            .accessibilityValue("\(MissionPresentation.nombreJavaScript(brouillon.rayonKm)) km")
            .accessibilityIdentifier("filtre-rayon")
            if !ExplorerFiltres.rayonApplicable(profile: profile) {
                Text("Votre adresse n'est pas renseignée : la distance des missions ne peut pas être calculée et le rayon ne s'applique pas.")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("filtre-rayon-inactif")
            }
        }
    }

    private var taux: some View {
        JoleneTextField("Taux horaire minimum (€/h)", text: $tauxSaisi, kind: .montant, placeholder: "Ex : 25",
                        identifier: "filtre-taux")
            .onChange(of: tauxSaisi) { saisie in brouillon.tauxMin = ExplorerFiltres.taux(depuisSaisie: saisie) }
    }

    private func selecteur<Valeur: Hashable & Sendable>(_ titre: String, identifier: String,
                                                         options: [ExplorerFiltres.Option<Valeur>],
                                                         selection: Binding<Valeur>) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(titre).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            Picker(titre, selection: selection) {
                ForEach(options, id: \.valeur) { option in
                    Text(option.titre).tag(option.valeur)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(identifier)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: JoleneSpacing.md) {
            JoleneButton("Réinitialiser", style: .secondary) {
                brouillon = brouillon.reinitialises(profile: profile)
                tauxSaisi = ExplorerFiltres.saisie(depuisTaux: brouillon.tauxMin)
            }
            .accessibilityIdentifier("filtres-reset")
            JoleneButton("Afficher les missions") {
                appliquer(brouillon)
                dismiss()
            }
            .accessibilityIdentifier("filtres-apply")
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, JoleneSpacing.lg)
        .padding(.vertical, JoleneSpacing.md)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(JoleneColor.rose100).frame(height: 1) }
    }
}
