import XCTest
import SwiftUI
import UIKit
import JoleneCore
@testable import JoleneDesign

/// Lot 1 (T1b) : règles pures des nouveaux composants. Chaque composant expose la partie
/// calculable (identifiants, libellés d'accessibilité, correspondances de style, contrastes)
/// pour qu'elle soit vérifiée sans XCUITest ; le dernier cas évalue le corps de chaque vue
/// dans un `UIHostingController` (aucun piège à l'exécution). Le parcours visible reste
/// couvert par les XCUITest démo des écrans qui montent ces composants.
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
        // Le primaire du lot 0 garde son texte blanc (inchangé au lot 1) ; le secondaire reste en bordure rose.
        XCTAssertTrue(JoleneButton.Style.primary.isFilled)
        XCTAssertFalse(JoleneButton.Style.primary.usesDarkTextOnFill)
        XCTAssertFalse(JoleneButton.Style.secondary.isFilled)
        XCTAssertFalse(JoleneButton.Style.secondary.usesDarkTextOnFill)
        XCTAssertEqual(JoleneButton.Style.allCases.count, 3)
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

    // MARK: - FilterChip

    func testFilterChipExposeSonEtatCommeAriaPressedEtResteLisibleActif() {
        // RechercheMissions.tsx : `aria-pressed={chip.actif}`, actif = dégradé hero.
        let actif = FilterChip.Appearance.resolve(isSelected: true)
        XCTAssertTrue(actif.usesGradient)
        XCTAssertEqual(actif.accessibilityValue, "activé")
        XCTAssertEqual(actif.foregroundHex, JoleneColor.onGradientHex)
        let inactif = FilterChip.Appearance.resolve(isSelected: false)
        XCTAssertFalse(inactif.usesGradient)
        XCTAssertEqual(inactif.accessibilityValue, "désactivé")
        XCTAssertNil(inactif.foregroundHex, "Inactif : jeton dynamique bubblegum")
        XCTAssertEqual(FilterChip.minimumHeight, 44, "Cible tactile 44 pt (min-h-[44px] du web)")
        // Texte d'une pastille active ≥ 4,5:1 sur les deux extrémités du dégradé hero, en clair et en sombre
        // (JoleneColor.rose / .mauve) ; le blanc du web n'atteint pas le seuil AA sur le rose.
        let texte = JoleneHex.parse(JoleneColor.onGradientHex)!
        for teinte in [JoleneHSL(326, 100, 71), JoleneHSL(326, 90, 65), JoleneHSL(267, 100, 75), JoleneHSL(267, 85, 70)] {
            XCTAssertGreaterThanOrEqual(texte.contrastRatio(with: teinte.rgb), 4.5, "\(teinte)")
        }
        XCTAssertLessThan(JoleneHex(red: 1, green: 1, blue: 1).contrastRatio(with: JoleneHSL(326, 100, 71).rgb), 4.5)
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
        // formatHeures : toLocaleString('fr-FR', { maximumFractionDigits: 2 }) (sorties relevées sous Node 24).
        XCTAssertEqual(SlotList.heures(21), "21")
        XCTAssertEqual(SlotList.heures(17.5), "17,5")
        XCTAssertEqual(SlotList.heures(7 + 20.0 / 60), "7,33")
        XCTAssertEqual(SlotList.heures(7 + 50.0 / 60), "7,83")
        XCTAssertEqual(SlotList.heures(1234.5), "1\u{202F}234,5")
        XCTAssertEqual(SlotList.heures(0), "0")
        XCTAssertEqual(SlotList.resume(count: 3, totalHeures: 21), "3 créneaux · 21 h au total")
        XCTAssertEqual(SlotList.resume(count: 1, totalHeures: 7.5), "1 créneau · 7,5 h au total")
    }

    func testSlotListDepuisLePlanningCandidatBloqueOuExact() {
        // Planning non exact : encart « Planning exact à confirmer » + message de blocage du cœur, aucune ligne.
        let bloque = PlanningCandidat(creneaux: [], exact: false, totalHeures: 0, periodeEtendue: false,
                                      messageBlocage: PlanningCandidatRules.messagePlanningIncomplet)
        let presentationBloquee = SlotList.Presentation.planning(bloque)
        XCTAssertEqual(presentationBloquee.blocked,
                       SlotList.Presentation.Blocked(title: "Planning exact à confirmer",
                                                     message: PlanningCandidatRules.messagePlanningIncomplet))
        XCTAssertTrue(presentationBloquee.visibleItems.isEmpty)
        XCTAssertNil(presentationBloquee.resume)
        // Planning exact sur deux jours : résumé accordé, lignes du cœur, mention des jours non travaillés.
        let lundi = MissionSlot(id: "c1", debut: "2026-11-02T07:00:00Z", fin: "2026-11-02T15:00:00Z", estPause: false, typeCreneau: "PREVISIONNEL")
        let mardi = MissionSlot(id: "c2", debut: "2026-11-03T07:00:00Z", fin: "2026-11-03T16:30:00Z", estPause: false, typeCreneau: "PREVISIONNEL")
        let exact = PlanningCandidat(creneaux: [lundi, mardi], exact: true, totalHeures: 17.5, periodeEtendue: true, messageBlocage: nil)
        let presentation = SlotList.Presentation.planning(exact, limit: 1)
        XCTAssertNil(presentation.blocked)
        XCTAssertEqual(presentation.resume, "2 créneaux · 17,5 h au total")
        XCTAssertEqual(presentation.visibleItems.map(\.label), [MissionPresentation.creneau(lundi)])
        XCTAssertEqual(presentation.remainingText, "+ 1 autre créneau dans le récapitulatif complet")
        XCTAssertEqual(presentation.footnote,
                       "Seuls les créneaux listés sont travaillés. Les autres jours de la période ne sont pas travaillés.")
        XCTAssertNil(SlotList.Presentation.planning(exact, mentionJoursNonTravailles: false).footnote)
        let ponctuel = PlanningCandidat(creneaux: [lundi], exact: true, totalHeures: 8, periodeEtendue: false, messageBlocage: nil)
        XCTAssertNil(SlotList.Presentation.planning(ponctuel).footnote, "Mention réservée à une période étendue")
        // Planning non exact sans message (cas défensif) : message d'incomplétude du cœur, jamais un encart vide.
        let sansMessage = PlanningCandidat(creneaux: [], exact: false, totalHeures: 0, periodeEtendue: false, messageBlocage: nil)
        XCTAssertEqual(SlotList.Presentation.planning(sansMessage).blocked?.message, PlanningCandidatRules.messagePlanningIncomplet)
    }

    // MARK: - StickyActionBar

    func testStickyActionBarAfficheLesValeursServeurTellesQuellesEtGereLeChargement() {
        // DetailMissionSoignant.tsx l.1568-1611 : montant + précision (« avant cotisations libérales »
        // ou « estimation figée à l'acceptation ») + CTA ; `loading` ou `disabled` bloquent le CTA.
        let content = StickyActionBar.Content(montant: "~1 234 € net estimé", precision: "avant cotisations libérales",
                                              actionTitle: "Postuler", identifier: "mission-detail-sticky")
        XCTAssertEqual(content.accessibilitySummary, "~1 234 € net estimé, avant cotisations libérales")
        // Le résumé est un seul élément combiné : il porte l'identifiant `-montant` (les enfants combinés
        // ne sont pas exposés aux XCUITest).
        XCTAssertEqual(content.montantIdentifier, "mission-detail-sticky-montant")
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
        XCTAssertEqual(content.montantIdentifier, "mission-detail-sticky-montant")
        XCTAssertEqual(StickyActionBar.maximumContentWidth, 640, "Même largeur utile que le détail mission sur iPad")
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
        let vues: [(String, AnyView)] = [
            ("destructif", AnyView(JoleneButton("Supprimer mon compte", style: .destructive) {})),
            ("destructif en chargement", AnyView(JoleneButton("Supprimer", style: .destructive, isLoading: true) {})),
            ("confirmation", AnyView(ConfirmationSheet(.init(title: "T", message: "M", identifier: "sheet"), onCancel: {}, onConfirm: {}))),
            ("confirmation phrase", AnyView(ConfirmationSheet(suppression, isLoading: false, onCancel: {}, onConfirm: {}))),
            ("confirmation contenu", AnyView(ConfirmationSheet(.init(title: "T", message: "M", identifier: "recap"), isLoading: true,
                                                                isConfirmEnabled: false, onCancel: {}, onConfirm: {}) {
                SlotList(planning: planning, identifier: "recap-creneaux")
            })),
            ("pastilles", AnyView(FilterChipRow(identifier: "explorer-chips") {
                FilterChip("🔥 Urgentes", isSelected: true, identifier: "chip-urgentes") {}
                FilterChip("🌙 Nuit", isSelected: false, identifier: "chip-nuit") {}
            })),
            ("créneaux vides", AnyView(SlotList(items: [], identifier: "mission-detail-creneaux"))),
            ("créneaux", AnyView(SlotList(slots: [lundi], identifier: "mission-detail-creneaux", showsResume: true))),
            ("planning exact", AnyView(SlotList(planning: planning, identifier: "recap-creneaux", limit: 1))),
            ("planning bloqué", AnyView(SlotList(planning: bloque, identifier: "recap-creneaux"))),
            ("barre collante", AnyView(StickyActionBar(sticky, isLoading: true) {})),
            ("barre montée", AnyView(Color.clear.stickyActionBar(isPresented: true, sticky) {})),
            ("encart", AnyView(InlineNotice("Message", title: "Titre", tone: .warning, identifier: "notice"))),
            ("squelette", AnyView(SkeletonBlock(size: .lg, identifier: "skeleton"))),
            ("carte squelette", AnyView(SkeletonCard(identifier: "skeleton-card"))),
            ("en-tête", AnyView(SectionHeader("Prochaines missions", identifier: "accueil-prochaines", actionTitle: "Tout voir") {})),
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
