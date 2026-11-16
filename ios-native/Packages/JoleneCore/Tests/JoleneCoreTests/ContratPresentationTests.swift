import XCTest
@testable import JoleneCore

/// Lot 2, T9a — présentation des contrats (`Contrats/ContratPresentation.swift`) : cartes de la liste (rendu mobile
/// `renduCarte` de `ListeContrats.tsx` l.205-226), dates en heure de Paris (masques date-fns du web), textes du
/// contenu et de la préparation du document (`ContratMission.tsx` l.377, l.388, l.635-637 ; consigne T9a de
/// `DECISIONS_LOT2.md`), « Document officiel figé » (l.620-625), section Signatures (l.666-706), certificat résumé
/// (`CertificatSignature.tsx` l.109-168) et renvois web. Chaque texte vient de `TextesWeb` ou de `LibellesWeb` ;
/// aucune règle n'est écrite à l'écran.
final class ContratPresentationTests: XCTestCase {
    private func resume(statut: String = "EN_ATTENTE_SIGNATURES", soignant: Bool? = false, numero: String? = "C-2026-1",
                        type: String? = "CDD", creeLe: String? = "2026-10-29T00:00:00Z",
                        intitule: String? = "Nuit en médecine") -> ContratResume {
        ContratResume(id: "k-1", missionId: "m-1", statut: statut, typeContrat: type, creeLe: creeLe, numeroContrat: numero,
                      signatureSoignant: soignant, mission: MissionResumeContrat(intitule: intitule))
    }

    private func detail(statut: String = "EN_ATTENTE_SIGNATURES", soignant: Bool? = false, etablissement: Bool? = false,
                        soignantLe: String? = nil, etablissementLe: String? = nil) -> ContratDetail {
        ContratDetail(id: "k-1", missionId: "m-1", statut: statut, typeContrat: "CDD", signatureSoignant: soignant,
                      signatureEtablissement: etablissement, signatureSoignantLe: soignantLe,
                      signatureEtablissementLe: etablissementLe, creeLe: "2026-11-01T14:00:00Z", numeroContrat: "C-2026-1")
    }

    // MARK: - Liste

    func testCarteDeListeCommeLeRenduMobileDuWeb() {
        let carte = ContratPresentation.carte(resume())
        XCTAssertEqual(carte.id, "k-1")
        XCTAssertEqual(carte.numero, "C-2026-1")
        XCTAssertEqual(carte.statut, .enAttente)
        XCTAssertEqual(carte.badge, "⏳ En attente")
        XCTAssertEqual(carte.mission, "📋 Nuit en médecine")
        XCTAssertEqual(carte.typeEtDate, "CDD · Créé le 29/10/2026", "cree_le 00:00 UTC = 01:00 à Paris (heure d'hiver)")
        XCTAssertEqual(carte.action, "✍️ Signer le contrat")
        XCTAssertTrue(carte.aSigner)
    }

    func testCarteSansNumeroNiMissionNiDateLisible() {
        let carte = ContratPresentation.carte(resume(statut: "SIGNE_COMPLET", soignant: true, numero: nil, type: nil,
                                                     creeLe: "pas une date", intitule: ""))
        XCTAssertEqual(carte.numero, "—", "`c.numero_contrat || '—'` (l.210)")
        XCTAssertEqual(carte.statut, .signe)
        XCTAssertEqual(carte.badge, "✅ Signé")
        XCTAssertEqual(carte.mission, "📋 —", "intitulé vide : `|| '—'` (l.214)")
        XCTAssertEqual(carte.typeEtDate, " · Créé le —", "type NULL rendu vide par React ; date illisible : tiret, jamais une date inventée")
        XCTAssertEqual(carte.action, "Voir le contrat")
        XCTAssertFalse(carte.aSigner)
    }

    func testCarteAnnuleeJamaisASignerExpireeEncoreProposee() {
        let annulee = ContratPresentation.carte(resume(statut: "ANNULE"))
        XCTAssertEqual(annulee.badge, "❌ Annulé")
        XCTAssertFalse(annulee.aSigner)
        XCTAssertEqual(annulee.action, "Voir le contrat")
        // `aSigner` du web (l.156-158) n'exclut que ANNULE : un contrat expiré non signé garde l'appel à signer,
        // et la page du contrat affiche son bandeau d'expiration.
        let expiree = ContratPresentation.carte(resume(statut: "EXPIRE"))
        XCTAssertEqual(expiree.badge, "⏳ En attente")
        XCTAssertTrue(expiree.aSigner)
    }

    // MARK: - Dates

