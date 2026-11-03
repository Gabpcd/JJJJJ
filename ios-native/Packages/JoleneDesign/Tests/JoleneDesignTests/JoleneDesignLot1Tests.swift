import XCTest
import SwiftUI
import UIKit
import JoleneCore
@testable import JoleneDesign

/// Écarts assumés du lot 0 entre les jetons rendus et `src/index.css` (`.dark`), relevés par la garde de
/// dérive (revue B8 n°2) : fonds et texte secondaire en mode sombre. Ils ne sont pas alignés dans T1b
/// (changement de la hiérarchie fond / carte de tous les écrans du lot 0 en sombre, à décider avec un
/// contrôle visuel) ; les contrastes sont vérifiés sur les deux valeurs.
enum EcartsSombresLot0 {
    static let table: [String: (rendu: JoleneHSL, web: JoleneHSL)] = [
        "jolene-lavender": (JoleneHSL(268, 38, 10), JoleneHSL(270, 25, 16)),
        "jolene-cloud": (JoleneHSL(268, 30, 14), JoleneHSL(268, 25, 12)),
        "jolene-bubblegum": (JoleneHSL(271, 20, 72), JoleneHSL(271, 15, 68)),
    ]
    static let fondsWeb = [JoleneHSL(270, 25, 16), JoleneHSL(268, 25, 12)]
    static let bubblegumWeb = JoleneHSL(271, 15, 68)
}

/// Lot 1 (T1b) : règles pures des nouveaux composants. Chaque composant expose la partie
/// calculable (identifiants, libellés d'accessibilité, correspondances de style, contrastes)
/// pour qu'elle soit vérifiée sans XCUITest. Le dernier cas évalue le corps de chaque vue dans un
/// `UIHostingController` à 390 pt (taille finie, largeur non nulle, aucun piège à l'exécution) ;
/// seules la bascule de `StickyActionBar` (taille standard et accessibility5) et la hauteur de
/// `SectionHeader` y sont mesurées. Le parcours visible reste couvert par les XCUITest démo des
/// écrans qui montent ces composants.
final class JoleneDesignLot1Tests: XCTestCase {
    // MARK: - Contraste (WCAG 2.x)

    func testContrasteSuitLesValeursDeReferenceWCAG() {
        let blanc = JoleneHex(red: 1, green: 1, blue: 1)
        let noir = JoleneHex(red: 0, green: 0, blue: 0)
        XCTAssertEqual(blanc.contrastRatio(with: noir), 21, accuracy: 0.001)
        XCTAssertEqual(noir.contrastRatio(with: blanc), 21, accuracy: 0.001, "Le rapport est symétrique")
        XCTAssertEqual(blanc.contrastRatio(with: blanc), 1, accuracy: 0.001)
        XCTAssertEqual(blanc.relativeLuminance, 1, accuracy: 0.0001)
        XCTAssertEqual(noir.relativeLuminance, 0, accuracy: 0.0001)
        // #777777 : valeur de référence classique, 4,48:1 sur blanc (juste sous le seuil AA).
        let gris = JoleneHex.parse("#777777")!
        XCTAssertEqual(gris.contrastRatio(with: blanc), 4.48, accuracy: 0.01)
    }

    // MARK: - JoleneButton.destructive

    func testDestructiveStyleReproduitBoutonY2KAvecUnTexteLisible() {
        // src/components/y2k/BoutonY2K.tsx (variant destructive) : `from-[#FF4D6B] to-[#FF6BBE]`, `text-[#2b183d]`.
        XCTAssertEqual(JoleneColor.destructiveGradientHex, ["#FF4D6B", "#FF6BBE"])
        XCTAssertEqual(JoleneColor.onGradientHex, "#2B183D")
        let debut = JoleneHex.parse(JoleneColor.destructiveGradientHex[0])!
        let fin = JoleneHex.parse(JoleneColor.destructiveGradientHex[1])!
        XCTAssertEqual(debut, JoleneHex(red: 1, green: 77 / 255, blue: 107 / 255))
        XCTAssertEqual(fin, JoleneHex(red: 1, green: 107 / 255, blue: 190 / 255))
        // Texte sombre ≥ 4,5:1 (AA) sur les deux extrémités ; le blanc n'atteindrait que ~3,2:1.
        let texte = JoleneHex.parse(JoleneColor.onGradientHex)!
        for stop in [debut, fin] {
            XCTAssertGreaterThanOrEqual(texte.contrastRatio(with: stop), 4.5)
        }
        XCTAssertLessThan(JoleneHex(red: 1, green: 1, blue: 1).contrastRatio(with: debut), 4.5,
                          "Le texte blanc du primaire ne convient pas au dégradé destructif")
        XCTAssertTrue(JoleneButton.Style.destructive.isFilled)
        XCTAssertTrue(JoleneButton.Style.destructive.usesDarkTextOnFill)
        // Revue B8 : le primaire passe lui aussi au texte sombre (BoutonY2K primary `text-[#2b183d]`,
        // `.bg-gradient-hero { color: #2b183d }`) ; le secondaire reste en bordure rose.
        XCTAssertTrue(JoleneButton.Style.primary.isFilled)
        XCTAssertTrue(JoleneButton.Style.primary.usesDarkTextOnFill)
        XCTAssertFalse(JoleneButton.Style.secondary.isFilled)
        XCTAssertFalse(JoleneButton.Style.secondary.usesDarkTextOnFill)
        XCTAssertEqual(JoleneButton.Style.allCases.count, 3)
    }

    func testToutBoutonPleinPorteLeTexteSombreAASurChaqueArretDeSonDegrade() {
        // Revue B8 (majeur) : le texte blanc du primaire plafonnait à 2,59:1 sur le rose et 2,78:1 sur
        // le mauve (#B57EFF : 2,84:1), sous le seuil AA (4,5:1) et même sous 3:1. Règle unique : tout
        // style plein utilise `JoleneColor.onGradient`, vérifié sur chaque arrêt, en clair ET en sombre.
        XCTAssertEqual(JoleneColor.roseHSL, JoleneDynamicHSL(light: JoleneHSL(326, 100, 71), dark: JoleneHSL(326, 90, 65)))
        XCTAssertEqual(JoleneColor.mauveHSL, JoleneDynamicHSL(light: JoleneHSL(267, 100, 75), dark: JoleneHSL(267, 85, 70)))
        XCTAssertEqual(JoleneColor.heroGradientStops, [JoleneColor.roseHSL, JoleneColor.mauveHSL])
        let texte = JoleneHex.parse(JoleneColor.onGradientHex)!
        for style in JoleneButton.Style.allCases {
            XCTAssertEqual(style.usesDarkTextOnFill, style.isFilled, "\(style) : texte sombre si et seulement si plein")
            for arret in style.fillStops {
                XCTAssertGreaterThanOrEqual(texte.contrastRatio(with: arret), 4.5, "\(style) sur \(arret)")
            }
        }
        XCTAssertEqual(JoleneButton.Style.primary.fillStops,
                       [JoleneColor.roseHSL.light.rgb, JoleneColor.roseHSL.dark.rgb,
                        JoleneColor.mauveHSL.light.rgb, JoleneColor.mauveHSL.dark.rgb],
                       "Primaire : rose et mauve du dégradé hero, clair et sombre")
        XCTAssertEqual(JoleneButton.Style.destructive.fillStops,
                       JoleneColor.destructiveGradientHex.compactMap(JoleneHex.parse))
        XCTAssertTrue(JoleneButton.Style.secondary.fillStops.isEmpty, "Secondaire : surface claire, pas de dégradé")
        // Valeurs relevées avant correction (texte blanc du lot 0).
        let blanc = JoleneHex(red: 1, green: 1, blue: 1)
        XCTAssertEqual(blanc.contrastRatio(with: JoleneColor.roseHSL.light.rgb), 2.59, accuracy: 0.01)
        XCTAssertEqual(blanc.contrastRatio(with: JoleneColor.mauveHSL.light.rgb), 2.78, accuracy: 0.01)
        XCTAssertEqual(blanc.contrastRatio(with: JoleneHex.parse("#B57EFF")!), 2.84, accuracy: 0.01)
    }

    // MARK: - ConfirmationSheet

