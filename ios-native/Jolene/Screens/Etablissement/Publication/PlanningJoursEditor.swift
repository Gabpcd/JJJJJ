import SwiftUI
import JoleneCore
import JoleneDesign

/// Dates et horaires réels d'une mission à publier (lot 5, T9), port de `FormulaireRecurrence.tsx` et
/// `LigneHoraireJour.tsx` réduit au périmètre natif : période (première et dernière date), jours **dérivés** de la
/// période (travaillé ou repos), créneaux de chaque jour travaillé (heures murales de Paris, fin le même jour ou le
/// lendemain), « Appliquer le 1er horaire aux jours sélectionnés », erreurs structurelles du web. La vue ne garde aucun
/// état du planning : chaque geste appelle `PublicationModel`, qui re-dérive. Non portés : sélection rapide des dates
/// (renvoi web), contrôle par semaine civile et couleurs de durée (règles du travail, serveur seulement).
///
/// Une date vide n'affiche aucune date fictive : « Choisir la date » la pose (jour de l'horloge de la session) ; les
/// boutons « Jour précédent » / « Jour suivant » la décalent d'un jour, le sélecteur la change librement.
///
/// Identifiants : `publier-date-{debut|fin}` (sélecteur), `-choisir`, `-precedent`, `-suivant` ;
/// `publier-jours-resume`, `publier-appliquer-tous`, `publier-jour-{yyyy-MM-dd}` (valeur : « Travaillé » / « Repos »),
/// `publier-creneau-{date}-{i}` (i à partir de 0, comme le `data-testid` du web) et ses contrôles `-debut`, `-fin`,
/// `-lendemain`, `-supprimer`, `-controle`, `publier-creneau-{date}-ajouter`, `publier-erreur-structure`.
struct PlanningJoursEditor: View {
    @ObservedObject var model: PublicationModel

