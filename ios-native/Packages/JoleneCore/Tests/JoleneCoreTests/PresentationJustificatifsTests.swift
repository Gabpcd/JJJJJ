import XCTest
@testable import JoleneCore

/// Présentation de l'écran Justificatifs (lot 2 T7), portée du rendu de `src/pages/DocumentsSoignant.tsx` : bandeaux de
/// profil (l.530-555), en-tête de progression (l.558-598), expirations proches (l.601-609), incohérence (l.287-306,
/// l.643-650), cartes des exigences (l.654-811, REJETE avant EXPIRE), documents complémentaires (l.852-903), attestation
/// signée (l.115-120), issues d'envoi (l.377-430, consignes T7 de `DECISIONS_LOT2.md`). État dérivé, aucune règle locale
/// à l'écran ; dates `d MMM yyyy` en français, heure de Paris.
final class PresentationJustificatifsTests: XCTestCase {
    private typealias P = PresentationJustificatifs
    private let maintenant = DemoWorld.fixedNow

    private func demo() throws -> DossierDocuments {
        let fichier = try DemoFixtures.loadDocuments()
        return DossierDocuments.assembler(profil: fichier.profil, regles: fichier.exigences, documents: fichier.documents,
                                          attestationSanteSigneeLe: fichier.attestationSanteSigneeLe)
    }

    private func regle(_ type: String, critique: Bool = true, profession: String = "IDE") -> ExigenceDocument {
        ExigenceDocument(id: "r-\(type)", profession: profession, typeDocument: type, estCritique: critique, typeExerciceRequis: "TOUS")
    }

    private func dossier(_ documents: [DocumentSoignant], regles: [ExigenceDocument]? = nil, profession: String? = "IDE",
                         exercice: String? = "SALARIE", rpps: Bool = false) -> DossierDocuments {
        let profil = SoignantExigencesDocuments(profession: profession, typeExercice: exercice, rppsVerifie: rpps, adeliVerifie: false)
        return DossierDocuments.assembler(profil: profil, regles: regles ?? [regle("CARTE_IDENTITE"), regle("DIPLOME")],
                                          documents: documents, attestationSanteSigneeLe: nil)
    }

    private func carte(_ type: String, dans cartes: [CarteJustificatif]) throws -> CarteJustificatif {
        try XCTUnwrap(cartes.first { $0.typeDocument == type }, type)
    }

    // MARK: - Bandeaux de profil et en-tête

    func testBandeauxDuProfilIncompletSansBouton() {
        XCTAssertEqual(P.bandeauxProfil(dossier([], profession: nil)),
                       [BandeauProfil(titre: "Profession non définie",
                                      texte: "Renseignez votre profession dans votre profil pour voir les documents qui vous concernent.")])
        XCTAssertEqual(P.bandeauxProfil(dossier([], exercice: nil)).map(\.titre), ["Mode d’exercice à préciser"])
        XCTAssertEqual(P.bandeauxProfil(dossier([], exercice: "")).map(\.titre), ["Mode d’exercice à préciser"], "chaîne vide : falsy")
        XCTAssertEqual(P.bandeauxProfil(dossier([])), [])
        XCTAssertEqual(P.bandeauxProfil(DossierDocuments()), [], "sans dossier : l'écran « Votre dossier » prend le relais")
    }

    func testEnteteDuDossierDeDemonstration() throws {
        let entete = try XCTUnwrap(P.entete(try demo(), maintenant: maintenant))
        XCTAssertEqual(entete, .aCompleter(titre: "Il vous reste 1 document — ~3 min, une photo suffit",
                                           prochaineEtape: "Prochaine étape : Pièce d'identité",
                                           bouton: "Téléverser — Pièce d'identité", typeProchaine: "CARTE_IDENTITE",
                                           valides: 2, total: 3,
                                           note: "Vous pouvez postuler dès maintenant — validez vos documents pour être accepté par les établissements."))
    }