    func testConfirmationSheetReprendLesDefautsDeModalConfirmation() {
        // src/components/ModalConfirmation.tsx : labelConfirmer 'Confirmer', labelAnnuler 'Annuler', variante 'primaire'.
        let config = ConfirmationSheet.Configuration(title: "Retirer la candidature ?",
                                                     message: "Cette action est définitive.",
                                                     identifier: "candidature-retrait")
        XCTAssertEqual(config.confirmTitle, "Confirmer")
        XCTAssertEqual(config.cancelTitle, "Annuler")
        XCTAssertEqual(config.variant, .primary)
        XCTAssertEqual(config.confirmButtonStyle, .primary)
        XCTAssertNil(config.requiredPhrase)
        XCTAssertNil(config.resolvedPhrasePrompt, "Sans phrase exigée, aucun champ de saisie")
        // Identifiants dérivés : un XCUITest atteint chaque contrôle sans lire le libellé.
        XCTAssertEqual(config.titleIdentifier, "candidature-retrait-title")
        XCTAssertEqual(config.messageIdentifier, "candidature-retrait-message")
        XCTAssertEqual(config.inputIdentifier, "candidature-retrait-input")
        XCTAssertEqual(config.confirmIdentifier, "candidature-retrait-confirm")
        XCTAssertEqual(config.cancelIdentifier, "candidature-retrait-cancel")
    }

    func testConfirmationSheetDangerUtiliseLeStyleDestructifEtBloqueLaFermeturePendantLeChargement() {
        var config = ConfirmationSheet.Configuration(title: "Annuler la mission ?", message: "Un justificatif est requis.",
                                                     identifier: "mission-annulation")
        config.variant = .danger
        config.confirmTitle = "Annuler la mission"
        XCTAssertEqual(config.confirmButtonStyle, .destructive)
        XCTAssertEqual(config.confirmTitle, "Annuler la mission")
        // RecapitulatifCandidatureDialog : `if (!open && !chargement) onFermer()` — pas de fermeture pendant l'appel.
        XCTAssertTrue(ConfirmationSheet.Configuration.canDismiss(isLoading: false))
        XCTAssertFalse(ConfirmationSheet.Configuration.canDismiss(isLoading: true))
        // RecapitulatifCandidatureDialog : `disabled={chargement || !planning.exact}`.
        XCTAssertTrue(config.canConfirm(isLoading: false, isConfirmEnabled: true, typedPhrase: ""))
        XCTAssertFalse(config.canConfirm(isLoading: true, isConfirmEnabled: true, typedPhrase: ""))
        XCTAssertFalse(config.canConfirm(isLoading: false, isConfirmEnabled: false, typedPhrase: ""))
    }

    func testConfirmationSheetExigeLaPhraseExacteCommeLaSuppressionDeCompteWeb() {
        // SectionConfidentialite.tsx l.192 : `disabled={deleteConfirmText !== 'SUPPRIMER' || deleteLoading}` —
        // égalité stricte, sans normalisation de casse ni d'espaces.
        let config = ConfirmationSheet.Configuration(title: "Supprimer mon compte", message: "Texte serveur verbatim.",
                                                     variant: .danger, identifier: "compte-supprimer",
                                                     requiredPhrase: "SUPPRIMER")
        XCTAssertEqual(config.resolvedPhrasePrompt, "Saisissez SUPPRIMER pour confirmer")
        XCTAssertTrue(config.canConfirm(isLoading: false, isConfirmEnabled: true, typedPhrase: "SUPPRIMER"))
        for saisie in ["", "supprimer", "Supprimer", " SUPPRIMER", "SUPPRIMER ", "SUPPRIME"] {
            XCTAssertFalse(config.canConfirm(isLoading: false, isConfirmEnabled: true, typedPhrase: saisie), "« \(saisie) » refusé")
        }
        XCTAssertFalse(config.canConfirm(isLoading: true, isConfirmEnabled: true, typedPhrase: "SUPPRIMER"),
                       "Pas de double envoi pendant l'appel")
        let libelle = ConfirmationSheet.Configuration(title: "T", message: "M", identifier: "x",
                                                      requiredPhrase: "SUPPRIMER", phrasePrompt: "Tapez SUPPRIMER")
        XCTAssertEqual(libelle.resolvedPhrasePrompt, "Tapez SUPPRIMER", "Libellé fourni par l'écran, repris tel quel")
    }

    func testConfirmationSheetLibelleEtExempleDeSaisieViennentDeLAppelant() {
        // Revue B8 n°2 : l'exemple de saisie (placeholder) valait la phrase, sans paramètre. Défauts vouvoyés
        // réservés aux confirmations non juridiques ; la suppression de compte (T8, HARD STOP n°4) passe le texte
        // RGPD du web tel quel, en tutoiement : SectionConfidentialite.tsx l.171-172 « Tape SUPPRIMER pour
        // confirmer », l.178 placeholder « Tape SUPPRIMER ».
        let defaut = ConfirmationSheet.Configuration(title: "T", message: "M", identifier: "x", requiredPhrase: "SUPPRIMER")
        XCTAssertEqual(defaut.resolvedPhrasePrompt, "Saisissez SUPPRIMER pour confirmer")
        XCTAssertEqual(defaut.resolvedPhrasePlaceholder, "SUPPRIMER", "Par défaut, l'exemple est la phrase exigée")
        XCTAssertNil(ConfirmationSheet.Configuration(title: "T", message: "M", identifier: "x").resolvedPhrasePlaceholder,
                     "Sans phrase exigée, aucun champ")
        let web = ConfirmationSheet.Configuration(title: "Supprimer mon compte", message: "Texte RGPD verbatim.", variant: .danger,
                                                  identifier: "compte-supprimer", requiredPhrase: "SUPPRIMER",
                                                  phrasePrompt: "Tape SUPPRIMER pour confirmer", phrasePlaceholder: "Tape SUPPRIMER")
        XCTAssertEqual(web.resolvedPhrasePrompt, "Tape SUPPRIMER pour confirmer")
        XCTAssertEqual(web.resolvedPhrasePlaceholder, "Tape SUPPRIMER")
        XCTAssertTrue(web.canConfirm(isLoading: false, isConfirmEnabled: true, typedPhrase: "SUPPRIMER"))
        XCTAssertFalse(web.canConfirm(isLoading: false, isConfirmEnabled: true, typedPhrase: "Tape SUPPRIMER"),
                       "L'exemple de saisie n'est jamais la valeur attendue")
    }

    func testConfirmationSheetFermetureDemandeeIgnoreePendantLeChargement() {
        // Garde unique, partagée par les deux variantes du modificateur (avec ou sans contenu `extra`).
        var fermee = false
        ConfirmationSheet.requestDismiss(isLoading: true) { fermee = true }
        XCTAssertFalse(fermee, "Pas de fermeture pendant l'appel serveur")
        ConfirmationSheet.requestDismiss(isLoading: false) { fermee = true }
        XCTAssertTrue(fermee)
    }

    // MARK: - FilterChip

