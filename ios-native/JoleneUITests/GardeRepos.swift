import Foundation
import ObjectiveC
import XCTest

/// Garde de repos XCUITest (`docs/mobile-swift/DECISIONS_LOT2.md`, « Garde de repos XCUITest — 26/11/2026 »). Cible de
/// tests d'interface uniquement : rien de ce fichier n'entre dans le binaire livré.
///
/// Déclencheur établi, cause non établie : sur iPad (iOS 26.2, Xcode 26.4.1), environ 4 touchers « OK » du clavier sur 80
/// laissent la partie d'XCTest logée dans l'app sans jamais répondre à « animations idle » (journal du simulateur du job
/// 138917774902 : demande de 02:31:04.774 restée sans réponse jusqu'à la fin du test). Chaque geste suivant attend 60 s
/// de plus (« App animations complete notification not received »), jusqu'à la fin du processus de l'app ; aucune
/// assertion n'échoue, le test dépasse ses 10 minutes.
///
/// Mesure : la méthode où le spindump du lanceur montre son fil principal,
/// `-[XCUIApplicationProcess waitForQuiescenceIncludingAnimationsIdle:usingActivity:isPreEvent:]` (et sa variante à deux
/// arguments), est enveloppée. L'original est appelé tel quel et chronométré. Une attente avec animations d'au moins 50 s
/// est suivie d'une attente de la seule boucle principale : si celle-ci est rapide, l'expiration vient des animations ;
/// pour CE processus d'app seulement, les appels suivants passent `includingAnimationsIdle = false` (l'attente du repos de
/// la boucle principale reste), et une ligne « Jolene diagnostic repos-xcuitest » est écrite au journal de l'éclat. Une
/// boucle principale lente ne change rien (une app occupée n'est jamais masquée). Chaque test repart à zéro.
///
/// Limite : API privée d'XCTest, Xcode épinglé (26.4.1). Seules les signatures relevées sont enveloppées, encodage de types
/// vérifié (`GardeReposDecision.forme`) ; sinon rien n'est posé, une ligne « garde de repos non installée » est écrite, et
/// les tests se comportent exactement comme avant. Aucune assertion n'est affaiblie, aucun test n'est rejoué.
enum GardeRepos {
    enum Installation: Equatable {
        case installee([String])
        case nonInstallee([String])
    }

    struct Expiration: Equatable {
        let test: String
        let duree: TimeInterval
    }

    private static let verrou = NSLock()
    nonisolated(unsafe) private static var etat = GardeReposDecision()
    nonisolated(unsafe) private static var profondeur = 0
    nonisolated(unsafe) private static var testCourant = "?"
    nonisolated(unsafe) private static var expirationsVues: [Expiration] = []
    nonisolated(unsafe) private static var installationFaite: Installation?
    nonisolated(unsafe) private static var installationJournalisee = false

    private static func sous<T>(_ action: () -> T) -> T {
        verrou.lock()
        defer { verrou.unlock() }
        return action()
    }

    /// État de la pose, lu par `DemoGardeReposTests`.
    static var installation: Installation? { sous { installationFaite } }

    /// Expirations relevées pendant le test nommé.
    static func expirations(pendant test: String) -> [Expiration] {
        sous { expirationsVues.filter { $0.test == test } }
    }

    /// Appelée par `JoleneUITestCase.setUpWithError` : pose la garde une fois par processus du lanceur, journalise son
    /// état au premier test de l'éclat, puis oublie les processus d'app suspendus (nouveau test, nouveau lancement).
    static func debutDeTest(_ nom: String) {
        let (installation, aJournaliser) = sous { () -> (Installation, Bool) in
            if installationFaite == nil { installationFaite = poser() }
            etat.oublier()
            testCourant = nom
            defer { installationJournalisee = true }
            return (installationFaite ?? .nonInstallee([]), !installationJournalisee)
        }
        guard aJournaliser else { return }
        switch installation {
        case let .installee(selecteurs): journaliser(GardeReposDecision.ligneInstallee(selecteurs: selecteurs))
        case let .nonInstallee(vus): journaliser(GardeReposDecision.ligneNonInstallee(vus: vus))
        }
    }

    /// Activité XCTest (ligne « t = … s <ligne> » du journal de l'éclat). XCTest appelle la méthode enveloppée sur le fil
    /// principal du lanceur (spindump du job 139506151098) ; hors de ce fil, la ligne part sur la sortie standard.
    private static func journaliser(_ ligne: String) {
        guard Thread.isMainThread else {
            print(ligne)
            return
        }
        MainActor.assumeIsolated { XCTContext.runActivity(named: ligne) { _ in } }
    }

    // MARK: Pose

