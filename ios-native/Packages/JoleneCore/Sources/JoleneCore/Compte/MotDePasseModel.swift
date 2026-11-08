import Foundation
import Combine

/// Issue d'un changement de mot de passe terminé après le retrait de son écran (revue B8, m3), affichée par le hub
/// (`compte-mdp-issue-hub`) : textes de l'écran, verbatim.
public struct IssueChangementHorsEcran: Equatable, Sendable {
    public let texte: String
    public let estSucces: Bool

    public init(texte: String, estSucces: Bool) {
        self.texte = texte
        self.estSucces = estSucces
    }
}

/// Modèle de l'écran « Changer mon mot de passe » (lot 3, T11, D13), port de `ChangementMotDePasse.tsx`
/// l.26-110. Tenu par le hub (`ProfileScreen`), et non par l'écran (revue B8, m3) : un retour programmé de la
/// pile du Profil (tap push, ligne du centre) en pleine demande ne perd pas l'issue, alors que le mot de passe a
/// pu changer. L'écran signale son ouverture (`ouvertureEcran`) et son retrait de la pile (`retraitEcran`) :
/// - retrait hors demande : formulaire, issue et verrou effacés (démontage du composant web) ;
/// - retrait pendant la demande : elle continue, son issue est annoncée par le hub (`issueAuHub`) jusqu'à la
///   réouverture de l'écran.
/// Règles :
/// - formulaire DÉRIVÉ de la saisie (force, correspondance, validité) : rien n'est re-saisi ni figé ;
/// - une seule demande à la fois (`enCours`, garde `enCours.current` l.44) ;
/// - `.modifie` → champs vidés puis « Mot de passe modifié avec succès. » ; l'audit
///   `DONNEES_PERSO_MODIFICATION` (best-effort, l.78-92) part ensuite et ne retarde ni n'annule l'annonce ;
/// - refus (ancien incorrect, refus GoTrue traduit) : message affiché, saisie conservée ;
/// - réauthentification exigée par le serveur : refus VERROUILLÉ pour la durée de l'écran (aucun nouvel envoi,
///   renvoi vers « Mot de passe oublié ? », D13 ; principe « un gap connu reste verrouillé ») ;
/// - délai dépassé, coupure ou erreur inconnue : le serveur a pu changer le mot de passe, rien n'est annoncé
///   ni renvoyé (`confirmationIndisponible`) ;
/// - session expirée : « Vérifier ma session » (revalidation, libellés du lot 1) ;
/// - toute réponse reçue pour un epoch périmé est ignorée (identité partie : ni annonce ni audit).
@MainActor
public final class MotDePasseModel: ObservableObject {
    /// Saisies (jamais journalisées). Toute frappe efface l'encart de succès et le refus, sauf le refus
    /// verrouillé de la réauthentification.
    @Published public var ancien = "" { didSet { saisieModifiee(ancien, oldValue) } }
    @Published public var nouveau = "" { didSet { saisieModifiee(nouveau, oldValue) } }
    @Published public var confirmation = "" { didSet { saisieModifiee(confirmation, oldValue) } }
    @Published public private(set) var enCours = false
    @Published public private(set) var succes: String?
    @Published public private(set) var erreur: String?
    @Published public private(set) var sessionExpiree = false
    @Published public private(set) var reauthentificationExigee = false
    /// Jeton d'annonce VoiceOver des encarts (`InlineNotice.announcementID`).
    @Published public private(set) var annonces = 0
    /// Instance de l'écran empilée sur le Profil (jeton de `ouvertureEcran`), nil hors de la pile.
    @Published public private(set) var ecranOuvert: UUID?

    private let session: SessionStore
    private let snapshot: SessionSnapshot

    public init(session: SessionStore, snapshot: SessionSnapshot) {
        self.session = session
        self.snapshot = snapshot
    }

    // MARK: - Écran (revue B8, m3)

    /// Issue à annoncer par le hub : celle d'une demande terminée alors que son écran n'est plus sur la pile.
    public var issueAuHub: IssueChangementHorsEcran? {
        guard ecranOuvert == nil else { return nil }
        if let succes { return IssueChangementHorsEcran(texte: succes, estSucces: true) }
        if let erreur { return IssueChangementHorsEcran(texte: erreur, estSucces: false) }
        return nil
    }

    /// L'écran `jeton` est affiché (apparition ; un retour d'onglet le réaffirme).
    public func ouvertureEcran(_ jeton: UUID) {
        ecranOuvert = jeton
    }