    func testFilterChipExposeSonEtatParLeSeulTraitSelectionneEtResteLisibleActif() {
        // RechercheMissions.tsx : `aria-pressed={chip.actif}`, actif = `bg-gradient-hero`.
        // Revue B8 : un seul mécanisme vocalisé (trait `.isSelected`, « Sélectionné ») ; plus de valeur
        // « activé / désactivé » (double annonce, « désactivé » confondu avec un contrôle indisponible).
        let actif = FilterChip.Appearance.resolve(isSelected: true)
        XCTAssertTrue(actif.usesGradient)
        XCTAssertTrue(actif.announcesSelected)
        XCTAssertEqual(actif.accessibilityHint, "Retire ce filtre")
        XCTAssertEqual(actif.foregroundHex, JoleneColor.onGradientHex)
        let inactif = FilterChip.Appearance.resolve(isSelected: false)
        XCTAssertFalse(inactif.usesGradient)
        XCTAssertFalse(inactif.announcesSelected)
        XCTAssertEqual(inactif.accessibilityHint, "Applique ce filtre")
        XCTAssertNil(inactif.foregroundHex, "Inactif : jeton dynamique bubblegum")
        XCTAssertEqual(FilterChip.minimumHeight, 44, "Cible tactile 44 pt (min-h-[44px] du web)")
        // `.bg-gradient-hero` web : trois arrêts rose → mauve → cyan (jeton `heroGradientFull`), encre
        // `#2b183d` du même jeton (src/index.css), qui l'emporte sur le `text-white` des chips.
        XCTAssertEqual(JoleneColor.cyanHSL, JoleneDynamicHSL(light: JoleneHSL(192, 100, 72), dark: JoleneHSL(192, 90, 68)))
        XCTAssertEqual(JoleneColor.heroGradientFullStops, [JoleneColor.roseHSL, JoleneColor.mauveHSL, JoleneColor.cyanHSL])
        XCTAssertEqual(FilterChip.activeGradientStops, JoleneColor.heroGradientFullStops)
        // Texte d'une pastille active ≥ 4,5:1 sur chaque arrêt, en clair et en sombre.
        let texte = JoleneHex.parse(JoleneColor.onGradientHex)!
        for arret in FilterChip.activeGradientStops {
            XCTAssertGreaterThanOrEqual(texte.contrastRatio(with: arret.light.rgb), 4.5, "\(arret.light)")
            XCTAssertGreaterThanOrEqual(texte.contrastRatio(with: arret.dark.rgb), 4.5, "\(arret.dark)")
        }
        XCTAssertLessThan(JoleneHex(red: 1, green: 1, blue: 1).contrastRatio(with: JoleneColor.roseHSL.light.rgb), 4.5)
    }

    func testFilterChipNeVocalisePasLEmojiDecoratif() {
        // Libellés web « 🔥 Urgentes / 📅 Week-end / 🌙 Nuit / ☀️ Jour » : l'emoji reste affiché,
        // VoiceOver lit le seul mot (sinon « feu, Urgentes »).
        XCTAssertEqual(FilterChip.spokenLabel("🔥 Urgentes"), "Urgentes")
        XCTAssertEqual(FilterChip.spokenLabel("📅 Week-end"), "Week-end")
        XCTAssertEqual(FilterChip.spokenLabel("🌙 Nuit"), "Nuit")
        XCTAssertEqual(FilterChip.spokenLabel("☀️ Jour"), "Jour", "Emoji texte + sélecteur de variation U+FE0F")
        XCTAssertEqual(FilterChip.spokenLabel("Urgentes"), "Urgentes")
        XCTAssertEqual(FilterChip.spokenLabel("24 h max"), "24 h max", "Les chiffres ne sont pas des emoji décoratifs")
        XCTAssertEqual(FilterChip.spokenLabel("🔥"), "🔥", "Un libellé réduit à l'emoji est conservé, jamais vide")
    }

    // MARK: - SlotList

    func testSlotListGardeLesIdentifiantsDuDetailMissionDuLot0() {
        // MissionDetailScreen (lot 0) + DemoConsultationTests l.96-102 : conteneur `mission-detail-creneaux`,
        // lignes `mission-detail-creneau-<index + 1>`. Le préfixe par défaut retire le suffixe « -creneaux ».
        XCTAssertEqual(SlotList.itemPrefix(for: "mission-detail-creneaux"), "mission-detail")
        XCTAssertEqual(SlotList.itemPrefix(for: "candidature-recap"), "candidature-recap")
        XCTAssertEqual(SlotList.identifier(prefix: SlotList.itemPrefix(for: "mission-detail-creneaux"), index: 0),
                       "mission-detail-creneau-1")
        XCTAssertEqual(SlotList.identifier(prefix: "candidature-recap", index: 11), "candidature-recap-creneau-12")
        XCTAssertEqual(SlotList.resume(count: 0), "Aucun créneau")
        XCTAssertEqual(SlotList.resume(count: 1), "1 créneau")
        XCTAssertEqual(SlotList.resume(count: 3), "3 créneaux")
    }

