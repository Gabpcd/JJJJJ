import Foundation

/// Stockage brut de l'avatar (bucket `jolene-documents`) : dépôt, URL signée et lecture des octets. Aucune règle
/// métier : l'enchaînement, le reçu et la relecture sont ceux d'`EnvoiAvatar`. Supabase : `SupabaseAvatarStorage`
/// (JoleneSupabase) ; démo : `DemoStockageAvatar` (mémoire vive, aucun réseau).
public protocol StockageAvatarPort: Sendable {
    /// Dépose l'objet (`contentType image/jpeg`, `upsert: false`). Refus CERTAIN du stockage (réponse 4xx :
    /// politique, MIME, taille, objet existant) → `RefusStockageAvatar` ; toute autre erreur laisse l'issue inconnue.
    func deposer(chemin: String, jpeg: Data, context: MissionReadContext) async throws
    func urlSignee(chemin: String, dureeSecondes: Int, context: MissionReadContext) async throws -> URL
    /// Octets à l'URL signée relue ; nil si illisibles. Jamais journalisés.
    func image(url: URL) async -> Data?
}

/// Refus certain du stockage : la réponse dit que l'objet n'a pas été déposé.
public struct RefusStockageAvatar: Error, Equatable, Sendable {
    public let statut: Int?
    public init(statut: Int?) { self.statut = statut }
}

/// Essais d'avatar en cours dans ce processus : la réconciliation ne touche jamais le reçu d'un envoi encore en vol
/// (écran rouvert pendant un envoi), qui se terminera lui-même, ni celui qu'une autre réconciliation est en train de
/// solder (revue B8 de T10, m6 : deux réconciliations du même reçu ne s'entrelacent jamais).
public actor RegistreEnvoisAvatar {
    public static let partage = RegistreEnvoisAvatar()
    private var essais: Set<String> = []

    public init() {}

    func debuter(_ attemptId: String) -> Bool { essais.insert(attemptId).inserted }
    func terminer(_ attemptId: String) { essais.remove(attemptId) }
    func contient(_ attemptId: String) -> Bool { essais.contains(attemptId) }
}

/// Changement de photo de profil (lot 3, T10), comme `AvatarUpload.handleFile` (l.119-171) avec un reçu durable
/// (PRINCIPES §4) et une relecture (PRINCIPES §3) :
/// 1. reçu laissé par un envoi interrompu soldé d'abord (réconciliation, jamais de renvoi automatique) ;
/// 2. reçu `prepared` écrit puis relu AVANT toute requête (échec → `RefusAvatar`, rien n'est envoyé) ;
/// 3. `started`, dépôt `<uid>/avatar-<ms>.jpg` ; refus certain → `refused`, `RefusAvatar` (aucun `p_avatar_url`) ;
/// 4. `stored`, URL signée 5 ans, `fn_modifier_mon_profil(p_avatar_url:)` par le port du profil, qui RELIT le profil ;
///    succès seulement si `avatar_url` relue est l'URL envoyée ; refus serveur → `refused`, message verbatim ;
/// 5. succès : reçu effacé, URL relue rendue.
/// Toute autre erreur (délai, réseau, HTTP 5xx) laisse le reçu en `started` ou `stored` : issue inconnue, que
/// `reconcilier` tranche par relecture de `avatar_url`.
///
/// Reçu ILLISIBLE (octets présents mais indécodables : version inconnue, JSON altéré, autre utilisateur ; revue B8 de
/// T10, m8) : l'envoi reste fail-closed (rien ne part), mais `reconcilier` — ouverture de l'écran — le retire, essai
/// inconnu clos sans requête ; la photo affichée est `avatar_url` relue à l'ouverture, et le prochain envoi choisi par
/// l'utilisateur repart d'un reçu neuf. Sans cette reprise, un reçu illisible bloquait tout envoi pour toujours (le
/// trousseau survit à la réinstallation). Une erreur du MAGASIN (trousseau verrouillé, refus du système) n'est pas un
/// reçu illisible : rien n'est effacé, la réconciliation échoue fermée.
public struct EnvoiAvatar: AvatarStoragePort {
    private let stockage: StockageAvatarPort
    private let profil: ProfilPort
    private let recus: RecusAvatarPort
    private let horloge: ClockPort
    private let registre: RegistreEnvoisAvatar
    private let identifiant: @Sendable () -> String

    public init(stockage: StockageAvatarPort, profil: ProfilPort, recus: RecusAvatarPort, horloge: ClockPort,
                registre: RegistreEnvoisAvatar = .partage, identifiant: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.stockage = stockage; self.profil = profil; self.recus = recus; self.horloge = horloge
        self.registre = registre; self.identifiant = identifiant
    }

    public func televerser(jpeg: Data, context: MissionReadContext) async throws -> URL {
        try MissionBusiness.validateContext(context)
        guard !jpeg.isEmpty else { throw RefusAvatar(AvatarProfil.Textes.fichierVide) }
        guard jpeg.count <= AvatarProfil.tailleMaxOctets else { throw RefusAvatar(AvatarProfil.Textes.fichierTropLourd) }
        // 1. Reçu précédent soldé (relecture), jamais rejoué ; reçu illisible : refus (fail-closed, aucune reprise ici).
        _ = try await reconcilier(context: context, reprendreIllisible: false)
        let userId = context.userId
        // 2. Reçu durable avant toute requête.
        let recu = RecuAvatar(userId: userId, attemptId: identifiant(),
                              chemin: AvatarProfil.chemin(userId: userId, instant: horloge.now()))
        guard await registre.debuter(recu.attemptId) else { throw RefusAvatar(AvatarProfil.Textes.echecEnvoi) }
        do {
            let url = try await envoyer(recu, jpeg: jpeg, context: context)
            await registre.terminer(recu.attemptId)
            return url
        } catch {
            await registre.terminer(recu.attemptId)
            throw error
        }
    }

