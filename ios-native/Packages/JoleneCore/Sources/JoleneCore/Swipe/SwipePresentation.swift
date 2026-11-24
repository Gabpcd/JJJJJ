import Foundation

/// Textes de la vue Swipe d'Explorer (lot 4, T3b ; `LOT4_PLAN.md` §3 T3b), repris de `VueSwipeMissions.tsx`,
/// `CardMissionSwipe.tsx`, `ModalDetailMissionSwipe.tsx`, `BoutonsActionSwipe.tsx` et de la bascule de
/// `RechercheMissions.tsx` (rôle SOIGNANT). **Aucun texte juridique ni d'engagement ici** : la feuille « première
/// candidature » est dans `TextesWeb.PremiereCandidature` (HARD STOP n°4, verbatim), le récapitulatif et le choix de
/// contrat dans `LibellesCandidature` / `TextesWeb.Candidature` (lot 1). Les textes tutoyés du web passent au
/// vouvoiement (décision 9 du lot 1 et D24 du lot 4 : seule la personne change) ; les refus et avertissements du serveur
/// sont affichés tels quels. Textes sans équivalent web, non juridiques : `restantes` (compteur du paquet),
/// `candidatureRetiree` et `voirMission` (décision D4 : carte non remise, accès au détail), `voirDetail` (bouton du
/// détail, le web rend toute la carte cliquable), `fermer`, `commande` (le web annonce aussi « Carte »).
public enum SwipeTextes {
    // MARK: Bascule d'Explorer

    // source: RechercheMissions.tsx l.289 (`aria-label="Vue Swipe, Liste ou Carte"` ; pas de vue Carte en natif)
    public static let commande = "Vue Swipe ou Liste"
    // source: l.291-292
    public static let vueSwipe = "Swipe"
    public static let vueListe = "Liste"

    // MARK: Chargement, erreur

    // source: VueSwipeMissions.tsx l.390 (vouvoyé : « ton matching »)
    public static let chargement = "Calcul de votre matching..."
    // source: l.395, l.397, l.406
    public static let echecTitre = "Planning des missions indisponible"
    public static let echecDescription = "Les missions ne sont pas affichées tant que leurs dates et horaires exacts ne peuvent pas être vérifiés."
    public static let reessayer = "Réessayer"

    // MARK: Fin de paquet

    // source: l.417 (vouvoyé : « Tu as tout vu »)
    public static let toutVuTitre = "Vous avez tout vu pour aujourd'hui"
    // source: l.418 (vouvoyé : « Crée », « tu recevras », « ton profil »)
    public static let toutVuDescription = "Créez une alerte : vous recevrez un email dès qu'une nouvelle mission correspondant à votre profil est publiée."
    // source: l.420, l.425
    public static let toutVuAlerte = "🔔 Me prévenir des prochaines missions"
    public static let elargirRayon = "📍 Élargir le rayon (+20 km)"
    // source: l.436
    public static let rienTitre = "Aucune nouvelle mission à parcourir"
    // source: l.437 (vouvoyé : « Consulte », « crée »)
    public static let rienDescription = "Consultez la liste pour retrouver toutes les missions disponibles, ou créez une alerte pour les prochaines publications."
    // source: l.439, l.443
    public static let rienAlerte = "🔔 Me prévenir dès qu'une mission arrive"
    public static let voirListe = "Voir la recherche en liste"

    // source: l.455 (vouvoyé : « Tes missions sauvegardées »)
    public static func favorisTitre(_ nombre: Int) -> String { "Vos missions sauvegardées (\(nombre))" }

    // MARK: Annonces

    // source: l.239
    public static let favoriSauvegarde = "Mission sauvegardée ⭐"
    // source: l.240 (vouvoyé : « Retrouve-la »)
    public static let favoriSauvegardeDetail = "Retrouvez-la en fin de deck ou dans Mes favoris."
    // source: l.255
    public static let candidatureEnvoyee = "Candidature envoyée ✓"
    // source: l.261
    public static let annuler = "Annuler"
    /// Décision D4 : la carte n'est pas remise dans le paquet (la ligne `swipes` est immuable), le web annonce
    /// « Candidature annulée » en la remettant.
    public static let candidatureRetiree = "Candidature retirée"
    public static let voirMission = "Voir la mission"
    public static let fermer = "Fermer"

