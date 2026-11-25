import Foundation
import Combine

/// Textes des réclamations générales (lot 4, T8), repris de `src/pages/MesReclamations.tsx` (onglet « Réclamations » de
/// `/soignant/litiges`). Chaque texte du web figure tel quel à sa ligne source (`LitigesVerbatimTests`) ; les textes
/// tutoyés, aucun n'étant juridique, passent au vouvoiement (décision 9 du lot 1, liste `vouvoiements`). Les refus du
/// serveur (« Rôle non autorisé ») s'affichent mot pour mot. Textes sans équivalent web, non juridiques :
/// `chargementImpossible` (le web affiche une liste vide sur une erreur de lecture : jamais un état vide fabriqué
/// ici), `nonConfirmee` (relecture qui ne confirme pas, PRINCIPES §3).
public enum ReclamationsTextes {
    // source: src/pages/MesReclamations.tsx:122
    public static let titre = "Mes réclamations"
    // source: src/pages/MesReclamations.tsx:123 (vouvoyé)
    public static let sousTitre = "Signalez un problème ou suivez vos demandes"
    // source: src/pages/MesReclamations.tsx:127 (bouton), l.180 (titre de la feuille)
    public static let signaler = "Signaler un problème"
    // source: src/pages/MesReclamations.tsx:134
    public static let vide = "Aucune réclamation pour le moment."
    // source: src/pages/MesReclamations.tsx:160
    public static let reponseJolene = "Réponse Jolene :"
    // source: src/pages/MesReclamations.tsx:184
    public static let categorie = "Catégorie"
    // source: src/pages/MesReclamations.tsx:196
    public static let sujet = "Sujet"
    // source: src/pages/MesReclamations.tsx:200 (vouvoyé)
    public static let sujetPlaceholder = "Décrivez brièvement le problème"
    // source: src/pages/MesReclamations.tsx:205
    public static let details = "Détails"
    // source: src/pages/MesReclamations.tsx:209 (vouvoyé)
    public static let detailsPlaceholder = "Expliquez la situation en détail : dates, montants, personnes concernées..."
    // source: src/pages/MesReclamations.tsx:216
    public static let annuler = "Annuler"
    // source: src/pages/MesReclamations.tsx:219
    public static let envoyer = "Envoyer"
    // source: src/pages/MesReclamations.tsx:99 (repli d'une erreur sans message, contrainte 23514 comprise)
    public static let erreurSoumission = "Erreur lors de la soumission"
    // source: src/pages/MesReclamations.tsx:101 (vouvoyé)
    public static let envoyee = "Réclamation envoyée — nous reviendrons vers vous rapidement"

    /// Échec de lecture de la liste : message neutre, sans équivalent web.
    public static let chargementImpossible = "Vos réclamations n’ont pas pu être chargées."
    /// Relecture qui ne montre pas la réclamation annoncée (PRINCIPES §3) : jamais un succès affiché.
    public static let nonConfirmee = "L’envoi de la réclamation n’a pas pu être confirmé. Réessayez."

    /// `CATEGORIES` (l.22-28), dans l'ordre du sélecteur.
    // source: src/pages/MesReclamations.tsx:23-27
    public static func libelle(_ categorie: CategorieReclamation) -> String {
        switch categorie {
        case .mission: return "Mission (annulation, litige, problème)"
        case .paiement: return "Paiement (retard, montant incorrect)"
        case .comportement: return "Comportement (soignant ou établissement)"
        case .technique: return "Problème technique (bug, accès)"
        case .autre: return "Autre"
        }
    }

    /// `CATEGORIES.find(c => c.value === r.categorie)?.label || r.categorie` (l.144) : une catégorie inconnue garde son code.
    public static func libelleCategorie(_ code: String) -> String {
        CategorieReclamation(rawValue: code).map(libelle) ?? code
    }