    func testEnteteSelonLeNombreDePiecesValides() {
        let aucune = P.entete(dossier([]), maintenant: maintenant)
        if case let .aCompleter(titre, _, _, type, valides, total, _)? = aucune {
            XCTAssertEqual(titre, "Il vous reste 2 documents — ~3 min, une photo suffit")
            XCTAssertEqual(type, "CARTE_IDENTITE")
            XCTAssertEqual(valides, 0)
            XCTAssertEqual(total, 2)
        } else {
            XCTFail("en-tête à compléter attendu : \(String(describing: aucune))")
        }
        let valides = [DocumentSoignant(id: "a", typeDocument: "CARTE_IDENTITE", statutVerification: "VERIFIE"),
                       DocumentSoignant(id: "b", typeDocument: "DIPLOME", statutVerification: "VERIFIE")]
        XCTAssertEqual(P.entete(dossier(valides), maintenant: maintenant),
                       .aJour(titre: "Tous vos documents obligatoires sont à jour 🎉",
                              detail: "Retrouvez ici vos justificatifs et leurs dates de validité."))
        XCTAssertEqual(P.entete(dossier(valides, exercice: nil), maintenant: maintenant),
                       .aJour(titre: "Les justificatifs affichés sont à jour", detail: "Retrouvez ici vos justificatifs et leurs dates de validité."))
        XCTAssertEqual(P.entete(dossier([], regles: [regle("RIB", critique: false)]), maintenant: maintenant),
                       .aucuneExigence(titre: "Vos justificatifs",
                                       detail: "Aucun document obligatoire n’est affiché pour votre profil actuellement."))
        XCTAssertNil(P.entete(dossier([], profession: nil), maintenant: maintenant), "sans profession, aucun en-tête (l.558)")
        XCTAssertNil(P.entete(dossier([], profession: ""), maintenant: maintenant))
    }

    // MARK: - Expirations et incohérence

    func testExpirationProcheDuDossierDeDemonstration() throws {
        let expirations = P.expirations(try demo(), maintenant: maintenant)
        XCTAssertEqual(expirations.map(\.document.id), ["demo-doc-rcp"])
        XCTAssertEqual(expirations.first?.texte, "⏰ Votre Assurance RCP expire dans 12 jours (14 nov. 2026).")
        XCTAssertEqual(expirations.first?.typeDocument, "RCP_ASSURANCE")
        let demain = dossier([DocumentSoignant(id: "x", typeDocument: "CARTE_IDENTITE", valideJusqua: "2026-11-03",
                                               statutVerification: "VERIFIE")])
        XCTAssertEqual(P.expirations(demain, maintenant: maintenant).first?.texte,
                       "⏰ Votre Pièce d'identité expire dans 1 jour (3 nov. 2026).")
        let horsDelai = dossier([DocumentSoignant(id: "x", typeDocument: "CARTE_IDENTITE", valideJusqua: "2027-01-15",
                                                  statutVerification: "VERIFIE")])
        XCTAssertEqual(P.expirations(horsDelai, maintenant: maintenant), [])
    }

    func testIncoherenceCommeLeWeb() {
        let sans = dossier([DocumentSoignant(id: "x", typeDocument: "CARTE_IDENTITE", statutVerification: "VERIFIE")])
        XCTAssertNil(P.incoherence(sans, coherence: CoherenceDocuments(coherent: true), maintenant: maintenant))
        XCTAssertNil(P.incoherence(sans, coherence: nil, maintenant: maintenant))
        XCTAssertNil(P.incoherence(dossier([]), coherence: CoherenceDocuments(coherent: false, problemes: ["Nom"]), maintenant: maintenant),
                     "aucune pièce : aucun contrôle (l.288)")
        XCTAssertEqual(P.incoherence(sans, coherence: CoherenceDocuments(coherent: false, problemes: ["Nom différent", "Prénom différent"]),
                                     maintenant: maintenant),
                       "⚠️ Incohérence détectée entre vos documents : Nom différent. Prénom différent Vérifiez que tous vos documents sont à jour et au même nom.")
        let rcpExpiree = dossier([DocumentSoignant(id: "r", typeDocument: "RCP_ASSURANCE", valideJusqua: "2026-10-01",
                                                   statutVerification: "VERIFIE")])
        XCTAssertEqual(P.incoherence(rcpExpiree, coherence: nil, maintenant: maintenant),
                       "⚠️ Incohérence détectée entre vos documents : Votre assurance RCP est expirée. Vérifiez que tous vos documents sont à jour et au même nom.")
        XCTAssertEqual(P.incoherence(rcpExpiree, coherence: CoherenceDocuments(coherent: false, problemes: ["Nom différent"]),
                                     maintenant: maintenant),
                       "⚠️ Incohérence détectée entre vos documents : Votre assurance RCP est expirée. Nom différent Vérifiez que tous vos documents sont à jour et au même nom.")
        XCTAssertEqual(P.incoherence(rcpExpiree, coherence: CoherenceDocuments(coherent: false, problemes: []), maintenant: maintenant),
                       "⚠️ Incohérence détectée entre vos documents : Votre assurance RCP est expirée. Vérifiez que tous vos documents sont à jour et au même nom.",
                       "incohérent sans problème : seules les alertes locales (l.297)")
    }