    // MARK: Carte

    // source: CardMissionSwipe.tsx l.185, l.195
    public static let urgent = "🔥 Urgent"
    public static let paiementRapide = "⚡ Paiement rapide"
    // source: l.85-89 (`momentLabel`)
    public static let momentFerie = "🎉 férié"
    public static let momentDimanche = "☀️ dimanche"
    public static let momentPlanningAConfirmer = "planning à confirmer"
    public static let momentNuit = "🌙 nuit"
    public static let momentJour = "☀️ jour"
    // source: l.96-98 (`contratLabel`)
    public static let contratSalarie = "Salarié (CDD)"
    public static let contratLiberal = "Libéral"
    public static let contratTous = "Salarié ou libéral"
    // source: l.240
    public static let horairesNonVerifies = "Horaires non vérifiés"
    // source: l.273 (« Pourquoi {score} ? »)
    public static func pourquoi(_ score: Int) -> String { "Pourquoi \(score) ?" }
    /// Bouton du détail (le web : « Toucher pour voir le détail », l.279, sur une carte entièrement cliquable).
    public static let voirDetail = "Voir le détail"

    // MARK: Détail

    // source: ModalDetailMissionSwipe.tsx l.99, l.121, l.126, l.134, l.142, l.150
    public static let etablissement = "Établissement"
    public static let conditions = "Conditions"
    public static let profession = "Profession"
    public static let service = "Service"
    public static let tarifHoraire = "Tarif horaire"
    public static let duree = "Durée"
    // source: l.161, l.182, l.196
    public static let remunerationIndicative = "Rémunération indicative"
    public static let totalBrut = "Total brut"
    public static let totalAvantCotisations = "Total avant cotisations"
    // source: l.235, l.246
    public static let datesEtHoraires = "Dates et horaires travaillés"
    public static let pourquoiCeMatch = "Pourquoi ce match"
    // source: l.254, l.261, l.274, l.280, l.292
    public static let raisonTarif = "Tarif vs marché local"
    public static let raisonDistance = "Distance"
    public static let raisonEtablissement = "Qualité établissement"
    public static let raisonUrgence = "Urgence (bonus)"
    public static let raisonPaiementRapide = "⚡ Paiement rapide"
    // source: l.268 (vouvoyé : « Tes horaires préférés »), l.286 (vouvoyé : « Tu connais cet établissement »)
    public static let raisonHoraire = "Vos horaires préférés"
    public static let raisonConnaissance = "Vous connaissez cet établissement"
    // source: l.303, l.306
    public static let suivant = "Suivant"
    public static let verifierEtPostuler = "Vérifier et postuler"

    // MARK: Compteur (natif)

    /// Compteur du paquet (`swipe-restantes`) : « 12 missions à parcourir », « 1 mission à parcourir ».
    public static func restantes(_ nombre: Int) -> String {
        nombre == 1 ? "1 mission à parcourir" : "\(nombre) missions à parcourir"
    }
}

/// Mise en forme de la carte et du détail du swipe (lot 4, T3b), port des fonctions pures de `CardMissionSwipe.tsx` et
/// de `ModalDetailMissionSwipe.tsx`. Montants, score, distance et note d'établissement sont les **valeurs du serveur**,
/// affichées telles quelles (PRINCIPES §3) : seuls les arrondis d'affichage du web sont reproduits (`Math.round`).
/// Écart assumé avec le détail web : les lignes qu'il **calcule** côté client (brut de base = total brut − majorations,
/// cumul des majorations, IFM + ICP, total avant cotisations reconstitué) ne sont pas portées ; seules les colonnes
/// servies (`total_brut`, `net_a_payer`, `net_estime`) sont affichées.
public enum SwipePresentation {
    // MARK: Lieu