    /// `STATUT_CONFIG[r.statut] || STATUT_CONFIG.EN_ATTENTE` (l.30-35, l.142) : un statut inconnu s'affiche « En attente ».
    // source: src/pages/MesReclamations.tsx:31-34
    public static func libelleStatut(_ code: String) -> String {
        switch code {
        case "EN_COURS": return "En cours de traitement"
        case "RESOLUE": return "Résolue"
        case "FERMEE": return "Fermée"
        default: return "En attente"
        }
    }

    /// `format(new Date(iso), "d MMM yyyy 'à' HH:mm", { locale: fr })` à l'heure de Paris (l.150, l.164).
    public static func dateHeure(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty, let instant = try? DateHeureParis.instantJolene(iso) else { return nil }
        return DateHeureParis.format(instant, "d MMM yyyy 'à' HH:mm")
    }

    /// « {catégorie} · {date} » (l.150).
    public static func meta(_ reclamation: Reclamation) -> String {
        let categorie = libelleCategorie(reclamation.categorie)
        guard let date = dateHeure(reclamation.creeLe) else { return categorie }
        return "\(categorie) · \(date)"
    }

    /// Textes tutoyés du web et leur forme vouvoyée (décision 9 du lot 1 ; aucun n'est juridique).
    public static let vouvoiements: [(web: String, natif: String, ligne: Int)] = [
        ("Signale un problème ou suis tes demandes", sousTitre, 123),
        ("Décris brièvement le problème", sujetPlaceholder, 200),
        ("Explique la situation en détail : dates, montants, personnes concernées...", detailsPlaceholder, 209),
        ("Réclamation envoyée — nous reviendrons vers toi rapidement", envoyee, 101),
    ]
}

/// Modèle de « Mes réclamations » (lot 4, T8), port de `ReclamationsContent` (`src/pages/MesReclamations.tsx`).
///
/// - Liste dans l'ordre serveur (`cree_le` décroissant) ; une erreur de lecture est affichée (le web montre alors une
///   liste vide), avec « Réessayer ».
/// - Soumission (l.87-109) : catégorie de la liste fermée du serveur (`reclamations_categorie_check`), sujet et détails
///   non vides après `trim` (bouton désactivé sinon, comme le web). `fn_soumettre_reclamation` ne pose ni `success` ni
///   `ok` : le succès est l'`id` rendu puis la ligne relue (gateway) ; il n'est annoncé qu'après une relecture de la
///   liste qui la contient (PRINCIPES §3). Refus du serveur mot pour mot dans la feuille restée ouverte.
/// - Mêmes règles que `LitigesModel` : appels bornés, epoch, dernière lecture seule, relecture après une erreur de
///   transport, jamais de renvoi, annulation jamais présentée en erreur.
@MainActor
public final class ReclamationsModel: ObservableObject {
    @Published public private(set) var liste: EtatLecture<[Reclamation]> = .chargement
    @Published public private(set) var erreur: String?
    @Published public private(set) var confirmation: String?
    @Published public private(set) var jeton = 0
    @Published public private(set) var sessionExpiree = false

    @Published public private(set) var formulaireOuvert = false
    @Published public private(set) var categorie: CategorieReclamation = .mission
    @Published public private(set) var sujet = ""
    @Published public private(set) var details = ""
    @Published public private(set) var envoiEnCours = false
    @Published public private(set) var erreurFormulaire: String?

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var revision = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    public var reclamations: [Reclamation] { liste.valeur ?? [] }

    /// « Envoyer » : `disabled={submitting || !sujet.trim() || !details.trim()}` (l.217).
    public var peutEnvoyer: Bool {
        formulaireOuvert && !envoiEnCours && !LitigesPresentation.nettoyer(sujet).isEmpty
            && !LitigesPresentation.nettoyer(details).isEmpty
    }

    public func charger() async {
        erreur = nil
        await lire(explicite: true)
    }

    public func effacerMessages() {
        erreur = nil
        confirmation = nil
    }

    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    // MARK: - Formulaire