    func testSlotListFormateLesCreneauxParLeCoeurEtDistingueLesPauses() {
        // Le libellé vient de `MissionPresentation.creneau` (cœur), jamais recalculé dans le composant.
        let travail = MissionSlot(debut: "2026-11-03T07:00:00+00:00", fin: "2026-11-03T11:00:00+00:00", estPause: false, typeCreneau: "PREVISIONNEL")
        let pause = MissionSlot(debut: "2026-11-03T11:00:00+00:00", fin: "2026-11-03T11:30:00+00:00", estPause: true, typeCreneau: "PREVISIONNEL")
        let items = SlotList.items([travail, pause])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].label, MissionPresentation.creneau(travail))
        XCTAssertEqual(items[0].label, "Mardi 3 novembre · 08:00–12:00", "Heure de Paris (UTC+1 en novembre)")
        XCTAssertFalse(items[0].isPause)
        XCTAssertEqual(items[0].systemImage, "clock")
        XCTAssertEqual(items[0].accessibilityLabel, "Créneau : \(MissionPresentation.creneau(travail))")
        XCTAssertTrue(items[1].isPause)
        XCTAssertEqual(items[1].systemImage, "cup.and.saucer")
        XCTAssertTrue(items[1].label.hasPrefix("Pause · "), "Le préfixe « Pause · » est celui du cœur")
        XCTAssertEqual(items[1].accessibilityLabel, "Pause : \(MissionPresentation.creneau(pause))")
        // Identifiants stables même pour deux créneaux au libellé identique.
        XCTAssertEqual(SlotList.items([travail, travail]).map(\.id), ["creneau-1", "creneau-2"])
    }

    func testSlotListLimiteEtResumeCommePlanningMissionCandidat() {
        // PlanningMissionCandidat.tsx : `slice(0, limite)` puis « + N autre(s) créneau(x) dans le récapitulatif complet ».
        let slots = (1...5).map { jour in
            MissionSlot(debut: "2026-11-0\(jour)T07:00:00Z", fin: "2026-11-0\(jour)T15:00:00Z", estPause: false, typeCreneau: "PREVISIONNEL")
        }
        let limitee = SlotList.Presentation(items: SlotList.items(slots), limit: 2)
        XCTAssertEqual(limitee.visibleItems.map(\.id), ["creneau-1", "creneau-2"])
        XCTAssertEqual(limitee.hiddenCount, 3)
        XCTAssertEqual(limitee.remainingText, "+ 3 autres créneaux dans le récapitulatif complet")
        XCTAssertEqual(SlotList.Presentation(items: SlotList.items(slots), limit: 4).remainingText,
                       "+ 1 autre créneau dans le récapitulatif complet")
        let complete = SlotList.Presentation(items: SlotList.items(slots))
        XCTAssertEqual(complete.visibleItems.count, 5)
        XCTAssertEqual(complete.hiddenCount, 0)
        XCTAssertNil(complete.remainingText)
        XCTAssertEqual(SlotList.Presentation(items: SlotList.items(slots), limit: -1).visibleItems.count, 0,
                       "Une limite négative est ramenée à zéro, jamais interprétée comme « tout sauf le dernier »")
        // Revue B8 n°2 : `formatHeures` web (toLocaleString fr-FR, 2 décimales) vit dans le cœur, règle unique
        // (`MissionPresentation.heuresPlanning`, vecteurs Node dans JoleneCoreTests) ; le composant l'appelle.
        XCTAssertEqual(SlotList.resume(count: 3, totalHeures: 21), "3 créneaux · 21 h au total")
        XCTAssertEqual(SlotList.resume(count: 1, totalHeures: 7.5), "1 créneau · 7,5 h au total")
        for total in [0, 7 + 20.0 / 60, 1234.5, 2.675] {
            XCTAssertEqual(SlotList.resume(count: 2, totalHeures: total),
                           "2 créneaux · \(MissionPresentation.heuresPlanning(total)) h au total")
        }
    }

    func testSlotListDepuisLePlanningCandidatBloqueOuExact() {
        // Planning non exact : encart « Planning exact à confirmer » + message de blocage du cœur, aucune ligne.
        let bloque = PlanningCandidat(creneaux: [], exact: false, totalHeures: 0, periodeEtendue: false,
                                      messageBlocage: PlanningCandidatRules.messagePlanningIncomplet)
        let presentationBloquee = SlotList.Presentation.planning(bloque, libelle: MissionPresentation.creneau)
        XCTAssertEqual(presentationBloquee.blocked,
                       SlotList.Presentation.Blocked(title: "Planning exact à confirmer",
                                                     message: PlanningCandidatRules.messagePlanningIncomplet))
        XCTAssertTrue(presentationBloquee.visibleItems.isEmpty)
        XCTAssertNil(presentationBloquee.resume)
        // Planning exact sur deux jours : résumé accordé, lignes du cœur, mention des jours non travaillés.
        let lundi = MissionSlot(id: "c1", debut: "2026-11-02T07:00:00Z", fin: "2026-11-02T15:00:00Z", estPause: false, typeCreneau: "PREVISIONNEL")
        let mardi = MissionSlot(id: "c2", debut: "2026-11-03T07:00:00Z", fin: "2026-11-03T16:30:00Z", estPause: false, typeCreneau: "PREVISIONNEL")
        let exact = PlanningCandidat(creneaux: [lundi, mardi], exact: true, totalHeures: 17.5, periodeEtendue: true, messageBlocage: nil)
        let presentation = SlotList.Presentation.planning(exact, libelle: MissionPresentation.creneau, limit: 1)
        XCTAssertNil(presentation.blocked)
        XCTAssertEqual(presentation.resume, "2 créneaux · 17,5 h au total")
        XCTAssertEqual(presentation.visibleItems.map(\.label), [MissionPresentation.creneau(lundi)])
        XCTAssertEqual(presentation.remainingText, "+ 1 autre créneau dans le récapitulatif complet")
        XCTAssertEqual(presentation.footnote,
                       "Seuls les créneaux listés sont travaillés. Les autres jours de la période ne sont pas travaillés.")
        XCTAssertNil(SlotList.Presentation.planning(exact, libelle: MissionPresentation.creneau,
                                                    mentionJoursNonTravailles: false).footnote)
        let ponctuel = PlanningCandidat(creneaux: [lundi], exact: true, totalHeures: 8, periodeEtendue: false, messageBlocage: nil)
        XCTAssertNil(SlotList.Presentation.planning(ponctuel, libelle: MissionPresentation.creneau).footnote,
                     "Mention réservée à une période étendue")
        // Planning non exact sans message (cas défensif) : message d'incomplétude du cœur, jamais un encart vide.
        let sansMessage = PlanningCandidat(creneaux: [], exact: false, totalHeures: 0, periodeEtendue: false, messageBlocage: nil)
        XCTAssertEqual(SlotList.Presentation.planning(sansMessage, libelle: MissionPresentation.creneau).blocked?.message,
                       PlanningCandidatRules.messagePlanningIncomplet)
    }

    func testSlotListPlanningUtiliseLeFormateurDeLigneFourniParLAppelant() {
        // Revue B8 : le format des lignes du web (année, « → », date de fin + « (lendemain) », durée
        // « · X h ») n'est PAS celui du détail lot 0 (`MissionPresentation.creneau`). La variante planning
        // exige donc le formateur de ligne (aucun défaut) : le récapitulatif T6b branche celui du cœur.
        let nuit = MissionSlot(id: "n1", debut: "2026-11-02T07:00:00Z", fin: "2026-11-03T07:00:00Z", estPause: false, typeCreneau: "PREVISIONNEL")
        let planning = PlanningCandidat(creneaux: [nuit], exact: true, totalHeures: 24, periodeEtendue: false, messageBlocage: nil)
        let presentation = SlotList.Presentation.planning(planning, libelle: { "ligne \($0.id ?? "?") du cœur" })
        XCTAssertEqual(presentation.visibleItems.map(\.label), ["ligne n1 du cœur"])
        XCTAssertEqual(presentation.visibleItems.map(\.id), ["creneau-1"], "Identifiant positionnel inchangé")
        XCTAssertEqual(SlotList.items([nuit], libelle: { _ in "L" }).map(\.label), ["L"])
        // Variante créneaux : format du détail lot 0 par défaut (écart documenté : un créneau
        // 08:00 → 08:00 le lendemain n'y montre pas la date de fin).
        XCTAssertEqual(SlotList.items([nuit]).map(\.label), [MissionPresentation.creneau(nuit)])
    }

    func testSlotListIdentifiantsSuffixesEnAnglaisEtEncartBloqueParametrable() {
        // Revue B8 n°2 : suffixes unifiés en anglais (convention du plan : `-empty`, `-blocked`, `-submit`) ;
        // lignes `<prefix>-creneau-<n>` inchangées (lot 0, DemoConsultationTests l.96-102).
        let detail = SlotList.Identifiers(container: "mission-detail-creneaux")
        XCTAssertEqual(detail.container, "mission-detail-creneaux")
        XCTAssertEqual(detail.summary, "mission-detail-creneaux-summary")
        XCTAssertEqual(detail.empty, "mission-detail-creneaux-empty")
        XCTAssertEqual(detail.remaining, "mission-detail-creneaux-remaining")
        XCTAssertEqual(detail.footnote, "mission-detail-creneaux-footnote")
        XCTAssertEqual(detail.blocked, "mission-detail-creneaux-blocked")
        XCTAssertEqual(detail.row(0), "mission-detail-creneau-1")
        // T6b (LOT1_PLAN) : l'encart « Planning exact à confirmer » s'appelle `candidature-planning-blocked`,
        // imposé par l'écran sans rouvrir le package.
        let recap = SlotList.Identifiers(container: "candidature-recap", itemPrefix: "candidature-recap",
                                         blocked: "candidature-planning-blocked")
        XCTAssertEqual(recap.blocked, "candidature-planning-blocked")
        XCTAssertEqual(recap.summary, "candidature-recap-summary")
        XCTAssertEqual(recap.row(2), "candidature-recap-creneau-3")
        // Annonce VoiceOver du planning bloqué (InlineNotice) : sur demande de l'écran, jamais par défaut.
        let bloque = PlanningCandidat(creneaux: [], exact: false, totalHeures: 0, periodeEtendue: false,
                                      messageBlocage: PlanningCandidatRules.messagePlanningIncomplet)
        let presentation = SlotList.Presentation.planning(bloque, libelle: MissionPresentation.creneau)
        XCTAssertEqual(SlotList.blockedAnnouncement(presentation, announces: true),
                       "Attention : Planning exact à confirmer. \(PlanningCandidatRules.messagePlanningIncomplet)")
        XCTAssertNil(SlotList.blockedAnnouncement(presentation, announces: false))
        let exact = PlanningCandidat(creneaux: [], exact: true, totalHeures: 0, periodeEtendue: false, messageBlocage: nil)
        XCTAssertNil(SlotList.blockedAnnouncement(.planning(exact, libelle: MissionPresentation.creneau), announces: true),
                     "Rien à annoncer hors planning bloqué")
    }

    func testSlotListVideNAffichePasDeResumeRedondant() {
        // Revue B8 : « Aucun créneau » puis « Aucun créneau communiqué. » — le résumé est masqué sur une liste vide.
        let vide = SlotList.Presentation(items: [], resume: SlotList.resume(count: 0))
        XCTAssertNil(vide.displayedResume)
        let slot = MissionSlot(debut: "2026-11-02T07:00:00Z", fin: "2026-11-02T15:00:00Z", estPause: false, typeCreneau: "PREVISIONNEL")
        let pleine = SlotList.Presentation(items: SlotList.items([slot]), resume: SlotList.resume(count: 1))
        XCTAssertEqual(pleine.displayedResume, "1 créneau")
    }

    // MARK: - StickyActionBar

    func testStickyActionBarAfficheLesValeursServeurTellesQuellesEtGereLeChargement() {
        // DetailMissionSoignant.tsx l.1568-1611 : montant + précision (« avant cotisations libérales »
        // ou « estimation figée à l'acceptation ») + CTA ; `loading` ou `disabled` bloquent le CTA.
        let content = StickyActionBar.Content(montant: "~1 234 € net estimé", precision: "avant cotisations libérales",
                                              actionTitle: "Postuler", identifier: "mission-detail-sticky")
        XCTAssertEqual(content.accessibilitySummary, "~1 234 € net estimé, avant cotisations libérales")
        // Le résumé est un seul élément combiné : il porte l'identifiant `-amount` (les enfants combinés
        // ne sont pas exposés aux XCUITest).
        XCTAssertEqual(content.amountIdentifier, "mission-detail-sticky-amount")
        XCTAssertEqual(content.actionIdentifier, "mission-detail-sticky-action")
        let sansPrecision = StickyActionBar.Content(montant: "Rétrocession 70 %", precision: nil,
                                                    actionTitle: "Accepter", identifier: "mission-detail-sticky")
        XCTAssertEqual(sansPrecision.accessibilitySummary, "Rétrocession 70 %")
        XCTAssertTrue(StickyActionBar.isActionEnabled(isLoading: false, isDisabled: false))
        XCTAssertFalse(StickyActionBar.isActionEnabled(isLoading: true, isDisabled: false))
        XCTAssertFalse(StickyActionBar.isActionEnabled(isLoading: false, isDisabled: true))
    }

    func testStickyActionBarAccepteUnIdentifiantDActionImpose() {
        // LOT1_PLAN T6b : le CTA du détail mission s'appelle `candidature-submit`.
        let content = StickyActionBar.Content(montant: "70,00 €/h", precision: nil, actionTitle: "Postuler",
                                              identifier: "mission-detail-sticky", actionIdentifier: "candidature-submit")
        XCTAssertEqual(content.actionIdentifier, "candidature-submit")
        XCTAssertEqual(content.amountIdentifier, "mission-detail-sticky-amount")
        XCTAssertEqual(StickyActionBar.maximumContentWidth, 640, "Même largeur utile que le détail mission sur iPad")
    }

    func testStickyActionBarPasseEnColonneAuxTaillesDAccessibilite() {
        // Revue B8 : aux tailles Dynamic Type d'accessibilité, montant au-dessus et CTA pleine largeur ;
        // le montant serveur n'est jamais tronqué (aucune limite de lignes).
        XCTAssertEqual(StickyActionBar.layout(for: .large), .horizontal)
        XCTAssertEqual(StickyActionBar.layout(for: .xxxLarge), .horizontal)
        XCTAssertEqual(StickyActionBar.layout(for: .accessibility1), .vertical)
        XCTAssertEqual(StickyActionBar.layout(for: .accessibility5), .vertical)
        XCTAssertNil(StickyActionBar.montantLineLimit, "Montant serveur jamais tronqué")
    }

    @MainActor
    func testStickyActionBarChoisitSaDispositionMesureeDansUnHebergeur() {
        // Revue B8 n°2 : la bascule était annoncée, pas vérifiée. Hauteur rendue de la barre automatique
        // comparée à la même barre forcée en ligne puis en colonne (`layoutOverride`, interne aux tests).
        func hauteur<V: View>(_ vue: V, largeur: CGFloat = 390) -> CGFloat {
            UIHostingController(rootView: vue).sizeThatFits(in: CGSize(width: largeur, height: 2000)).height
        }
        func barre(_ content: StickyActionBar.Content, _ disposition: StickyActionBar.Layout?,
                   taille: DynamicTypeSize = .large) -> some View {
            StickyActionBar(content, layoutOverride: disposition) {}.environment(\.dynamicTypeSize, taille)
        }
        let court = StickyActionBar.Content(montant: "70,00 €/h", precision: nil, actionTitle: "Postuler", identifier: "s")
        let long = StickyActionBar.Content(montant: "~12 345,67 € net estimé sur la période complète",
                                           precision: "estimation figée à l'acceptation", actionTitle: "Accepter la mission",
                                           identifier: "s")
        // Taille standard, montant court : tout tient, la barre reste en ligne.
        let enLigne = hauteur(barre(court, .horizontal)), enColonne = hauteur(barre(court, .vertical))
        XCTAssertGreaterThan(enColonne, enLigne + 20, "La mesure distingue les deux dispositions")
        XCTAssertEqual(hauteur(barre(court, nil)), enLigne, accuracy: 0.5)
        // Montant long à 320 pt : `ViewThatFits` replie en colonne (montant au-dessus, CTA pleine largeur).
        XCTAssertEqual(hauteur(barre(long, nil), largeur: 320), hauteur(barre(long, .vertical), largeur: 320), accuracy: 0.5)
        XCTAssertNotEqual(hauteur(barre(long, .horizontal), largeur: 320), hauteur(barre(long, .vertical), largeur: 320),
                          accuracy: 0.5)
        // accessibility5 : colonne imposée, même pour un montant court qui tiendrait en ligne.
        let a11yColonne = hauteur(barre(court, .vertical, taille: .accessibility5))
        XCTAssertEqual(hauteur(barre(court, nil, taille: .accessibility5)), a11yColonne, accuracy: 0.5)
        XCTAssertNotEqual(hauteur(barre(court, .horizontal, taille: .accessibility5)), a11yColonne, accuracy: 0.5)
        XCTAssertGreaterThan(a11yColonne, enColonne, "Texte agrandi : la colonne grandit avec Dynamic Type")
    }

    // MARK: - InlineNotice

    func testInlineNoticeAnnonceSonTonAvantLeMessage() {
        // La couleur seule ne porte jamais l'information : icône + préfixe vocalisé par ton.
        XCTAssertEqual(InlineNotice.Tone.info.systemImage, "info.circle")
        XCTAssertEqual(InlineNotice.Tone.success.systemImage, "checkmark.circle")
        XCTAssertEqual(InlineNotice.Tone.warning.systemImage, "exclamationmark.triangle")
        XCTAssertEqual(InlineNotice.Tone.error.systemImage, "xmark.octagon")
        XCTAssertEqual(InlineNotice.Tone.info.accessibilityPrefix, "Information")
        XCTAssertEqual(InlineNotice.Tone.success.accessibilityPrefix, "Succès")
        XCTAssertEqual(InlineNotice.Tone.warning.accessibilityPrefix, "Attention")
        XCTAssertEqual(InlineNotice.Tone.error.accessibilityPrefix, "Erreur")
        XCTAssertEqual(InlineNotice.accessibilityLabel(tone: .error, title: nil, message: "Session expirée."),
                       "Erreur : Session expirée.")
        XCTAssertEqual(InlineNotice.accessibilityLabel(tone: .warning, title: "Documents", message: "RCP expirée."),
                       "Attention : Documents. RCP expirée.")
        XCTAssertEqual(InlineNotice.Tone.allCases.count, 4)
    }

    func testInlineNoticeIconeEtTexteContrastentSurChaqueTonEnClairEtEnSombre() {
        // Revue B8 : le ton n'est visible que par l'icône → ≥ 3:1 (WCAG 1.4.11) ; texte ≥ 4,5:1.
        // butter-700 sur butter-100 ne faisait que ≈ 2,4:1 ; encres de BadgeY2K (text-jolene-*-800/900).
        XCTAssertLessThan(JoleneColor.butter700HSL.light.rgb.contrastRatio(with: JoleneColor.butter100HSL.light.rgb), 3)
        for tone in InlineNotice.Tone.allCases {
            for (encre, fond) in [(tone.inkHSL.light, tone.backgroundHSL.light), (tone.inkHSL.dark, tone.backgroundHSL.dark)] {
                XCTAssertGreaterThanOrEqual(encre.rgb.contrastRatio(with: fond.rgb), 3, "\(tone) : icône \(encre) sur \(fond)")
            }
            XCTAssertGreaterThanOrEqual(JoleneColor.midnightHSL.light.rgb.contrastRatio(with: tone.backgroundHSL.light.rgb), 4.5, "\(tone) clair")
            XCTAssertGreaterThanOrEqual(JoleneColor.midnightHSL.dark.rgb.contrastRatio(with: tone.backgroundHSL.dark.rgb), 4.5, "\(tone) sombre")
        }
        // BadgeY2K : warning butter-800 / butter-100, success cyan-900 / cyan-100, info mauve-800 / mauve-100.
        XCTAssertEqual(InlineNotice.Tone.warning.inkHSL, JoleneColor.butter800HSL)
        XCTAssertEqual(InlineNotice.Tone.warning.backgroundHSL, JoleneColor.butter100HSL)
        XCTAssertEqual(InlineNotice.Tone.success.inkHSL, JoleneColor.cyan900HSL)
        XCTAssertEqual(InlineNotice.Tone.success.backgroundHSL, JoleneColor.cyan100HSL)
        XCTAssertEqual(InlineNotice.Tone.info.inkHSL, JoleneColor.mauve800HSL)
        XCTAssertEqual(InlineNotice.Tone.info.backgroundHSL, JoleneColor.mauve100HSL)
        XCTAssertEqual(InlineNotice.Tone.error.inkHSL, JoleneColor.rose700HSL)
        XCTAssertEqual(InlineNotice.Tone.error.backgroundHSL, JoleneColor.rose100HSL)
        // Valeurs sources (src/index.css, `:root` puis `.dark`).
        XCTAssertEqual(JoleneColor.butter800HSL, JoleneDynamicHSL(light: JoleneHSL(50, 70, 32), dark: JoleneHSL(50, 100, 89)))
        XCTAssertEqual(JoleneColor.cyan900HSL, JoleneDynamicHSL(light: JoleneHSL(192, 65, 25), dark: JoleneHSL(192, 100, 95)))
        XCTAssertEqual(JoleneColor.mauve800HSL, JoleneDynamicHSL(light: JoleneHSL(267, 65, 42), dark: JoleneHSL(267, 100, 91)))
        XCTAssertEqual(JoleneColor.cyan100HSL, JoleneDynamicHSL(light: JoleneHSL(192, 100, 91), dark: JoleneHSL(192, 55, 18)))
    }

    func testInlineNoticeAnnonceLAlerteSeulementSurDemande() {
        // `role="alert"` web : annoncé à l'apparition. VoiceOver ne le fait pas seul → option explicite,
        // réservée aux encarts qui apparaissent après une action (erreur serveur, refus).
        XCTAssertNil(InlineNotice.announcement(tone: .error, title: nil, message: "Session expirée.", announcesOnAppear: false))
        XCTAssertEqual(InlineNotice.announcement(tone: .error, title: nil, message: "Session expirée.", announcesOnAppear: true),
                       "Erreur : Session expirée.")
        XCTAssertEqual(InlineNotice.announcement(tone: .warning, title: "Planning", message: "À confirmer.", announcesOnAppear: true),
                       "Attention : Planning. À confirmer.")
    }

    func testInlineNoticeReannonceUneMemeErreurSurNouveauJetonSeulement() {
        // Revue B8 n°2 : `.task(id: annonce)` taisait une même erreur revenue (id inchangé) et réannonçait
        // l'encart à chaque réapparition dans un conteneur paresseux. Clé = texte + jeton de l'appelant
        // (ex. numéro de tentative) ; une clé déjà annoncée par cette vue ne l'est plus.
        let premiere = InlineNotice.announcementKey(tone: .error, title: nil, message: "Réseau indisponible.",
                                                    announcesOnAppear: true, announcementID: 1)
        XCTAssertEqual(premiere?.text, "Erreur : Réseau indisponible.")
        XCTAssertEqual(premiere?.id, 1)
        XCTAssertTrue(InlineNotice.shouldAnnounce(premiere, lastAnnounced: nil))
        XCTAssertFalse(InlineNotice.shouldAnnounce(premiere, lastAnnounced: premiere), "Réapparition : silence")
        let seconde = InlineNotice.announcementKey(tone: .error, title: nil, message: "Réseau indisponible.",
                                                   announcesOnAppear: true, announcementID: 2)
        XCTAssertNotEqual(premiere, seconde)
        XCTAssertTrue(InlineNotice.shouldAnnounce(seconde, lastAnnounced: premiere), "Même erreur, nouvelle tentative")
        XCTAssertNil(InlineNotice.announcementKey(tone: .error, title: nil, message: "Réseau indisponible.",
                                                  announcesOnAppear: false, announcementID: 3))
        XCTAssertFalse(InlineNotice.shouldAnnounce(nil, lastAnnounced: premiere))
        XCTAssertEqual(InlineNotice.announcementKey(tone: .warning, title: "Planning", message: "À confirmer.",
                                                    announcesOnAppear: true)?.id, 0, "Jeton par défaut : 0")
    }

    // MARK: - SkeletonBlock

    func testSkeletonBlockReprendLesHauteursDuSkeletonWebEtSeDeclareEnChargement() {
        // src/components/ui/skeleton.tsx : sm h-3 (12 px), md h-4 (16 px), lg h-6 (24 px) ; role status, aria-busy.
        XCTAssertEqual(SkeletonBlock.Size.sm.height, 12)
        XCTAssertEqual(SkeletonBlock.Size.md.height, 16)
        XCTAssertEqual(SkeletonBlock.Size.lg.height, 24)
        XCTAssertEqual(SkeletonBlock.accessibilityLabel, "Chargement en cours")
        XCTAssertEqual(SkeletonBlock.Size.allCases.count, 3)
        // src/index.css (prefers-reduced-motion) : `.animate-pulse { animation: none }`.
        XCTAssertTrue(SkeletonBlock.animates(reduceMotion: false))
        XCTAssertFalse(SkeletonBlock.animates(reduceMotion: true))
    }

    // MARK: - SectionHeader

    func testSectionHeaderDeriveSesIdentifiants() {
        XCTAssertEqual(SectionHeader.titleIdentifier(for: "accueil-prochaines"), "accueil-prochaines-title")
        XCTAssertEqual(SectionHeader.actionIdentifier(for: "accueil-prochaines"), "accueil-prochaines-action")
        // Revue B8 n°2 : la cible de 44 pt est posée DANS le label du bouton (avec `contentShape`), plus autour.
        XCTAssertEqual(SectionHeader.minimumTapTarget, 44)
    }

    @MainActor
    func testSectionHeaderAvecActionMesureAuMoins44Points() {
        let hote = UIHostingController(rootView: SectionHeader("Prochaines missions", identifier: "accueil-prochaines",
                                                              actionTitle: "Tout voir") {})
        XCTAssertGreaterThanOrEqual(hote.sizeThatFits(in: CGSize(width: 390, height: 1000)).height, 44)
    }

    // MARK: - EmptyState (revue T4a : action secondaire ET « Actualiser »)

    @MainActor
    func testEmptyStateExposeZeroUneOuDeuxActionsDansLOrdre() {
        XCTAssertEqual(EmptyState(systemImage: "hourglass", title: "T", message: "M", identifier: "vide").actionIdentifiers, [])
        XCTAssertEqual(EmptyState(systemImage: "magnifyingglass", title: "T", message: "M", identifier: "missions-empty",
                                  actionTitle: "Actualiser", actionIdentifier: "missions-refresh") {}.actionIdentifiers,
                       ["missions-refresh"], "init du lot 0 inchangé : une action")
        let deux = EmptyState(systemImage: "magnifyingglass", title: "T", message: "M", identifier: "missions-empty",
                              actionTitle: "Élargir le rayon (+20 km)", actionIdentifier: "missions-empty-action", action: {},
                              secondaryActionTitle: "Actualiser", secondaryActionIdentifier: "missions-refresh", secondaryAction: {})
        XCTAssertEqual(deux.actionIdentifiers, ["missions-empty-action", "missions-refresh"],
                       "l'action secondaire du web d'abord, puis « Actualiser », toutes deux affichées")
    }

    // MARK: - Texte sans fond propre (revue B8 n°2, majeur)

    func testTexteSansFondPropreAtteintAASurToutesLesSurfacesOuIlEstPose() {
        // SectionHeader et le « reste » de SlotList n'ont pas de fond : ils héritent de la surface de l'écran —
        // carte (`cloud`), fond des écrans du lot 0 (`lavender` : MissionsListScreen l.55, MissionDetailScreen l.37,
        // ProfileScreen l.42), bas du `softGradient` (`rose100` : RootView, LoginScreen). En rose-700, l'action
        // « Tout voir » (callout semibold 16 pt : pas du grand texte) tombait à 4,12:1 et 3,54:1.
        XCTAssertEqual(JoleneColor.rose800HSL, JoleneDynamicHSL(light: JoleneHSL(326, 70, 38), dark: JoleneHSL(326, 100, 88)))
        XCTAssertEqual(JoleneColor.inheritedSurfacesHSL, [JoleneColor.cloudHSL, JoleneColor.lavenderHSL, JoleneColor.rose100HSL])
        XCTAssertEqual(SectionHeader.titleInkHSL, JoleneColor.midnightHSL)
        XCTAssertEqual(SectionHeader.actionInkHSL, JoleneColor.rose800HSL)
        XCTAssertEqual(SlotList.summaryInkHSL, JoleneColor.midnightHSL)
        XCTAssertEqual(SlotList.remainingInkHSL, JoleneColor.rose800HSL)
        let encres: [(String, JoleneDynamicHSL)] = [
            ("SectionHeader titre", SectionHeader.titleInkHSL), ("SectionHeader action", SectionHeader.actionInkHSL),
            ("SlotList résumé", SlotList.summaryInkHSL), ("SlotList reste", SlotList.remainingInkHSL),
        ]
        for (nom, encre) in encres {
            for surface in JoleneColor.inheritedSurfacesHSL {
                XCTAssertGreaterThanOrEqual(encre.light.rgb.contrastRatio(with: surface.light.rgb), 4.5, "\(nom), clair, sur \(surface.light)")
                XCTAssertGreaterThanOrEqual(encre.dark.rgb.contrastRatio(with: surface.dark.rgb), 4.5, "\(nom), sombre, sur \(surface.dark)")
            }
            // Fonds sombres de src/index.css non rendus (écart du lot 0) : un alignement futur reste AA.
            for fond in EcartsSombresLot0.fondsWeb {
                XCTAssertGreaterThanOrEqual(encre.dark.rgb.contrastRatio(with: fond.rgb), 4.5, "\(nom), sombre, sur \(fond) (web)")
            }
        }
        // Valeurs de la revue (clair) : rose-700 avant, rose-800 après.
        let clair = { (encre: JoleneDynamicHSL, fond: JoleneDynamicHSL) in encre.light.rgb.contrastRatio(with: fond.light.rgb) }
        XCTAssertEqual(clair(JoleneColor.rose700HSL, JoleneColor.lavenderHSL), 4.12, accuracy: 0.01)
        XCTAssertEqual(clair(JoleneColor.rose700HSL, JoleneColor.rose100HSL), 3.54, accuracy: 0.01)
        XCTAssertEqual(clair(JoleneColor.rose700HSL, JoleneColor.cloudHSL), 4.62, accuracy: 0.01)
        XCTAssertEqual(clair(JoleneColor.rose800HSL, JoleneColor.lavenderHSL), 6.10, accuracy: 0.01)
        XCTAssertEqual(clair(JoleneColor.rose800HSL, JoleneColor.rose100HSL), 5.23, accuracy: 0.01)
        XCTAssertEqual(clair(JoleneColor.rose800HSL, JoleneColor.cloudHSL), 6.83, accuracy: 0.01)
    }

    func testTexteSecondaireDeSlotListAtteintAASurLesCartesEtLesEcrans() {
        // Liste vide, pauses et mention des jours non travaillés : texte secondaire `bubblegum` (jeton du lot 0).
        // ≥ 4,5:1 sur cloud et lavender, clair et sombre ; 4,44:1 seulement sur rose100 en clair : SlotList se pose
        // sur une carte ou un écran, jamais sur le `softGradient` (consigne écrite sur le composant).
        XCTAssertEqual(SlotList.secondaryInkHSL, JoleneColor.bubblegumHSL)
        for surface in [JoleneColor.cloudHSL, JoleneColor.lavenderHSL] {
            XCTAssertGreaterThanOrEqual(SlotList.secondaryInkHSL.light.rgb.contrastRatio(with: surface.light.rgb), 4.5, "\(surface.light)")
            XCTAssertGreaterThanOrEqual(SlotList.secondaryInkHSL.dark.rgb.contrastRatio(with: surface.dark.rgb), 4.5, "\(surface.dark)")
        }
        for fond in EcartsSombresLot0.fondsWeb {
            XCTAssertGreaterThanOrEqual(SlotList.secondaryInkHSL.dark.rgb.contrastRatio(with: fond.rgb), 4.5, "\(fond) (web)")
            XCTAssertGreaterThanOrEqual(EcartsSombresLot0.bubblegumWeb.rgb.contrastRatio(with: fond.rgb), 4.5, "bubblegum web sur \(fond)")
        }
        XCTAssertEqual(JoleneColor.bubblegumHSL.light.rgb.contrastRatio(with: JoleneColor.rose100HSL.light.rgb), 4.44, accuracy: 0.01)
    }

    // MARK: - Jetons ↔ src/index.css (garde de dérive)

    func testLesSourcesHSLReprennentSrcIndexCssSaufEcartsDocumentes() throws {
        // Revue B8 n°2 : `midnightHSL.dark` (320 100 97) et `butter700HSL.dark` (50 95 75) ne venaient pas de
        // src/index.css (270 30% 95%, 50 100% 82%) : alignés. La garde relit le fichier du dépôt et compare
        // chaque source `…HSL` aux variables `:root` puis `.dark` ; trois écarts du lot 0 restent assumés
        // (fonds lavender / cloud et texte secondaire bubblegum en sombre), listés et vérifiés ici.
        let variables = try Self.variablesJoleneDeIndexCss()
        let jetons: [(String, JoleneDynamicHSL)] = [
            ("jolene-rose", JoleneColor.roseHSL), ("jolene-mauve", JoleneColor.mauveHSL), ("jolene-cyan", JoleneColor.cyanHSL),
            ("jolene-butter", JoleneColor.butterHSL),
            ("jolene-rose-700", JoleneColor.rose700HSL), ("jolene-rose-800", JoleneColor.rose800HSL),
            ("jolene-mauve-700", JoleneColor.mauve700HSL), ("jolene-mauve-800", JoleneColor.mauve800HSL),
            ("jolene-cyan-700", JoleneColor.cyan700HSL), ("jolene-cyan-900", JoleneColor.cyan900HSL),
            ("jolene-butter-700", JoleneColor.butter700HSL), ("jolene-butter-800", JoleneColor.butter800HSL),
            ("jolene-rose-100", JoleneColor.rose100HSL), ("jolene-mauve-100", JoleneColor.mauve100HSL),
            ("jolene-cyan-100", JoleneColor.cyan100HSL), ("jolene-butter-100", JoleneColor.butter100HSL),
            ("jolene-lavender", JoleneColor.lavenderHSL), ("jolene-cloud", JoleneColor.cloudHSL),
            ("jolene-midnight", JoleneColor.midnightHSL), ("jolene-bubblegum", JoleneColor.bubblegumHSL),
        ]
        for (nom, jeton) in jetons {
            let css = try XCTUnwrap(variables[nom], "--\(nom) absent de src/index.css")
            XCTAssertEqual(jeton.light, css.light, "--\(nom) (:root)")
            if let ecart = EcartsSombresLot0.table[nom] {
                XCTAssertEqual(css.dark, ecart.web, "--\(nom) (.dark) : la valeur web documentée a changé")
                XCTAssertEqual(jeton.dark, ecart.rendu, "--\(nom) (.dark) : la valeur rendue documentée a changé")
            } else {
                XCTAssertEqual(jeton.dark, css.dark, "--\(nom) (.dark)")
            }
        }
        XCTAssertEqual(Set(EcartsSombresLot0.table.keys), ["jolene-lavender", "jolene-cloud", "jolene-bubblegum"])
        XCTAssertEqual(JoleneColor.midnightHSL.dark, JoleneHSL(270, 30, 95))
        XCTAssertEqual(JoleneColor.butter700HSL.dark, JoleneHSL(50, 100, 82))
        // Le fond doux et les jetons `Color` restent construits sur ces mêmes sources.
        XCTAssertEqual(JoleneColor.softGradientStops, [JoleneColor.lavenderHSL, JoleneColor.rose100HSL])
    }

    /// Variables `--jolene-*: H S% L%;` de src/index.css, réparties entre `:root` (avant `.dark {`) et `.dark`.
    static func variablesJoleneDeIndexCss() throws -> [String: JoleneDynamicHSL] {
        // Tests/JoleneDesignTests/<fichier> → racine du dépôt (6 niveaux), motif de LinksAASATests (JoleneCore).
        var racine = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { racine.deleteLastPathComponent() }
        let fichier = racine.appendingPathComponent("src/index.css")
        guard FileManager.default.fileExists(atPath: fichier.path) else {
            throw XCTSkip("src/index.css introuvable : \(fichier.path)")
        }
        let texte = try String(contentsOf: fichier, encoding: .utf8)
        let debutSombre = try XCTUnwrap(texte.range(of: "\n  .dark {")?.lowerBound, "bloc .dark introuvable")
        let motif = try NSRegularExpression(pattern: #"--(jolene-[a-z0-9-]+):\s*([0-9.]+)\s+([0-9.]+)%\s+([0-9.]+)%\s*;"#)
        var clair: [String: JoleneHSL] = [:], sombre: [String: JoleneHSL] = [:]
        for resultat in motif.matches(in: texte, range: NSRange(texte.startIndex..., in: texte)) {
            let groupe = { (i: Int) in String(texte[Range(resultat.range(at: i), in: texte)!]) }
            let hsl = JoleneHSL(Double(groupe(2))!, Double(groupe(3))!, Double(groupe(4))!)
            let position = Range(resultat.range, in: texte)!.lowerBound
            if position < debutSombre { clair[groupe(1)] = hsl } else { sombre[groupe(1)] = hsl }
        }
        var variables: [String: JoleneDynamicHSL] = [:]
        for (nom, valeur) in clair { if let dark = sombre[nom] { variables[nom] = JoleneDynamicHSL(light: valeur, dark: dark) } }
        return variables
    }

    // MARK: - Rendu des vues (corps évalué, aucun piège)

    @MainActor
    func testLesVuesDuLot1SeRendentDansUnHebergeurUIKit() {
        let lundi = MissionSlot(debut: "2026-11-02T07:00:00Z", fin: "2026-11-02T15:00:00Z", estPause: false, typeCreneau: "PREVISIONNEL")
        let planning = PlanningCandidat(creneaux: [lundi, lundi], exact: true, totalHeures: 16, periodeEtendue: true, messageBlocage: nil)
        let bloque = PlanningCandidat(creneaux: [], exact: false, totalHeures: 0, periodeEtendue: false,
                                      messageBlocage: PlanningCandidatRules.messageErreurChargement)
        let suppression = ConfirmationSheet.Configuration(title: "Supprimer mon compte", message: "M", variant: .danger,
                                                          identifier: "compte-supprimer", requiredPhrase: "SUPPRIMER")
        let sticky = StickyActionBar.Content(montant: "70,00 €/h", precision: "estimation figée à l'acceptation",
                                             actionTitle: "Postuler", identifier: "sticky", actionIdentifier: "candidature-submit")
        let longue = StickyActionBar.Content(montant: "~12 345,67 € net estimé sur la période complète",
                                             precision: "estimation figée à l'acceptation", actionTitle: "Accepter la mission",
                                             identifier: "sticky-a11y")
        let vues: [(String, AnyView)] = [
            ("destructif", AnyView(JoleneButton("Supprimer mon compte", style: .destructive) {})),
            ("destructif en chargement", AnyView(JoleneButton("Supprimer", style: .destructive, isLoading: true) {})),
            ("confirmation", AnyView(ConfirmationSheet(.init(title: "T", message: "M", identifier: "sheet"), onCancel: {}, onConfirm: {}))),
            ("confirmation phrase", AnyView(ConfirmationSheet(suppression, isLoading: false, onCancel: {}, onConfirm: {}))),
            ("confirmation contenu", AnyView(ConfirmationSheet(.init(title: "T", message: "M", identifier: "recap"), isLoading: true,
                                                                isConfirmEnabled: false, onCancel: {}, onConfirm: {}) {
                SlotList(planning: planning, identifier: "recap-creneaux", libelle: MissionPresentation.creneau)
            })),
            ("pastilles", AnyView(FilterChipRow(identifier: "explorer-chips") {
                FilterChip("🔥 Urgentes", isSelected: true, identifier: "chip-urgentes") {}
                FilterChip("🌙 Nuit", isSelected: false, identifier: "chip-nuit") {}
            })),
            ("créneaux vides", AnyView(SlotList(items: [], identifier: "mission-detail-creneaux"))),
            ("créneaux", AnyView(SlotList(slots: [lundi], identifier: "mission-detail-creneaux", showsResume: true))),
            ("planning exact", AnyView(SlotList(planning: planning, identifier: "recap-creneaux",
                                                libelle: MissionPresentation.creneau, limit: 1))),
            ("planning bloqué", AnyView(SlotList(planning: bloque, identifier: "recap-creneaux", libelle: MissionPresentation.creneau))),
            ("planning bloqué annoncé", AnyView(SlotList(planning: bloque, identifier: "candidature-recap",
                                                         libelle: MissionPresentation.creneau,
                                                         blockedIdentifier: "candidature-planning-blocked",
                                                         announcesBlocked: true, blockedAnnouncementID: 2))),
            ("barre collante", AnyView(StickyActionBar(sticky, isLoading: true) {})),
            ("barre collante accessibilité", AnyView(StickyActionBar(longue) {}.environment(\.dynamicTypeSize, .accessibility5))),
            ("modificateur confirmation", AnyView(Color.clear.confirmationSheet(isPresented: .constant(true), suppression, onConfirm: {}))),
            ("modificateur confirmation contenu", AnyView(Color.clear.confirmationSheet(
                isPresented: .constant(true), .init(title: "T", message: "M", identifier: "recap"), isLoading: true, onConfirm: {}
            ) { SlotList(planning: planning, identifier: "recap-creneaux", libelle: MissionPresentation.creneau) })),
            ("créneaux identifiants doublons", AnyView(SlotList(items: [.init(id: "x", label: "A", isPause: false),
                                                                       .init(id: "x", label: "B", isPause: true)],
                                                               identifier: "doublons", showsResume: true))),
            ("encart annoncé", AnyView(InlineNotice("Erreur serveur", tone: .error, identifier: "notice-annonce", announcesOnAppear: true))),
            ("encart réannoncé", AnyView(InlineNotice("Erreur serveur", tone: .error, identifier: "notice-annonce",
                                                      announcesOnAppear: true, announcementID: 3))),
            ("confirmation exemple web", AnyView(ConfirmationSheet(.init(title: "T", message: "M", variant: .danger, identifier: "c",
                                                                         requiredPhrase: "SUPPRIMER",
                                                                         phrasePrompt: "Tape SUPPRIMER pour confirmer",
                                                                         phrasePlaceholder: "Tape SUPPRIMER"),
                                                                   onCancel: {}, onConfirm: {}))),
            ("barre montée", AnyView(Color.clear.stickyActionBar(isPresented: true, sticky) {})),
            ("encart", AnyView(InlineNotice("Message", title: "Titre", tone: .warning, identifier: "notice"))),
            ("squelette", AnyView(SkeletonBlock(size: .lg, identifier: "skeleton"))),
            ("carte squelette", AnyView(SkeletonCard(identifier: "skeleton-card"))),
            ("en-tête", AnyView(SectionHeader("Prochaines missions", identifier: "accueil-prochaines", actionTitle: "Tout voir") {})),
            ("état vide deux actions", AnyView(EmptyState(systemImage: "magnifyingglass", title: "Aucune mission trouvée",
                                                          message: "M", identifier: "missions-empty",
                                                          actionTitle: "Élargir le rayon (+20 km)",
                                                          actionIdentifier: "missions-empty-action", action: {},
                                                          secondaryActionTitle: "Actualiser",
                                                          secondaryActionIdentifier: "missions-refresh", secondaryAction: {}))),
        ]
        for (nom, vue) in vues {
            let hote = UIHostingController(rootView: vue)
            let taille = hote.sizeThatFits(in: CGSize(width: 390, height: 1200))
            XCTAssertTrue(taille.width.isFinite && taille.height.isFinite, "\(nom) : taille finie")
            XCTAssertGreaterThan(taille.width, 0, "\(nom) : largeur non nulle")
            hote.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            hote.view.layoutIfNeeded()
        }
    }
}
