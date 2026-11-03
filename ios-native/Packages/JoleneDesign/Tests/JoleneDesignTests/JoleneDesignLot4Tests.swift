import XCTest
import SwiftUI
import UIKit
import CoreImage
import JoleneCore
@testable import JoleneDesign

/// Lot 4 (T1b) : règles pures des dix composants du lot 4 (paquet de swipe, bulles et composeur de la
/// messagerie, indicateur de saisie, grille des disponibilités, étoiles, pastille de statut, QR code, score
/// de matching, carte de renvoi web). Chaque composant expose la partie calculable (seuils, libellés,
/// identifiants, encres) pour qu'elle soit vérifiée sans XCUITest ; les textes repris du web sont relus dans
/// les fichiers sources du dépôt (garde « verbatim », HARD STOP n°4). Les vecteurs JavaScript (`toFixed`,
/// `Math.round`, `String.prototype.trim`, `length` UTF-16) ont été produits par Node 24.14.0 (moteur du web),
/// jamais ajustés au port. Les derniers cas évaluent chaque vue dans un `UIHostingController` : cibles de
/// 44 pt mesurées sur le contrôle lui-même, bascule de disposition et retour à la ligne aux tailles Dynamic
/// Type XXL (`xxLarge`, `xxxLarge`) et d'accessibilité. Le parcours visible reste couvert par les XCUITest
/// démo des tranches qui montent ces composants (T3b à T12).
final class JoleneDesignLot4Tests: XCTestCase {
    // MARK: - Outils

    private static func contrastes(_ encre: JoleneDynamicHSL, sur fond: JoleneDynamicHSL) -> (clair: Double, sombre: Double) {
        (encre.light.rgb.contrastRatio(with: fond.light.rgb), encre.dark.rgb.contrastRatio(with: fond.dark.rgb))
    }

    private static let encreSurDegrade = JoleneHex.parse(JoleneColor.onGradientHex)!

