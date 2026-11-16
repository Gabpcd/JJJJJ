import SwiftUI
import JoleneCore
import JoleneDesign

/// Section « Paiements à confirmer » de l'onglet Revenus (lot 3, T13, B9) : vue de `PaiementsDeclaresModel` (JoleneCore),
/// port de `src/components/BandeauPaiementDeclare.tsx` (monté en tête de l'aperçu de `/soignant/mes-gains`, l.382-384),
/// placée au-dessus des paiements rapides comme sur le web. Cible du push `PAIEMENT_RECU` (correction 15 :
/// `?tab=paiements`, l'onglet s'ouvre sur `revenus-paiements-declares`).
///
/// Une carte par paiement `DECLARE` : en-tête (« 💰 {établissement} déclare vous avoir payé {montant} », mission,
/// indication), qui déplie le détail (méthode, date, référence, mission, taux, brut, montant déclaré, pointages) et les
/// actions « Confirmer la réception » et « Contester » ; « Contester » ouvre le formulaire du motif (obligatoire, 500
/// caractères au plus). Tous les textes viennent de `PaiementsDeclaresTextes` (verbatim web ; deux textes vouvoyés :
/// l.55, TJ7 ; l.259, décision 9 du lot 1 et TJ8) par `CartePaiementDeclare` ; les règles (une mutation à la fois,
/// relecture, refus verbatim) sont dans le modèle et testées là. La vue n'ajoute aucune logique, aucun calcul de montant
/// et aucun texte ; l'en-tête n'est pas recomposé : il rend `prefixe` puis `montant`, dont `titre` (libellé
/// d'accessibilité) est la concaténation (revue B8 n°1, m5).
///
/// Rien n'est rendu pendant la première lecture ni sans paiement à confirmer (`return null` du web, l.216), sauf l'issue
/// d'une mutation, qui reste affichée après la disparition de la dernière carte.
struct PaiementsDeclaresSection: View {
    @ObservedObject var model: PaiementsDeclaresModel

    var body: some View {
        if model.afficheSection {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                issue
                if case let .echec(message) = model.etat {
                    erreur(message)
                }
                ForEach(model.cartes) { carte in
                    CartePaiementDeclareVue(carte: carte, model: model)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("revenus-paiements-declares")
        }
    }

    @ViewBuilder
    private var issue: some View {
        switch model.issue {
        case .confirme?:
            InlineNotice(PaiementsDeclaresTextes.paiementConfirme, tone: .success, identifier: "paiement-confirme",
                         announcesOnAppear: true, announcementID: model.numeroIssue)
        case .conteste?:
            InlineNotice(PaiementsDeclaresTextes.contestationEnvoyee, tone: .success, identifier: "paiement-conteste",
                         announcesOnAppear: true, announcementID: model.numeroIssue)
        case let .erreur(message)?:
            InlineNotice(message, tone: .error, identifier: "paiement-erreur", announcesOnAppear: true,
                         announcementID: model.numeroIssue)
        case nil:
            EmptyView()
        }
    }

    private func erreur(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            InlineNotice(message, title: PaiementsDeclaresTextes.indisponibles, tone: .error,
                         identifier: "paiements-declares-erreur")
            JoleneButton(PaiementsDeclaresTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                .accessibilityIdentifier("paiements-declares-reessayer")
        }
    }
}

/// Carte d'un paiement déclaré (l.240-420) : en-tête toujours visible, détail et actions une fois dépliée.
private struct CartePaiementDeclareVue: View {
    let carte: CartePaiementDeclare
    @ObservedObject var model: PaiementsDeclaresModel