    public func ouvrirFormulaire() {
        guard !envoiEnCours else { return }
        effacerMessages()
        erreurFormulaire = nil
        formulaireOuvert = true
    }

    /// « Annuler » ou feuille refermée : comme le web, la saisie est gardée jusqu'à l'envoi réussi.
    public func fermerFormulaire() {
        guard !envoiEnCours else { return }
        formulaireOuvert = false
        erreurFormulaire = nil
    }

    public func choisir(_ nouvelle: CategorieReclamation) {
        guard !envoiEnCours else { return }
        categorie = nouvelle
    }

    public func saisirSujet(_ texte: String) {
        guard !envoiEnCours else { return }
        sujet = texte
    }

    public func saisirDetails(_ texte: String) {
        guard !envoiEnCours else { return }
        details = texte
    }

    /// « Envoyer » (l.87-109) ; `true` si la réclamation est relue dans la liste (la feuille se referme).
    @discardableResult
    public func envoyer() async -> Bool {
        guard peutEnvoyer else { return false }
        let choix = categorie
        let objet = LitigesPresentation.nettoyer(sujet)
        let texte = LitigesPresentation.nettoyer(details)
        let avant = Set(reclamations.map(\.id))
        envoiEnCours = true
        erreurFormulaire = nil
        defer { envoiEnCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.reclamations
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.soumettre(categorie: choix, sujet: objet, details: texte, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            sessionExpiree = false
            switch issue {
            case let .refusee(message):
                erreurFormulaire = message.isEmpty ? ReclamationsTextes.erreurSoumission : message
                return false
            case let .soumise(reclamation):
                await lire(explicite: false)
                guard await controller.epoch == snapshot.epoch else { return false }
                guard reclamations.contains(where: { $0.id == reclamation.id }) else {
                    erreurFormulaire = ReclamationsTextes.nonConfirmee
                    return false
                }
                confirmerEnvoi()
                return true
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = LitigesModel.message(pour: error, repli: ReclamationsTextes.erreurSoumission) else { return false }
            sessionExpiree = issue.sessionExpiree
            erreurFormulaire = issue.message
            guard !issue.sessionExpiree else { return false }
            // Le serveur a pu enregistrer la réclamation (délai, réponse perdue) : relecture, jamais de renvoi. Une
            // réclamation nouvelle aux mêmes catégorie, sujet et détails fait foi ; sinon l'erreur reste dans la feuille.
            await lire(explicite: false)
            guard await controller.epoch == snapshot.epoch, reclamations.contains(where: {
                !avant.contains($0.id) && $0.categorie == choix.rawValue && $0.sujet == objet && $0.details == texte
            }) else { return false }
            confirmerEnvoi()
            return true
        }
    }

    /// Réclamation relue dans la liste : formulaire remis à neuf (l.102-105), succès du web annoncé.
    private func confirmerEnvoi() {
        formulaireOuvert = false
        erreurFormulaire = nil
        sujet = ""
        details = ""
        categorie = .mission
        erreur = nil
        confirmation = ReclamationsTextes.envoyee
        jeton += 1
    }

    // MARK: - Interne

    private func lire(explicite: Bool) async {
        revision += 1
        let revisionLecture = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.reclamations
        let context = snapshot.context
        do {
            let lignes = try await bounded(timeout: controller.resolutionTimeout) { try await port.lister(context: context) }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return }
            liste = .prete(lignes)
            sessionExpiree = false
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled,
                  let issue = LitigesModel.message(pour: error, repli: ReclamationsTextes.chargementImpossible) else { return }
            if issue.sessionExpiree { sessionExpiree = true }
            let message = issue.sessionExpiree ? issue.message : ReclamationsTextes.chargementImpossible
            if liste.estPrete {
                if explicite { signaler(message) }
            } else {
                liste = .echec(message)
            }
        }
    }

    private func signaler(_ message: String) {
        confirmation = nil
        erreur = message
        jeton += 1
    }
}