    // MARK: - Cartes des exigences

    func testCartesDuDossierDeDemonstration() throws {
        let cartes = P.cartes(try demo(), maintenant: maintenant, enVerification: [], reverification: nil, demandeRevue: nil)
        XCTAssertEqual(cartes.map(\.typeDocument), ["CARTE_IDENTITE", "DIPLOME", "RCP_ASSURANCE", "RIB"], "critiques puis optionnelles")
        XCTAssertEqual(cartes.map(\.ouvreLesOptionnels), [false, false, false, true])
        XCTAssertEqual(cartes.map(\.obligatoire), [true, true, true, false])
        XCTAssertEqual(cartes.map(\.titre), ["Pièce d'identité", "Diplôme d'État", "Assurance RCP", "RIB"])
        XCTAssertEqual(cartes.first?.description, "Exigence de démonstration")

        // REJETE prime sur la date passée (l.660-663) : motif affiché tel quel, ponctuation du web comprise.
        let identite = try carte("CARTE_IDENTITE", dans: cartes)
        XCTAssertEqual(identite.badge, BadgeJustificatif(texte: "Rejeté", ton: .erreur, enCours: false))
        XCTAssertEqual(identite.messages, [TexteJustificatif(
            texte: "Document non valide — Pièce de démonstration illisible.. Vous pouvez le remplacer ou demander une revue humaine.",
            ton: .erreur)])
        XCTAssertEqual(identite.actions.map(\.genre), [.televerser, .voir, .reverifier, .demanderRevue])
        XCTAssertEqual(identite.actions.map(\.libelle), ["Réessayer", "Voir", "Revérifier", "Demander une revue humaine"])
        XCTAssertEqual(identite.actions.map(\.principale), [true, false, false, false])
        XCTAssertNil(identite.fichier)

        let diplome = try carte("DIPLOME", dans: cartes)
        XCTAssertEqual(diplome.fichier, "📎 diplome-demonstration.pdf (téléversé le 21 oct. 2026)")
        XCTAssertEqual(diplome.badge, BadgeJustificatif(texte: "Vérifié ✅", ton: .succes, enCours: false))
        XCTAssertEqual(diplome.dates, ["Délivré le 1 juil. 2020"])
        XCTAssertEqual(diplome.actions.map(\.libelle), ["Voir le document", "Remplacer"], "vérifié : ni revérification ni revue")

        XCTAssertEqual(try carte("RCP_ASSURANCE", dans: cartes).dates, ["Valide jusqu'au 14 nov. 2026"])

        let rib = try carte("RIB", dans: cartes)
        XCTAssertEqual(rib.badge, BadgeJustificatif(texte: "Expiré", ton: .attention, enCours: false))
        XCTAssertEqual(rib.messages, [TexteJustificatif(texte: "Document expiré depuis le 15 oct. 2026. Veuillez en téléverser un récent.",
                                                        ton: .attention)])
        XCTAssertEqual(rib.actions.map(\.libelle), ["Téléverser un nouveau document", "Revérifier"])
    }