    /// `formatQuartier` : « Paris 16e » pour les codes postaux parisiens (« 1er » pour le premier), sinon « Ville CP ».
    public static func quartier(ville: String?, codePostal: String?) -> String {
        let ville = (ville ?? "").isEmpty ? nil : ville
        let codePostal = (codePostal ?? "").isEmpty ? nil : codePostal
        if let ville, let codePostal, codePostal.count == 5, codePostal.hasPrefix("75"),
           codePostal.allSatisfy({ $0.isASCII && $0.isNumber }),
           let arrondissement = Int(codePostal.suffix(2)), (1...20).contains(arrondissement) {
            return "\(ville) \(arrondissement)\(arrondissement == 1 ? "er" : "e")"
        }
        return [ville, codePostal].compactMap { $0 }.joined(separator: " ")
    }

    /// Ligne du lieu : quartier (ou « — »), puis « · N km » quand le serveur sert une distance.
    public static func lieu(_ carte: CarteSwipe) -> String {
        let quartier = quartier(ville: carte.mission.etablissement?.adresseVille,
                                codePostal: carte.mission.etablissement?.adresseCodePostal)
        var texte = quartier.isEmpty ? "—" : quartier
        if let distance = carte.distanceServeurKm { texte += " · \(MissionPresentation.nombreJavaScript(distance)) km" }
        return texte
    }

    /// Nom de l'établissement du payload (`etablissement_nom`), « Établissement » s'il manque.
    public static func etablissement(_ carte: CarteSwipe) -> String {
        let nom = (carte.etablissementNom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return nom.isEmpty ? SwipeTextes.etablissement : nom
    }

    /// Note de l'établissement, arrondie comme le web (`Math.round`) ; `nil` sans note.
    public static func scoreEtablissement(_ score: Double?) -> String? {
        guard let score, score.isFinite else { return nil }
        return MissionPresentation.nombreJavaScript(CalendrierCivil.arrondiJS(score))
    }

    /// Note de l'établissement dans le détail : « 92/100 ».
    public static func scoreEtablissementDetail(_ score: Double?) -> String? {
        scoreEtablissement(score).map { "\($0)/100" }
    }

    // MARK: Rémunération

    /// Colonnes financières du payload, lues par `MontantMission` (`montantFinanceAfficheMission(mission)` du web).
    public static func finance(_ carte: CarteSwipe) -> MissionFinanceAffichee {
        let record = carte.mission.record
        return MissionFinanceAffichee(professionRequise: record.professionRequise, typeContratRecherche: record.typeContratRecherche,
                                      typeContratApplique: carte.typeContratApplique, soignantAssigneId: nil,
                                      tauxHoraireBase: record.tauxHoraireBase, tauxRistPlafonne: record.tauxRistPlafonne,
                                      ristPlafondApplique: record.ristPlafondApplique, netEstime: carte.netEstime,
                                      netAPayer: record.netAPayer, totalBrut: record.totalBrut)
    }

    public static func montant(_ carte: CarteSwipe) -> MontantMissionAffiche? {
        MontantMission.montantAffiche(finance(carte))
    }

    /// `missionEstLiberale` du web : le montant affiché est un honoraire libéral.
    public static func estLiberale(_ carte: CarteSwipe) -> Bool {
        montant(carte)?.nature == .honorairesLiberaux
    }

    /// Badge ⚡ : mission libérale au sens du montant affiché **et** drapeau serveur `paiement_rapide`.
    public static func paiementRapide(_ carte: CarteSwipe) -> Bool {
        estLiberale(carte) && carte.paiementRapide
    }

    /// Accroche de la carte : montant et son unité (« ~162€ » « net estimé* », « 840€ » « honoraires », sinon le taux
    /// horaire « 29€ » « /h », « — » sans taux).
    public struct Accroche: Equatable, Sendable {
        public var montant: String
        public var unite: String

        public var texte: String { unite == "/h" ? montant + unite : montant + " " + unite }
    }

    public static func accroche(_ carte: CarteSwipe) -> Accroche {
        if let affiche = montant(carte) {
            let entier = MissionPresentation.nombreJavaScript(CalendrierCivil.arrondiJS(affiche.montant))
            return Accroche(montant: (affiche.approximatif ? "~" : "") + entier + "€", unite: affiche.libelleCourt)
        }
        // `mission.taux_horaire_base ? … : '—'` : un taux nul ou absent n'est pas affiché.
        if let taux = carte.mission.record.tauxHoraireBase, taux.isFinite, taux != 0 {
            return Accroche(montant: MissionPresentation.nombreJavaScript(taux) + "€", unite: "/h")
        }
        return Accroche(montant: "—", unite: "/h")
    }

    // MARK: Planning

    public static func planning(_ carte: CarteSwipe) -> PlanningCandidat {
        PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(mission: carte.mission))
    }