    func testDatesEnHeureDeParisAvecLesMasquesDuWeb() {
        XCTAssertEqual(ContratPresentation.date("2026-10-29T01:00:00Z", masque: LibellesWeb.Contrat.formatDateHeure),
                       "29/10/2026 à 02:00")
        XCTAssertEqual(ContratPresentation.date("2026-07-01T10:00:00+00:00", masque: LibellesWeb.Contrat.formatDateHeure),
                       "01/07/2026 à 12:00", "heure d'été")
        XCTAssertEqual(ContratPresentation.date("2026-10-29T01:00:05.000Z", masque: LibellesWeb.Certificat.formatDateHeure),
                       "29/10/2026 à 02:00:05")
        XCTAssertEqual(ContratPresentation.date("2026-11-01T23:30:00Z", masque: LibellesWeb.Contrats.formatDateCreation),
                       "02/11/2026", "minuit passé à Paris")
        XCTAssertNil(ContratPresentation.date(nil, masque: LibellesWeb.Contrat.formatDateHeure))
        XCTAssertNil(ContratPresentation.date("", masque: LibellesWeb.Contrat.formatDateHeure))
        XCTAssertNil(ContratPresentation.date("illisible", masque: LibellesWeb.Contrat.formatDateHeure))
    }

    // MARK: - Contenu et préparation du document

    func testMessageDuContenuSelonLeMotif() {
        let ouvert = detail()
        let signe = detail(soignant: true)
        XCTAssertNil(ContratPresentation.messageContenu(motif: nil, contrat: ouvert), "original contrôlé : le lecteur l'affiche")
        XCTAssertEqual(ContratPresentation.messageContenu(motif: .cddAPreparer, contrat: ouvert), TextesWeb.Contrat.contenuPasDisponible)
        XCTAssertEqual(ContratPresentation.messageContenu(motif: .nonFige, contrat: ouvert), TextesWeb.Contrat.contenuPasDisponible)
        XCTAssertEqual(ContratPresentation.messageContenu(motif: .renduRefuse(messageServeur: "x"), contrat: ouvert),
                       TextesWeb.Contrat.contenuPasDisponible)
        XCTAssertEqual(ContratPresentation.messageContenu(motif: .storageMismatch, contrat: signe), TextesWeb.Contrat.originalIndisponible,
                       "contrat porteur d'une signature : aucune reconstitution (l.635-636)")
        XCTAssertEqual(ContratPresentation.messageContenu(motif: .hashMismatch, contrat: detail(statut: "SIGNE_SOIGNANT")),
                       TextesWeb.Contrat.originalIndisponible)
    }

    func testMessageDePreparationDansLaZoneDeSignature() {
        XCTAssertEqual(ContratPresentation.messagePreparation(motif: .renduRefuse(messageServeur: "Contrat introuvable.")),
                       "Le document contractuel final n’a pas pu être préparé. Contrat introuvable. Réessayez avant de signer.")
        XCTAssertEqual(ContratPresentation.messagePreparation(motif: .renduRefuse(messageServeur: nil)),
                       "Le document contractuel final n’a pas pu être préparé. Réessayez avant de signer.")
        XCTAssertEqual(ContratPresentation.messagePreparation(motif: .variablesNonRendues),
                       "Le document contractuel final est encore incomplet. Réessayez avant de signer.")
        for motif: MotifOriginalIndisponible? in [nil, .nonFige, .hashMismatch, .storageMismatch, .signatureMismatch, .cddAPreparer] {
            XCTAssertNil(ContratPresentation.messagePreparation(motif: motif), "\(String(describing: motif))")
        }
    }

    func testDocumentOfficielFigeAvecSonEmpreinte() {
        let empreinte = VerificationOriginal.empreinte("<p>Contrat</p>")
        var contrat = detail()
        contrat.contenuHtmlRenduLe = "2026-11-01T14:05:00Z"
        contrat.hashDocument = empreinte
        XCTAssertEqual(ContratPresentation.documentFige(contrat),
                       "Document officiel figé le 01/11/2026 à 15:05 — empreinte " + String(empreinte.prefix(8)) + "…"
                       + String(empreinte.suffix(4)))
        contrat.hashDocument = nil
        XCTAssertEqual(ContratPresentation.documentFige(contrat), "Document officiel figé le 01/11/2026 à 15:05")
        contrat.contenuHtmlRenduLe = "illisible"
        XCTAssertNil(ContratPresentation.documentFige(contrat))
        contrat.contenuHtmlRenduLe = nil
        XCTAssertNil(ContratPresentation.documentFige(contrat), "affiché seulement quand `contenu_html_rendu_le` existe (l.620)")
    }

    // MARK: - Signatures