    func testCartesDesStatutsEnCoursEtDeLaRevue() throws {
        let enAttente = DocumentSoignant(id: "d1", typeDocument: "CARTE_IDENTITE", nomFichier: "cni.jpg", statutVerification: "EN_ATTENTE",
                                         televerseLe: "2026-11-01T10:00:00.000Z")
        let d = dossier([enAttente])
        var c = try carte("CARTE_IDENTITE", dans: P.cartes(d, maintenant: maintenant, enVerification: ["d1"], reverification: nil, demandeRevue: nil))
        XCTAssertEqual(c.badge, BadgeJustificatif(texte: "Vérification automatique en cours (~30 s)", ton: .attention, enCours: true))
        XCTAssertEqual(c.actions.map(\.genre), [.voir, .reverifier, .televerser], "aucune revue pendant la vérification (l.739)")
        XCTAssertEqual(c.fichier, "📎 cni.jpg (téléversé le 1 nov. 2026)")

        c = try carte("CARTE_IDENTITE", dans: P.cartes(d, maintenant: maintenant, enVerification: [], reverification: nil, demandeRevue: nil))
        XCTAssertEqual(c.badge, BadgeJustificatif(texte: "Analyse non conclue — revue humaine disponible", ton: .attention, enCours: false))
        XCTAssertEqual(c.actions.map(\.libelle), ["Voir le document", "Revérifier", "Demander une revue humaine", "Remplacer"])

        c = try carte("CARTE_IDENTITE", dans: P.cartes(d, maintenant: maintenant, enVerification: [], reverification: nil, demandeRevue: "d1"))
        let revue = try XCTUnwrap(c.actions.first { $0.genre == .demanderRevue })
        XCTAssertEqual(revue.libelle, "Demande en cours…")
        XCTAssertTrue(revue.enCours)

        c = try carte("CARTE_IDENTITE", dans: P.cartes(d, maintenant: maintenant, enVerification: [], reverification: "d1", demandeRevue: nil))
        XCTAssertEqual(c.badge?.enCours, true, "revérification en cours : même badge que le suivi (l.664)")
        XCTAssertEqual(c.actions.first { $0.genre == .reverifier }?.enCours, true)

        let revueHumaine = dossier([DocumentSoignant(id: "d2", typeDocument: "CARTE_IDENTITE", statutVerification: "REVUE_MANUELLE_REQUISE")])
        c = try carte("CARTE_IDENTITE", dans: P.cartes(revueHumaine, maintenant: maintenant, enVerification: [], reverification: nil, demandeRevue: nil))
        XCTAssertEqual(c.badge, BadgeJustificatif(texte: "Demande reçue — en attente d’attribution", ton: .info, enCours: false))
        XCTAssertEqual(c.actions.map(\.genre), [.voir, .reverifier, .televerser])
        XCTAssertEqual(c.fichier, "📎", "nom et date absents : rien d'inventé")

        let indisponible = dossier([DocumentSoignant(id: "d3", typeDocument: "CARTE_IDENTITE", statutVerification: "API_INDISPONIBLE")])
        c = try carte("CARTE_IDENTITE", dans: P.cartes(indisponible, maintenant: maintenant, enVerification: [], reverification: nil, demandeRevue: nil))
        XCTAssertEqual(c.badge, BadgeJustificatif(texte: "Vérification temporairement indisponible", ton: .neutre, enCours: false))
        XCTAssertEqual(c.actions.map(\.genre), [.voir, .reverifier, .demanderRevue, .televerser])
    }