    /// `momentLabel` : férié puis dimanche d'après les majorations servies ; jour ou nuit d'après les horaires réels ;
    /// planning non exact : « planning à confirmer ».
    public static func moment(_ carte: CarteSwipe) -> String {
        if (carte.montants.majorationFerie ?? 0) > 0 { return SwipeTextes.momentFerie }
        if (carte.montants.majorationDimanche ?? 0) > 0 { return SwipeTextes.momentDimanche }
        let planning = planning(carte)
        guard planning.exact else { return SwipeTextes.momentPlanningAConfirmer }
        return planning.creneaux.contains(where: PlanningCandidatRules.creneauContientNuit) ? SwipeTextes.momentNuit : SwipeTextes.momentJour
    }

    /// « 8 h · ☀️ jour » ; planning non exact : « Horaires non vérifiés · planning à confirmer ».
    public static func dureeMoment(_ carte: CarteSwipe) -> String {
        let planning = planning(carte)
        let duree = planning.exact ? "\(MissionPresentation.heuresPlanning(planning.totalHeures)) h" : SwipeTextes.horairesNonVerifies
        return "\(duree) · \(moment(carte))"
    }

    // MARK: Étiquettes

    /// `contratLabel` : régime **recherché** par la mission (`type_contrat_applique` est nul tant qu'elle n'est pas
    /// attribuée) ; jamais le régime du profil.
    public static func contrat(_ typeContratRecherche: String?) -> String? {
        switch typeContratRecherche {
        case "SALARIE": return SwipeTextes.contratSalarie
        case "LIBERAL": return SwipeTextes.contratLiberal
        case "TOUS": return SwipeTextes.contratTous
        default: return nil
        }
    }

    /// Étiquettes de la carte, dans l'ordre du web : profession (code tel quel), service, contrat.
    public static func etiquettes(_ carte: CarteSwipe) -> [String] {
        let record = carte.mission.record
        return [record.professionRequise.isEmpty ? nil : record.professionRequise,
                (record.service ?? "").isEmpty ? nil : record.service,
                contrat(record.typeContratRecherche)].compactMap { $0 }
    }

    /// « Pourquoi 85 ? » n'est affiché qu'avec un score connu **et** au moins une raison.
    public static func raisons(_ carte: CarteSwipe) -> String? {
        guard carte.score != nil else { return nil }
        let raisons = carte.raisons
        return raisons.isEmpty ? nil : raisons
    }

    // MARK: Accessibilité

    /// `aria-label` de la carte : « Mission IDE à Clinique, environ 162 euros net estimé*, score 85 sur 100. Toucher
    /// pour le détail. »
    public static func libelleAccessibilite(_ carte: CarteSwipe) -> String {
        var texte = "Mission \(carte.mission.record.professionRequise) à \(carte.etablissementNom ?? "")"
        if let affiche = montant(carte) {
            let entier = MissionPresentation.nombreJavaScript(CalendrierCivil.arrondiJS(affiche.montant))
            texte += ", \(affiche.approximatif ? "environ " : "")\(entier) euros \(affiche.libelleCourt)"
        }
        if let score = carte.score { texte += ", score \(score) sur 100" }
        return texte + ". Toucher pour le détail."
    }

