import Foundation
import Combine

/// Modèle de l'écran de publication d'une mission (lot 5, T9 ; `LOT5_PLAN.md` §2.6), port du parcours de
/// `FormulaireMission.tsx` et `FormulaireRecurrence.tsx` réduit au périmètre natif (D8), sur
/// `gateways.etablissement.publication` pour l'epoch de la session, appel borné à `SessionController.resolutionTimeout`.
///
/// **État dérivé** (principe du dépôt, `PlanningDerive`) : la période [première date, dernière date] dérive les jours,
/// les jours portent les créneaux, et les créneaux envoyés sont dérivés des jours travaillés. Rien n'est saisi deux
/// fois ni prérempli par un défaut figé : changer une borne re-dérive les jours ; un jour dont la date reste dans la
/// période garde son état, ses créneaux et ses exceptions ; un jour sorti disparaît ; un jour nouveau arrive « repos »
/// avec le créneau proposé par le web. Erreurs de planning, créneaux matérialisés et total d'heures sont recalculés à
/// chaque lecture, jamais stockés.
///
/// Envoi (§2.4, PRINCIPES §3) : « Publier la mission » ouvre le récapitulatif sur un brouillon figé ; « Publier »
/// l'envoie une seule fois (`enCours` posé avant toute suspension : un double toucher ne part qu'une fois). « Publiée »
/// n'existe qu'après la relecture de la mission créée, faite par le port ; un refus serveur s'affiche mot pour mot ; une
/// issue inconnue (délai, transport) ou non confirmée n'est jamais un succès et n'est jamais renvoyée automatiquement.
///
/// Validation locale structurelle seulement : champs obligatoires, période, créneau manquant ou invalide,
/// chevauchement. Les règles du temps de travail et la validation de la mission restent au serveur (D9).
@MainActor
public final class PublicationModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case saisie
        /// Mission créée **et relue** par le port.
        case publiee(missionId: String)
    }

    /// Récapitulatif avant envoi : brouillon figé et créneaux matérialisés qu'il porte.
    public struct Recapitulatif: Equatable, Sendable {
        public var brouillon: PublicationMission
        public var creneaux: [PlanningDerive.CreneauMaterialise]

        public init(brouillon: PublicationMission, creneaux: [PlanningDerive.CreneauMaterialise]) {
            self.brouillon = brouillon; self.creneaux = creneaux
        }

        /// Total d'heures des créneaux du récapitulatif (dérivé).
        public var totalHeures: Double { creneaux.reduce(0) { $0 + $1.dureeHeures } }
    }

    /// Issue affichée au-dessus du formulaire.
    public enum Annonce: Equatable, Sendable {
        /// Refus serveur mot pour mot, ou erreur locale : rien n'a été publié.
        case erreur(String)
        /// `fn_blocage_publication_etab` : message serveur mot pour mot et renvoi web.
        case blocage(code: String, message: String)
        /// Issue inconnue ou relecture qui ne confirme pas ; `missionId` quand le serveur en a rendu un.
        case nonConfirmee(detail: String?, missionId: String?)
    }

    @Published public private(set) var saisie = PublicationSaisie()
    @Published public private(set) var etat: Etat = .saisie
    @Published public private(set) var recap: Recapitulatif?
    @Published public private(set) var annonce: Annonce?
    /// Envoi en vol : toute autre action est ignorée.
    @Published public private(set) var enCours = false
    /// Une borne de la période a été saisie : l'erreur « période invalide » ne s'affiche qu'ensuite (web l.438).
    @Published public private(set) var datesModifiees = false
    /// Publication non confirmée (issue inconnue ou relecture différente) : la mission existe peut-être. Le formulaire
    /// ne repart plus depuis cet écran (revue B8 sécurité de la vague D, m3, risque de doublon) ; « Voir mes missions »
    /// (liste relue) reste la seule suite, l'avertissement restant affiché. Jamais levé par une modification de saisie.
    @Published public private(set) var relectureRequise = false
    /// Plancher du taux horaire salarié, lu au serveur par `chargerTauxMinimum()`. Fermé : tant qu'il n'est pas lu
    /// (`.enCours`) ou s'il est illisible (`.indisponible`), aucun taux n'est publiable ; aucune constante ne le remplace.
    @Published public private(set) var plancher: PlancherTaux = .enCours

    public enum PlancherTaux: Equatable, Sendable {
        case enCours
        case lu(Double)
        /// Lecture impossible (paramètre absent, réponse illisible, délai, transport) ; `motif` pour le diagnostic.
        case indisponible(motif: String)
    }

    /// Plancher retenu, `nil` tant qu'il n'est pas lu.
    public var tauxMinimum: Double? {
        if case let .lu(valeur) = plancher { return valeur }
        return nil
    }

    private let controller: SessionController
    private let snapshot: EtablissementSessionSnapshot
    private let nouvelIdClient: () -> String

    /// `nouvelIdClient` : identifiant local d'un créneau (stable pendant la saisie) ; injecté par les tests.
    public init(controller: SessionController, snapshot: EtablissementSessionSnapshot,
                nouvelIdClient: @escaping () -> String = { UUID().uuidString }) {
        self.controller = controller
        self.snapshot = snapshot
        self.nouvelIdClient = nouvelIdClient
    }

    // MARK: - État dérivé

    /// Champs obligatoires manquants ou invalides, dans l'ordre du formulaire.
    /// Plancher non lu : `.infinity` (comme une constante illisible, `PublicationRules.tauxMinimum`) ferme le champ.
    public var champsInvalides: [PublicationRules.Champ] {
        PublicationRules.champsInvalides(saisie, minimum: tauxMinimum ?? .infinity)
    }

    /// Avis sous le champ du taux quand un taux lisible est sous le plancher lu (texte validé, montant lu).
    public var avisTauxSousLeMinimum: String? {
        guard let minimum = tauxMinimum, PublicationRules.tauxSousLeMinimum(saisie.taux, minimum: minimum) else { return nil }
        return PublicationPresentation.tauxSousLeMinimum(minimum)
    }

    /// Lit le plancher au serveur pour l'epoch de la session (borné comme l'envoi). Lecture impossible : `.indisponible`
    /// et le message générique de la publication (texte existant), jamais une valeur inventée. Rappelable (« tirer pour
    /// actualiser ») ; un plancher déjà lu n'est jamais remplacé par une erreur ultérieure.
    public func chargerTauxMinimum() async {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.etablissement.publication
        let context = snapshot.context
        let resultat: Result<Double, Error>
        do {
            resultat = .success(try await bounded(timeout: controller.resolutionTimeout) {
                try await port.tauxMinimumSalarie(context: context)
            })
        } catch {
            resultat = .failure(error)
        }
        guard await epochValide() else { return }
        switch resultat {
        case let .success(valeur) where valeur.isFinite && valeur > 0:
            plancher = .lu(valeur)
            if annonce == .erreur(PublicationPresentation.messageErreurGenerique) { annonce = nil }
        case .success:
            if tauxMinimum == nil { signalerPlancherIndisponible("valeur non positive") }
        case let .failure(erreur):
            if Self.message(erreur) == nil { return } // annulation : rien à signaler
            if tauxMinimum == nil { signalerPlancherIndisponible(String(describing: erreur)) }
        }
    }

    private func signalerPlancherIndisponible(_ motif: String) {
        plancher = .indisponible(motif: motif)
        if annonce == nil { annonce = .erreur(PublicationPresentation.messageErreurGenerique) }
    }

    /// Erreurs structurelles du planning (`FormulaireRecurrence.tsx` l.180-218) ; une date illisible vaut une période
    /// invalide (fail-closed).
    public var erreursPlanning: [PlanningDerive.Erreur] {
        (try? PlanningDerive.validerPeriode(dateDebut: saisie.dateDebut, dateFin: saisie.dateFin, jours: saisie.jours))
            ?? [PlanningDerive.Erreur(type: .plageInvalide, message: PlanningDerive.messagePeriodeInvalide)]
    }

    /// Erreurs de planning à afficher : comme le web (l.438-441), une période invalide n'est signalée qu'après une
    /// première saisie de date.
    public var erreursPlanningAffichees: [PlanningDerive.Erreur] {
        erreursPlanning.filter { datesModifiees || $0.type != .plageInvalide }
    }

    /// Créneaux en erreur structurelle (encadrés par l'écran, web l.282-284).
    public var creneauxEnErreur: Set<String> {
        Set(erreursPlanning.flatMap { $0.creneauxAffectes ?? [] })
    }

    /// Créneaux valides des jours travaillés, triés par début : la liste qui sera envoyée, dérivée des jours.
    public var creneaux: [PlanningDerive.CreneauMaterialise] {
        (try? PlanningDerive.materialiserPlanning(saisie.jours)) ?? []
    }

    public var joursTravailles: Int { saisie.jours.filter(\.actif).count }

    /// Le récapitulatif peut s'ouvrir : champs et planning structurellement valides, au moins un créneau, aucun envoi.
    public var peutOuvrirRecap: Bool {
        etat == .saisie && !enCours && recap == nil && !relectureRequise && champsInvalides.isEmpty && erreursPlanning.isEmpty
            && !creneaux.isEmpty
    }

    private var modifiable: Bool { etat == .saisie && !enCours && recap == nil }

    // MARK: - Saisie des champs

    public func definirIntitule(_ valeur: String) {
        guard modifiable else { return }
        saisie.intitule = PublicationRules.intitule(valeur)
    }

    public func definirDescription(_ valeur: String) {
        guard modifiable else { return }
        saisie.description = valeur
    }

    /// Profession de la liste native seulement (une profession renvoyée au web n'est jamais retenue, D8) ; vide pour
    /// revenir à « aucune ».
    public func definirProfession(_ code: String) {
        guard modifiable, code.isEmpty || PublicationRules.professionPubliable(code) else { return }
        saisie.profession = code
    }

    public func definirService(_ valeur: String) {
        guard modifiable else { return }
        saisie.service = valeur
    }

    public func definirTaux(_ valeur: String) {
        guard modifiable else { return }
        saisie.taux = valeur
    }

    public func definirModeAttribution(_ mode: ModeAttributionPublication) {
        guard modifiable else { return }
        saisie.modeAttribution = mode
    }

    public func definirUrgente(_ urgente: Bool) {
        guard modifiable else { return }
        saisie.estUrgente = urgente
    }

    public func definirNiveauUrgence(_ niveau: Int) {
        guard modifiable, PublicationRules.niveauxUrgence.contains(niveau) else { return }
        saisie.niveauUrgence = niveau
    }

    // MARK: - Période → jours (re-dérivation)

    /// Première date de la période (`YYYY-MM-DD`, vide pour l'effacer) ; les jours sont re-dérivés.
    public func definirDateDebut(_ date: String) {
        definirPeriode(debut: date, fin: saisie.dateFin)
    }

    /// Dernière date de la période ; les jours sont re-dérivés.
    public func definirDateFin(_ date: String) {
        definirPeriode(debut: saisie.dateDebut, fin: date)
    }

    /// Fixe les deux bornes puis re-dérive les jours (`FormulaireRecurrence.tsx` l.164-178) : jours restés dans la
    /// période conservés tels quels, jours nouveaux « repos », jours sortis supprimés. Une période vide, inversée ou de
    /// plus de 366 dates ne garde aucun jour, comme le web.
    public func definirPeriode(debut: String, fin: String) {
        guard modifiable else { return }
        datesModifiees = true
        saisie.dateDebut = debut
        saisie.dateFin = fin
        saisie.jours = (try? PlanningDerive.rederiver(dateDebut: debut, dateFin: fin, precedents: saisie.jours,
                                                      nouvelIdClient: nouvelIdClient)) ?? []
    }

    /// Première date choisie sans valeur préalable : le jour civil de Paris de l'horloge de la session (action
    /// explicite de l'utilisateur, jamais un préremplissage). Sans effet si la date est déjà choisie.
    public func choisirDateDebut() async {
        guard saisie.dateDebut.isEmpty, let aujourdhui = await aujourdhui() else { return }
        definirDateDebut(aujourdhui)
    }

    /// Dernière date choisie sans valeur préalable : la première date si elle existe, sinon le jour de l'horloge.
    public func choisirDateFin() async {
        guard saisie.dateFin.isEmpty else { return }
        if !saisie.dateDebut.isEmpty {
            definirDateFin(saisie.dateDebut)
        } else if let aujourdhui = await aujourdhui() {
            definirDateFin(aujourdhui)
        }
    }

    /// Décale la première date de `jours` jours civils.
    public func decalerDateDebut(jours: Int) {
        guard let date = try? PlanningDerive.ajouterJoursDate(saisie.dateDebut, jours) else { return }
        definirDateDebut(date)
    }

    /// Décale la dernière date de `jours` jours civils.
    public func decalerDateFin(jours: Int) {
        guard let date = try? PlanningDerive.ajouterJoursDate(saisie.dateFin, jours) else { return }
        definirDateFin(date)
    }

    private func aujourdhui() async -> String? {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        return DateHeureParis.cleJour(gateways.clock.now())
    }

    // MARK: - Jours → créneaux

    /// Bascule travaillé / repos ; un jour remis au repos garde ses créneaux saisis.
    public func basculerJour(_ date: String) {
        guard modifiable else { return }
        saisie.jours = PlanningDerive.basculer(saisie.jours, date: date, nouvelIdClient: nouvelIdClient)
    }

    public func ajouterCreneau(_ date: String) {
        guard modifiable else { return }
        saisie.jours = PlanningDerive.ajouterCreneau(saisie.jours, date: date, nouvelIdClient: nouvelIdClient)
    }

    public func retirerCreneau(date: String, clientId: String) {
        guard modifiable else { return }
        saisie.jours = PlanningDerive.retirerCreneau(saisie.jours, date: date, clientId: clientId)
    }

    /// Remplace le créneau de même identifiant local (heures murales de Paris, fin le lendemain ou non).
    public func modifierCreneau(date: String, creneau: PlanningDerive.Creneau) {
        guard modifiable else { return }
        saisie.jours = PlanningDerive.modifierCreneau(saisie.jours, date: date, creneau: creneau)
    }

    /// « Appliquer le 1er horaire aux jours sélectionnés » : initialiseur, les créneaux datés restent la vérité.
    public func appliquerPremierCreneauATous() {
        guard modifiable else { return }
        saisie.jours = PlanningDerive.appliquerPremierCreneauATous(saisie.jours, nouvelIdClient: nouvelIdClient)
    }

    // MARK: - Récapitulatif et envoi

    /// Ouvre le récapitulatif sur un brouillon figé ; aucun appel réseau. Sans effet si la saisie n'est pas valide.
    public func ouvrirRecapitulatif() {
        guard peutOuvrirRecap, let taux = PublicationRules.taux(saisie.taux) else { return }
        annonce = nil
        let materialises = creneaux
        guard let charge = PublicationPayload.creneaux(materialises) else {
            annonce = .erreur(PublicationPresentation.planningIllisible)
            return
        }
        let description = saisie.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = saisie.service.trimmingCharacters(in: .whitespacesAndNewlines)
        let brouillon = PublicationMission(
            intitule: saisie.intitule, description: description.isEmpty ? nil : saisie.description,
            professionRequise: saisie.profession, service: service.isEmpty ? nil : service, tauxHoraireBase: taux,
            estUrgente: saisie.estUrgente, creneaux: charge, niveauUrgence: saisie.niveauUrgence,
            modeAttribution: saisie.modeAttribution)
        recap = Recapitulatif(brouillon: brouillon, creneaux: materialises)
    }

    /// Ferme le récapitulatif (« Modifier », geste), jamais pendant un envoi.
    public func annulerRecapitulatif() {
        guard !enCours else { return }
        recap = nil
    }

    /// « Publier » : un seul envoi du brouillon du récapitulatif, puis l'issue du port.
    public func confirmerPublication() async {
        guard !enCours, etat == .saisie, !relectureRequise, let ouvert = recap else { return }
        enCours = true
        defer { enCours = false }
        annonce = nil
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.etablissement.publication
        let context = snapshot.context
        let brouillon = ouvert.brouillon
        let issue: PublicationOutcome
        do {
            issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.publier(brouillon, context: context)
            }
        } catch {
            guard await epochValide(), let message = Self.message(error) else { return }
            recap = nil
            if let erreur = error as? JoleneError, erreur.kind == .unauthorized {
                // Refus de session avant toute écriture : rien n'a été publié.
                annonce = .erreur(erreur.message)
            } else {
                // Issue inconnue (délai, transport) : la mission existe peut-être ; jamais renvoyée automatiquement.
                relectureRequise = true
                annonce = .nonConfirmee(detail: message, missionId: nil)
            }
            return
        }
        guard await epochValide() else { return }
        recap = nil
        switch issue {
        case let .publiee(missionId):
            etat = .publiee(missionId: missionId)
        case let .refusee(_, message):
            annonce = .erreur(message)
            // Revue de #1194, m3 : un refus (dont le verrou du plancher, `P0001`) peut venir d'un paramètre relevé
            // depuis la lecture ; le plancher est relu, sans autre texte ni état d'écran.
            await chargerTauxMinimum()
        case let .blocageEtablissement(code, message):
            annonce = .blocage(code: code, message: message)
        case let .nonConfirmee(missionId):
            relectureRequise = true
            annonce = .nonConfirmee(detail: nil, missionId: missionId)
        }
    }

    public func effacerAnnonce() {
        annonce = nil
    }

    /// Repart d'un formulaire vide après une publication confirmée.
    public func nouvellePublication() {
        guard !enCours, case .publiee = etat else { return }
        saisie = PublicationSaisie()
        recap = nil
        annonce = nil
        datesModifiees = false
        etat = .saisie
    }

    private func epochValide() async -> Bool {
        await controller.epoch == snapshot.epoch
    }

    /// Message affiché d'une erreur ; `nil` pour une annulation (jamais une erreur affichée).
    static func message(_ error: Error) -> String? {
        if let jolene = error as? JoleneError { return jolene.kind == .cancelled ? nil : jolene.message }
        if error is CancellationError { return nil }
        return PublicationPresentation.messageErreurGenerique
    }
}