    /// Texte d'un fichier du dépôt (racine = 6 niveaux au-dessus de ce fichier, motif de `JoleneDesignLot1Tests`).
    private static func sourceWeb(_ chemin: String) throws -> String {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8)
    }

    @MainActor
    private static func taille<V: View>(_ vue: V, largeur: CGFloat = 390, taille: DynamicTypeSize = .large) -> CGSize {
        UIHostingController(rootView: vue.environment(\.dynamicTypeSize, taille))
            .sizeThatFits(in: CGSize(width: largeur, height: 4000))
    }

    // MARK: - Jetons ajoutés (garde de dérive du lot 1)

    func testLesJetonsDuLot4ReprennentSrcIndexCss() throws {
        let variables = try JoleneDesignLot1Tests.variablesJoleneDeIndexCss()
        for (nom, jeton) in [("jolene-rose-200", JoleneColor.rose200HSL), ("jolene-butter-400", JoleneColor.butter400HSL)] {
            let css = try XCTUnwrap(variables[nom], "--\(nom) absent de src/index.css")
            XCTAssertEqual(jeton.light, css.light, "--\(nom) (:root)")
            XCTAssertEqual(jeton.dark, css.dark, "--\(nom) (.dark)")
        }
        // `.bg-gradient-celebrate` : conique rose → mauve → cyan → butter → rose, encre #2b183d (src/index.css).
        XCTAssertEqual(JoleneColor.celebrateGradientStops,
                       [JoleneColor.roseHSL, JoleneColor.mauveHSL, JoleneColor.cyanHSL, JoleneColor.butterHSL, JoleneColor.roseHSL])
        let css = try Self.sourceWeb("src/index.css")
        let bloc = try XCTUnwrap(css.range(of: ".bg-gradient-celebrate {").map { String(css[$0.lowerBound...].prefix(260)) })
        XCTAssertTrue(bloc.contains("color: #2b183d;"))
        for variable in ["--jolene-rose", "--jolene-mauve", "--jolene-cyan", "--jolene-butter"] {
            XCTAssertTrue(bloc.contains("hsl(var(\(variable)))"), "\(variable) dans .bg-gradient-celebrate")
        }
        for arret in JoleneColor.celebrateGradientStops {
            XCTAssertGreaterThanOrEqual(Self.encreSurDegrade.contrastRatio(with: arret.light.rgb), 4.5, "\(arret.light)")
            XCTAssertGreaterThanOrEqual(Self.encreSurDegrade.contrastRatio(with: arret.dark.rgb), 4.5, "\(arret.dark)")
        }
    }

    // MARK: - SwipeCardStack / SwipeActionBar

    func testSwipeActionsReprennentLesBoutonsDuWebEtLesActionsDuBlueprint() throws {
        // BoutonsActionSwipe.tsx : ✕ DISLIKE, ⭐ FAVORI, ❤️ LIKE, dans cet ordre ; h-14 / h-14 / h-16 (56, 56, 64 pt).
        XCTAssertEqual(SwipeCardAction.allCases, [.passer, .sauvegarder, .candidater])
        XCTAssertEqual(SwipeCardAction.allCases.map(\.accessibilityActionName), ["Passer", "Sauvegarder", "Candidater"],
                       "Actions d'accessibilité du blueprint lot 4 T1b")
        XCTAssertEqual(SwipeCardAction.passer.buttonAccessibilityLabel, "Passer cette mission")
        XCTAssertEqual(SwipeCardAction.sauvegarder.buttonAccessibilityLabel, "Sauvegarder cette mission pour y revenir")
        XCTAssertEqual(SwipeCardAction.candidater.buttonAccessibilityLabel, "Vérifier le planning avant de postuler à cette mission")
        let web = try Self.sourceWeb("src/components/swipe/BoutonsActionSwipe.tsx")
        for action in SwipeCardAction.allCases {
            XCTAssertTrue(web.contains("aria-label=\"\(action.buttonAccessibilityLabel)\""), "verbatim : \(action)")
            XCTAssertGreaterThanOrEqual(action.buttonDiameter, 44)
        }
        XCTAssertEqual(SwipeCardAction.allCases.map(\.buttonDiameter), [56, 56, 64])
        XCTAssertTrue(web.contains("h-14 w-14") && web.contains("h-16 w-16"))
        XCTAssertEqual(SwipeCardAction.allCases.map(\.systemImage), ["xmark", "star.fill", "heart.fill"])
        XCTAssertEqual(SwipeCardAction.allCases.map { $0.identifier(prefix: "swipe") },
                       ["swipe-passer", "swipe-sauvegarder", "swipe-candidater"])
    }

    func testSwipeGesteValideA120PointsEtIgnoreUnDepartVertical() {
        XCTAssertEqual(SwipeCardGesture.threshold, 120)
        XCTAssertEqual(SwipeCardGesture.activationDistance, 8, "StackCards.tsx : drag établi au-delà de 8 px")
        XCTAssertNil(SwipeCardGesture.decision(forHorizontalTranslation: 0))
        XCTAssertNil(SwipeCardGesture.decision(forHorizontalTranslation: 119.9))
        XCTAssertNil(SwipeCardGesture.decision(forHorizontalTranslation: -119.9))
        XCTAssertEqual(SwipeCardGesture.decision(forHorizontalTranslation: 120), .candidater, "Droite = « VÉRIFIER »")
        XCTAssertEqual(SwipeCardGesture.decision(forHorizontalTranslation: 400), .candidater)
        XCTAssertEqual(SwipeCardGesture.decision(forHorizontalTranslation: -120), .passer, "Gauche = « SUIVANT »")
        XCTAssertEqual(SwipeCardGesture.decision(forHorizontalTranslation: -400), .passer)
        // Axe décidé une fois au-delà de 8 pt ; à égalité ou vertical dominant, le paquet n'intercepte pas.
        XCTAssertEqual(SwipeCardGesture.axis(for: CGSize(width: 5, height: 0)), .undetermined)
        XCTAssertEqual(SwipeCardGesture.axis(for: CGSize(width: 7.9, height: 7.9)), .undetermined)
        XCTAssertEqual(SwipeCardGesture.axis(for: CGSize(width: 8, height: 0)), .horizontal)
        XCTAssertEqual(SwipeCardGesture.axis(for: CGSize(width: -20, height: 5)), .horizontal)
        XCTAssertEqual(SwipeCardGesture.axis(for: CGSize(width: 8, height: 8)), .vertical)
        XCTAssertEqual(SwipeCardGesture.axis(for: CGSize(width: 3, height: -10)), .vertical)
    }

    func testSwipeRotationIndicateursEtCartesDeFondSuiventStackCards() throws {
        // StackCards.tsx : rotation `dragX / 14` bornée à ±15°, opacité des indicateurs `dragX / 80` bornée.
        XCTAssertEqual(SwipeCardGesture.rotationDegrees(for: 0), 0)
        XCTAssertEqual(SwipeCardGesture.rotationDegrees(for: 14), 1, accuracy: 1e-9)
        XCTAssertEqual(SwipeCardGesture.rotationDegrees(for: -70), -5, accuracy: 1e-9)
        XCTAssertEqual(SwipeCardGesture.rotationDegrees(for: 300), 15)
        XCTAssertEqual(SwipeCardGesture.rotationDegrees(for: -300), -15)
        XCTAssertEqual(SwipeCardGesture.indicatorOpacity(for: 40, toward: .candidater), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SwipeCardGesture.indicatorOpacity(for: 40, toward: .passer), 0)
        XCTAssertEqual(SwipeCardGesture.indicatorOpacity(for: -80, toward: .passer), 1)
        XCTAssertEqual(SwipeCardGesture.indicatorOpacity(for: -200, toward: .passer), 1)
        XCTAssertEqual(SwipeCardGesture.indicatorOpacity(for: 200, toward: .sauvegarder), 0, "Aucun geste pour le favori")
        // Deux cartes de fond : échelle 1 − 0,04 × rang, décalage 8 pt × rang, opacité 1 − 0,2 × rang.
        XCTAssertEqual(SwipeCardGesture.visibleBackgroundCards, 2)
        let premiere = SwipeCardGesture.backgroundStyle(depth: 1), seconde = SwipeCardGesture.backgroundStyle(depth: 2)
        XCTAssertEqual(premiere.scale, 0.96, accuracy: 1e-9)
        XCTAssertEqual(premiere.offsetY, 8)
        XCTAssertEqual(premiere.opacity, 0.8, accuracy: 1e-9)
        XCTAssertEqual(seconde.scale, 0.92, accuracy: 1e-9)
        XCTAssertEqual(seconde.offsetY, 16)
        XCTAssertEqual(seconde.opacity, 0.6, accuracy: 1e-9)
        // Réduire les animations : aucun mouvement animé (retour au centre, retrait de carte).
        XCTAssertNil(SwipeCardGesture.animation(reduceMotion: true))
        XCTAssertNotNil(SwipeCardGesture.animation(reduceMotion: false))
        XCTAssertEqual(SwipeCardGesture.cardIdentifier(prefix: "swipe", itemID: "demo-swipe-1"), "swipe-carte-demo-swipe-1")
        // Indicateurs verbatim, décoratifs (aria-hidden) ; encres AA même en grand texte.
        let web = try Self.sourceWeb("src/components/swipe/StackCards.tsx")
        let droite = try XCTUnwrap(SwipeCardGesture.indicator(for: .candidater))
        let gauche = try XCTUnwrap(SwipeCardGesture.indicator(for: .passer))
        XCTAssertNil(SwipeCardGesture.indicator(for: .sauvegarder))
        XCTAssertEqual(droite.text, "VÉRIFIER")
        XCTAssertEqual(gauche.text, "SUIVANT")
        XCTAssertTrue(web.contains(droite.text) && web.contains(gauche.text))
        XCTAssertTrue(web.contains("Math.max(-15, Math.min(15, dragX / 14))"))
        XCTAssertTrue(web.contains("dragX / 80"))
        for indicateur in [droite, gauche] {
            let c = Self.contrastes(indicateur.inkHSL, sur: indicateur.backgroundHSL)
            XCTAssertGreaterThanOrEqual(c.clair, 4.5, indicateur.text)
            XCTAssertGreaterThanOrEqual(c.sombre, 4.5, indicateur.text)
        }
    }

    func testSwipeIconesDesBoutonsContrastentSurLeurFond() {
        // Icône = information (bouton sans texte) : ≥ 3:1 (WCAG 1.4.11), vérifié aussi à 4,5:1 quand c'est possible.
        let passer = Self.contrastes(JoleneColor.bubblegumHSL, sur: JoleneColor.cloudHSL)
        XCTAssertEqual(SwipeCardAction.passer.iconInkHSL, JoleneColor.bubblegumHSL)
        XCTAssertGreaterThanOrEqual(passer.clair, 4.5)
        XCTAssertGreaterThanOrEqual(passer.sombre, 4.5)
        XCTAssertEqual(SwipeCardAction.sauvegarder.iconInkHSL, JoleneColor.butter800HSL, "Contour de l'étoile (text-jolene-butter-800)")
        let etoile = Self.contrastes(JoleneColor.butter800HSL, sur: JoleneColor.cloudHSL)
        XCTAssertGreaterThanOrEqual(etoile.clair, 3)
        XCTAssertGreaterThanOrEqual(etoile.sombre, 3)
        XCTAssertNil(SwipeCardAction.candidater.iconInkHSL, "Cœur : encre #2B183D du dégradé hero")
        for arret in JoleneColor.heroGradientFullStops {
            XCTAssertGreaterThanOrEqual(Self.encreSurDegrade.contrastRatio(with: arret.light.rgb), 4.5)
            XCTAssertGreaterThanOrEqual(Self.encreSurDegrade.contrastRatio(with: arret.dark.rgb), 4.5)
        }
    }

    @MainActor
    func testSwipeBoutonsMesurentLeurDiametreEtAuMoins44Points() {
        for action in SwipeCardAction.allCases {
            for taille in [DynamicTypeSize.large, .xxxLarge, .accessibility5] {
                let mesure = Self.taille(SwipeActionButton(action: action, prefix: "swipe", isDisabled: false) {}, taille: taille)
                XCTAssertEqual(mesure.width, action.buttonDiameter, accuracy: 0.5, "\(action) à \(taille)")
                XCTAssertEqual(mesure.height, action.buttonDiameter, accuracy: 0.5, "\(action) à \(taille)")
                XCTAssertGreaterThanOrEqual(min(mesure.width, mesure.height), 44)
            }
        }
    }

    @MainActor
    func testSwipeCardStackTransmetUneSeuleActionEtAucunePendantUnAppel() {
        // Une carte n'est retirée qu'après `ok:true` (blueprint §2.5) : le paquet transmet l'action et ne retire rien
        // lui-même ; pendant l'appel serveur (`isBusy`), gestes, boutons et actions d'accessibilité sont inertes.
        var recu: [String] = []
        let cartes = [CarteTest(id: "m1"), CarteTest(id: "m2")]
        let libre = SwipeCardStack(cartes, onAction: { action, carte in recu.append("\(action.rawValue):\(carte.id)") }) { Text($0.id) }
        libre.perform(.passer, on: cartes[0])
        libre.perform(.candidater, on: cartes[0])
        XCTAssertEqual(recu, ["passer:m1", "candidater:m1"])
        let occupe = SwipeCardStack(cartes, isBusy: true, onAction: { action, _ in recu.append(action.rawValue) }) { Text($0.id) }
        occupe.perform(.sauvegarder, on: cartes[0])
        XCTAssertEqual(recu.count, 2, "isBusy : aucune action transmise")
    }

    // MARK: - ChatBubble

    func testChatBubblePlaceChaqueAuteurCommeLeWeb() throws {
        // PageMessagerie.tsx l.751-773 : « moi » à droite sur `bg-gradient-hero` (coin bas-droit réduit),
        // interlocuteur à gauche sur `bg-card` bordé, admin Jolene à gauche avec « Admin Jolene », message système centré.
        XCTAssertEqual(ChatBubble.Kind.allCases, [.moi, .interlocuteur, .jolene, .systeme])
        XCTAssertEqual(ChatBubble.Kind.moi.frameAlignment, .trailing)
        XCTAssertEqual(ChatBubble.Kind.interlocuteur.frameAlignment, .leading)
        XCTAssertEqual(ChatBubble.Kind.jolene.frameAlignment, .leading)
        XCTAssertEqual(ChatBubble.Kind.systeme.frameAlignment, .center)
        XCTAssertTrue(ChatBubble.Kind.moi.usesGradient)
        XCTAssertEqual(ChatBubble.Kind.allCases.filter(\.usesGradient), [.moi])
        XCTAssertEqual(ChatBubble.jolenePrefix, "Admin Jolene")
        let web = try Self.sourceWeb("src/pages/PageMessagerie.tsx")
        XCTAssertTrue(web.contains("<Shield className=\"h-3 w-3\" /> Admin Jolene"))
        XCTAssertTrue(web.contains("max-w-[80%]"))
        XCTAssertTrue(web.contains("whitespace-pre-wrap break-words"), "Contenu jamais tronqué")
        XCTAssertNil(ChatBubble.contentLineLimit)
        XCTAssertEqual(ChatBubble.nonConfirmeText, "Envoi non confirmé", "DECISIONS_LOT4 D8")
    }

    func testChatBubbleVocaliseAuteurContenuHeureEtEnvoiNonConfirme() {
        XCTAssertEqual(ChatBubble.accessibilityLabel(contenu: "Bonjour", kind: .moi, auteur: nil, heure: "14:32", delivery: .confirme),
                       "Vous : Bonjour, 14:32")
        XCTAssertEqual(ChatBubble.accessibilityLabel(contenu: "Bonjour", kind: .interlocuteur, auteur: "Clinique Démo", heure: "09:05",
                                                     delivery: .confirme),
                       "Clinique Démo : Bonjour, 09:05")
        XCTAssertEqual(ChatBubble.accessibilityLabel(contenu: "Bonjour", kind: .interlocuteur, auteur: nil, heure: nil, delivery: .confirme),
                       "Bonjour")
        XCTAssertEqual(ChatBubble.accessibilityLabel(contenu: "Bonjour", kind: .jolene, auteur: "Camille", heure: "10:00", delivery: .confirme),
                       "Admin Jolene : Bonjour, 10:00", "L'admin est annoncé « Admin Jolene », comme le web")
        XCTAssertEqual(ChatBubble.accessibilityLabel(contenu: "Conversation ouverte", kind: .systeme, auteur: nil, heure: "10:00",
                                                     delivery: .confirme),
                       "Conversation ouverte", "Message système : contenu seul, sans heure (web)")
        XCTAssertEqual(ChatBubble.accessibilityLabel(contenu: "Bonjour", kind: .moi, auteur: nil, heure: "14:32", delivery: .nonConfirme),
                       "Vous : Bonjour, 14:32. Envoi non confirmé")
    }

    func testChatBubbleEncresAAPourChaqueAuteur() {
        // « moi » : encre #2B183D sur chaque arrêt du dégradé hero complet ; autres : midnight sur cloud.
        XCTAssertNil(ChatBubble.Kind.moi.textInkHSL)
        XCTAssertNil(ChatBubble.Kind.moi.backgroundHSL)
        for arret in JoleneColor.heroGradientFullStops {
            XCTAssertGreaterThanOrEqual(Self.encreSurDegrade.contrastRatio(with: arret.light.rgb), 4.5)
            XCTAssertGreaterThanOrEqual(Self.encreSurDegrade.contrastRatio(with: arret.dark.rgb), 4.5)
        }
        for kind in [ChatBubble.Kind.interlocuteur, .jolene, .systeme] {
            guard let encre = kind.textInkHSL, let fond = kind.backgroundHSL else {
                XCTFail("\(kind) : encre et fond attendus")
                continue
            }
            let texte = Self.contrastes(encre, sur: fond)
            XCTAssertGreaterThanOrEqual(texte.clair, 4.5, "\(kind) clair")
            XCTAssertGreaterThanOrEqual(texte.sombre, 4.5, "\(kind) sombre")
            if let meta = kind.metaInkHSL {
                let heure = Self.contrastes(meta, sur: fond)
                XCTAssertGreaterThanOrEqual(heure.clair, 4.5, "\(kind) heure clair")
                XCTAssertGreaterThanOrEqual(heure.sombre, 4.5, "\(kind) heure sombre")
            }
        }
        // En-tête « Admin Jolene » (text-jolene-rose-700) sur la bulle `cloud` : 4,62:1 en clair.
        let entete = Self.contrastes(ChatBubble.jolenePrefixInkHSL, sur: JoleneColor.cloudHSL)
        XCTAssertGreaterThanOrEqual(entete.clair, 4.5)
        XCTAssertGreaterThanOrEqual(entete.sombre, 4.5)
        // « Envoi non confirmé » est posé sous la bulle, sans fond propre : AA sur toutes les surfaces héritées.
        for surface in JoleneColor.inheritedSurfacesHSL {
            let c = Self.contrastes(ChatBubble.nonConfirmeInkHSL, sur: surface)
            XCTAssertGreaterThanOrEqual(c.clair, 4.5, "\(surface.light)")
            XCTAssertGreaterThanOrEqual(c.sombre, 4.5, "\(surface.dark)")
        }
        for fond in EcartsSombresLot0.fondsWeb {
            XCTAssertGreaterThanOrEqual(ChatBubble.nonConfirmeInkHSL.dark.rgb.contrastRatio(with: fond.rgb), 4.5)
        }
    }

    @MainActor
    func testChatBubbleRetourneALaLigneSansTronquer() {
        let court = Self.taille(ChatBubble("Bonjour", kind: .interlocuteur, heure: "09:05"), largeur: 320, taille: .xxxLarge)
        let long = Self.taille(ChatBubble(String(repeating: "Mission de nuit confirmée ", count: 12), kind: .interlocuteur,
                                          heure: "09:05"), largeur: 320, taille: .xxxLarge)
        XCTAssertGreaterThan(long.height, court.height * 2, "Le contenu passe à la ligne, jamais « … »")
        XCTAssertLessThanOrEqual(long.width, 320)
    }

    // MARK: - MessageComposer

    func testMessageComposerReprendLesTextesEtLimitesDInputMessage() throws {
        let web = try Self.sourceWeb("src/components/messagerie/InputMessage.tsx")
        XCTAssertEqual(MessageComposer.maxLength, 4000)
        XCTAssertEqual(MessageComposer.warnThreshold, 3500)
        XCTAssertEqual(MessageComposer.urgentBelow, 100)
        XCTAssertTrue(web.contains("const MAX_LENGTH = 4000;"))
        XCTAssertTrue(web.contains("const WARN_THRESHOLD = 3500;"))
        XCTAssertTrue(web.contains("restantes < 100 ? 'text-destructive'"))
        XCTAssertEqual(MessageComposer.placeholder, "Votre message…")
        XCTAssertEqual(MessageComposer.fieldAccessibilityLabel, "Saisir un message")
        XCTAssertEqual(MessageComposer.sendAccessibilityLabel, "Envoyer le message")
        XCTAssertEqual(MessageComposer.archivedText, "Conversation archivée — lecture seule.")
        for texte in ["placeholder=\"\(MessageComposer.placeholder)\"", "aria-label=\"\(MessageComposer.fieldAccessibilityLabel)\"",
                      "aria-label=\"\(MessageComposer.sendAccessibilityLabel)\"", MessageComposer.archivedText,
                      "{restantes} caractères restants"] {
            XCTAssertTrue(web.contains(texte), "verbatim : \(texte)")
        }
        let ids = MessageComposer.Identifiers("messagerie-composeur")
        XCTAssertEqual(ids.field, "messagerie-composeur-champ")
        XCTAssertEqual(ids.send, "messagerie-composeur-envoyer")
        XCTAssertEqual(ids.counter, "messagerie-composeur-compteur")
        XCTAssertEqual(ids.archived, "messagerie-composeur-archivee")
        XCTAssertEqual(MessageComposer.minimumTapTarget, 44)
    }

    func testMessageComposerCompteEnUnitesUTF16CommeJavaScript() {
        // Node 24.14.0 : `'é'.length` 1, `'é'.length` 2, `'👩‍⚕️'.length` 5, `'🇫🇷'.length` 4, `'😀'.length` 2.
        let vecteurs: [(String, Int)] = [("é", 1), ("e\u{0301}", 2), ("👩‍⚕️", 5), ("🇫🇷", 4), ("a", 1), ("😀", 2), ("\u{00A0}", 1), ("", 0)]
        for (texte, attendu) in vecteurs {
            XCTAssertEqual(MessageComposer.length(texte), attendu, texte.debugDescription)
        }
        XCTAssertEqual(MessageComposer.limited(String(repeating: "a", count: 4001)), String(repeating: "a", count: 4000))
        XCTAssertEqual(MessageComposer.limited("abc"), "abc")
        // Écart assumé : `slice(0, 4000)` du web garde une demi-paire de substitution (U+D83D) ; le natif retire le
        // caractère entier, jamais coupé.
        let coupe = String(repeating: "a", count: 3999) + "😀"
        XCTAssertEqual(MessageComposer.limited(coupe), String(repeating: "a", count: 3999))
        XCTAssertEqual(MessageComposer.length(MessageComposer.limited(coupe)), 3999)
        XCTAssertEqual(MessageComposer.limited(String(repeating: "😀", count: 2001)), String(repeating: "😀", count: 2000))
    }

    func testMessageComposerRogneCommeStringTrimDuWeb() {
        // Node 24.14.0, `texte.trim()` : espaces Unicode Zs, BOM, U+2028/2029 retirés ; U+200B, U+180E, U+0085 conservés.
        let vecteurs: [(String, String)] = [
            ("  bonjour  ", "bonjour"), ("\u{00A0}x\u{00A0}", "x"), ("\u{FEFF}x", "x"), ("\u{2028}x\u{2029}", "x"),
            ("\u{200B}x", "\u{200B}x"), ("\u{3000}x", "x"), ("\u{180E}x", "\u{180E}x"), ("\u{0085}x", "\u{0085}x"),
            ("\tx\n\r", "x"), ("\u{000B}x\u{000C}", "x"), ("\u{2007}x\u{202F}", "x"), ("   ", ""), ("", ""),
            (" \u{0301}a", "\u{0301}a"), ("a\n\nb", "a\n\nb"),
        ]
        for (texte, attendu) in vecteurs {
            XCTAssertEqual(MessageComposer.trimmed(texte).unicodeScalars.map(\.value), attendu.unicodeScalars.map(\.value),
                           texte.debugDescription)
        }
    }

    func testMessageComposerCompteurEtEnvoiSuiventLeWeb() {
        // `texte.length >= WARN_THRESHOLD` affiche « {restantes} caractères restants » (sans accord, verbatim) ;
        // `restantes < 100` passe en encre d'alerte.
        XCTAssertNil(MessageComposer.counterText(for: String(repeating: "a", count: 3499)))
        XCTAssertEqual(MessageComposer.counterText(for: String(repeating: "a", count: 3500)), "500 caractères restants")
        XCTAssertFalse(MessageComposer.isCounterUrgent(for: String(repeating: "a", count: 3500)))
        XCTAssertEqual(MessageComposer.counterText(for: String(repeating: "a", count: 3900)), "100 caractères restants")
        XCTAssertFalse(MessageComposer.isCounterUrgent(for: String(repeating: "a", count: 3900)))
        XCTAssertEqual(MessageComposer.counterText(for: String(repeating: "a", count: 3901)), "99 caractères restants")
        XCTAssertTrue(MessageComposer.isCounterUrgent(for: String(repeating: "a", count: 3901)))
        XCTAssertEqual(MessageComposer.counterText(for: String(repeating: "a", count: 3999)), "1 caractères restants")
        XCTAssertEqual(MessageComposer.counterText(for: String(repeating: "a", count: 4000)), "0 caractères restants")
        XCTAssertEqual(MessageComposer.counterText(for: String(repeating: "😀", count: 1750)), "500 caractères restants",
                       "Seuil en unités UTF-16, comme `texte.length`")
        XCTAssertEqual(MessageComposer.remaining(String(repeating: "a", count: 10)), 3990)
        // `disabled={envoi || !texte.trim()}` et retour anticipé si archivée.
        XCTAssertTrue(MessageComposer.canSend(text: "Bonjour", isSending: false, isArchived: false))
        XCTAssertFalse(MessageComposer.canSend(text: "  \n ", isSending: false, isArchived: false))
        XCTAssertFalse(MessageComposer.canSend(text: "Bonjour", isSending: true, isArchived: false), "Verrou pendant l'envoi")
        XCTAssertFalse(MessageComposer.canSend(text: "Bonjour", isSending: false, isArchived: true))
        XCTAssertTrue(MessageComposer.canSend(text: "\u{200B}", isSending: false, isArchived: false), "U+200B survit au trim JS")
        // Encres : compteur bubblegum, alerte rose-800, mention d'archive bubblegum ; AA sur la barre (cloud) et l'écran.
        for (encre, nom) in [(MessageComposer.counterInkHSL(urgent: false), "compteur"), (MessageComposer.counterInkHSL(urgent: true), "alerte"),
                             (MessageComposer.archivedInkHSL, "archive")] {
            for surface in [JoleneColor.cloudHSL, JoleneColor.lavenderHSL] {
                let c = Self.contrastes(encre, sur: surface)
                XCTAssertGreaterThanOrEqual(c.clair, 4.5, "\(nom) clair")
                XCTAssertGreaterThanOrEqual(c.sombre, 4.5, "\(nom) sombre")
            }
        }
        XCTAssertEqual(MessageComposer.counterInkHSL(urgent: true), JoleneColor.rose800HSL)
        XCTAssertNotEqual(MessageComposer.counterInkHSL(urgent: false), MessageComposer.counterInkHSL(urgent: true))
    }

    @MainActor
    func testMessageComposerBoutonDEnvoiMesureAuMoins44Points() {
        for taille in [DynamicTypeSize.large, .xxxLarge, .accessibility5] {
            for (actif, envoi) in [(true, false), (false, false), (false, true)] {
                let mesure = Self.taille(MessageComposer.SendButton(isEnabled: actif, isSending: envoi, identifier: "envoyer") {}, taille: taille)
                XCTAssertGreaterThanOrEqual(mesure.width, 44, "\(taille) actif=\(actif) envoi=\(envoi)")
                XCTAssertGreaterThanOrEqual(mesure.height, 44, "\(taille) actif=\(actif) envoi=\(envoi)")
            }
        }
    }

    // MARK: - TypingIndicator

    func testTypingIndicatorReprendLesLibellesEtCoupeLAnimation() throws {
        let web = try Self.sourceWeb("src/pages/PageMessagerie.tsx")
        XCTAssertEqual(TypingIndicator.accessibilityLabel, "L'interlocuteur écrit")
        XCTAssertEqual(TypingIndicator.statusText, "Est en train d'écrire…")
        XCTAssertTrue(web.contains("aria-label=\"\(TypingIndicator.accessibilityLabel)\""))
        XCTAssertTrue(web.contains("\"\(TypingIndicator.statusText)\""))
        // Trois points, délais 0 / 150 / 300 ms (`animate-bounce`), coupés par « Réduire les animations ».
        XCTAssertEqual(TypingIndicator.dotDelays, [0, 0.15, 0.3])
        for delai in ["'0ms'", "'150ms'", "'300ms'"] { XCTAssertTrue(web.contains("animationDelay: \(delai)")) }
        XCTAssertTrue(TypingIndicator.animates(reduceMotion: false))
        XCTAssertFalse(TypingIndicator.animates(reduceMotion: true))
        // Points = information graphique : ≥ 3:1 sur la bulle `cloud` (rose-400 du web : 2,15:1, écart assumé).
        let points = Self.contrastes(TypingIndicator.dotInkHSL, sur: JoleneColor.cloudHSL)
        XCTAssertGreaterThanOrEqual(points.clair, 3)
        XCTAssertGreaterThanOrEqual(points.sombre, 3)
        for fond in EcartsSombresLot0.fondsWeb {
            XCTAssertGreaterThanOrEqual(TypingIndicator.dotInkHSL.dark.rgb.contrastRatio(with: fond.rgb), 3)
        }
    }

    // MARK: - AvailabilityWeekGrid

    private static let lundi = AvailabilityWeekGrid.Day(id: "2026-11-02", label: "Lundi 2 Nov.", isToday: true, isPast: false,
                                                        journee: .init(isAvailable: true), nuit: .init())
    private static let dimanche = AvailabilityWeekGrid.Day(id: "2026-11-01", label: "Dimanche 1 Nov.", isToday: false, isPast: true,
                                                           journee: .init(), nuit: .init(isAvailable: true))

    func testAvailabilityWeekGridReprendLesCreneauxEtTextesDeMesDisponibilites() throws {
        let web = try Self.sourceWeb("src/pages/MesDisponibilites.tsx")
        XCTAssertEqual(AvailabilityWeekGrid.Creneau.allCases.map(\.rawValue), ["JOURNEE", "NUIT"])
        XCTAssertEqual(AvailabilityWeekGrid.Creneau.allCases.map(\.label), ["Jour", "Nuit"])
        XCTAssertTrue(web.contains("type Creneau = 'JOURNEE' | 'NUIT';"))
        XCTAssertTrue(web.contains("/>Jour") && web.contains("/>Nuit"))
        XCTAssertEqual(AvailabilityWeekGrid.todayText, "aujourd'hui")
        XCTAssertTrue(web.contains(">aujourd'hui</span>"))
        XCTAssertTrue(web.contains("opacity-40"))
        XCTAssertEqual(AvailabilityWeekGrid.pastOpacity, 0.4, accuracy: 1e-9)
        // Icône pleine quand le créneau est déclaré : l'état ne repose jamais sur la seule couleur.
        XCTAssertEqual(AvailabilityWeekGrid.Creneau.journee.systemImage(isSelected: false), "sun.max")
        XCTAssertEqual(AvailabilityWeekGrid.Creneau.journee.systemImage(isSelected: true), "sun.max.fill")
        XCTAssertEqual(AvailabilityWeekGrid.Creneau.nuit.systemImage(isSelected: false), "moon")
        XCTAssertEqual(AvailabilityWeekGrid.Creneau.nuit.systemImage(isSelected: true), "moon.fill")
        // Compteur : `${n} créneau${n > 1 ? 'x' : ''} déclaré${n > 1 ? 's' : ''}. ` (rien à zéro).
        XCTAssertTrue(web.contains("créneau${nbDispos > 1 ? 'x' : ''} déclaré${nbDispos > 1 ? 's' : ''}. "))
        XCTAssertNil(AvailabilityWeekGrid.resume(count: 0))
        XCTAssertEqual(AvailabilityWeekGrid.resume(count: 1), "1 créneau déclaré.")
        XCTAssertEqual(AvailabilityWeekGrid.resume(count: 3), "3 créneaux déclarés.")
    }

    func testAvailabilityWeekGridDesactiveLesJoursPassesEtLeCreneauEnCours() {
        // `disabled={passe}` et `if (enCours.has(cle)) return;` : seul le créneau en cours est bloqué, pas sa ligne.
        XCTAssertTrue(AvailabilityWeekGrid.isToggleEnabled(.init(), isPast: false))
        XCTAssertTrue(AvailabilityWeekGrid.isToggleEnabled(.init(isAvailable: true), isPast: false))
        XCTAssertFalse(AvailabilityWeekGrid.isToggleEnabled(.init(), isPast: true))
        XCTAssertFalse(AvailabilityWeekGrid.isToggleEnabled(.init(isAvailable: true, isPending: true), isPast: false))
        XCTAssertEqual(Self.lundi.state(.journee), .init(isAvailable: true))
        XCTAssertEqual(Self.lundi.state(.nuit), .init())
        XCTAssertEqual(AvailabilityWeekGrid.identifier(prefix: "dispos", dayID: "2026-11-02", creneau: .journee), "dispos-2026-11-02-journee")
        XCTAssertEqual(AvailabilityWeekGrid.identifier(prefix: "dispos", dayID: "2026-11-02", creneau: .nuit), "dispos-2026-11-02-nuit")
        XCTAssertEqual(AvailabilityWeekGrid.rowIdentifier(prefix: "dispos", dayID: "2026-11-02"), "dispos-2026-11-02")
        XCTAssertEqual(AvailabilityWeekGrid.titleIdentifier(prefix: "dispos-semaine-1"), "dispos-semaine-1-title")
        XCTAssertEqual(AvailabilityWeekGrid.accessibilityLabel(day: Self.lundi, creneau: .journee), "Lundi 2 Nov., aujourd'hui, Jour")
        XCTAssertEqual(AvailabilityWeekGrid.accessibilityLabel(day: Self.dimanche, creneau: .nuit), "Dimanche 1 Nov., Nuit")
        XCTAssertEqual(AvailabilityWeekGrid.layout(for: .large), .horizontal)
        XCTAssertEqual(AvailabilityWeekGrid.layout(for: .xxxLarge), .horizontal)
        XCTAssertEqual(AvailabilityWeekGrid.layout(for: .accessibility1), .vertical)
        XCTAssertEqual(AvailabilityWeekGrid.minimumTapTarget, 44, "Web min-h-[36px] relevé à 44 pt (HIG)")
    }

    func testAvailabilityWeekGridEncresAA() throws {
        // Jour déclaré : dégradé hero + encre #2B183D ; Nuit déclarée : midnight + cloud (inversés en sombre) ;
        // non déclaré : bubblegum sur cloud ; libellé du jour midnight, « aujourd'hui » rose-800.
        XCTAssertNil(AvailabilityWeekGrid.Creneau.journee.selectedInkHSL)
        XCTAssertEqual(AvailabilityWeekGrid.Creneau.journee.selectedFillHSL, JoleneColor.heroGradientStops)
        for fond in AvailabilityWeekGrid.Creneau.journee.selectedFillHSL {
            XCTAssertGreaterThanOrEqual(Self.encreSurDegrade.contrastRatio(with: fond.light.rgb), 4.5)
            XCTAssertGreaterThanOrEqual(Self.encreSurDegrade.contrastRatio(with: fond.dark.rgb), 4.5)
        }
        XCTAssertEqual(AvailabilityWeekGrid.Creneau.nuit.selectedFillHSL, [JoleneColor.midnightHSL])
        let nuit = Self.contrastes(try XCTUnwrap(AvailabilityWeekGrid.Creneau.nuit.selectedInkHSL), sur: JoleneColor.midnightHSL)
        XCTAssertGreaterThanOrEqual(nuit.clair, 4.5)
        XCTAssertGreaterThanOrEqual(nuit.sombre, 4.5)
        for (encre, nom) in [(AvailabilityWeekGrid.unselectedInkHSL, "non déclaré"), (AvailabilityWeekGrid.dayLabelInkHSL, "jour"),
                             (AvailabilityWeekGrid.todayInkHSL, "aujourd'hui")] {
            let c = Self.contrastes(encre, sur: JoleneColor.cloudHSL)
            XCTAssertGreaterThanOrEqual(c.clair, 4.5, nom)
            XCTAssertGreaterThanOrEqual(c.sombre, 4.5, nom)
        }
    }

    @MainActor
    func testAvailabilityWeekGridCiblesDe44PointsEtColonneAuxTaillesDAccessibilite() {
        for creneau in AvailabilityWeekGrid.Creneau.allCases {
            for taille in [DynamicTypeSize.large, .accessibility5] {
                let mesure = Self.taille(AvailabilityToggle(creneau: creneau, state: .init(isAvailable: creneau == .nuit), isPast: false,
                                                            accessibilityLabel: "L", identifier: "t") {}, taille: taille)
                XCTAssertGreaterThanOrEqual(mesure.width, 44, "\(creneau) \(taille)")
                XCTAssertGreaterThanOrEqual(mesure.height, 44, "\(creneau) \(taille)")
            }
        }
        // Bascule mesurée : aux tailles d'accessibilité, libellé au-dessus et créneaux en dessous, jamais tronqués.
        func grille(_ disposition: AvailabilityWeekGrid.Layout?) -> some View {
            AvailabilityWeekGrid(title: "Semaine du 2 novembre", days: [Self.lundi, Self.dimanche], identifier: "dispos",
                                 layoutOverride: disposition) { _, _ in }
        }
        let enLigne = Self.taille(grille(.horizontal)), enColonne = Self.taille(grille(.vertical))
        XCTAssertGreaterThan(enColonne.height, enLigne.height + 20, "La mesure distingue les deux dispositions")
        XCTAssertEqual(Self.taille(grille(nil)).height, enLigne.height, accuracy: 0.5, "Taille standard : en ligne")
        let a11y = Self.taille(grille(.vertical), largeur: 320, taille: .accessibility5)
        XCTAssertEqual(Self.taille(grille(nil), largeur: 320, taille: .accessibility5).height, a11y.height, accuracy: 0.5)
        XCTAssertNotEqual(Self.taille(grille(.horizontal), largeur: 320, taille: .accessibility5).height, a11y.height, accuracy: 0.5)
        XCTAssertLessThanOrEqual(a11y.width, 320)
    }

    // MARK: - StarRow

    func testStarRowReprendToFixedEtMathRoundDuWeb() throws {
        // EvaluationsSoignant.tsx : `i <= Math.round(note)` étoiles pleines, `note.toFixed(1)` affiché.
        let web = try Self.sourceWeb("src/pages/EvaluationsSoignant.tsx")
        XCTAssertTrue(web.contains("i <= Math.round(note)"))
        XCTAssertTrue(web.contains("{note.toFixed(1)}"))
        XCTAssertEqual(StarRow.starCount, 5)
        // Node 24.14.0 : (note, note.toFixed(1), Math.round(note)).
        let vecteurs: [(Double, String, Double)] = [
            (0, "0.0", 0), (0.04, "0.0", 0), (0.05, "0.1", 0), (0.15, "0.1", 0), (0.25, "0.3", 0), (0.35, "0.3", 0),
            (0.45, "0.5", 0), (0.49999999999999994, "0.5", 0), (0.5, "0.5", 1), (0.75, "0.8", 1), (1, "1.0", 1),
            (1.05, "1.1", 1), (1.25, "1.3", 1), (1.45, "1.4", 1), (1.5, "1.5", 2), (2.25, "2.3", 2),
            (2.4999999999999996, "2.5", 2), (2.5, "2.5", 3), (2.55, "2.5", 3), (2.65, "2.6", 3), (3.14159, "3.1", 3),
            (3.45, "3.5", 3), (3.5, "3.5", 4), (3.75, "3.8", 4), (3.95, "4.0", 4), (3.96, "4.0", 4), (4, "4.0", 4),
            (4.04, "4.0", 4), (4.05, "4.0", 4), (4.15, "4.2", 4), (4.25, "4.3", 4), (4.333333333333333, "4.3", 4),
            (4.35, "4.3", 4), (4.45, "4.5", 4), (4.5, "4.5", 5), (4.55, "4.5", 5), (4.65, "4.7", 5), (4.75, "4.8", 5),
            (4.85, "4.8", 5), (4.95, "5.0", 5), (4.96, "5.0", 5), (4.99, "5.0", 5), (5, "5.0", 5), (5.25, "5.3", 5),
            (5.5, "5.5", 6), (6, "6.0", 6), (-0.04, "-0.0", 0), (-0.25, "-0.3", 0), (-0.5, "-0.5", 0), (-1.5, "-1.5", -1),
        ]
        for (note, texte, arrondi) in vecteurs {
            XCTAssertEqual(StarRow.texteNote(note), texte, "\(note).toFixed(1)")
            XCTAssertEqual(StarRow.mathRound(note), arrondi, "Math.round(\(note))")
            XCTAssertEqual(StarRow.filledCount(note), Int(min(5, max(0, arrondi))), "étoiles pleines pour \(note)")
        }
        XCTAssertEqual(StarRow.texteNote(-0.0), "0.0", "(-0).toFixed(1) === '0.0'")
        // Valeurs impossibles en JSON, gardées : ni « NaN » ni étoile.
        XCTAssertEqual(StarRow.texteNote(.nan), "—")
        XCTAssertEqual(StarRow.filledCount(.nan), 0)
        XCTAssertEqual(StarRow.filledCount(.infinity), 0)
    }

    func testStarRowVocaliseLaNoteEnFrancaisEtResteLisible() {
        XCTAssertEqual(StarRow.accessibilityLabel(4.25), "Note : 4,3 sur 5")
        XCTAssertEqual(StarRow.accessibilityLabel(5), "Note : 5,0 sur 5")
        XCTAssertEqual(StarRow.accessibilityLabel(.nan), "Note indisponible")
        // Étoile pleine : remplissage butter-400 + contour butter-800 (≥ 3:1) ; vide : contour bubblegum ; valeur midnight.
        XCTAssertEqual(StarRow.filledFillHSL, JoleneColor.butter400HSL)
        XCTAssertEqual(StarRow.filledStrokeHSL, JoleneColor.butter800HSL)
        for surface in [JoleneColor.cloudHSL, JoleneColor.lavenderHSL] {
            for (encre, seuil, nom) in [(StarRow.filledStrokeHSL, 3.0, "contour plein"), (StarRow.emptyStrokeHSL, 3.0, "contour vide"),
                                        (StarRow.valueInkHSL, 4.5, "valeur")] {
                let c = Self.contrastes(encre, sur: surface)
                XCTAssertGreaterThanOrEqual(c.clair, seuil, "\(nom) clair sur \(surface.light)")
                XCTAssertGreaterThanOrEqual(c.sombre, seuil, "\(nom) sombre sur \(surface.dark)")
            }
        }
    }

    // MARK: - StatusPill (implémentation du lot 3, reprise à l'identique)

    func testStatusPillLibellesAASurChaqueTon() {
        XCTAssertEqual(StatusPill.Tone.allCases, [.info, .success, .warning, .error, .neutral])
        for ton in StatusPill.Tone.allCases {
            let libelle = Self.contrastes(ton.labelInkHSL, sur: ton.backgroundHSL)
            XCTAssertGreaterThanOrEqual(libelle.clair, 4.5, "\(ton)")
            XCTAssertGreaterThanOrEqual(libelle.sombre, 4.5, "\(ton)")
            let icone = Self.contrastes(ton.iconInkHSL, sur: ton.backgroundHSL)
            XCTAssertGreaterThanOrEqual(icone.clair, 3, "\(ton)")
            XCTAssertGreaterThanOrEqual(icone.sombre, 3, "\(ton)")
        }
        // Libellé serveur verbatim (statuts de litige, copies de bulletin) : la pastille ne normalise rien.
        XCTAssertEqual(StatusPill.Presentation(label: "Accord mutuel ✅", identifier: "litige-statut").accessibilityLabel, "Accord mutuel ✅")
        XCTAssertEqual(StatusPill.defaultTone, .info)
        XCTAssertEqual(StatusPill.defaultSize, .md)
    }

    // MARK: - QRCodeImage

    func testQRCodeImageSeDecodeEnLaChaineDEntree() throws {
        // PageParrainage.tsx l.219 : `QRCodeSVG value={lienRef} size={140} level="M" bgColor="#FFFFFF" fgColor="#1A1A2E"`.
        let web = try Self.sourceWeb("src/pages/PageParrainage.tsx")
        XCTAssertTrue(web.contains("size={140} level=\"M\" bgColor=\"#FFFFFF\" fgColor=\"#1A1A2E\""))
        XCTAssertEqual(QRCodeImage.correctionLevel, "M")
        XCTAssertEqual(QRCodeImage.foregroundHex, "#1A1A2E")
        XCTAssertEqual(QRCodeImage.backgroundHex, "#FFFFFF")
        XCTAssertEqual(QRCodeImage.defaultSide, 140)
        // Couleurs fixes en clair comme en sombre (lisibles par un scanner) : 17:1.
        XCTAssertEqual(JoleneHex.parse(QRCodeImage.foregroundHex)!.contrastRatio(with: JoleneHex.parse(QRCodeImage.backgroundHex)!),
                       17.06, accuracy: 0.01)
        let detecteur = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                 options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for charge in ["https://jolene.app/inscription/soignant?ref=DEMO-ABC123", "Évaluation — accentuée ✓", "x"] {
            let image = try XCTUnwrap(QRCodeImage.cgImage(for: charge), charge)
            XCTAssertEqual(image.width, image.height, "Image carrée")
            XCTAssertEqual(image.width % 8, 0, "Modules agrandis d'un facteur entier, sans lissage")
            let lus = detecteur.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(lus, [charge], "CIDetector relit exactement la chaîne d'entrée")
        }
        XCTAssertNotEqual(QRCodeImage.cgImage(for: "a")?.width, QRCodeImage.cgImage(for: String(repeating: "a", count: 120))?.width,
                          "La taille suit la charge (aucune image figée)")
    }

    // MARK: - ScoreBadge

    func testScoreBadgeAfficheLaValeurServeurEtRienSansScore() throws {
        // CardMissionSwipe.tsx : `{mission.score}/100`, `premium` si ≥ 80 ; ModalDetailMissionSwipe.tsx : `Match {mission.score}/100`.
        let carte = try Self.sourceWeb("src/components/swipe/CardMissionSwipe.tsx")
        let detail = try Self.sourceWeb("src/components/swipe/ModalDetailMissionSwipe.tsx")
        XCTAssertTrue(carte.contains("{mission.score}/100"))
        XCTAssertTrue(carte.contains("mission.score >= 80"))
        XCTAssertTrue(carte.contains("score ${mission.score} sur 100"))
        XCTAssertTrue(detail.contains("Match {mission.score}/100"))
        XCTAssertEqual(ScoreBadge.texte(85, style: .carte), "85/100")
        XCTAssertEqual(ScoreBadge.texte(0, style: .carte), "0/100", "Un vrai zéro reste affiché")
        XCTAssertEqual(ScoreBadge.texte(85, style: .detail), "Match 85/100")
        XCTAssertNil(ScoreBadge.texte(nil, style: .carte), "Score inconnu : aucune pastille, jamais « 0/100 » fabriqué")
        XCTAssertNil(ScoreBadge.texte(nil, style: .detail))
        XCTAssertEqual(ScoreBadge.accessibilityLabel(85, style: .carte), "Score 85 sur 100")
        XCTAssertEqual(ScoreBadge.accessibilityLabel(85, style: .detail), "Match 85 sur 100")
        XCTAssertNil(ScoreBadge.accessibilityLabel(nil, style: .carte))
        XCTAssertFalse(ScoreBadge.estEleve(79))
        XCTAssertTrue(ScoreBadge.estEleve(80))
        XCTAssertTrue(ScoreBadge.estEleve(100))
        XCTAssertFalse(ScoreBadge.estEleve(0))
        XCTAssertEqual(ScoreBadge.systemImage, "sparkles")
        // `premium` : `.bg-gradient-celebrate` + encre #2B183D ; `info` : couleurs de StatusPill info.
        XCTAssertEqual(ScoreBadge.premiumStops, JoleneColor.celebrateGradientStops)
        XCTAssertEqual(ScoreBadge.premiumInkHex, JoleneColor.onGradientHex)
        XCTAssertEqual(ScoreBadge.infoTone, .info)
        let info = Self.contrastes(StatusPill.Tone.info.labelInkHSL, sur: StatusPill.Tone.info.backgroundHSL)
        XCTAssertGreaterThanOrEqual(info.clair, 4.5)
        XCTAssertGreaterThanOrEqual(info.sombre, 4.5)
    }

    // MARK: - WebHandoffCard

    func testWebHandoffCardAfficheLAdresseEtSesIdentifiants() throws {
        XCTAssertEqual(WebHandoffCard.displayURL(try XCTUnwrap(URL(string: "https://jolene.app/soignant/premium"))), "jolene.app/soignant/premium")
        XCTAssertEqual(WebHandoffCard.displayURL(try XCTUnwrap(URL(string: "https://jolene.app/soignant/mes-gains?tab=avances"))),
                       "jolene.app/soignant/mes-gains?tab=avances")
        XCTAssertEqual(WebHandoffCard.displayURL(try XCTUnwrap(URL(string: "https://jolene.app/"))), "jolene.app")
        XCTAssertEqual(WebHandoffCard.displayURL(try XCTUnwrap(URL(string: "https://jolene.app"))), "jolene.app")
        XCTAssertEqual(WebHandoffCard.displayURL(try XCTUnwrap(URL(string: "https://jolene.app/soignant/litiges#abc"))),
                       "jolene.app/soignant/litiges", "Le fragment n'est pas affiché")
        XCTAssertEqual(WebHandoffCard.defaultActionTitle, "Ouvrir sur jolene.app")
        XCTAssertNil(WebHandoffCard.actionLineLimit)
        let ids = WebHandoffCard.Identifiers(identifier: "renvoi-web")
        XCTAssertEqual(ids.container, "renvoi-web")
        XCTAssertEqual(ids.title, "renvoi-web-title")
        XCTAssertEqual(ids.message, "renvoi-web-message")
        XCTAssertEqual(ids.url, "renvoi-web-url")
        XCTAssertEqual(ids.action, "renvoi-web-action")
        // T1c : le bouton de `RenvoiWebScreen` s'appelle `renvoi-web-ouvrir`, imposé sans rouvrir le package.
        XCTAssertEqual(WebHandoffCard.Identifiers(identifier: "renvoi-web", actionIdentifier: "renvoi-web-ouvrir").action, "renvoi-web-ouvrir")
        for (encre, nom) in [(WebHandoffCard.titleInkHSL, "titre"), (WebHandoffCard.messageInkHSL, "message"),
                             (WebHandoffCard.urlInkHSL, "adresse")] {
            let c = Self.contrastes(encre, sur: JoleneColor.cloudHSL)
            XCTAssertGreaterThanOrEqual(c.clair, 4.5, nom)
            XCTAssertGreaterThanOrEqual(c.sombre, 4.5, nom)
        }
    }

    @MainActor
    func testWebHandoffCardActionPasseALaLigneAuxGrandesTaillesSansTronquer() throws {
        let url = try XCTUnwrap(URL(string: "https://jolene.app/soignant/premium"))
        func carte(_ action: String) -> some View {
            WebHandoffCard(title: "Premium", message: "Cet écran est disponible sur jolene.app.", url: url, actionTitle: action,
                           identifier: "renvoi-web") {}
        }
        let longue = "Ouvrir la page des avances sur jolene.app dans Safari"
        for taille in [DynamicTypeSize.xxLarge, .xxxLarge, .accessibility3, .accessibility5] {
            let ligne = Self.taille(Text("Ag").font(JoleneFont.button), largeur: 2000, taille: taille).height
            let courte = Self.taille(carte("Ouvrir"), largeur: 280, taille: taille)
            let longueMesure = Self.taille(carte(longue), largeur: 280, taille: taille)
            XCTAssertGreaterThanOrEqual(longueMesure.height - courte.height, ligne * 0.9,
                                        "\(taille) : le libellé long ajoute au moins une ligne (retour à la ligne, pas « … »)")
            XCTAssertLessThanOrEqual(longueMesure.width, 280)
        }
    }

    // MARK: - Rendu des vues (corps évalué, aucun piège), tailles XXL et sombre

    @MainActor
    func testLesVuesDuLot4SeRendentDansUnHebergeurUIKit() throws {
        let url = try XCTUnwrap(URL(string: "https://jolene.app/soignant/premium"))
        let cartes = (1...4).map { CarteTest(id: "m\($0)") }
        let vues: [(String, AnyView)] = [
            ("paquet", AnyView(SwipeCardStack(cartes, onAction: { _, _ in }) { carte in
                Text("Carte \(carte.id)").frame(maxWidth: .infinity, minHeight: 300).background(JoleneColor.cloud)
            })),
            ("paquet occupé", AnyView(SwipeCardStack(cartes, isBusy: true, onAction: { _, _ in }) { Text($0.id) })),
            ("paquet vide", AnyView(SwipeCardStack([CarteTest](), onAction: { _, _ in }) { Text($0.id) })),
            ("barre swipe", AnyView(SwipeActionBar(onAction: { _ in }))),
            ("barre swipe désactivée", AnyView(SwipeActionBar(isDisabled: true, onAction: { _ in }))),
            ("bulle moi", AnyView(ChatBubble("Bonjour", kind: .moi, heure: "14:32", identifier: "message-1"))),
            ("bulle non confirmée", AnyView(ChatBubble("Bonjour", kind: .moi, heure: "14:32", delivery: .nonConfirme, identifier: "message-2"))),
            ("bulle interlocuteur", AnyView(ChatBubble("Bonjour\nà demain", kind: .interlocuteur, heure: "09:05", auteur: "Clinique Démo"))),
            ("bulle Jolene", AnyView(ChatBubble("Votre dossier est complet.", kind: .jolene, heure: "10:00"))),
            ("bulle système", AnyView(ChatBubble("Conversation ouverte", kind: .systeme))),
            ("composeur", AnyView(MessageComposer(text: .constant("Bonjour"), identifier: "composeur", onSend: {}))),
            ("composeur compteur", AnyView(MessageComposer(text: .constant(String(repeating: "a", count: 3950)), onSend: {}))),
            ("composeur envoi", AnyView(MessageComposer(text: .constant("Bonjour"), isSending: true, onSend: {}))),
            ("composeur archivé", AnyView(MessageComposer(text: .constant(""), isArchived: true, onSend: {}))),
            ("saisie", AnyView(TypingIndicator(identifier: "typing"))),
            ("grille", AnyView(AvailabilityWeekGrid(title: "Semaine du 2 novembre", days: [Self.lundi, Self.dimanche],
                                                    identifier: "dispos") { _, _ in })),
            ("grille en cours", AnyView(AvailabilityWeekGrid(title: "Semaine du 9 novembre", days: [
                .init(id: "2026-11-09", label: "Lundi 9 Nov.", isToday: false, isPast: false,
                      journee: .init(isAvailable: true, isPending: true), nuit: .init()),
            ], identifier: "dispos-2") { _, _ in })),
            ("étoiles", AnyView(StarRow(note: 4.25, identifier: "note"))),
            ("étoiles sans valeur", AnyView(StarRow(note: 0, showsValue: false))),
            ("étoiles NaN", AnyView(StarRow(note: .nan))),
            ("pastille", AnyView(StatusPill("Accord mutuel ✅", tone: .success, systemImage: "checkmark.circle", identifier: "statut"))),
            ("QR", AnyView(QRCodeImage("https://jolene.app/inscription/soignant?ref=DEMO-ABC123",
                                       accessibilityLabel: "QR code du lien de parrainage", identifier: "qr"))),
            ("score carte", AnyView(ScoreBadge(score: 85, identifier: "score"))),
            ("score info", AnyView(ScoreBadge(score: 42, style: .detail))),
            ("score inconnu", AnyView(ScoreBadge(score: nil))),
            ("renvoi web", AnyView(WebHandoffCard(title: "Premium", message: "Cet écran est disponible sur jolene.app.", url: url,
                                                  identifier: "renvoi-web", actionIdentifier: "renvoi-web-ouvrir") {})),
        ]
        for (nom, vue) in vues {
            for (taille, schema) in [(DynamicTypeSize.large, ColorScheme.light), (.xxxLarge, .dark), (.accessibility5, .light)] {
                let hote = UIHostingController(rootView: vue.environment(\.dynamicTypeSize, taille).environment(\.colorScheme, schema))
                let mesure = hote.sizeThatFits(in: CGSize(width: 390, height: 2000))
                XCTAssertTrue(mesure.width.isFinite && mesure.height.isFinite, "\(nom) à \(taille) : taille finie")
                XCTAssertLessThanOrEqual(mesure.width, 390.5, "\(nom) à \(taille) : aucune largeur au-delà de l'écran")
                hote.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                hote.view.layoutIfNeeded()
            }
        }
    }
}

/// Élément de paquet pour les tests (identifiant chaîne, comme `Mission.id`).
private struct CarteTest: Identifiable {
    let id: String
}