    // MARK: Détail

    /// Ligne « libellé : valeur » du détail.
    public struct Ligne: Equatable, Sendable, Identifiable {
        public var id: String
        public var libelle: String
        public var valeur: String
    }

    /// Bloc « Conditions » : profession, service, tarif horaire, durée (`formatDureeCompacte`).
    public static func conditions(_ carte: CarteSwipe) -> [Ligne] {
        let record = carte.mission.record
        let taux = record.tauxHoraireBase.flatMap { $0.isFinite && $0 != 0 ? "\(MissionPresentation.nombreJavaScript($0)) €/h" : nil }
        return [
            Ligne(id: "profession", libelle: SwipeTextes.profession, valeur: record.professionRequise.isEmpty ? "—" : record.professionRequise),
            Ligne(id: "service", libelle: SwipeTextes.service, valeur: (record.service ?? "").isEmpty ? "—" : record.service ?? "—"),
            Ligne(id: "tarif", libelle: SwipeTextes.tarifHoraire, valeur: taux ?? "—"),
            Ligne(id: "duree", libelle: SwipeTextes.duree, valeur: FormatMission.formatDureeCompacte(record.horaires)),
        ]
    }

    /// `formatMontant` du détail : euros sans décimales (« 162 € », « 1 234 € »), « — » sans valeur.
    public static func eurosEntiers(_ valeur: Double?) -> String {
        guard let valeur, valeur.isFinite else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.groupingSeparator = MissionPresentation.separateurMilliers
        formatter.roundingMode = .halfUp
        let nombre = formatter.string(from: NSNumber(value: valeur)) ?? MissionPresentation.nombreJavaScript(valeur.rounded())
        return "\(nombre)\(MissionPresentation.espaceSymbole)€"
    }

    /// Rémunération du détail : libellé du montant affiché (ou « Rémunération indicative ») et montant (« ~162 € »),
    /// puis les colonnes servies. `nil` : aucun montant servi, le bloc n'est pas affiché.
    public struct Remuneration: Equatable, Sendable {
        public var libelle: String
        /// Montant mis en avant ; `nil` sans montant positif.
        public var montant: String?
        public var lignes: [Ligne]
        /// Astérisque « net salarié estimé* » ou montant indicatif : la note du web l'accompagne.
        public var noteNetEstime: Bool
    }

    public static func remuneration(_ carte: CarteSwipe) -> Remuneration? {
        let record = carte.mission.record
        let affiche = montant(carte)
        guard record.totalBrut != nil || record.netAPayer != nil || affiche != nil else { return nil }
        var lignes: [Ligne] = []
        if let brut = record.totalBrut { lignes.append(Ligne(id: "total-brut", libelle: SwipeTextes.totalBrut, valeur: eurosEntiers(brut))) }
        if !estLiberale(carte), let avant = record.netAPayer {
            lignes.append(Ligne(id: "avant-cotisations", libelle: SwipeTextes.totalAvantCotisations, valeur: eurosEntiers(avant)))
        }
        let mis = affiche.flatMap { $0.montant > 0 ? ($0.approximatif ? "~" : "") + eurosEntiers($0.montant) : nil }
        return Remuneration(libelle: affiche?.libelle ?? SwipeTextes.remunerationIndicative, montant: mis, lignes: lignes,
                            noteNetEstime: affiche?.approximatif ?? false)
    }