    func testLignesDeLaSectionSignatures() {
        let lignes = ContratPresentation.lignesSignatures(detail(etablissement: true, etablissementLe: "2026-10-29T01:00:00Z"))
        XCTAssertEqual(lignes.map(\.texte), ["Établissement : ✅ Signé le 29/10/2026 à 02:00", "Soignant(e) : ⏳ En attente"])
        XCTAssertEqual(lignes.map(\.signee), [true, false])
        XCTAssertEqual(lignes.map(\.partie), [.etablissement, .soignant])
        // Contrat complet : les deux lignes sont signées même sans drapeau ni date (l.672, l.691).
        let complet = ContratPresentation.lignesSignatures(detail(statut: "SIGNE_COMPLET", soignant: nil, etablissement: nil))
        XCTAssertEqual(complet.map(\.texte), ["Établissement : ✅ Signé", "Soignant(e) : ✅ Signé"])
        // Date illisible : « Signé » sans date, jamais une date inventée.
        let illisible = ContratPresentation.lignesSignatures(detail(soignant: true, soignantLe: "illisible"))
        XCTAssertEqual(illisible.map(\.texte), ["Établissement : ⏳ En attente", "Soignant(e) : ✅ Signé"])
    }

    // MARK: - Certificat

    func testSignatairesDuCertificatCommeLeRenduResume() {
        let lignes = [
            SignatureCertificat(id: "s-1", contratId: "k-1", signataireRole: "etablissement", signeA: "2026-10-29T01:00:00Z",
                                otpValideA: "2026-10-29T01:00:00Z", pscSessionActive: false, rppsVerifie: false,
                                statutSignature: "signe"),
            SignatureCertificat(id: "s-2", contratId: "k-1", signataireRole: "soignant", pscSessionActive: nil, rppsVerifie: true,
                                statutSignature: "otp_envoye"),
        ]
        let signataires = ContratPresentation.signataires(lignes)
        XCTAssertEqual(signataires.map(\.id), ["s-1", "s-2"])
        XCTAssertEqual(signataires.map(\.role), ["Etablissement", "Soignant"], "`capitalize` du CSS (l.113)")
        XCTAssertEqual(signataires.map(\.statut), ["✅ Signé", "otp_envoye"], "code serveur brut hors `signe` (l.121)")
        XCTAssertEqual(signataires.map(\.signe), [true, false])
        XCTAssertEqual(signataires[0].lignes, [
            .init(libelle: "Date / heure", valeur: "29/10/2026 à 02:00:00"),
            .init(libelle: "OTP validé", valeur: "✓ Code SMS vérifié"),
            .init(libelle: "RPPS vérifié", valeur: "—"),
            .init(libelle: "PSC actif", valeur: "—"),
        ])
        XCTAssertEqual(signataires[1].lignes, [
            .init(libelle: "RPPS vérifié", valeur: "✓"),
            .init(libelle: "PSC actif", valeur: "—"),
        ], "ni date ni OTP : lignes absentes, comme le web (l.126, l.134)")
    }

    func testRoleCapitaliseCommeLeCSS() {
        XCTAssertEqual(ContratPresentation.roleAffiche("etablissement"), "Etablissement")
        XCTAssertEqual(ContratPresentation.roleAffiche("admin plateforme"), "Admin Plateforme")
        XCTAssertEqual(ContratPresentation.roleAffiche("SOIGNANT"), "SOIGNANT", "capitalize ne met pas en minuscules")
        XCTAssertEqual(ContratPresentation.roleAffiche(nil), "")
        XCTAssertEqual(ContratPresentation.roleAffiche(""), "")
    }

    // MARK: - Renvois web

    func testRenvoisWebVersLesPagesDuContrat() throws {
        XCTAssertEqual(ContratPresentation.renvoiSignature(contratId: "demo-contrat-001"),
                       .safari(try XCTUnwrap(URL(string: "https://jolene.app/contrat/demo-contrat-001"))))
        XCTAssertEqual(ContratPresentation.renvoiCertificat(contratId: "6d3f0a52-8b1e-4c7a-9f20-31e5c4b7d8a9"),
                       .safari(try XCTUnwrap(URL(string: "https://jolene.app/contrat/6d3f0a52-8b1e-4c7a-9f20-31e5c4b7d8a9/certificat"))))
        // Toujours une sortie Safari, même quand `/contrat/:id` deviendra natif (T10) : la signature reste sur le web
        // jusqu'à T9b, l'export PDF du certificat au-delà (LOT2_PLAN §1.2).
        XCTAssertFalse(try XCTUnwrap(ContratPresentation.renvoiSignature(contratId: "k-1")).isNative)
        for invalide in ["", "../admin", "k 1", "k-1?x=1", "k-1#f", "k/1"] {
            XCTAssertNil(ContratPresentation.renvoiSignature(contratId: invalide), invalide)
            XCTAssertNil(ContratPresentation.renvoiCertificat(contratId: invalide), invalide)
        }
    }
}