    /// Enveloppe chaque méthode connue de `XCUIApplicationProcess` ; appelée sous le verrou, une seule fois.
    private static func poser() -> Installation {
        guard let classe = NSClassFromString("XCUIApplicationProcess") else {
            return .nonInstallee(["classe XCUIApplicationProcess absente"])
        }
        var nombre: UInt32 = 0
        guard let methodes = class_copyMethodList(classe, &nombre) else { return .nonInstallee([]) }
        defer { free(methodes) }
        var vus: [String] = []
        var poses: [String] = []
        for index in 0..<Int(nombre) {
            let methode = methodes[index]
            let selecteur = NSStringFromSelector(method_getName(methode))
            guard selecteur.hasPrefix(GardeReposDecision.prefixeSelecteur) else { continue }
            let encodage = method_getTypeEncoding(methode).map { String(cString: $0) } ?? "?"
            vus.append("\(selecteur) \(encodage)")
            guard let forme = GardeReposDecision.forme(selecteur: selecteur, encodage: encodage) else { continue }
            envelopper(methode, forme: forme)
            poses.append("\(selecteur) \(encodage)")
        }
        return poses.isEmpty ? .nonInstallee(vus) : .installee(poses)
    }

    private static func envelopper(_ methode: Method, forme: GardeReposDecision.Forme) {
        let selecteur = method_getName(methode)
        let imp = method_getImplementation(methode)
        switch forme {
        case .deuxBooleens:
            typealias Original = @convention(c) (AnyObject, Selector, Bool, Bool) -> Void
            let original = unsafeBitCast(imp, to: Original.self)
            let bloc: @convention(block) (AnyObject, Bool, Bool) -> Void = { objet, animations, avantGeste in
                attendre(objet, animations: animations) { original(objet, selecteur, $0, avantGeste) }
            }
            method_setImplementation(methode, imp_implementationWithBlock(unsafeBitCast(bloc, to: AnyObject.self)))
        case .troisBooleens:
            typealias Original = @convention(c) (AnyObject, Selector, Bool, Bool, Bool) -> Void
            let original = unsafeBitCast(imp, to: Original.self)
            let bloc: @convention(block) (AnyObject, Bool, Bool, Bool) -> Void = { objet, animations, activite, avantGeste in
                attendre(objet, animations: animations) { original(objet, selecteur, $0, activite, avantGeste) }
            }
            method_setImplementation(methode, imp_implementationWithBlock(unsafeBitCast(bloc, to: AnyObject.self)))
        case .activiteObjet:
            typealias Original = @convention(c) (AnyObject, Selector, Bool, AnyObject?, Bool) -> Void
            let original = unsafeBitCast(imp, to: Original.self)
            let bloc: @convention(block) (AnyObject, Bool, AnyObject?, Bool) -> Void = { objet, animations, activite, avantGeste in
                attendre(objet, animations: animations) { original(objet, selecteur, $0, activite, avantGeste) }
            }
            method_setImplementation(methode, imp_implementationWithBlock(unsafeBitCast(bloc, to: AnyObject.self)))
        }
    }

    // MARK: Attente

    /// Appel enveloppé. Un appel imbriqué (variante à deux arguments qui appelle celle à trois) passe tel quel : seul
    /// l'appel extérieur mesure et décide.
    private static func attendre(_ objet: AnyObject, animations demande: Bool, original: (Bool) -> Void) {
        let exterieur = sous { () -> Bool in
            profondeur += 1
            return profondeur == 1
        }
        defer { sous { profondeur -= 1 } }
        guard exterieur else {
            original(demande)
            return
        }
        let processus = identifiant(objet)
        let avecAnimations = sous { etat.avecAnimations(processus: processus, demande: demande) }
        let debut = ProcessInfo.processInfo.systemUptime
        original(avecAnimations)
        let duree = ProcessInfo.processInfo.systemUptime - debut
        guard sous({ etat.aVerifier(processus: processus, avecAnimations: avecAnimations, duree: duree) }) else { return }
        // Attente expirée : la boucle principale seule est-elle au repos ? (Sinon l'app est occupée : rien ne change.)
        let debutBoucle = ProcessInfo.processInfo.systemUptime
        original(false)
        let dureeBoucle = ProcessInfo.processInfo.systemUptime - debutBoucle
        let ligne = sous { () -> String? in
            guard etat.apresVerification(processus: processus, dureeAttente: duree, dureeBoucleSeule: dureeBoucle) else { return nil }
            expirationsVues.append(Expiration(test: testCourant, duree: duree))
            return GardeReposDecision.ligneExpiration(duree: duree, test: testCourant)
        }
        if let ligne { journaliser(ligne) }
    }

    /// Identifiant du processus d'app : `processID` (relevé sur Xcode 16.4, encodage `i16@0:8`) s'il est lisible et
    /// valide, sinon l'identité de l'objet (négative, pour ne jamais rencontrer un pid).
    private static func identifiant(_ objet: AnyObject) -> Int64 {
        let selecteur = NSSelectorFromString("processID")
        if let methode = class_getInstanceMethod(type(of: objet), selecteur),
           let encodage = method_getTypeEncoding(methode).map({ String(cString: $0) }),
           encodage.filter({ !$0.isNumber }) == "i@:" {
            typealias Lecture = @convention(c) (AnyObject, Selector) -> Int32
            let pid = unsafeBitCast(method_getImplementation(methode), to: Lecture.self)(objet, selecteur)
            if pid > 0 { return Int64(pid) }
        }
        return -Int64(UInt32(truncatingIfNeeded: ObjectIdentifier(objet).hashValue)) - 1
    }
}