    func testCartesRejeteeManquanteEtDiplomeAConfirmer() throws {
        let rejete = dossier([DocumentSoignant(id: "r1", typeDocument: "CARTE_IDENTITE", statutVerification: "REJETE", motifRejet: "")])
        var c = try carte("CARTE_IDENTITE", dans: P.cartes(rejete, maintenant: maintenant, enVerification: [], reverification: nil, demandeRevue: nil))
        XCTAssertEqual(c.messages.map(\.texte), ["Document non valide. Vous pouvez le remplacer ou demander une revue humaine."],
                       "motif vide ou nul : aucun tiret (l.761)")
        c = try carte("CARTE_IDENTITE", dans: P.cartes(rejete, maintenant: maintenant, enVerification: ["r1"], reverification: nil, demandeRevue: nil))
        XCTAssertEqual(c.badge, BadgeJustificatif(texte: "Vérification en cours (~30 s)", ton: .attention, enCours: true))
        XCTAssertEqual(c.messages, [], "en vérification : le motif est masqué (l.754-765)")

        let manquant = try carte("DIPLOME", dans: P.cartes(rejete, maintenant: maintenant, enVerification: [], reverification: nil, demandeRevue: nil))
        XCTAssertNil(manquant.badge)
        XCTAssertEqual(manquant.messages, [TexteJustificatif(texte: "Document à téléverser — une photo suffit", ton: .attention)])
        XCTAssertEqual(manquant.actions, [ActionJustificatif(genre: .televerser, libelle: "+ Téléverser", enCours: false, principale: true)])

        let iade = dossier([DocumentSoignant(id: "dip", typeDocument: "DIPLOME", statutVerification: "VERIFIE", professionCertifiee: "IDE")],
                           regles: [regle("DIPLOME", profession: "IADE")], profession: "IADE")
        c = try carte("DIPLOME", dans: P.cartes(iade, maintenant: maintenant, enVerification: [], reverification: nil, demandeRevue: nil))
        XCTAssertNil(c.badge, "diplôme qui ne certifie pas la spécialité : jamais « Vérifié » (l.695)")
        XCTAssertEqual(c.messages, [TexteJustificatif(
            texte: "La qualification IADE n’est pas confirmée par ce diplôme. Vous pouvez le remplacer ou demander une nouvelle vérification.",
            ton: .attention)])
        XCTAssertEqual(c.actions.map(\.genre), [.voir, .reverifier, .televerser])
    }

    // MARK: - Documents complémentaires

    func testDocumentsComplementairesSansTexteDAcces() throws {
        let complementaires = P.complementaires(try demo())
        XCTAssertEqual(complementaires.map(\.typeDocument), ["ATTESTATION_SCOLARITE", "LICENCE_REMPLACEMENT"])
        XCTAssertEqual(complementaires.map(\.titre), ["🎓 Attestation de scolarité / passage en année supérieure",
                                                       "🩺 Licence de remplacement (interne en médecine)"])
        XCTAssertEqual(complementaires.map(\.description), [nil, nil],
                       "textes d'accès (pré-éligibilité, remplacements) en attente de Gabrielle (HARD STOP n°4)")
        XCTAssertEqual(complementaires.map(\.bouton), ["+ Téléverser", "+ Téléverser"])
        XCTAssertEqual(complementaires.map(\.statut), [nil, nil])

        let medecin = DossierDocuments.assembler(
            profil: SoignantExigencesDocuments(profession: "MEDECIN", typeExercice: "LIBERAL", rppsVerifie: true, adeliVerifie: false),
            regles: [], documents: [DocumentSoignant(id: "o", typeDocument: "CARTE_ORDRE", nomFichier: "ordre.pdf", statutVerification: "EN_ATTENTE"),
                                    DocumentSoignant(id: "l", typeDocument: "LICENCE_REMPLACEMENT", statutVerification: "VERIFIE")],
            attestationSanteSigneeLe: nil)
        let cartes = P.complementaires(medecin)
        XCTAssertEqual(cartes.map(\.typeDocument), ["LICENCE_REMPLACEMENT", "CARTE_ORDRE"], "RPPS vérifié : scolarité masquée, licence d'un médecin gardée")
        XCTAssertEqual(cartes.first?.statut, "Vérifié ✓")
        XCTAssertEqual(cartes.first?.bouton, "Remplacer")
        XCTAssertEqual(cartes.last?.titre, "Inscription à l’Ordre après l’internat")
        XCTAssertEqual(cartes.last?.description,
                       "Vous êtes désormais médecin inscrit à l’Ordre ? Ajoutez l’attestation précisant votre qualification. L’équipe vérifiera cette preuve pour mettre à jour votre parcours.")
        XCTAssertEqual(cartes.last?.statut, "ordre.pdf · En attente de vérification")
        XCTAssertEqual(cartes.last?.bouton, "Remplacer l’attestation")

        let ordreInconnu = DossierDocuments.assembler(
            profil: SoignantExigencesDocuments(profession: "MEDECIN", typeExercice: "LIBERAL", rppsVerifie: false, adeliVerifie: false),
            regles: [], documents: [DocumentSoignant(id: "o", typeDocument: "CARTE_ORDRE", nomFichier: "ordre.pdf", statutVerification: "INCONNU")],
            attestationSanteSigneeLe: nil)
        XCTAssertEqual(P.complementaires(ordreInconnu).last?.statut, "ordre.pdf · Statut à actualiser")
        XCTAssertEqual(P.complementaires(dossier([], rpps: true)), [], "RPPS vérifié hors médecin : aucune carte")
        let sansOrdre = DossierDocuments.assembler(
            profil: SoignantExigencesDocuments(profession: "MEDECIN", typeExercice: "LIBERAL", rppsVerifie: true, adeliVerifie: false),
            regles: [], documents: [], attestationSanteSigneeLe: nil)
        XCTAssertEqual(P.complementaires(sansOrdre).last?.bouton, "+ Ajouter l’attestation")
    }