    private typealias P = PublicationPresentation
    private static let francais = Locale(identifier: "fr_FR")

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Text(P.datesTitre)
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                Text(P.datesAide)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
            date(P.dateDebut, cle: model.saisie.dateDebut, identifiant: "publier-date-debut", borne: .debut)
            date(P.dateFin, cle: model.saisie.dateFin, identifiant: "publier-date-fin", borne: .fin)
            if !model.saisie.jours.isEmpty { jours }
            erreurs
        }
    }

    // MARK: - Période

    private enum Borne { case debut, fin }

    private func definir(_ borne: Borne, _ cle: String) {
        switch borne {
        case .debut: model.definirDateDebut(cle)
        case .fin: model.definirDateFin(cle)
        }
    }

    private func decaler(_ borne: Borne, de jours: Int) {
        switch borne {
        case .debut: model.decalerDateDebut(jours: jours)
        case .fin: model.decalerDateFin(jours: jours)
        }
    }

    private func choisir(_ borne: Borne) {
        Task {
            switch borne {
            case .debut: await model.choisirDateDebut()
            case .fin: await model.choisirDateFin()
            }
        }
    }

    @ViewBuilder
    private func date(_ titre: String, cle: String, identifiant: String, borne: Borne) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(titre).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            if let choisie = P.dateDuJour(cle) {
                HStack(spacing: JoleneSpacing.sm) {
                    pas("minus.circle", P.jourPrecedent, identifiant: "\(identifiant)-precedent") { decaler(borne, de: -1) }
                    DatePicker(titre, selection: Binding(get: { choisie }, set: { definir(borne, P.cleJour($0)) }),
                               displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Self.francais)
                        // Jour civil de Paris : le sélecteur affiche et rend la date dans ce fuseau.
                        .environment(\.timeZone, DateHeureParis.fuseau)
                        .frame(minHeight: 44)
                        .accessibilityLabel(titre)
                        .accessibilityIdentifier(identifiant)
                    pas("plus.circle", P.jourSuivant, identifiant: "\(identifiant)-suivant") { decaler(borne, de: 1) }
                    Spacer(minLength: 0)
                }
            } else {
                // Date absente : aucune date fictive affichée ; l'appui la pose.
                Button { choisir(borne) } label: {
                    Label(P.choisirDate, systemImage: "calendar")
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.rose800)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(titre), \(P.choisirDate)")
                .accessibilityIdentifier("\(identifiant)-choisir")
            }
        }
    }

    private func pas(_ symbole: String, _ libelle: String, identifiant: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(JoleneColor.rose700)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(libelle)
        .accessibilityIdentifier(identifiant)
    }

    // MARK: - Jours dérivés

    private var jours: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(P.resumeJours(travailles: model.joursTravailles, total: model.saisie.jours.count))
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityIdentifier("publier-jours-resume")
            JoleneButton(P.appliquerATous, style: .secondary) { model.appliquerPremierCreneauATous() }
                .disabled(model.joursTravailles == 0)
                .accessibilityIdentifier("publier-appliquer-tous")
            LazyVStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                ForEach(model.saisie.jours, id: \.date) { jour in
                    carte(jour)
                }
            }
        }
    }

    private func carte(_ jour: PlanningDerive.Jour) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Button { model.basculerJour(jour.date) } label: {
                HStack(spacing: JoleneSpacing.sm) {
                    Image(systemName: jour.actif ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(jour.actif ? JoleneColor.rose700 : JoleneColor.bubblegum)
                        .accessibilityHidden(true)
                    Text(P.libelleJour(jour.date))
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    JoleneBadge(P.etatJour(jour.actif), tone: jour.actif ? .success : .info)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(P.libelleJourTravaille(jour.date))
            .accessibilityValue(P.etatJour(jour.actif))
            .accessibilityAddTraits(jour.actif ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("publier-jour-\(jour.date)")

            if jour.actif {
                ForEach(Array(jour.creneaux.enumerated()), id: \.element.clientId) { rang, creneau in
                    ligne(jour.date, rang: rang, creneau: creneau)
                }
                Button { model.ajouterCreneau(jour.date) } label: {
                    Label(P.ajouterCreneau, systemImage: "plus")
                        .font(JoleneFont.caption.weight(.semibold))
                        .foregroundStyle(JoleneColor.rose700)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("publier-creneau-\(jour.date)-ajouter")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JoleneSpacing.md)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    // MARK: - Créneau

    private func ligne(_ date: String, rang: Int, creneau: PlanningDerive.Creneau) -> some View {
        let identifiant = "publier-creneau-\(date)-\(rang)"
        let controle = P.controleCreneau(date: date, creneau: creneau)
        let enErreur = model.creneauxEnErreur.contains(creneau.clientId) || !controle.valide
        return VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            HStack(spacing: JoleneSpacing.sm) {
                heure(P.heureDebut, date: date, creneau: creneau, fin: false, identifiant: "\(identifiant)-debut")
                Image(systemName: "arrow.right")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityHidden(true)
                heure(P.heureFin, date: date, creneau: creneau, fin: true, identifiant: "\(identifiant)-fin")
                Spacer(minLength: 0)
                Button { model.retirerCreneau(date: date, clientId: creneau.clientId) } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(JoleneColor.bubblegum)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // « Supprimer le créneau 1 du 2026-11-02 » (`aria-label` du web, `LigneHoraireJour.tsx` l.90).
                .accessibilityLabel("Supprimer le créneau \(rang + 1) du \(date)")
                .accessibilityIdentifier("\(identifiant)-supprimer")
            }
            Toggle(isOn: Binding(get: { creneau.finJourSuivant }, set: { definirLendemain($0, date: date, creneau: creneau) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(P.dateDeFin).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                    Text(creneau.finJourSuivant ? P.lendemain(date) : P.memeJour(date))
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                }
            }
            .tint(JoleneColor.rose700)
            .frame(minHeight: 44)
            .accessibilityLabel("\(P.dateDeFin), \(P.lendemain(date))")
            .accessibilityIdentifier("\(identifiant)-lendemain")
            Text(controle.texte)
                .font(JoleneFont.caption)
                .foregroundStyle(enErreur ? JoleneColor.rose800 : JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(identifiant)-controle")
        }
        .padding(JoleneSpacing.sm)
        .background(JoleneColor.lavender)
        .overlay {
            RoundedRectangle(cornerRadius: JoleneRadius.field)
                .strokeBorder(enErreur ? JoleneColor.rose800 : JoleneColor.rose100, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifiant)
    }

    private func definirLendemain(_ lendemain: Bool, date: String, creneau: PlanningDerive.Creneau) {
        var suivant = creneau
        suivant.finJourSuivant = lendemain
        model.modifierCreneau(date: date, creneau: suivant)
    }

    private func definirHeure(_ heure: String, fin: Bool, date: String, creneau: PlanningDerive.Creneau) {
        var suivant = creneau
        if fin { suivant.heureFin = heure } else { suivant.heureDebut = heure }
        model.modifierCreneau(date: date, creneau: suivant)
    }

    /// Sélecteur d'heure murale : lu et écrit sur un jour de référence en UTC (`PublicationPresentation.fuseauHeures`),
    /// sans changement d'heure ; l'heure réelle à Paris est validée par `PlanningDerive`.
    private func heure(_ titre: String, date: String, creneau: PlanningDerive.Creneau, fin: Bool, identifiant: String) -> some View {
        let valeur = fin ? creneau.heureFin : creneau.heureDebut
        return VStack(alignment: .leading, spacing: 2) {
            Text(titre).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            DatePicker(titre, selection: Binding(get: { P.dateDeLHeure(valeur) ?? Date(timeIntervalSinceReferenceDate: 0) },
                                                 set: { definirHeure(P.heure($0), fin: fin, date: date, creneau: creneau) }),
                       displayedComponents: .hourAndMinute)
                .labelsHidden()
                .environment(\.locale, Self.francais)
                .environment(\.timeZone, P.fuseauHeures)
                .frame(minHeight: 44)
                .accessibilityLabel(titre)
                .accessibilityIdentifier(identifiant)
        }
    }

    // MARK: - Erreurs structurelles

    @ViewBuilder private var erreurs: some View {
        let erreurs = model.erreursPlanningAffichees
        if !erreurs.isEmpty {
            InlineNotice(erreurs.map(\.message).joined(separator: "\n"), tone: .error, identifier: "publier-erreur-structure")
        }
    }
}