    /// « Pourquoi ce match » : barèmes du scoring servis par le breakdown (`ModalDetailMissionSwipe.tsx` l.251-296).
    /// Vide sans score ou sans breakdown. Valeurs du serveur rendues comme le web (`{breakdown.tarif} / 20`).
    public static func raisonsDetail(_ carte: CarteSwipe) -> [Ligne] {
        guard carte.score != nil, !carte.breakdown.isEmpty else { return [] }
        let points = carte.breakdown
        func nombre(_ valeur: Double) -> String { MissionPresentation.nombreJavaScript(valeur) }
        var lignes: [Ligne] = []
        if let tarif = points["tarif"] { lignes.append(Ligne(id: "tarif", libelle: SwipeTextes.raisonTarif, valeur: "\(nombre(tarif)) / 20")) }
        if let distance = points["distance"] {
            // `breakdown.distance_km` : nombre servi, ou `null` (ignoré comme `!= null` du web).
            let libelle = points["distance_km"].map { "\(SwipeTextes.raisonDistance) (\(nombre($0)) km)" } ?? SwipeTextes.raisonDistance
            lignes.append(Ligne(id: "distance", libelle: libelle, valeur: "\(nombre(distance)) / 20"))
        }
        if let horaire = points["horaire"] { lignes.append(Ligne(id: "horaire", libelle: SwipeTextes.raisonHoraire, valeur: "\(nombre(horaire)) / 15")) }
        if let etablissement = points["etablissement"] {
            lignes.append(Ligne(id: "etablissement", libelle: SwipeTextes.raisonEtablissement, valeur: "\(nombre(etablissement)) / 15"))
        }
        if let urgence = points["urgence"], urgence > 0 {
            lignes.append(Ligne(id: "urgence", libelle: SwipeTextes.raisonUrgence, valeur: "+\(nombre(urgence)) / 10"))
        }
        if let connaissance = points["connaissance_etab"], connaissance > 0 {
            lignes.append(Ligne(id: "connaissance", libelle: SwipeTextes.raisonConnaissance, valeur: "+\(nombre(connaissance))"))
        }
        if let rapide = points["paiement_rapide"], rapide > 0 {
            lignes.append(Ligne(id: "paiement-rapide", libelle: SwipeTextes.raisonPaiementRapide, valeur: "+\(nombre(rapide))"))
        }
        return lignes
    }

    // MARK: Fin de paquet

    /// État vide du paquet : « tout vu » si la dernière lecture a servi au moins une carte, sinon « rien de nouveau »
    /// (la RPC exclut les missions déjà parcourues : ne jamais affirmer qu'il n'existe aucune mission).
    public struct FinDePaquet: Equatable, Sendable {
        public var titre: String
        public var description: String
        public var alerte: String
        /// Action secondaire : élargir le rayon (tout vu) ou revenir à la liste (rien de nouveau).
        public var elargirLeRayon: Bool
        public var secondaire: String
    }

    public static func finDePaquet(paquetLuNonVide: Bool) -> FinDePaquet {
        paquetLuNonVide
            ? FinDePaquet(titre: SwipeTextes.toutVuTitre, description: SwipeTextes.toutVuDescription, alerte: SwipeTextes.toutVuAlerte,
                          elargirLeRayon: true, secondaire: SwipeTextes.elargirRayon)
            : FinDePaquet(titre: SwipeTextes.rienTitre, description: SwipeTextes.rienDescription, alerte: SwipeTextes.rienAlerte,
                          elargirLeRayon: false, secondaire: SwipeTextes.voirListe)
    }

    /// Missions sauvegardées re-proposées : cinq au plus (`slice(0, 5)` du web), le titre annonce le total lu.
    public static let favorisAffiches = 5
}

public extension FiltrePaquetSwipe {
    /// Filtre du paquet dérivé des critères d'Explorer (`filtreDeck` de `RechercheMissions.tsx` l.374-382) : les chips
    /// rapides et la feuille de filtres s'appliquent au paquet comme à la liste. Source unique : `ExplorerFiltres`
    /// (principe « État dérivé »), jamais un second état de filtres pour le swipe.
    init(explorer filtres: ExplorerFiltres) {
        self.init(urgentesOnly: filtres.urgentesOnly, horaire: filtres.horaire, profession: filtres.profession,
                  ville: filtres.ville, rayonKm: filtres.rayonKm, tauxMin: filtres.tauxMin,
                  typeContrat: filtres.typeContrat.rawValue)
    }
}