    // MARK: - Attestation, fichier choisi

    func testAttestationSigneeEtFichierChoisi() {
        XCTAssertNil(P.attestationSigneeLe(DossierDocuments()))
        let signe = DossierDocuments(attestationSanteSigneeLe: "2026-11-02T00:00:00.000Z")
        XCTAssertEqual(P.attestationSigneeLe(signe), "✅ Attestation signée le 2 novembre 2026")
        XCTAssertEqual(P.attestationSigneeLe(DossierDocuments(attestationSanteSigneeLe: "illisible")),
                       "✅ Attestation signée le illisible", "valeur serveur gardée, jamais une date supposée")
        XCTAssertEqual(P.fichierChoisi(nom: "photo.jpg"), "📎 photo.jpg")
        XCTAssertEqual(P.taille(octets: 2048), "2 Ko")
        XCTAssertEqual(P.taille(octets: 1536), "2 Ko", "toFixed(0) : demi arrondi au-dessus")
        XCTAssertEqual(P.taille(octets: 500), "0 Ko")
        XCTAssertEqual(P.date("2026-11-14"), "14 nov. 2026")
        XCTAssertNil(P.date(nil))
        XCTAssertNil(P.date(""))
        XCTAssertNil(P.date("illisible"))
    }

    // MARK: - Issues d'envoi et d'actions

    func testMessagesDesIssuesDEnvoi() {
        XCTAssertEqual(P.messageEnvoi(.termine(.verificationDemandee(documentId: "d"))),
                       TexteJustificatif(texte: "Document téléversé — vérification en cours (~30 s).", ton: .succes))
        XCTAssertEqual(P.messageEnvoi(.termine(.enregistre(documentId: "d"))),
                       TexteJustificatif(texte: "Document téléversé. Vérification manuelle en attente.", ton: .info))
        XCTAssertNil(P.messageEnvoi(.termine(.verdictRendu(documentId: "d"))), "verdict déjà rendu : le badge suffit")
        XCTAssertNil(P.messageEnvoi(.inactif))
        XCTAssertNil(P.messageEnvoi(.enCours(typeDocument: "DIPLOME")))
        XCTAssertEqual(P.messageEnvoi(.termine(.refuse(code: "CHEMIN_DOCUMENT_INVALIDE")))?.texte, MessagesDocuments.enregistrementImpossible)
        XCTAssertEqual(P.messageEnvoi(.termine(.refuse(code: "METADONNEES_DOCUMENT_INVALIDES")))?.ton, .erreur)
        XCTAssertEqual(P.messageEnvoi(.termine(.refuse(code: "STOCKAGE_409")))?.texte,
                       "Téléversement impossible : Une erreur est survenue. Veuillez réessayer.")
        XCTAssertEqual(P.messageEnvoi(.termine(.refuse(code: "TYPE_DOCUMENT_INVALIDE")))?.texte, MessagesDocuments.erreurGenerique)
        XCTAssertEqual(P.messageEnvoi(.termine(.refuse(code: "SQLSTATE_P0001")))?.texte, MessagesDocuments.erreurGenerique,
                       "trigger des pièces de santé : jamais son texte")
        XCTAssertEqual(P.messageEnvoi(.termine(.incertain)), TexteJustificatif(texte: LibellesJustificatifs.envoiAVerifier, ton: .attention))
        XCTAssertEqual(P.messageEnvoi(.termine(.nonEnvoye)), TexteJustificatif(texte: LibellesJustificatifs.envoiNonRecu, ton: .attention))
        XCTAssertEqual(P.messageEnvoi(.recuEnCours), TexteJustificatif(texte: LibellesJustificatifs.envoiPrecedentAVerifier, ton: .attention))
        XCTAssertEqual(P.messageEnvoi(.suiviIllisible), TexteJustificatif(texte: LibellesJustificatifs.suiviIllisible, ton: .erreur))
        XCTAssertEqual(P.messageEnvoi(.refuseAvantEnvoi(message: "Refus local")), TexteJustificatif(texte: "Refus local", ton: .erreur))
        XCTAssertEqual(P.messageEnvoi(.erreur("Hors ligne")), TexteJustificatif(texte: "Hors ligne", ton: .erreur))

        let fermants: [DocumentsModel.EtatEnvoi] = [.termine(.verificationDemandee(documentId: "d")), .termine(.enregistre(documentId: "d")),
                                                     .termine(.verdictRendu(documentId: "d")), .termine(.incertain)]
        for etat in fermants { XCTAssertTrue(P.fermeLeTeleversement(etat), "\(etat)") }
        let ouverts: [DocumentsModel.EtatEnvoi] = [.inactif, .enCours(typeDocument: "DIPLOME"), .termine(.refuse(code: "X")), .termine(.nonEnvoye),
                                                    .refuseAvantEnvoi(message: "m"), .recuEnCours, .suiviIllisible, .erreur("e")]
        for etat in ouverts { XCTAssertFalse(P.fermeLeTeleversement(etat), "\(etat)") }
    }

