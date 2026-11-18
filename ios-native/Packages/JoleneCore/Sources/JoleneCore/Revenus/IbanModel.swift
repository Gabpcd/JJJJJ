import Foundation
import Combine

/// Modèle de l'écran « Coordonnées bancaires » (lot 3, T14b, B9 ; D20, TJ6), port de `SectionIbanPrime`
/// (`SectionPaiements.tsx` l.227-376).
///
/// Règles :
/// - lecture `fn_consulter_mon_iban` à l'ouverture ; IBAN affiché masqué (quatre derniers caractères seulement) ;
/// - saisie DÉRIVÉE : validité (`IbanRules`), « IBAN invalide » / « IBAN valide », bouton actif seulement sur un IBAN
///   valide et un titulaire non blanc, libellés selon `iban_renseigne` ;
/// - une seule demande à la fois (`enCours`) ; le champ IBAN est vidé dès l'envoi, quelle que soit l'issue (jamais
///   conservé, jamais journalisé ni persisté) ; le titulaire est vidé sur un succès seulement (l.271) ;
/// - « IBAN enregistré » seulement sur `.enregistre`, que le port ne rend qu'après relecture probante (D20) ; un refus
///   est affiché par `IbanPresentation.refus` (TJ6), jamais comme un succès ;
/// - après un refus ou une erreur, l'état est relu (un délai dépassé ne prouve pas que le serveur n'a pas agi) ; rien
///   n'est renvoyé automatiquement ;
/// - une lecture en vol pendant l'envoi est invalidée (`generation`) : sa réponse n'écrase jamais l'état relu ;
/// - session expirée : « Session à vérifier » et « Vérifier ma session » (libellés du lot 1, TJ6 règle 2) ;
/// - toute réponse reçue pour un epoch périmé est ignorée.
@MainActor
public final class IbanModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case pret(ConsultationIban)
        case echec(String)
    }

    public enum Issue: Equatable, Sendable {
        case enregistre
        case refus(RefusIbanAffiche)
        case erreur(String)
    }

    /// Saisie de l'IBAN, mise en majuscules comme le web (`setIban(e.target.value.toUpperCase())`, l.331). Toute frappe
    /// efface l'issue affichée.
    @Published public var iban = "" {
        didSet {
            let majuscules = iban.uppercased()
            if majuscules != iban { iban = majuscules }
            if iban != oldValue, !iban.isEmpty { issue = nil }
        }
    }
    @Published public var titulaire = "" {
        didSet { if titulaire != oldValue { issue = nil } }
    }
    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var enCours = false
    @Published public private(set) var issue: Issue?
    @Published public private(set) var sessionExpiree = false
    /// Jeton d'annonce VoiceOver des encarts (une même issue répétée est réannoncée).
    @Published public private(set) var annonces = 0

    private let session: SessionStore
    private let snapshot: SessionSnapshot
    private var generation = 0

    public init(session: SessionStore, snapshot: SessionSnapshot) {
        self.session = session
        self.snapshot = snapshot
    }

    // MARK: - Présentation dérivée

    public var consultation: ConsultationIban? {
        if case let .pret(lue) = etat { return lue }
        return nil
    }

    /// `current?.iban_renseigne && current.iban_verifie` (l.287).
    public var afficheEnregistre: Bool { consultation.map { $0.ibanRenseigne && $0.ibanVerifie } ?? false }
    /// `current?.iban_renseigne && !current.iban_verifie` (l.302).
    public var afficheRibRequis: Bool { consultation.map { $0.ibanRenseigne && !$0.ibanVerifie } ?? false }
    public var masque: String? {
        guard afficheEnregistre, let last4 = consultation?.ibanLast4 else { return nil }
        return IbanRules.masque(last4: last4)
    }
    /// `Titulaire : {iban_titulaire}` (l.295-297), titulaire non vide seulement.
    public var ligneTitulaire: String? {
        guard afficheEnregistre, let titulaire = consultation?.ibanTitulaire, !titulaire.isEmpty else { return nil }
        return IbanTextes.titulairePrefixe + titulaire
    }
    public var libelleChamp: String {
        consultation?.ibanRenseigne == true ? IbanTextes.libelleModifier : IbanTextes.libelleIban
    }
    public var libelleBouton: String {
        if enCours { return IbanTextes.enregistrement }
        return consultation?.ibanRenseigne == true ? IbanTextes.mettreAJour : IbanTextes.enregistrer
    }
    public var afficheInvalide: Bool { IbanRules.afficheInvalide(iban) }
    public var afficheValide: Bool { IbanRules.estValide(iban) }
    public var peutEnregistrer: Bool {
        consultation != nil && !enCours && IbanRules.peutEnregistrer(iban: iban, titulaire: titulaire)
    }

    // MARK: - Lecture

    public func charger() async {
        generation += 1
        let courant = generation
        guard let gateways = await session.controller.gateways(for: snapshot.epoch), generation == courant else { return }
        let port = gateways.iban
        let context = snapshot.context
        do {
            let lue = try await bounded(timeout: session.controller.resolutionTimeout) {
                try await port.consulter(context: context)
            }
            guard await memeEpoch(), generation == courant else { return }
            etat = .pret(lue)
        } catch {
            guard await memeEpoch(), generation == courant, let message = Self.message(error) else { return }
            if (error as? JoleneError)?.kind == .unauthorized { sessionExpiree = true }
            // Après une première lecture, un échec de relecture garde l'état affiché et passe par l'encart d'issue.
            if consultation == nil { etat = .echec(message) }
        }
    }

    // MARK: - Enregistrement

    public func enregistrer() async {
        guard peutEnregistrer else { return }
        enCours = true
        defer { enCours = false }
        // Revue B8 de #1142, m4 : une lecture en vol (`.task` relancé par la réapparition de l'écran) peut être partie
        // avant l'écriture ; sa réponse ne doit jamais écraser l'état relu par l'envoi. Invalidée ici, et de nouveau au
        // retour du port (lecture lancée pendant l'envoi).
        generation += 1
        issue = nil
        let ibanEnvoye = IbanRules.nettoyer(iban)
        let titulaireEnvoye = IbanRules.titulaireNettoye(titulaire)
        iban = ""
        guard let gateways = await session.controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.iban
        let context = snapshot.context
        let resultat: ResultatIban
        do {
            resultat = try await bounded(timeout: session.controller.resolutionTimeout) {
                try await port.enregistrer(iban: ibanEnvoye, titulaire: titulaireEnvoye, context: context)
            }
        } catch {
            generation += 1
            guard await memeEpoch(), let message = Self.message(error) else { return }
            if (error as? JoleneError)?.kind == .unauthorized { sessionExpiree = true }
            publier(.erreur(message))
            await charger()
            return
        }
        generation += 1
        guard await memeEpoch() else { return }
        sessionExpiree = false
        switch resultat {
        case .enregistre(let relue):
            etat = .pret(relue)
            titulaire = ""
            publier(.enregistre)
        case let .refuse(code, message):
            publier(.refus(IbanPresentation.refus(code: code, message: message)))
            await charger()
        }
    }

    /// « Vérifier ma session » : revalide la session ; si elle reste prête pour l'epoch de l'écran, relit l'état.
    public func verifierSession() async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch, await memeEpoch() else { return }
        sessionExpiree = false
        if case .echec = etat { etat = .chargement }
        issue = nil
        await charger()
    }

    // MARK: - Interne

    private func publier(_ nouvelle: Issue) {
        issue = nouvelle
        annonces += 1
    }

    private func memeEpoch() async -> Bool { await session.controller.epoch == snapshot.epoch }

    /// Message d'une erreur ; nil pour une annulation (la vue a disparu : rien à afficher).
    private static func message(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        guard let jolene = error as? JoleneError else { return IbanTextes.erreurGenerique }
        return jolene.kind == .cancelled ? nil : jolene.message
    }
}