    public func reconcilier(context: MissionReadContext) async throws -> ReconciliationAvatar {
        try await reconcilier(context: context, reprendreIllisible: true)
    }

    public func image(url: URL) async -> Data? { await stockage.image(url: url) }

    // MARK: - Interne

    private func reconcilier(context: MissionReadContext, reprendreIllisible: Bool) async throws -> ReconciliationAvatar {
        try MissionBusiness.validateContext(context)
        let recu: RecuAvatar?
        do {
            recu = try await recus.lire(userId: context.userId)
        } catch let erreur as RecuAvatar.Erreur where reprendreIllisible && (erreur == .illisible || erreur == .utilisateurDifferent) {
            // Reçu illisible (m8) : essai inconnu, retiré sans requête ; `avatar_url` relue à l'ouverture fait foi.
            try await effacer(userId: context.userId)
            return .aucune
        } catch {
            throw RefusAvatar(AvatarProfil.Textes.echecEnvoi)
        }
        // Essai en vol (envoi ou autre réconciliation) : jamais touché.
        guard let recu, await registre.debuter(recu.attemptId) else { return .aucune }
        do {
            let issue = try await solder(recu, context: context)
            await registre.terminer(recu.attemptId)
            return issue
        } catch {
            await registre.terminer(recu.attemptId)
            throw error
        }
    }

    private func solder(_ recu: RecuAvatar, context: MissionReadContext) async throws -> ReconciliationAvatar {
        if recu.estTermine {
            try await effacer(recu)
            return .aucune
        }
        if recu.phase != .prepared {
            // Dépôt parti : seule la relecture de `avatar_url` dit si le profil a été lié.
            let relu = try await profil.profil(context: context)
            if AvatarProfil.urlDesigne(relu.avatarUrl, chemin: recu.chemin), let avatar = relu.avatarUrl,
               let url = URL(string: avatar) {
                try? await recus.effacer(userId: recu.userId)
                return .confirmee(url)
            }
        }
        // Rien n'est lié au profil (ou rien n'est parti) : l'essai est clos sans renvoi.
        try await journaliser(recu.vers(.notSent))
        try await effacer(recu)
        return .nonConfirmee
    }

    private func envoyer(_ prepare: RecuAvatar, jpeg: Data, context: MissionReadContext) async throws -> URL {
        try await journaliser(prepare)
        let enCours = try prepare.vers(.started)
        try await journaliser(enCours)
        do {
            try await stockage.deposer(chemin: prepare.chemin, jpeg: jpeg, context: context)
        } catch is RefusStockageAvatar {
            try await clore(enCours, .refused)
            throw RefusAvatar(AvatarProfil.Textes.echecEnvoi)
        }
        let depose = try enCours.vers(.stored)
        try await journaliser(depose)
        let url = try await stockage.urlSignee(chemin: prepare.chemin, dureeSecondes: AvatarProfil.dureeURLSigneeSecondes,
                                               context: context)
        let relu: ProfilComplet
        do {
            relu = try await profil.modifier(ModificationProfil(avatarUrl: url.absoluteString), context: context)
        } catch let refus as RefusEnregistrementProfil {
            try await clore(depose, .refused)
            throw RefusAvatar(refus.message)
        }
        guard relu.avatarUrl == url.absoluteString else {
            // Profil relu sans l'URL envoyée : issue non prouvée, la réconciliation tranchera par relecture.
            throw JoleneError(.unknown, AvatarProfil.Textes.echecEnvoi)
        }
        // Lié et relu : un reçu impossible à effacer n'annule pas le succès (la réconciliation suivante le confirmera).
        try? await recus.effacer(userId: depose.userId)
        return url
    }

    /// Écrit puis relit le reçu : un reçu qui ne se relit pas à l'identique bloque l'envoi (fail-closed).
    private func journaliser(_ recu: RecuAvatar) async throws {
        do {
            let precedent = try await recus.lire(userId: recu.userId)
            if let precedent, precedent.attemptId != recu.attemptId, !precedent.estTermine {
                throw RecuAvatar.Erreur.recuEnCours
            }
            try recu.verifierSuccession(apres: precedent?.attemptId == recu.attemptId ? precedent : nil)
            try await recus.ecrire(recu)
            guard try await recus.lire(userId: recu.userId) == recu else { throw RecuAvatar.Erreur.illisible }
        } catch {
            throw RefusAvatar(AvatarProfil.Textes.echecEnvoi)
        }
    }

    private func clore(_ recu: RecuAvatar, _ phase: RecuAvatar.Phase) async throws {
        try await journaliser(recu.vers(phase))
        try await effacer(recu)
    }

    private func effacer(_ recu: RecuAvatar) async throws {
        try await effacer(userId: recu.userId)
    }

    /// Effacement BRUT par clé (`avatar.<userId>`), lisible ou non : seule voie de reprise d'un reçu illisible. Point de
    /// fusion : servi par `ReceiptStorePort.effacer(CleRecu)` du lot 2, jamais par `ReceiptJournal.effacer`, qui exige
    /// un reçu lisible.
    private func effacer(userId: String) async throws {
        do { try await recus.effacer(userId: userId) } catch { throw RefusAvatar(AvatarProfil.Textes.echecEnvoi) }
    }
}