    /// En tête d'écran, « vérification en cours » ne survit pas au verdict relu : le badge de la carte le porte ensuite.
    func testIssueAfficheeSeRetireAuVerdict() {
        let demandee = DocumentsModel.EtatEnvoi.termine(.verificationDemandee(documentId: "d"))
        XCTAssertEqual(P.issueAffichee(demandee, enVerification: ["d"])?.texte, "Document téléversé — vérification en cours (~30 s).")
        XCTAssertNil(P.issueAffichee(demandee, enVerification: []), "verdict relu : plus de « vérification en cours »")
        XCTAssertNil(P.issueAffichee(demandee, enVerification: ["autre"]))
        XCTAssertEqual(P.issueAffichee(.termine(.enregistre(documentId: "d")), enVerification: []),
                       P.messageEnvoi(.termine(.enregistre(documentId: "d"))))
        XCTAssertEqual(P.issueAffichee(.termine(.incertain), enVerification: []), P.messageEnvoi(.termine(.incertain)))
        XCTAssertEqual(P.issueAffichee(.suiviIllisible, enVerification: []), P.messageEnvoi(.suiviIllisible))
        XCTAssertNil(P.issueAffichee(.inactif, enVerification: []))
    }

    func testMessagesDeRevérificationCommeLesToastsDuWeb() {
        XCTAssertEqual(P.messageReverification(.verifie, motif: "x"), TexteJustificatif(texte: "✅ Document vérifié automatiquement !", ton: .succes))
        XCTAssertEqual(P.messageReverification(.rejete, motif: "Illisible"), TexteJustificatif(texte: "❌ Document rejeté : Illisible", ton: .erreur))
        XCTAssertEqual(P.messageReverification(.rejete, motif: nil).texte, "❌ Document rejeté : Non conforme")
        XCTAssertEqual(P.messageReverification(.rejete, motif: "").texte, "❌ Document rejeté : Non conforme")
        XCTAssertEqual(P.messageReverification(.revueManuelleRequise, motif: nil),
                       TexteJustificatif(texte: "Document reçu. Une revue humaine est en attente d’attribution.", ton: .info))
        XCTAssertEqual(P.messageReverification(.enAttente, motif: nil), TexteJustificatif(texte: "⏳ Vérification en attente...", ton: .info))
        XCTAssertEqual(LibellesJustificatifs.revueEnvoyee, "Demande envoyée. Un membre de l’équipe vérifiera le document.")
    }
}