    /// L'écran `jeton` a quitté la pile (retour de l'utilisateur, ou retour programmé). Sans effet si un autre
    /// écran l'a déjà remplacé. Hors demande : formulaire, issue et verrou effacés ; pendant la demande : rien
    /// n'est effacé, l'issue ira au hub.
    public func retraitEcran(_ jeton: UUID) {
        guard ecranOuvert == jeton else { return }
        ecranOuvert = nil
        guard !enCours else { return }
        reinitialiser()
    }

    private func reinitialiser() {
        reauthentificationExigee = false
        ancien = ""
        nouveau = ""
        confirmation = ""
        succes = nil
        erreur = nil
        sessionExpiree = false
    }

    // MARK: - Formulaire dérivé

    public var force: ForceMotDePasse { .calculer(nouveau) }
    /// Jauge affichée une fois la saisie commencée (`nouveauMdp.length > 0`, l.156).
    public var afficheJauge: Bool { !nouveau.utf16.isEmpty }
    /// `confirmationMdp.length > 0 && !correspond` (l.169).
    public var afficheNonCorrespondance: Bool { !confirmation.utf16.isEmpty && !correspond }
    /// `correspond` (l.174).
    public var afficheCorrespondance: Bool { correspond }
    public var correspond: Bool { MotDePasse.correspond(nouveau: nouveau, confirmation: confirmation) }
    public var formValide: Bool { MotDePasse.formValide(ancien: ancien, nouveau: nouveau, confirmation: confirmation) }
    /// `disabled={!formValide || loading}` (l.183), plus le verrou de la réauthentification.
    public var peutSoumettre: Bool { formValide && !enCours && !reauthentificationExigee }

    // MARK: - Changement

    public func changer() async {
        guard peutSoumettre else { return }
        enCours = true
        defer { enCours = false }
        succes = nil
        erreur = nil
        guard let gateways = await session.controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.motDePasse
        let context = snapshot.context
        let (ancienSaisi, nouveauSaisi) = (ancien, nouveau)
        // Garde d'identité (revue B8, m2) : consultée par le port entre la vérification et la mise à jour.
        let (controleur, epoch) = (session.controller, snapshot.epoch)
        let identiteCourante: @Sendable () async -> Bool = { await controleur.epoch == epoch }
        let issue: ResultatMotDePasse
        do {
            issue = try await bounded(timeout: session.controller.resolutionTimeout) {
                try await port.changer(ancien: ancienSaisi, nouveau: nouveauSaisi, context: context,
                                       identiteCourante: identiteCourante)
            }
        } catch {
            guard await memeEpoch(), !(error is CancellationError) else { return }
            let jolene = error as? JoleneError
            switch jolene?.kind {
            case .cancelled?:
                return
            case .unauthorized?:
                sessionExpiree = true
                erreur = jolene?.message
            case .contract?:
                erreur = jolene?.message
            default:
                // Délai, réseau, erreur inconnue : le mot de passe a pu changer, aucune annonce.
                erreur = MotDePasse.Textes.confirmationIndisponible
            }
            annonces += 1
            return
        }
        guard await memeEpoch() else { return }
        sessionExpiree = false
        switch issue {
        case .modifie:
            ancien = ""
            nouveau = ""
            confirmation = ""
            succes = MotDePasse.Textes.succes
            annonces += 1
            enCours = false
            await auditer(gateways)
        case .ancienIncorrect:
            erreur = MotDePasse.Textes.ancienIncorrect
            annonces += 1
        case .reauthentificationRequise:
            reauthentificationExigee = true
            erreur = MotDePasse.Textes.reauthentificationRequise
            annonces += 1
        case .refuse(let message):
            erreur = message
            annonces += 1
        }
    }

    /// « Vérifier ma session » : revalide la session ; si elle reste prête pour l'epoch de l'écran, le refus
    /// est effacé (saisie conservée pour un nouvel appui). Une autre identité est reprise par la racine.
    public func verifierSession() async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch, await memeEpoch() else { return }
        sessionExpiree = false
        erreur = nil
    }

    // MARK: - Interne

    private func saisieModifiee(_ valeur: String, _ ancienne: String) {
        guard valeur != ancienne else { return }
        succes = nil
        if !reauthentificationExigee { erreur = nil }
    }

    private func auditer(_ gateways: Gateways) async {
        let audit = gateways.audit
        let context = snapshot.context
        let userId = snapshot.user.id
        let details = MotDePasse.auditDetails(horodatage: gateways.clock.now())
        _ = try? await bounded(timeout: session.controller.resolutionTimeout) {
            try await audit.ecrire(action: .donneesPersoModification, typeRessource: MotDePasse.auditTypeRessource,
                                   idRessource: userId, details: details, context: context)
        }
    }

    private func memeEpoch() async -> Bool { await session.controller.epoch == snapshot.epoch }
}