    private var deplie: Bool { model.deplie == carte.id }
    private var enCours: Bool { model.enCours == carte.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.basculer(carte.id) } label: { entete }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([carte.titre, carte.mission, carte.indication].compactMap { $0 }.joined(separator: ", "))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("paiement-deplier-\(carte.id)")
            if deplie {
                Divider()
                detail
                    .padding(JoleneSpacing.md)
                    .background(JoleneColor.cloud)
            }
        }
        .background(JoleneColor.rose100)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.card).strokeBorder(JoleneColor.rose700.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paiement-declare-\(carte.id)")
    }

    private var entete: some View {
        HStack(alignment: .top, spacing: JoleneSpacing.md) {
            Image(systemName: "banknote")
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.rose800)
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                // Une seule source avec le libellé d'accessibilité (`carte.titre` = `prefixe` + `montant`), rendue telle
                // quelle (`verbatim` : ni clé de traduction, ni Markdown).
                (Text(verbatim: carte.prefixe) + Text(verbatim: carte.montant).foregroundColor(JoleneColor.rose800))
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                if let mission = carte.mission {
                    Text(mission)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(carte.indication)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: JoleneSpacing.sm)
            Image(systemName: deplie ? "chevron.up" : "chevron.down")
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                ForEach(carte.infos, id: \.cle) { info in
                    ligne("\(info.libelle) \(info.valeur)", identifiant: "paiement-\(info.cle)-\(carte.id)")
                }
            }
            if let mission = carte.blocMission {
                encadre {
                    Text(mission.intitule)
                        .font(JoleneFont.caption.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                    ligne(mission.periode, identifiant: "paiement-periode-\(carte.id)")
                    ligne(mission.horaires, identifiant: "paiement-horaires-\(carte.id)")
                    ligne(mission.taux, identifiant: "paiement-taux-\(carte.id)")
                    if let heures = mission.heuresRetenues {
                        ligne(heures, identifiant: "paiement-heures-retenues-\(carte.id)")
                    }
                    if let brut = mission.brut {
                        ligne(brut, identifiant: "paiement-brut-\(carte.id)")
                    }
                    ligne(mission.montantDeclare, identifiant: "paiement-montant-declare-\(carte.id)")
                }
            }
            if let pointages = carte.pointages {
                encadre {
                    Text(pointages.titre)
                        .font(JoleneFont.caption.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("paiement-pointages-\(carte.id)")
                    ForEach(Array(pointages.lignes.enumerated()), id: \.offset) { index, texte in
                        ligne(texte, identifiant: "paiement-pointage-\(index)-\(carte.id)")
                    }
                }
            }
            actions
            if model.contestation == carte.id {
                formulaireContestation
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: JoleneSpacing.sm) { boutons }
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) { boutons }
        }
    }

    @ViewBuilder
    private var boutons: some View {
        JoleneButton(PaiementsDeclaresTextes.confirmerReception, isLoading: enCours) {
            Task { await model.confirmer(carte.id) }
        }
        .disabled(model.enCours != nil)
        .accessibilityIdentifier("paiement-confirmer-\(carte.id)")
        JoleneButton(PaiementsDeclaresTextes.contester, style: .secondary) { model.basculerContestation(carte.id) }
            .disabled(model.enCours != nil)
            .accessibilityIdentifier("paiement-contester-\(carte.id)")
    }

    /// `MotifContestationModal` (l.47-68) : motif obligatoire, 500 caractères au plus, envoi désactivé sans motif.
    private var formulaireContestation: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(PaiementsDeclaresTextes.motifTitre)
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.rose700)
            TextField(PaiementsDeclaresTextes.motifPlaceholder,
                      text: Binding(get: { model.motif }, set: { model.saisirMotif($0) }), axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 16))
                .padding(JoleneSpacing.md)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .disabled(model.enCours != nil)
                .accessibilityLabel(PaiementsDeclaresTextes.motifTitre)
                .accessibilityIdentifier("paiement-motif")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: JoleneSpacing.sm) { boutonsContestation }
                VStack(alignment: .leading, spacing: JoleneSpacing.sm) { boutonsContestation }
            }
        }
        .padding(JoleneSpacing.md)
        .background(JoleneColor.rose100)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
    }

    @ViewBuilder
    private var boutonsContestation: some View {
        JoleneButton(PaiementsDeclaresTextes.envoyerContestation, style: .destructive, isLoading: enCours) {
            Task { await model.envoyerContestation() }
        }
        .disabled(!model.peutEnvoyerContestation)
        .accessibilityIdentifier("paiement-contestation-envoyer")
        JoleneButton(PaiementsDeclaresTextes.annuler, style: .secondary) { model.annulerContestation() }
            .disabled(model.enCours != nil)
            .accessibilityIdentifier("paiement-contestation-annuler")
    }

    private func ligne(_ texte: String, identifiant: String) -> some View {
        Text(texte)
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.midnight)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifiant)
    }

    private func encadre<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) { contenu() }
            .padding(JoleneSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.bubblegum.opacity(0.3), lineWidth: 1))
            .accessibilityElement(children: .contain)
    }
}
