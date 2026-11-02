import XCTest
import SwiftUI
import JoleneCore
@testable import JoleneDesign

/// Lot 1 (T1b) : règles pures des nouveaux composants. Les vues SwiftUI ne sont pas
/// rendues ici ; chaque composant expose la partie calculable (identifiants, libellés
/// d'accessibilité, correspondances de style) pour qu'elle soit vérifiée sans simulateur
/// d'interface. Le rendu est couvert par les XCUITest démo des écrans qui les montent.
final class JoleneDesignLot1Tests: XCTestCase {
    // MARK: - JoleneButton.destructive

    func testDestructiveStyleReproduitLeDegradeBoutonY2K() {
        // src/components/y2k/BoutonY2K.tsx : `from-[#FF4D6B] to-[#FF6BBE]`.
        XCTAssertEqual(JoleneColor.destructiveGradientHex, ["#FF4D6B", "#FF6BBE"])
        let debut = JoleneHex.parse(JoleneColor.destructiveGradientHex[0])
        let fin = JoleneHex.parse(JoleneColor.destructiveGradientHex[1])
        XCTAssertEqual(debut, JoleneHex(red: 1, green: 77 / 255, blue: 107 / 255))
        XCTAssertEqual(fin, JoleneHex(red: 1, green: 107 / 255, blue: 190 / 255))
        // Les styles pleins (dégradé) portent un texte blanc ; le secondaire reste en bordure rose.
        XCTAssertTrue(JoleneButton.Style.destructive.isFilled)
        XCTAssertTrue(JoleneButton.Style.primary.isFilled)
        XCTAssertFalse(JoleneButton.Style.secondary.isFilled)
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
        // Identifiants dérivés : un XCUITest atteint chaque contrôle sans lire le libellé.
        XCTAssertEqual(config.titleIdentifier, "candidature-retrait-title")
        XCTAssertEqual(config.messageIdentifier, "candidature-retrait-message")
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
    }

    // MARK: - FilterChip

    func testFilterChipExposeSonEtatCommeAriaPressed() {
        // RechercheMissions.tsx : `aria-pressed={chip.actif}`, actif = dégradé hero + texte blanc.
        let actif = FilterChip.Appearance.resolve(isSelected: true)
        XCTAssertTrue(actif.usesGradient)
        XCTAssertEqual(actif.accessibilityValue, "activé")
        let inactif = FilterChip.Appearance.resolve(isSelected: false)
        XCTAssertFalse(inactif.usesGradient)
        XCTAssertEqual(inactif.accessibilityValue, "désactivé")
        XCTAssertEqual(FilterChip.minimumHeight, 44, "Cible tactile 44 pt (min-h-[44px] du web)")
    }

    // MARK: - SlotList

    func testSlotListNommeLesCreneauxCommeLeDetailMissionEtAccordeLeResume() {
        // MissionDetailScreen (lot 0) : `mission-detail-creneau-<index + 1>`.
        XCTAssertEqual(SlotList.identifier(prefix: "mission-detail", index: 0), "mission-detail-creneau-1")
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

    // MARK: - StickyActionBar

    func testStickyActionBarAfficheLesValeursServeurTellesQuellesEtGereLeChargement() {
        // DetailMissionSoignant.tsx l.1568-1611 : montant + précision (« avant cotisations libérales »
        // ou « estimation figée à l'acceptation ») + CTA ; `loading` ou `disabled` bloquent le CTA.
        let content = StickyActionBar.Content(montant: "~1 234 € net estimé", precision: "avant cotisations libérales",
                                              actionTitle: "Postuler", identifier: "mission-detail-sticky")
        XCTAssertEqual(content.accessibilitySummary, "~1 234 € net estimé, avant cotisations libérales")
        XCTAssertEqual(content.montantIdentifier, "mission-detail-sticky-montant")
        XCTAssertEqual(content.precisionIdentifier, "mission-detail-sticky-precision")
        XCTAssertEqual(content.actionIdentifier, "mission-detail-sticky-action")
        let sansPrecision = StickyActionBar.Content(montant: "Rétrocession 70 %", precision: nil,
                                                    actionTitle: "Accepter", identifier: "mission-detail-sticky")
        XCTAssertEqual(sansPrecision.accessibilitySummary, "Rétrocession 70 %")
        XCTAssertTrue(StickyActionBar.isActionEnabled(isLoading: false, isDisabled: false))
        XCTAssertFalse(StickyActionBar.isActionEnabled(isLoading: true, isDisabled: false))
        XCTAssertFalse(StickyActionBar.isActionEnabled(isLoading: false, isDisabled: true))
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
    }

    // MARK: - SectionHeader

    func testSectionHeaderDeriveSesIdentifiants() {
        XCTAssertEqual(SectionHeader.titleIdentifier(for: "accueil-prochaines"), "accueil-prochaines-title")
        XCTAssertEqual(SectionHeader.actionIdentifier(for: "accueil-prochaines"), "accueil-prochaines-action")
    }

    // MARK: - Construction des vues (le corps est vérifié par les XCUITest démo)

    @MainActor
    func testLesVuesDuLot1SeConstruisentSansRendu() {
        _ = JoleneButton("Supprimer mon compte", style: .destructive) {}
        _ = ConfirmationSheet(.init(title: "T", message: "M", identifier: "sheet"), onCancel: {}, onConfirm: {})
        _ = ConfirmationSheet(.init(title: "T", message: "M", identifier: "sheet"), isLoading: true, onCancel: {}, onConfirm: {}) {
            Text("Détail")
        }
        _ = FilterChip("Urgentes", isSelected: true, identifier: "explorer-chip-urgentes") {}
        _ = SlotList(items: [], identifier: "mission-detail-creneaux")
        _ = StickyActionBar(.init(montant: "70,00 €/h", precision: nil, actionTitle: "Postuler", identifier: "sticky")) {}
        _ = InlineNotice("Message", tone: .warning, identifier: "notice")
        _ = SkeletonBlock(size: .lg, identifier: "skeleton")
        _ = SectionHeader("Prochaines missions", identifier: "accueil-prochaines")
    }
}
