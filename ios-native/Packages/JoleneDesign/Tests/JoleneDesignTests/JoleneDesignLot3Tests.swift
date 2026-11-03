import XCTest
import SwiftUI
import UIKit
@testable import JoleneDesign

/// Lot 3 (T1b) : règles pures des composants du lot 3 (`ToggleRow`, `SegmentedChoice`, `AvatarView`,
/// `AmountRow`, `StatusPill`, `PermissionCard`, `PasswordCriteriaList`). Chaque composant expose sa
/// partie calculable (identifiants, libellés vocalisés, encres, seuils) pour qu'elle soit vérifiée sans
/// XCUITest ; les textes repris du web sont relus dans le fichier source du dépôt (garde de dérive,
/// HARD STOP n°4). La section « Rendu » évalue le corps de chaque vue dans un `UIHostingController`
/// (390 pt, clair et sombre, Dynamic Type standard et accessibility5) et mesure la cible tactile de
/// `ToggleRow` et d'un segment de `SegmentedChoice`. Le parcours visible reste couvert par les XCUITest
/// démo des écrans qui monteront ces composants (T5, T6, T9 à T14b).
final class JoleneDesignLot3Tests: XCTestCase {
    // MARK: - Sources web (garde de dérive)

    /// Fichier du dépôt relu par les gardes : Tests/JoleneDesignTests/<fichier> → racine (6 niveaux),
    /// motif de `JoleneDesignLot1Tests.variablesJoleneDeIndexCss`. Un fichier absent saute le test ; la
    /// porte CI exige `skipped == 0` (ios-swift-ci.yml), un saut ne passe donc pas inaperçu.
    static func sourceWeb(_ chemin: String) throws -> String {
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent(chemin)
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("\(chemin) introuvable : \(fichier.path)")
        }
        return try String(contentsOf: fichier, encoding: .utf8)
    }

    /// Contraste d'une encre sur un fond, en clair puis en sombre.
    static func contrastes(_ encre: JoleneDynamicHSL, sur fond: JoleneDynamicHSL) -> (clair: Double, sombre: Double) {
        (encre.light.rgb.contrastRatio(with: fond.light.rgb), encre.dark.rgb.contrastRatio(with: fond.dark.rgb))
    }

    /// Encre vue à travers un voile d'opacité (composition sRGB, comme `opacity` sur un fond opaque).
    static func voile(_ encre: JoleneHex, sur fond: JoleneHex, opacite: Double) -> JoleneHex {
        JoleneHex(red: encre.red * opacite + fond.red * (1 - opacite), green: encre.green * opacite + fond.green * (1 - opacite),
                  blue: encre.blue * opacite + fond.blue * (1 - opacite))
    }

    /// Surfaces d'un composant posé sur une carte (`cloud`) ou un écran (`lavender`), jamais sur le
    /// bas du `softGradient` (`rose100`, où `bubblegum` tombe à 4,44:1).
    static let cartesEtEcrans = [JoleneColor.cloudHSL, JoleneColor.lavenderHSL]

    // MARK: - ToggleRow

    func testToggleRowReprendToggleCanalEtVocaliseLaRaisonDuBlocage() throws {
        // PageParametresNotifications.tsx (ToggleCanal l.442-461) : `role="switch"`, `aria-label={label}`,
        // `opacity-50` et clic ignoré quand `disabled`.
        let web = try Self.sourceWeb("src/pages/PageParametresNotifications.tsx")
        XCTAssertTrue(web.contains("role=\"switch\""))
        XCTAssertTrue(web.contains("${disabled ? 'opacity-50' : ''}"), "Opacité du canal désactivé")
        XCTAssertTrue(web.contains("onClick={() => !disabled && onChange(!actif)}"), "Clic ignoré quand désactivé")
        XCTAssertEqual(ToggleRow.disabledOpacity, 0.5)
        // `ToggleCanal` n'a pas de hauteur minimale (interrupteur `h-6 w-11`, ligne `p-3`) : les 44 pt viennent
        // de la cible tactile minimale d'Apple, pas du web.
        XCTAssertTrue(web.contains("relative inline-flex h-6 w-11 shrink-0"))
        XCTAssertEqual(ToggleRow.minimumHeight, 44, "Cible tactile 44 pt (recommandation Apple)")

        let actif = ToggleRow.Presentation.resolve(title: "Email", description: nil, isDisabled: false, disabledReason: nil)
        XCTAssertEqual(actif.accessibilityLabel, "Email")
        XCTAssertNil(actif.accessibilityHint)
        XCTAssertNil(actif.visibleReason)
        XCTAssertEqual(actif.opacity, 1)
        XCTAssertTrue(actif.allowsToggle)

        // Ligne d'événement : libellé court vocalisé, description en indice (lue après l'état).
        let evenement = ToggleRow.Presentation.resolve(title: "Rappel mission J-1", description: "Rappel la veille du début de mission",
                                                       isDisabled: false, disabledReason: "Canal SMS désactivé dans les canaux globaux")
        XCTAssertEqual(evenement.accessibilityLabel, "Rappel mission J-1")
        XCTAssertEqual(evenement.accessibilityHint, "Rappel la veille du début de mission")
        XCTAssertNil(evenement.visibleReason, "La raison n'est montrée que si la ligne est bloquée")

        // Bloquée : la raison fournie par l'écran (texte web du `title`) est affichée hors du voile d'opacité ET
        // vocalisée dans le libellé, comme l'`aria-label` de la matrice web (l.410 : « canal global désactivé »),
        // donc lue même quand les indices VoiceOver sont coupés ; la description reste en indice.
        XCTAssertTrue(web.contains("${!canalGlobalActif ? 'canal global désactivé'"), "Blocage vocalisé dans l'aria-label web")
        let bloquee = ToggleRow.Presentation.resolve(title: "Rappel mission J-1", description: "Rappel la veille du début de mission",
                                                     isDisabled: true, disabledReason: "Canal SMS désactivé dans les canaux globaux")
        XCTAssertEqual(bloquee.accessibilityLabel, "Rappel mission J-1, Canal SMS désactivé dans les canaux globaux")
        XCTAssertEqual(bloquee.accessibilityHint, "Rappel la veille du début de mission", "La raison n'est pas répétée en indice")
        XCTAssertEqual(bloquee.visibleReason, "Canal SMS désactivé dans les canaux globaux")
        XCTAssertEqual(bloquee.opacity, ToggleRow.disabledOpacity)
        XCTAssertFalse(bloquee.allowsToggle)
        let bloqueeSansDescription = ToggleRow.Presentation.resolve(title: "Email", description: nil, isDisabled: true,
                                                                    disabledReason: "Canal EMAIL désactivé dans les canaux globaux")
        XCTAssertEqual(bloqueeSansDescription.accessibilityLabel, "Email, Canal EMAIL désactivé dans les canaux globaux")
        XCTAssertNil(bloqueeSansDescription.accessibilityHint)
        let bloqueeSansRaison = ToggleRow.Presentation.resolve(title: "Email", description: nil, isDisabled: true, disabledReason: nil)
        XCTAssertEqual(bloqueeSansRaison.accessibilityLabel, "Email")
        XCTAssertNil(bloqueeSansRaison.accessibilityHint)
        XCTAssertNil(bloqueeSansRaison.visibleReason)
        let raisonVide = ToggleRow.Presentation.resolve(title: "Email", description: nil, isDisabled: true, disabledReason: "  ")
        XCTAssertEqual(raisonVide.accessibilityLabel, "Email", "Une raison vide n'est ni affichée ni lue")
        XCTAssertNil(raisonVide.visibleReason)

        // Tap sur le libellé : bascule seulement si la ligne est active (double garde, comme le web).
        XCTAssertTrue(ToggleRow.toggled(false, allowsToggle: true))
        XCTAssertFalse(ToggleRow.toggled(true, allowsToggle: true))
        XCTAssertTrue(ToggleRow.toggled(true, allowsToggle: false), "Bloquée : valeur inchangée")
        XCTAssertFalse(ToggleRow.toggled(false, allowsToggle: false))
    }

    func testToggleRowTeinteEtIconeAtteignentTroisPourUnSurLesSurfaces() {
        // WCAG 1.4.11 (contraste non textuel) : piste active et icône ≥ 3:1 sur carte, écran et softGradient.
        // Le rose de marque (`bg-primary` du web) n'atteint que 2,51:1 sur `cloud` en clair : rose-700.
        XCTAssertEqual(ToggleRow.tintHSL, JoleneColor.rose700HSL)
        XCTAssertEqual(ToggleRow.iconInkHSL, JoleneColor.rose700HSL)
        for surface in JoleneColor.inheritedSurfacesHSL {
            let (clair, sombre) = Self.contrastes(ToggleRow.tintHSL, sur: surface)
            XCTAssertGreaterThanOrEqual(clair, 3, "teinte, clair, \(surface.light)")
            XCTAssertGreaterThanOrEqual(sombre, 3, "teinte, sombre, \(surface.dark)")
        }
        XCTAssertEqual(Self.contrastes(JoleneColor.roseHSL, sur: JoleneColor.cloudHSL).clair, 2.51, accuracy: 0.01)
        XCTAssertEqual(Self.contrastes(ToggleRow.tintHSL, sur: JoleneColor.rose100HSL).clair, 3.54, accuracy: 0.01)
        // Texte de la ligne : titre `midnight`, description et raison `bubblegum` (carte ou écran).
        XCTAssertEqual(ToggleRow.titleInkHSL, JoleneColor.midnightHSL)
        XCTAssertEqual(ToggleRow.secondaryInkHSL, JoleneColor.bubblegumHSL)
        for surface in Self.cartesEtEcrans {
            for encre in [ToggleRow.titleInkHSL, ToggleRow.secondaryInkHSL] {
                let (clair, sombre) = Self.contrastes(encre, sur: surface)
                XCTAssertGreaterThanOrEqual(clair, 4.5)
                XCTAssertGreaterThanOrEqual(sombre, 4.5)
            }
        }
    }

    func testToggleRowRaisonDuBlocageLisibleHorsDuVoile() {
        // Le voile `opacity-50` du web fait passer `bubblegum` sous 4,5:1 : acceptable pour un contrôle inactif
        // (WCAG 1.4.3, exception), pas pour la raison du blocage, qui est une information. Elle est donc
        // dessinée hors du voile, en encre pleine, sur carte et écran.
        XCTAssertEqual(ToggleRow.reasonInkHSL, JoleneColor.bubblegumHSL)
        for surface in Self.cartesEtEcrans {
            let (clair, sombre) = Self.contrastes(ToggleRow.reasonInkHSL, sur: surface)
            XCTAssertGreaterThanOrEqual(clair, 4.5, "raison, clair, \(surface.light)")
            XCTAssertGreaterThanOrEqual(sombre, 4.5, "raison, sombre, \(surface.dark)")
            let voilee = Self.voile(ToggleRow.reasonInkHSL.light.rgb, sur: surface.light.rgb, opacite: ToggleRow.disabledOpacity)
            XCTAssertLessThan(voilee.contrastRatio(with: surface.light.rgb), 4.5, "Sous le voile, la raison serait sous AA")
        }
    }

    // MARK: - SegmentedChoice

    func testSegmentedChoiceDeriveSesIdentifiantsEtAnnonceLaSeuleOptionChoisie() {
        // Thème Système / Clair / Sombre (D16, T11) : un identifiant par option, jamais déduit du libellé.
        XCTAssertEqual(SegmentedChoice.optionIdentifier("compte-theme", optionID: "systeme"), "compte-theme-systeme")
        XCTAssertEqual(SegmentedChoice.optionIdentifier("compte-theme", optionID: "sombre"), "compte-theme-sombre")
        XCTAssertEqual(SegmentedChoice.minimumHeight, 44)

        let choisie = SegmentedChoice.Appearance.resolve(isSelected: true)
        XCTAssertTrue(choisie.usesGradient)
        XCTAssertTrue(choisie.announcesSelected, "Trait « Sélectionné », seul mécanisme vocalisé (comme FilterChip)")
        XCTAssertEqual(choisie.foregroundHex, JoleneColor.onGradientHex)
        let autre = SegmentedChoice.Appearance.resolve(isSelected: false)
        XCTAssertFalse(autre.usesGradient)
        XCTAssertFalse(autre.announcesSelected)
        XCTAssertNil(autre.foregroundHex, "Inactive : jeton dynamique bubblegum")

        let options = [SegmentedChoice.Option(id: "systeme", title: "Système"), SegmentedChoice.Option(id: "clair", title: "Clair"),
                       SegmentedChoice.Option(id: "sombre", title: "Sombre")]
        XCTAssertEqual(options.filter { SegmentedChoice.isSelected($0, selection: "clair") }.map(\.id), ["clair"])
        XCTAssertTrue(options.filter { SegmentedChoice.isSelected($0, selection: "inconnu") }.isEmpty,
                      "Une sélection hors liste n'allume aucun segment, jamais le premier par défaut")
    }

    func testSegmentedChoiceSegmentActifLisibleSurLeDegradeEtInactifSurLaPiste() {
        XCTAssertEqual(SegmentedChoice.activeGradientStops, JoleneColor.heroGradientFullStops)
        let encre = JoleneHex.parse(JoleneColor.onGradientHex)!
        for arret in SegmentedChoice.activeGradientStops {
            XCTAssertGreaterThanOrEqual(encre.contrastRatio(with: arret.light.rgb), 4.5, "\(arret.light)")
            XCTAssertGreaterThanOrEqual(encre.contrastRatio(with: arret.dark.rgb), 4.5, "\(arret.dark)")
        }
        // Piste `lavender`, segments inactifs en `bubblegum` : 5,18:1 en clair.
        XCTAssertEqual(SegmentedChoice.trackHSL, JoleneColor.lavenderHSL)
        XCTAssertEqual(SegmentedChoice.inactiveInkHSL, JoleneColor.bubblegumHSL)
        let (clair, sombre) = Self.contrastes(SegmentedChoice.inactiveInkHSL, sur: SegmentedChoice.trackHSL)
        XCTAssertEqual(clair, 5.18, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(sombre, 4.5)
    }

    func testSegmentedChoicePasseEnColonneAuxTaillesDAccessibilite() {
        XCTAssertEqual(SegmentedChoice.layout(for: .large), .horizontal)
        XCTAssertEqual(SegmentedChoice.layout(for: .xxxLarge), .horizontal)
        for taille in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            XCTAssertEqual(SegmentedChoice.layout(for: taille), .vertical, "\(taille)")
        }
    }

    // MARK: - AvatarView

    func testAvatarViewInitialesCommeGetInitialsWeb() {
        // Vecteurs produits sous Node v24.14.0 par `getInitials` copiée de AvatarUpload.tsx l.25-27 :
        // `((prenom?.[0] || '') + (nom?.[0] || '')).toUpperCase() || '?'`.
        let vecteurs: [(String?, String?, String)] = [
            (nil, nil, "?"), ("", "", "?"), ("Camille", "Martin", "CM"), ("camille", "martin", "CM"), ("Élodie", "Durand", "ÉD"),
            ("Jean-Pierre", "N'Diaye", "JN"), ("Zoé", "", "Z"), ("", "Bernard", "B"), ("ßeta", "ǆan", "SSǄ"),
            ("Anne-Sophie", "de La Tour", "AD"), ("Marie", "Ñúñez", "MÑ"), ("Aïcha", "Diallo", "AD"), (" ", "X", " X"),
            ("Ö", "Ü", "ÖÜ"), ("e\u{301}lise", "", "E"),
        ]
        for (prenom, nom, attendu) in vecteurs {
            XCTAssertEqual(AvatarView.initials(prenom: prenom, nom: nom), attendu, "\(String(describing: prenom)) \(String(describing: nom))")
        }
        // Écart assumé : le web prend la première unité UTF-16 (moitié de paire de substitution, affichée « � ») ;
        // le natif prend le premier scalaire Unicode, identique au web sur tout caractère du plan multilingue de base.
        XCTAssertEqual(AvatarView.initials(prenom: "\u{1F600}Ana", nom: nil), "\u{1F600}")
    }

    func testAvatarViewHachageEtCouleurDeRepliCommeLeWeb() {
        // `hashName` (AvatarUpload.tsx l.19-23), Node v24.14.0 : entier 32 bits signé `| 0`, puis `Math.abs`.
        let vecteurs: [(String, Int, Int)] = [
            ("", 0, 0), ("CamilleMartin", 1_245_797_274, 0), ("camillemartin", 1_128_626_074, 4),
            ("ÉlodieDurand", 1_503_001_014, 0), ("Jean-PierreN'Diaye", 208_241_873, 5), ("Zoé", 90_164, 2),
            ("Bernard", 1_445_900_308, 4), ("ßetaǆan", 948_140_224, 4), ("Anne-Sophiede La Tour", 848_759_043, 3),
            ("MarieÑúñez", 1_426_669_539, 3), ("LucasLefèvre-Dubois", 2_007_402_227, 5), ("InèsBenali", 1_137_125_917, 1),
            ("Thi ThuNguyễn", 1_874_024_740, 4), ("AïchaDiallo", 305_232_991, 1), (" X", 1_080, 0), ("ÖÜ", 6_854, 2),
            ("DemoSoignant", 1_832_699_222, 2), ("Christophe-Alexandre-MaximilienVandenberghe-Lefebvre-Dupont", 379_143_248, 2),
            (String(repeating: "a", count: 50), 1_203_646_688, 2), (String(repeating: "z", count: 42), 393_043_904, 2),
            ("\u{1F600}Ana", 1_276_892_529, 3), ("e\u{301}lise", 689_913_397, 1),
        ]
        for (cle, hachage, index) in vecteurs {
            XCTAssertEqual(AvatarView.hashName(cle), hachage, cle)
            XCTAssertEqual(hachage % AvatarView.fallbackColorsHSL.count, index, cle)
        }
        // Clé = prénom + nom concaténés (`(prenom || '') + (nom || '')`), sans séparateur.
        XCTAssertEqual(AvatarView.fallbackColorIndex(prenom: "Camille", nom: "Martin"), 0)
        XCTAssertEqual(AvatarView.fallbackColorIndex(prenom: "Jean-Pierre", nom: "N'Diaye"), 5)
        XCTAssertEqual(AvatarView.fallbackColorIndex(prenom: nil, nom: "Bernard"), 4)
        XCTAssertEqual(AvatarView.fallbackColorIndex(prenom: nil, nom: nil), 0)
        // `Math.abs` de la valeur minimale d'un entier 32 bits : 2 147 483 648, jamais un débordement.
        XCTAssertEqual(AvatarView.magnitude(Int32.min), 2_147_483_648)
        XCTAssertEqual(AvatarView.magnitude(-5), 5)
    }

    func testAvatarViewCouleursDeRepliEtSeuilsDePoliceReprennentAvatarUpload() throws {
        let web = try Self.sourceWeb("src/components/AvatarUpload.tsx")
        // Garde de dérive des règles portées (hachage, initiales, seuils de police, libellé du bouton).
        XCTAssertTrue(web.contains("h = ((h << 5) - h + name.charCodeAt(i)) | 0;"))
        XCTAssertTrue(web.contains("return Math.abs(h);"))
        XCTAssertTrue(web.contains("return ((prenom?.[0] || '') + (nom?.[0] || '')).toUpperCase() || '?';"))
        XCTAssertTrue(web.contains("return FALLBACK_COLORS[hashName(name) % FALLBACK_COLORS.length];"))
        XCTAssertTrue(web.contains("const bg = getFallbackColor((prenom || '') + (nom || ''));"))
        XCTAssertTrue(web.contains("const fontSize = size >= 64 ? 'text-2xl' : size >= 32 ? 'text-sm' : 'text-xs';"))
        XCTAssertTrue(web.contains("export function AvatarDisplay({ src, prenom, nom, size = 40, rounded = 'full', className = '' }"))
        XCTAssertTrue(web.contains("'Changer ma photo de profil'"))
        XCTAssertEqual(AvatarView.changePhotoLabel, "Changer ma photo de profil")
        XCTAssertEqual(AvatarView.defaultSize, 40)
        // FALLBACK_COLORS, dans l'ordre (l.10-17).
        let bloc = try XCTUnwrap(web.range(of: "const FALLBACK_COLORS = [").map { web[$0.upperBound...] })
        let fin = try XCTUnwrap(bloc.range(of: "];"))
        let liste = String(bloc[..<fin.lowerBound])
        let motif = try NSRegularExpression(pattern: #"'hsl\(([0-9]+) ([0-9]+)% ([0-9]+)%\)'"#)
        let couleurs = motif.matches(in: liste, range: NSRange(liste.startIndex..., in: liste)).map { resultat -> JoleneHSL in
            let groupe = { (i: Int) in Double(String(liste[Range(resultat.range(at: i), in: liste)!]))! }
            return JoleneHSL(groupe(1), groupe(2), groupe(3))
        }
        XCTAssertEqual(couleurs, AvatarView.fallbackColorsHSL)
        XCTAssertEqual(couleurs.count, 6)
        // `text-2xl` (24 px) dès 64, `text-sm` (14 px) dès 32, sinon `text-xs` (12 px).
        XCTAssertEqual(AvatarView.initialsFontSize(for: 96), 24)
        XCTAssertEqual(AvatarView.initialsFontSize(for: 64), 24)
        XCTAssertEqual(AvatarView.initialsFontSize(for: 63), 14)
        XCTAssertEqual(AvatarView.initialsFontSize(for: 40), 14)
        XCTAssertEqual(AvatarView.initialsFontSize(for: 32), 14)
        XCTAssertEqual(AvatarView.initialsFontSize(for: 24), 12)
        XCTAssertEqual(AvatarView.cornerRadius(for: .full, size: 96), 48, "rounded-full")
        XCTAssertEqual(AvatarView.cornerRadius(for: .large, size: 96), 12, "rounded-xl")
    }

    func testAvatarViewInitialesBlanchesAtteignentAASurChaqueCouleurDeRepli() {
        // `text-white` sur chaque couleur de repli : ≥ 4,5:1 (le texte `text-sm` n'est pas du grand texte).
        let blanc = JoleneHex.parse(AvatarView.initialsInkHex)!
        XCTAssertEqual(blanc, JoleneHex(red: 1, green: 1, blue: 1))
        let ratios = AvatarView.fallbackColorsHSL.map { blanc.contrastRatio(with: $0.rgb) }
        for (couleur, ratio) in zip(AvatarView.fallbackColorsHSL, ratios) {
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(couleur)")
        }
        XCTAssertEqual(ratios.min() ?? 0, 4.87, accuracy: 0.01, "Le plus faible : émeraude hsl(152 69% 30%)")
    }

    func testAvatarViewLibelleVocaliseEtVignetteDecorative() {
        // `alt={`${prenom || ''} ${nom || ''}`}` (AvatarDisplay l.86), espaces de bord retirés.
        XCTAssertEqual(AvatarView.accessibilityLabel(prenom: "Camille", nom: "Martin"), "Camille Martin")
        XCTAssertEqual(AvatarView.accessibilityLabel(prenom: "Camille", nom: nil), "Camille")
        XCTAssertEqual(AvatarView.accessibilityLabel(prenom: nil, nom: "Martin"), "Martin")
        XCTAssertNil(AvatarView.accessibilityLabel(prenom: nil, nom: nil), "Sans nom : vignette décorative, masquée à VoiceOver")
        XCTAssertNil(AvatarView.accessibilityLabel(prenom: " ", nom: ""))
        // Téléversement en cours (`bg-black/50` + spinner) : annoncé comme un chargement.
        XCTAssertEqual(AvatarView.loadingAccessibilityValue(isLoading: true), SkeletonBlock.accessibilityLabel)
        XCTAssertNil(AvatarView.loadingAccessibilityValue(isLoading: false))
    }

    // MARK: - AmountRow

    func testAmountRowPrefixeApproximatifEtTiretCommeMesGains() throws {
        // MesGains.tsx l.748 : `${finance.approximatif ? '~' : ''}${fmt(finance.montant)}`, `'—'` sans montant.
        let web = try Self.sourceWeb("src/pages/MesGains.tsx")
        XCTAssertTrue(web.contains("{finance ? `${finance.approximatif ? '~' : ''}${fmt(finance.montant)}` : '—'}"))
        XCTAssertTrue(web.contains("'* Net salarié estimé après cotisations salariales (~22 %). '"), "Note « net estimé » (l.664)")
        XCTAssertEqual(AmountRow.approximatePrefix, "~")
        XCTAssertEqual(AmountRow.unavailableAmount, "—")

        let salarie = AmountRow.Content(title: "Infirmier(e) de nuit", subtitle: "Clinique du Parc", montant: "1 234,56 €",
                                        approximatif: true, nature: "Net salarié estimé*", details: ["brut : 1 580,00 €"],
                                        footnote: "* Net salarié estimé après cotisations salariales (~22 %).", identifier: "revenus-mission-m1")
        XCTAssertEqual(salarie.displayedAmount, "~1 234,56 €", "Montant formaté par le cœur, jamais recalculé ici")
        let liberal = AmountRow.Content(title: "Mission", montant: "980,00 €", approximatif: false,
                                        nature: "Honoraires prévisionnels du planning", identifier: "revenus-mission-m2")
        XCTAssertEqual(liberal.displayedAmount, "980,00 €")
        let indisponible = AmountRow.Content(title: "Mission", montant: nil, approximatif: true, nature: nil, identifier: "m3")
        XCTAssertEqual(indisponible.displayedAmount, "—", "Sans montant serveur : tiret, jamais « ~— » ni 0 €")
        let vide = AmountRow.Content(title: "Mission", montant: "  ", approximatif: false, identifier: "m4")
        XCTAssertEqual(vide.displayedAmount, "—", "Un montant vide n'est pas un montant")
    }

    func testAmountRowVocaliseLeMontantSansSymboles() {
        // VoiceOver lirait « tilde » et « astérisque » : préfixe « environ », astérisque retiré du libellé de
        // nature, note de bas de page (texte web verbatim fourni par l'écran) lue en indice.
        let salarie = AmountRow.Content(title: "Infirmier(e) de nuit", subtitle: "Clinique du Parc", montant: "1 234,56 €",
                                        approximatif: true, nature: "Net salarié estimé*", details: ["brut : 1 580,00 €"],
                                        footnote: "* Net salarié estimé après cotisations salariales (~22 %).", identifier: "m1")
        XCTAssertEqual(salarie.spokenAmount, "environ 1 234,56 €")
        XCTAssertTrue(salarie.hasFootnoteMarker)
        XCTAssertEqual(salarie.spokenNature, "Net salarié estimé")
        XCTAssertEqual(salarie.accessibilityLabel,
                       "Infirmier(e) de nuit, Clinique du Parc, environ 1 234,56 €, Net salarié estimé, brut : 1 580,00 €")
        XCTAssertEqual(salarie.footnote, "* Net salarié estimé après cotisations salariales (~22 %).", "Affichée verbatim")
        XCTAssertEqual(salarie.accessibilityHint, "Net salarié estimé après cotisations salariales (environ 22 %).",
                       "Indice sans « astérisque » ni « tilde »")
        let liberal = AmountRow.Content(title: "Mission", montant: "980,00 €", approximatif: false,
                                        nature: "Honoraires prévisionnels du planning", identifier: "m2")
        XCTAssertFalse(liberal.hasFootnoteMarker)
        XCTAssertEqual(liberal.spokenNature, "Honoraires prévisionnels du planning")
        XCTAssertEqual(liberal.accessibilityLabel, "Mission, 980,00 €, Honoraires prévisionnels du planning")
        XCTAssertNil(liberal.accessibilityHint)
        let indisponible = AmountRow.Content(title: "Mission", montant: nil, approximatif: true, identifier: "m3")
        XCTAssertEqual(indisponible.spokenAmount, "Montant indisponible")
        XCTAssertEqual(indisponible.accessibilityLabel, "Mission, Montant indisponible")
        let etoileSeule = AmountRow.Content(title: "T", montant: "1 €", approximatif: false, nature: " * ", footnote: " ** ",
                                            identifier: "m5")
        XCTAssertNil(etoileSeule.spokenNature, "Un libellé réduit à l'astérisque n'est pas lu")
        XCTAssertNil(etoileSeule.accessibilityHint, "Une note réduite à l'astérisque n'est pas lue")
        // Règle de vocalisation commune au libellé de nature et à la note : marques « * » de tête et de fin
        // retirées, « ~ » lu « environ », texte affiché inchangé.
        XCTAssertEqual(AmountRow.spokenText("Net salarié estimé*"), "Net salarié estimé")
        XCTAssertEqual(AmountRow.spokenText("** Note"), "Note")
        XCTAssertEqual(AmountRow.spokenText("(~22 %)"), "(environ 22 %)")
        XCTAssertEqual(AmountRow.spokenText("~ 5 %"), "environ 5 %")
        XCTAssertEqual(AmountRow.spokenText("Sans symbole"), "Sans symbole")
        XCTAssertNil(AmountRow.spokenText(nil))
        XCTAssertNil(AmountRow.spokenText("  "))
    }

    func testAmountRowEncresEtDisposition() {
        // Montant `text-primary font-bold` : rose-800, seul rose ≥ 4,5:1 sur carte, écran et softGradient.
        XCTAssertEqual(AmountRow.amountInkHSL, JoleneColor.rose800HSL)
        for surface in JoleneColor.inheritedSurfacesHSL {
            let (clair, sombre) = Self.contrastes(AmountRow.amountInkHSL, sur: surface)
            XCTAssertGreaterThanOrEqual(clair, 4.5)
            XCTAssertGreaterThanOrEqual(sombre, 4.5)
        }
        XCTAssertEqual(AmountRow.titleInkHSL, JoleneColor.midnightHSL)
        XCTAssertEqual(AmountRow.secondaryInkHSL, JoleneColor.bubblegumHSL)
        for surface in Self.cartesEtEcrans {
            XCTAssertGreaterThanOrEqual(Self.contrastes(AmountRow.secondaryInkHSL, sur: surface).clair, 4.5)
            XCTAssertGreaterThanOrEqual(Self.contrastes(AmountRow.secondaryInkHSL, sur: surface).sombre, 4.5)
        }
        XCTAssertEqual(AmountRow.layout(for: .large), .horizontal)
        XCTAssertEqual(AmountRow.layout(for: .accessibility2), .vertical, "Montant jamais tronqué aux grandes tailles")
        XCTAssertNil(AmountRow.amountLineLimit, "Aucune limite de lignes sur un montant serveur")
    }

    // MARK: - StatusPill

    func testStatusPillTonsLisiblesEnClairEtEnSombre() {
        XCTAssertEqual(StatusPill.Tone.allCases, [.info, .success, .warning, .error, .neutral])
        for ton in StatusPill.Tone.allCases {
            let texte = Self.contrastes(ton.labelInkHSL, sur: ton.backgroundHSL)
            XCTAssertGreaterThanOrEqual(texte.clair, 4.5, "\(ton) : libellé, clair")
            XCTAssertGreaterThanOrEqual(texte.sombre, 4.5, "\(ton) : libellé, sombre")
            let icone = Self.contrastes(ton.iconInkHSL, sur: ton.backgroundHSL)
            XCTAssertGreaterThanOrEqual(icone.clair, 3, "\(ton) : icône, clair")
            XCTAssertGreaterThanOrEqual(icone.sombre, 3, "\(ton) : icône, sombre")
        }
        // Mêmes encres d'icône que InlineNotice (lot 1) pour les quatre tons communs.
        XCTAssertEqual(StatusPill.Tone.info.iconInkHSL, JoleneColor.mauve800HSL)
        XCTAssertEqual(StatusPill.Tone.success.iconInkHSL, JoleneColor.cyan900HSL)
        XCTAssertEqual(StatusPill.Tone.warning.iconInkHSL, JoleneColor.butter800HSL)
        XCTAssertEqual(StatusPill.Tone.error.iconInkHSL, JoleneColor.rose700HSL)
        XCTAssertEqual(StatusPill.Tone.neutral.backgroundHSL, JoleneColor.lavenderHSL)
    }

    func testStatusPillEcartsAuBadgeY2KDocumentes() throws {
        // BadgeY2K.tsx : info `bg-jolene-mauve-100 text-jolene-mauve-800`, success `…cyan-100 text-jolene-cyan-900`,
        // warning `…butter-100 text-jolene-butter-800`, tailles sm `text-[10px] px-2 py-0.5` / md `text-xs px-2.5 py-1`.
        let web = try Self.sourceWeb("src/components/y2k/BadgeY2K.tsx")
        XCTAssertTrue(web.contains("'bg-jolene-mauve-100 text-jolene-mauve-800'"))
        XCTAssertTrue(web.contains("'bg-jolene-cyan-100 text-jolene-cyan-900'"))
        XCTAssertTrue(web.contains("'bg-jolene-butter-100 text-jolene-butter-800'"))
        XCTAssertTrue(web.contains("sm: 'text-[10px] px-2 py-0.5'"))
        XCTAssertTrue(web.contains("md: 'text-xs px-2.5 py-1'"))
        XCTAssertTrue(web.contains("variant = 'info', size = 'md'"), "Défauts du web : info, md")
        XCTAssertEqual(StatusPill.Tone.info.labelInkHSL, JoleneColor.mauve800HSL)
        XCTAssertEqual(StatusPill.Tone.success.labelInkHSL, JoleneColor.cyan900HSL)
        XCTAssertEqual(StatusPill.Tone.info.backgroundHSL, JoleneColor.mauve100HSL)
        XCTAssertEqual(StatusPill.Tone.success.backgroundHSL, JoleneColor.cyan100HSL)
        XCTAssertEqual(StatusPill.Tone.warning.backgroundHSL, JoleneColor.butter100HSL)
        // Écart 1 : le libellé « warning » du web (butter-800 sur butter-100) fait 4,09:1 en clair, sous AA.
        XCTAssertEqual(Self.contrastes(JoleneColor.butter800HSL, sur: JoleneColor.butter100HSL).clair, 4.09, accuracy: 0.01)
        XCTAssertEqual(StatusPill.Tone.warning.labelInkHSL, JoleneColor.midnightHSL)
        // Écart 2 : erreur en rose (choix d'InlineNotice), libellé rose-800 (rose-700 : 3,54:1 sur rose-100).
        XCTAssertEqual(StatusPill.Tone.error.labelInkHSL, JoleneColor.rose800HSL)
        XCTAssertEqual(StatusPill.Tone.error.backgroundHSL, JoleneColor.rose100HSL)
        // Ton neutre (`text-muted-foreground bg-muted`, PaiementsEscrowAVenir.tsx) : bubblegum sur lavender.
        XCTAssertEqual(StatusPill.Tone.neutral.labelInkHSL, JoleneColor.bubblegumHSL)
        // Tailles : marges du web en points.
        XCTAssertEqual(StatusPill.Size.sm.horizontalPadding, 8)
        XCTAssertEqual(StatusPill.Size.sm.verticalPadding, 2)
        XCTAssertEqual(StatusPill.Size.md.horizontalPadding, 10)
        XCTAssertEqual(StatusPill.Size.md.verticalPadding, 4)
        XCTAssertEqual(StatusPill.defaultTone, .info)
        XCTAssertEqual(StatusPill.defaultSize, .md)
    }

    func testStatusPillCapsuleSurUneLigneRectangleArrondiAuDela() throws {
        // BadgeY2K garde le badge sur une ligne (`whitespace-nowrap`, `rounded-full`). Le natif ne tronque jamais
        // un libellé serveur : il passe à la ligne, et une capsule (rayon = demi-hauteur) rognerait alors les
        // lettres des lignes extrêmes. Capsule sur une ligne, rectangle arrondi à rayon fixe au-delà.
        let web = try Self.sourceWeb("src/components/y2k/BadgeY2K.tsx")
        XCTAssertTrue(web.contains("'inline-flex items-center gap-1 font-medium whitespace-nowrap'"))
        XCTAssertTrue(web.contains("admin ? 'rounded-md shadow-none' : 'rounded-full'"))
        XCTAssertEqual(StatusPill.outline(isMultiline: false), .capsule)
        XCTAssertEqual(StatusPill.outline(isMultiline: true), .rounded(cornerRadius: StatusPill.multilineCornerRadius))
        XCTAssertEqual(StatusPill.multilineCornerRadius, 8)
        // Un coin de rayon r ne découpe que la zone à moins de r des deux bords : avec r ≤ marge horizontale,
        // aucun glyphe (ni l'icône) n'est rogné, quelle que soit la taille.
        for taille in StatusPill.Size.allCases {
            XCTAssertLessThanOrEqual(StatusPill.multilineCornerRadius, taille.horizontalPadding, "\(taille)")
        }
    }

    func testStatusPillLibelleVerbatimEtIdentifiant() {
        // Le libellé arrive du cœur tel quel (ex. PaiementsEscrowAVenir.tsx : « Versement en cours — estimé le 05/11 ») ;
        // il est vocalisé seul, l'icône est décorative.
        let pastille = StatusPill.Presentation(label: "Versement en cours — estimé le 05/11", identifier: "escrow-etat-m1")
        XCTAssertEqual(pastille.accessibilityLabel, "Versement en cours — estimé le 05/11")
        XCTAssertEqual(pastille.identifier, "escrow-etat-m1")
        XCTAssertEqual(StatusPill.Presentation(label: "  Réservé ", identifier: nil).accessibilityLabel, "  Réservé ",
                       "Aucune normalisation : verbatim")
    }

    // MARK: - PermissionCard

    func testPermissionCardPushSoignantReprendDemandePermissionPushVerbatim() throws {
        // HARD STOP n°4 : textes du pré-prompt soignant relus dans DemandePermissionPush.tsx (TEXTES.soignant l.20-28,
        // note l.148-150, boutons l.158 et l.164) ; vouvoiement d'origine, aucune reformulation.
        let web = try Self.sourceWeb("src/components/DemandePermissionPush.tsx")
        let contenu = PermissionCard.Content.pushSoignant(identifier: "push-preprompt")
        XCTAssertEqual(contenu.title, "Recevoir les alertes missions ?")
        XCTAssertEqual(contenu.message, "Jolene vous envoie des notifications pour les nouvelles missions, les rappels de pointage et les mises à jour de vos contrats.")
        XCTAssertEqual(contenu.benefits, ["Nouvelles missions correspondant à votre profil", "Rappels de pointage avant vos missions",
                                          "Mises à jour de contrats et paiements"])
        XCTAssertEqual(contenu.footnote, "Vous pouvez désactiver les notifications à tout moment depuis les réglages de votre téléphone.")
        XCTAssertEqual(contenu.primaryTitle, "Activer les notifications")
        XCTAssertEqual(contenu.secondaryTitle, "Plus tard")
        XCTAssertEqual(contenu.systemImage, "bell", "Icône `Bell` de lucide")
        let soignant = try XCTUnwrap(web.range(of: "  soignant: {").map { web[$0.lowerBound...] })
        let finSoignant = try XCTUnwrap(soignant.range(of: "  etablissement: {"))
        let bloc = String(soignant[..<finSoignant.lowerBound])
        XCTAssertTrue(bloc.contains("titre: '\(contenu.title)',"))
        XCTAssertTrue(bloc.contains("description: '\(contenu.message)',"))
        for avantage in contenu.benefits { XCTAssertTrue(bloc.contains("'\(avantage)',"), avantage) }
        XCTAssertTrue(web.contains("\n              \(contenu.footnote ?? "")\n"), "Note sous les avantages")
        XCTAssertTrue(web.contains("\n              Plus tard\n"))
        XCTAssertTrue(web.contains("\n              Activer les notifications\n"))
        XCTAssertTrue(web.contains("<Bell className=\"h-6 w-6 text-primary\" />"))
    }

    func testPermissionCardIdentifiantsDerivesEtActionSecondaireOptionnelle() {
        let contenu = PermissionCard.Content.pushSoignant(identifier: "push-preprompt")
        XCTAssertEqual(contenu.identifier, "push-preprompt")
        XCTAssertEqual(contenu.titleIdentifier, "push-preprompt-title")
        XCTAssertEqual(contenu.messageIdentifier, "push-preprompt-message")
        XCTAssertEqual(contenu.benefitsIdentifier, "push-preprompt-benefits")
        XCTAssertEqual(contenu.footnoteIdentifier, "push-preprompt-footnote")
        // Contrat d'identifiants du pré-prompt T5 (blueprint §3 T5 : `push-preprompt-activer`, `push-preprompt-plus-tard`).
        XCTAssertEqual(contenu.primaryIdentifier, "push-preprompt-activer")
        XCTAssertEqual(contenu.secondaryIdentifier, "push-preprompt-plus-tard")
        XCTAssertEqual(contenu.benefitIdentifier(index: 0), "push-preprompt-benefit-1")
        XCTAssertEqual(contenu.benefitIdentifier(index: 2), "push-preprompt-benefit-3")
        // Sans surcharge : dérivation `<id>-primary` / `<id>-secondary`, qui suit l'identifiant racine.
        var generique = PermissionCard.Content(title: "T", message: "M", primaryTitle: "P", secondaryTitle: "S", identifier: "carte")
        XCTAssertEqual(generique.primaryIdentifier, "carte-primary")
        XCTAssertEqual(generique.secondaryIdentifier, "carte-secondary")
        generique.identifier = "autre"
        XCTAssertEqual(generique.primaryIdentifier, "autre-primary")
        generique.secondaryIdentifier = "autre-plus-tard"
        XCTAssertEqual(generique.secondaryIdentifier, "autre-plus-tard")
        XCTAssertEqual(generique.primaryIdentifier, "autre-primary", "Surcharger l'un ne touche pas l'autre")
        // Carte d'état d'autorisation (T4, `EtatNotificationsAppareilRow`, reprise par T6) : sans avantages, sans
        // action secondaire ; textes de l'appelant ; bouton `push-ouvrir-reglages` du blueprint (§3 T4).
        let etat = PermissionCard.Content(title: "Autorisation du téléphone", message: "Message serveur ou web verbatim.",
                                          primaryTitle: "Ouvrir les réglages", identifier: "push-etat-appareil",
                                          primaryIdentifier: "push-ouvrir-reglages")
        XCTAssertTrue(etat.benefits.isEmpty)
        XCTAssertNil(etat.footnote)
        XCTAssertNil(etat.secondaryTitle)
        XCTAssertEqual(etat.systemImage, "bell")
        XCTAssertEqual(etat.identifier, "push-etat-appareil")
        XCTAssertEqual(etat.primaryIdentifier, "push-ouvrir-reglages")
        XCTAssertEqual(etat.titleIdentifier, "push-etat-appareil-title", "Les autres identifiants restent dérivés")
        // Pas de double envoi : l'action principale est bloquée pendant l'appel (comme ConfirmationSheet).
        XCTAssertTrue(PermissionCard.isPrimaryEnabled(isLoading: false))
        XCTAssertFalse(PermissionCard.isPrimaryEnabled(isLoading: true))
        XCTAssertFalse(PermissionCard.isSecondaryEnabled(isLoading: true), "« Plus tard » attend aussi la fin de la demande système")
    }

    func testPermissionCardLargeurMaximaleDeLaCarteEntiere() throws {
        // Le web limite tout le dialogue (`sm:max-w-md`) : sur iPad, fond et arrondi sont bornés avec le contenu.
        let web = try Self.sourceWeb("src/components/DemandePermissionPush.tsx")
        XCTAssertTrue(web.contains("<DialogContent className=\"sm:max-w-md\">"))
        XCTAssertEqual(PermissionCard.maxWidth, 480)
    }

    func testPermissionCardEncresLisibles() {
        // Pastille d'icône (`bg-primary/10 text-primary`) : rose-700 sur rose-100, ≥ 3:1 (icône).
        let icone = Self.contrastes(PermissionCard.iconInkHSL, sur: PermissionCard.iconBackgroundHSL)
        XCTAssertGreaterThanOrEqual(icone.clair, 3)
        XCTAssertGreaterThanOrEqual(icone.sombre, 3)
        // Titre `midnight`, message et note `bubblegum` sur la carte `cloud` ; avantages sur l'encart `lavender`
        // (`bg-muted/50`) ; note en `bubblegum` plein (le `/70` du web passerait sous 4,5:1).
        XCTAssertEqual(PermissionCard.surfaceHSL, JoleneColor.cloudHSL)
        XCTAssertEqual(PermissionCard.benefitsSurfaceHSL, JoleneColor.lavenderHSL)
        for (encre, fond) in [(PermissionCard.titleInkHSL, PermissionCard.surfaceHSL),
                              (PermissionCard.secondaryInkHSL, PermissionCard.surfaceHSL),
                              (PermissionCard.secondaryInkHSL, PermissionCard.benefitsSurfaceHSL)] {
            let (clair, sombre) = Self.contrastes(encre, sur: fond)
            XCTAssertGreaterThanOrEqual(clair, 4.5)
            XCTAssertGreaterThanOrEqual(sombre, 4.5)
        }
        let coche = Self.contrastes(PermissionCard.benefitIconInkHSL, sur: PermissionCard.benefitsSurfaceHSL)
        XCTAssertGreaterThanOrEqual(coche.clair, 3)
        XCTAssertGreaterThanOrEqual(coche.sombre, 3)
    }

    // MARK: - PasswordCriteriaList

    func testPasswordCriteriaListLibellesVerbatimDeChangementMotDePasse() throws {
        // ChangementMotDePasse.tsx (JaugeForce l.210-233, `calculerForce` l.198-208) : six libellés de force,
        // cinq critères, « Force : ».
        let web = try Self.sourceWeb("src/components/soignant/ChangementMotDePasse.tsx")
        XCTAssertTrue(web.contains("const labels = ['Très faible', 'Faible', 'Moyen', 'Bon', 'Fort', 'Excellent'];"))
        XCTAssertEqual(PasswordCriteriaList.strengthLabels, ["Très faible", "Faible", "Moyen", "Bon", "Fort", "Excellent"])
        XCTAssertTrue(web.contains("Force : <strong>{labels[force.score]}</strong>"))
        XCTAssertEqual(PasswordCriteriaList.strengthPrefix, "Force : ")
        let criteres = PasswordCriteriaList.criteresWeb(longueur: true, majuscule: false, minuscule: true, chiffre: false, special: true)
        XCTAssertEqual(criteres.map(\.id), ["longueur", "majuscule", "minuscule", "chiffre", "special"], "Clés et ordre de `criteres` web")
        XCTAssertEqual(criteres.map(\.label), ["12 caractères minimum", "1 majuscule", "1 minuscule", "1 chiffre", "1 caractère spécial"])
        XCTAssertEqual(criteres.map(\.isMet), [true, false, true, false, true], "Valeurs calculées par le cœur, reprises telles quelles")
        for critere in criteres {
            XCTAssertTrue(web.contains("<Critere ok={force.criteres.\(critere.id)} label=\"\(critere.label)\" />"), critere.id)
        }
    }

    func testPasswordCriteriaListForceSuitLeNombreDeCriteresRemplis() {
        // `score = Object.values(criteres).filter(Boolean).length` ; couleurs destructive ×2, warning ×2, primary, success.
        let tons: [StatusPill.Tone] = [.error, .error, .warning, .warning, .info, .success]
        for score in 0...5 {
            let drapeaux = (0..<5).map { $0 < score }
            let criteres = PasswordCriteriaList.criteresWeb(longueur: drapeaux[0], majuscule: drapeaux[1], minuscule: drapeaux[2],
                                                            chiffre: drapeaux[3], special: drapeaux[4])
            let presentation = PasswordCriteriaList.Presentation.resolve(criteres)
            XCTAssertEqual(presentation.score, score)
            XCTAssertEqual(presentation.strengthLabel, PasswordCriteriaList.strengthLabels[score])
            XCTAssertEqual(presentation.strengthText, "Force : \(PasswordCriteriaList.strengthLabels[score])")
            XCTAssertEqual(presentation.progress, Double(score) / 5, accuracy: 0.0001, "`width: (score / 5) * 100 %`")
            XCTAssertEqual(presentation.tone, tons[score])
        }
        // Le score ne dépend que du nombre de critères remplis, pas de leur position.
        let melange = PasswordCriteriaList.criteresWeb(longueur: false, majuscule: true, minuscule: false, chiffre: true, special: false)
        XCTAssertEqual(PasswordCriteriaList.Presentation.resolve(melange).strengthLabel, "Moyen")
        // Liste vide (cas défensif) : aucune division par zéro, force « Très faible ».
        let vide = PasswordCriteriaList.Presentation.resolve([])
        XCTAssertEqual(vide.score, 0)
        XCTAssertEqual(vide.progress, 0)
        XCTAssertEqual(vide.strengthLabel, "Très faible")
        // Identifiants et libellés vocalisés.
        // T11 passe `compte-mdp` : ids `compte-mdp-critere-<cle>` du blueprint (§3 T11).
        XCTAssertEqual(PasswordCriteriaList.strengthIdentifier("compte-mdp"), "compte-mdp-force")
        XCTAssertEqual(PasswordCriteriaList.criterionIdentifier("compte-mdp", criterionID: "special"), "compte-mdp-critere-special")
        XCTAssertEqual(PasswordCriteriaList.criterionAccessibilityLabel(.init(id: "chiffre", label: "1 chiffre", isMet: true)),
                       "1 chiffre, critère rempli")
        XCTAssertEqual(PasswordCriteriaList.criterionAccessibilityLabel(.init(id: "chiffre", label: "1 chiffre", isMet: false)),
                       "1 chiffre, critère non rempli")
    }

    func testPasswordCriteriaListEncresLisibles() {
        // Critère rempli (`text-success`) en cyan-900, non rempli en bubblegum : ≥ 4,5:1 sur carte et écran.
        XCTAssertEqual(PasswordCriteriaList.metInkHSL, JoleneColor.cyan900HSL)
        XCTAssertEqual(PasswordCriteriaList.unmetInkHSL, JoleneColor.bubblegumHSL)
        for surface in Self.cartesEtEcrans {
            for encre in [PasswordCriteriaList.metInkHSL, PasswordCriteriaList.unmetInkHSL, PasswordCriteriaList.strengthInkHSL] {
                let (clair, sombre) = Self.contrastes(encre, sur: surface)
                XCTAssertGreaterThanOrEqual(clair, 4.5)
                XCTAssertGreaterThanOrEqual(sombre, 4.5)
            }
        }
        // Jauge : remplissage de chaque ton ≥ 3:1 sur la piste mauve-100 (la force est aussi écrite en toutes lettres).
        XCTAssertEqual(PasswordCriteriaList.trackHSL, JoleneColor.mauve100HSL)
        for ton in [StatusPill.Tone.error, .warning, .info, .success] {
            let (clair, sombre) = Self.contrastes(ton.iconInkHSL, sur: PasswordCriteriaList.trackHSL)
            XCTAssertGreaterThanOrEqual(clair, 3, "\(ton)")
            XCTAssertGreaterThanOrEqual(sombre, 3, "\(ton)")
        }
    }

    // MARK: - Rendu des vues (corps évalué, aucun piège) et cibles tactiles mesurées

    @MainActor
    func testLesVuesDuLot3SeRendentDansUnHebergeurUIKitEnClairEtEnSombre() {
        let options = [SegmentedChoice.Option(id: "systeme", title: "Système"), SegmentedChoice.Option(id: "clair", title: "Clair"),
                       SegmentedChoice.Option(id: "sombre", title: "Sombre", systemImage: "moon")]
        let montant = AmountRow.Content(title: "Infirmier(e) de nuit — une mission au libellé très long pour forcer le retour à la ligne",
                                        subtitle: "Clinique du Parc", montant: "12 345,67 €", approximatif: true,
                                        nature: "Net salarié estimé*", details: ["brut : 15 800,00 €"],
                                        footnote: "* Net salarié estimé après cotisations salariales (~22 %).", identifier: "amount")
        let criteres = PasswordCriteriaList.criteresWeb(longueur: true, majuscule: true, minuscule: false, chiffre: false, special: false)
        let vues: [(String, AnyView)] = [
            ("interrupteur", AnyView(ToggleRow("Email", systemImage: "envelope", isOn: .constant(true), identifier: "canal-email"))),
            ("interrupteur bloqué", AnyView(ToggleRow("Rappel mission J-1", description: "Rappel la veille du début de mission",
                                                      isOn: .constant(false), isDisabled: true,
                                                      disabledReason: "Canal SMS désactivé dans les canaux globaux",
                                                      isBordered: false, identifier: "evt-rappel-sms"))),
            ("choix segmenté", AnyView(SegmentedChoice("Thème", options: options, selection: .constant("clair"), identifier: "theme"))),
            ("choix segmenté hors liste", AnyView(SegmentedChoice("Thème", options: options, selection: .constant("x"), identifier: "t2"))),
            ("avatar initiales", AnyView(AvatarView(prenom: "Camille", nom: "Martin", identifier: "avatar"))),
            ("avatar grand en chargement", AnyView(AvatarView(prenom: nil, nom: nil, size: 96, rounding: .large, isLoading: true))),
            ("avatar image", AnyView(AvatarView(image: Image(systemName: "person.crop.circle"), prenom: "Camille", nom: "Martin", size: 64))),
            ("montant", AnyView(AmountRow(montant))),
            ("montant indisponible", AnyView(AmountRow(.init(title: "Mission", montant: nil, approximatif: false, identifier: "a2")))),
            ("pastilles", AnyView(VStack {
                ForEach(StatusPill.Tone.allCases, id: \.self) { ton in
                    StatusPill("Paiement retardé", tone: ton, systemImage: "exclamationmark.triangle", identifier: "pill-\(ton)")
                }
                StatusPill("Réservé", size: .sm)
                StatusPill("Versement en cours — estimé le 05/11, après validation des présences par l'établissement",
                           tone: .neutral, systemImage: "clock", size: .sm, identifier: "pill-longue")
            })),
            ("pré-prompt", AnyView(PermissionCard(.pushSoignant(identifier: "push-preprompt"), onPrimary: {}, onSecondary: {}))),
            ("pré-prompt en cours", AnyView(PermissionCard(.pushSoignant(identifier: "push-preprompt"), isLoading: true,
                                                           onPrimary: {}, onSecondary: {}))),
            ("carte d'état", AnyView(PermissionCard(.init(title: "Autorisation du téléphone", message: "Message.",
                                                          primaryTitle: "Ouvrir les réglages", identifier: "push-etat-appareil",
                                                          primaryIdentifier: "push-ouvrir-reglages"), onPrimary: {}))),
            ("critères", AnyView(PasswordCriteriaList(criteria: criteres, identifier: "mdp"))),
            ("critères vides", AnyView(PasswordCriteriaList(criteria: [], identifier: "mdp-vide"))),
        ]
        for (nom, vue) in vues {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for taille in [DynamicTypeSize.large, .accessibility5] {
                    let hote = UIHostingController(rootView: AnyView(vue.environment(\.dynamicTypeSize, taille)))
                    hote.overrideUserInterfaceStyle = style
                    let mesure = hote.sizeThatFits(in: CGSize(width: 390, height: 2000))
                    XCTAssertTrue(mesure.width.isFinite && mesure.height.isFinite, "\(nom) (\(style.rawValue), \(taille)) : taille finie")
                    XCTAssertGreaterThan(mesure.width, 0, "\(nom) : largeur non nulle")
                    XCTAssertGreaterThan(mesure.height, 0, "\(nom) : hauteur non nulle")
                    hote.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                    hote.view.layoutIfNeeded()
                }
            }
        }
    }

    @MainActor
    func testCiblesTactilesMesureesAuMoins44Points() {
        // Mesure de la vue elle-même (et non d'un conteneur) : la ligne d'interrupteur et UN segment seul,
        // dont le cadre minimal est posé dans le label du bouton (zone de tap réelle).
        func hauteur(_ vue: some View) -> CGFloat {
            UIHostingController(rootView: vue).sizeThatFits(in: CGSize(width: 390, height: 2000)).height
        }
        XCTAssertGreaterThanOrEqual(hauteur(ToggleRow("Email", isOn: .constant(true), isBordered: false, identifier: "t")), 44)
        XCTAssertGreaterThanOrEqual(hauteur(ToggleRow("Email", isOn: .constant(true), identifier: "t")), 44)
        let segment = SegmentedChoice.Segment(option: .init(id: "clair", title: "Clair"), isSelected: false, identifier: "s-clair") {}
        XCTAssertGreaterThanOrEqual(hauteur(segment), 44)
        let segmentLargeur = UIHostingController(rootView: segment).sizeThatFits(in: CGSize(width: 390, height: 2000)).width
        XCTAssertGreaterThanOrEqual(segmentLargeur, 44, "Un segment court (« Clair ») garde 44 pt de large")
        XCTAssertGreaterThanOrEqual(hauteur(SegmentedChoice.Segment(option: .init(id: "sombre", title: "Sombre"), isSelected: true,
                                                                    identifier: "s-sombre") {}), 44)
    }

    @MainActor
    func testStatusPillLonguePasseALaLigneSansDepasserLaLargeurProposee() {
        // Libellé serveur trop long pour une ligne : la pastille passe à la ligne (rectangle arrondi), sans
        // tronquer ni déborder de la largeur proposée ; un libellé court reste sur une ligne.
        func taille(_ vue: some View, largeur: CGFloat) -> CGSize {
            UIHostingController(rootView: vue).sizeThatFits(in: CGSize(width: largeur, height: 2000))
        }
        let longue = StatusPill("Versement en cours — estimé le 05/11, après validation des présences par l'établissement")
        let courte = StatusPill("Réservé")
        let etroite = taille(longue, largeur: 200)
        XCTAssertLessThanOrEqual(etroite.width, 200, "Jamais plus large que la place proposée")
        XCTAssertGreaterThan(etroite.height, taille(courte, largeur: 200).height * 1.5, "Plusieurs lignes, rien de tronqué")
        XCTAssertEqual(taille(courte, largeur: 200).height, taille(courte, largeur: 390).height, accuracy: 0.5,
                       "Un libellé court garde une seule ligne")
    }
}
