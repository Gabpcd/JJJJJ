import XCTest
@testable import JoleneCore

/// Textes des litiges et des réclamations (lot 4, T8 ; HARD STOP n°4) : chaque texte repris du web figure tel quel à sa
/// ligne source ; chaque texte vouvoyé a son original tutoyé à sa ligne ; chaque refus du serveur rejoué par le monde
/// démo figure dans le dump ; aucun texte de délai, de pénalité ou de conséquence n'est ajouté (les textes de délai du
/// web ne sont pas portés : ne pas porter n'est pas reformuler).
final class LitigesVerbatimTests: XCTestCase {
    private typealias L = LitigesTextes
    private typealias R = ReclamationsTextes

    private static let onglets = "src/pages/LitigesContestationsSoignant.tsx"
    private static let litiges = "src/pages/LitigesSoignant.tsx"
    private static let fil = "src/components/FilDiscussionLitige.tsx"
    private static let reclamations = "src/pages/MesReclamations.tsx"

    /// (texte natif, fichier web, ligne) : le texte figure tel quel à sa ligne (échappements `\'` du JS ramenés à `'`).
    private static var attendus: [(String, String, Int)] {
        let filtres: [(String, String, Int)] = zip(FiltreLitiges.allCases, 204...209).map { filtre, ligne in
            ("id: '\(filtre.rawValue)' as FiltreStatut, label: '\(filtre.libelle)'", litiges, ligne)
        }
        let categories: [(String, String, Int)] = zip(CategorieReclamation.allCases, 23...27).map { categorie, ligne in
            ("{ value: '\(categorie.rawValue)', label: '\(R.libelle(categorie))' }", reclamations, ligne)
        }
        let statuts: [(String, String, Int)] = zip(["EN_ATTENTE", "EN_COURS", "RESOLUE", "FERMEE"], 31...34).map { code, ligne in
            ("\(code): { label: '\(R.libelleStatut(code))'", reclamations, ligne)
        }
        let textes: [(String, String, Int)] = [
            (L.titreEcran, onglets, 13), (L.titreEcran, onglets, 20), (L.ongletLitiges, onglets, 29), (L.ongletReclamations, onglets, 33),
            ("const TABS = ['litiges', 'reclamations'] as const;", onglets, 9),
            (L.chargementImpossible, litiges, 72), (L.missionsIndisponibles, litiges, 144), (L.litigeOuvert, litiges, 179),
            (L.titre, litiges, 191), (L.ouvrir, litiges, 196), (L.videTitre, litiges, 231), (L.missionSansIntitule, litiges, 258),
            ("🏥 {l.etablissements?.nom || mission?.etablissements?.nom || '\(L.etablissementIndisponible)'}", litiges, 261),
            ("\(L.prefixeMotif){l.motif}", litiges, 265), (L.propositionRecue, litiges, 270), (L.ouvertureTitre, litiges, 310), (L.avertissementOuverture, litiges, 315),
            (L.missionConcernee, litiges, 319), (L.aucuneMissionEligible, litiges, 321), (L.selectionnerMission, litiges, 324),
            ("{m.intitule} — {m.etablissements?.nom || '\(L.etablissementIndisponible)'} — ", litiges, 328),
            (L.motifDuLitige, litiges, 336), ("maxLength={\(LitigesPresentation.longueurMaxSaisie)}", litiges, 337),
            ("{newMotif.length}/\(LitigesPresentation.longueurMaxSaisie)", litiges, 338), (L.annuler, litiges, 342),
            ("newMotif.trim().length < \(LitigesPresentation.longueurMin)", litiges, 343),
            ("{creating ? '\(L.creation)' : '\(L.ouvrirLeLitige)'}", litiges, 344),
            ("p_motif: newMotif.trim(),", litiges, 174),
            (".in('statut', ['TERMINEE', 'EN_COURS'])", litiges, 137),
            ("(data as any)?.error || '\(L.erreurEnvoi)'", fil, 70), (L.revueAdmin, fil, 137), (L.litigeCloture, fil, 144),
            (L.aucunMessage, fil, 154),
            ("{isAdmin ? '\(L.auteurJolene)' : isMe ? '\(L.auteurVous)' : msg.type_auteur === 'SOIGNANT' ? '\(L.auteurSoignant)' : '\(L.auteurEtablissement)'}",
             fil, 163),
            ("format(new Date(msg.cree_le), 'd MMM HH:mm', { locale: fr })", fil, 166),
            (L.messagePlaceholder, fil, 196), ("maxLength={\(LitigesPresentation.longueurMaxSaisie)}", fil, 198),
            ("newMsg.trim().length < \(LitigesPresentation.longueurMin)", fil, 201),
            ("{sending ? '\(L.envoi)' : '\(L.envoyer)'}", fil, 202),
            ("(data as any)?.error || '\(R.erreurSoumission)'", reclamations, 99), (R.titre, reclamations, 122),
            (R.signaler, reclamations, 127), (R.vide, reclamations, 134), (R.reponseJolene, reclamations, 160),
            (R.signaler, reclamations, 180), (R.categorie, reclamations, 184), (R.sujet, reclamations, 196),
            (R.details, reclamations, 205), (R.annuler, reclamations, 216), (R.envoyer, reclamations, 219),
            ("\"d MMM yyyy 'à' HH:mm\"", reclamations, 150),
            (".select('id, categorie, sujet, details, statut, reponse_admin, cree_le, traite_le')", reclamations, 78),
        ]
        return textes + filtres + categories + statuts
    }

    func testChaqueTexteRepriseDuWebEstVerbatimASaLigne() throws {
        var lignes: [String: [String]] = [:]
        for (texte, fichier, ligne) in Self.attendus {
            if lignes[fichier] == nil { lignes[fichier] = try CompteVerbatimTests.lignes(fichier) }
            let source = try XCTUnwrap(lignes[fichier])
            XCTAssertGreaterThanOrEqual(source.count, ligne, fichier)
            let brute = source[ligne - 1].replacingOccurrences(of: "\\'", with: "'")
            XCTAssertTrue(brute.contains(texte), "« \(texte) » absent de \(fichier) l.\(ligne)")
        }
    }

    /// Textes tutoyés non juridiques passés au vouvoiement (décision 9 du lot 1) : l'original figure à sa ligne, et la
    /// forme native ne change que la personne.
    func testVouvoiementsOriginauxASaLigne() throws {
        let web = try CompteVerbatimTests.lignes(Self.litiges)
        for (original, natif, ligne) in L.vouvoiements {
            XCTAssertTrue(web[ligne - 1].contains(original), "« \(original) » absent de \(Self.litiges) l.\(ligne)")
            XCTAssertNotEqual(original, natif)
        }
        XCTAssertEqual(L.vouvoiements.map(\.natif), [
            "Suivez vos contestations de missions", "Vous n'avez aucun litige en cours.",
            "Décrivez le problème rencontré (minimum 10 caractères)...", "Une erreur est survenue. Réessayez.",
        ])
        let webReclamations = try CompteVerbatimTests.lignes(Self.reclamations)
        for (original, natif, ligne) in R.vouvoiements {
            XCTAssertTrue(webReclamations[ligne - 1].contains(original), "« \(original) » absent de \(Self.reclamations) l.\(ligne)")
            XCTAssertNotEqual(original, natif)
        }
        XCTAssertEqual(R.vouvoiements.map(\.natif), [
            "Signalez un problème ou suivez vos demandes", "Décrivez brièvement le problème",
            "Expliquez la situation en détail : dates, montants, personnes concernées...",
            "Réclamation envoyée — nous reviendrons vers vous rapidement",
        ])
    }

    /// Texte à portée juridique : mot pour mot, tutoiement du web compris, jamais reformulé sans validation.
    func testAvertissementDOuvertureMotPourMot() {
        XCTAssertEqual(L.avertissementOuverture,
                       "⚠️ Un litige déclenche une procédure de résolution entre toi et l'établissement. Privilégie d'abord la messagerie pour résoudre le problème.")
        XCTAssertFalse(L.vouvoiements.contains { $0.natif == L.avertissementOuverture }, "jamais vouvoyé d'office")
    }

    /// Tous les textes affichés par les écrans des litiges et des réclamations.
    private static var affiches: [String] {
        [L.titreEcran, L.ongletLitiges, L.ongletReclamations, L.titre, L.sousTitre, L.ouvrir, L.chargementImpossible, L.videTitre,
         L.videMessage, L.missionSansIntitule, L.etablissementIndisponible, L.prefixeMotif, L.propositionRecue, L.ouvertureTitre,
         L.avertissementOuverture, L.missionConcernee, L.aucuneMissionEligible, L.selectionnerMission, L.motifDuLitige,
         L.motifPlaceholder, L.annuler, L.creation, L.ouvrirLeLitige, L.missionsIndisponibles, L.erreurOuverture, L.litigeOuvert,
         L.revueAdmin, L.litigeCloture, L.aucunMessage, L.auteurJolene, L.auteurVous, L.auteurSoignant, L.auteurEtablissement,
         L.messagePlaceholder, L.envoi, L.envoyer, L.erreurEnvoi, L.nonConfirme, L.messageNonConfirme, L.filIndisponible,
         L.accordWebTitre, L.accordWebMessage, L.reessayer, L.verifierSession,
         R.titre, R.sousTitre, R.signaler, R.vide, R.reponseJolene, R.categorie, R.sujet, R.sujetPlaceholder, R.details,
         R.detailsPlaceholder, R.annuler, R.envoyer, R.erreurSoumission, R.envoyee, R.chargementImpossible, R.nonConfirmee]
            + FiltreLitiges.allCases.map(\.libelle) + CategorieReclamation.allCases.map(R.libelle)
            + ["EN_ATTENTE", "EN_COURS", "RESOLUE", "FERMEE"].map(R.libelleStatut)
    }

    /// HARD STOP : aucun délai, aucune pénalité, aucune conséquence datée dans les textes natifs. Les textes de délai
    /// du web ne sont pas portés : leurs lignes restent des témoins (si le web les change, la question est à rouvrir).
    func testAucunTexteDeDelaiNiDePenalite() throws {
        let delai = try NSRegularExpression(pattern: #"\d+\s?(?:h|heures?|jours?|j)\b|délai|pénalit|sous \d|escalade"#,
                                            options: [.caseInsensitive])
        for texte in Self.affiches {
            let plage = NSRange(texte.startIndex..., in: texte)
            XCTAssertNil(delai.firstMatch(in: texte, range: plage), "texte de délai ou de pénalité interdit : « \(texte) »")
        }
        // Témoins du web, non portés : bandeau de médiation (délai codé côté client, LOT4_PLAN §1.2), accords (D9).
        let web = try CompteVerbatimTests.lignes(Self.fil)
        XCTAssertTrue(web[130 - 1].contains("En médiation amiable — vous avez 7 jours pour vous accorder"),
                      "témoin web : \(Self.fil) l.130 a changé — instruire le nouveau texte avant tout portage")
        // « Proposition de résolution reçue — votre réponse est attendue » (l.270) est porté sans délai depuis la revue B8
        // des textes de la vague D (M3), vérifié à sa ligne par `attendus`.
        for texte in Self.affiches {
            XCTAssertFalse(texte.contains("7 jours") || texte.contains("médiation amiable"),
                           "texte non porté retrouvé : « \(texte) »")
        }
    }

    // MARK: - Refus du serveur (dump)

    /// Corps d'une fonction du dump, de son en-tête au `$$;` qui le ferme.
    private func corps(_ entete: String) throws -> String {
        let dump = try String(contentsOf: Lot3PortsTests.dumpURL, encoding: .utf8)
        let debut = try XCTUnwrap(dump.range(of: entete), "\(entete) introuvable dans supabase/schema/public.sql")
        let suite = dump[debut.upperBound...]
        let fin = try XCTUnwrap(suite.range(of: "$$;"), "fin du corps introuvable")
        return String(suite[..<fin.lowerBound])
    }

    /// Messages `'error', '…'` d'un corps (`''` du SQL ramené à `'`), dans l'ordre du texte.
    private func refus(_ corps: String) throws -> [String] {
        let motif = try NSRegularExpression(pattern: #"'error',\s*'((?:[^']|'')*)'"#)
        return motif.matches(in: corps, range: NSRange(corps.startIndex..., in: corps)).compactMap { resultat in
            Range(resultat.range(at: 1), in: corps).map { String(corps[$0]).replacingOccurrences(of: "''", with: "'") }
        }
    }

    func testMessagesServeurPresentsDansLeDump() throws {
        let ouverture = try corps(#"CREATE OR REPLACE FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_type_litige" "public"."type_litige", "p_motif" "text") RETURNS "jsonb""#)
        // Le refus « facture » ne concerne que les types de facture : inatteignable avec `AUTRE`, seul type ouvert ici.
        let facture = "Aucune facture contestable (ÉMISE, EN RETARD ou PAYÉE) pour cette mission."
        XCTAssertEqual(try refus(ouverture).filter { $0 != facture }, MessagesLitigesServeur.ouverture,
                       "refus de la signature à 3 arguments, dans l'ordre du serveur")
        XCTAssertTrue(try refus(ouverture).contains(facture))
        XCTAssertTrue(ouverture.contains("'success', true") && ouverture.contains("'litige_id', v_litige_id")
                      && ouverture.contains("'est_informatif', v_est_informatif"), "forme du succès")

        let message = try corps(#"CREATE OR REPLACE FUNCTION "public"."fn_ajouter_message_litige"("p_litige_id" "uuid", "p_contenu" "text") RETURNS "jsonb""#)
        XCTAssertEqual(Array(Set(try refus(message))).sorted(), MessagesLitigesServeur.message.sorted())
        XCTAssertTrue(message.contains("'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS',\n    'REVUE_ADMIN'"),
                      "statuts qui acceptent un message")
        XCTAssertTrue(message.contains("'message_id', v_message_id"))

        let reclamation = try corps(#"CREATE OR REPLACE FUNCTION "public"."fn_soumettre_reclamation"("p_categorie" "text", "p_sujet" "text", "p_details" "text", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb""#)
        XCTAssertEqual(try refus(reclamation), ["Non authentifié", "Rôle non autorisé"])
        XCTAssertTrue(reclamation.contains("jsonb_build_object('id', v_reclamation_id, 'statut', 'EN_ATTENTE')"),
                      "succès sans `success` ni `ok`")
        let dump = try String(contentsOf: Lot3PortsTests.dumpURL, encoding: .utf8)
        let categories = CategorieReclamation.allCases.map(\.rawValue)
        XCTAssertTrue(dump.contains(#"CONSTRAINT "reclamations_categorie_check" CHECK (("categorie" = ANY (ARRAY['MISSION'::"text", 'PAIEMENT'::"text", 'TECHNIQUE'::"text", 'COMPORTEMENT'::"text", 'AUTRE'::"text"])))"#))
        XCTAssertEqual(Set(categories), ["MISSION", "PAIEMENT", "TECHNIQUE", "COMPORTEMENT", "AUTRE"], "liste fermée du serveur")
        XCTAssertTrue(dump.contains(#"CONSTRAINT "reclamations_statut_check" CHECK (("statut" = ANY (ARRAY['EN_ATTENTE'::"text", 'EN_COURS'::"text", 'RESOLUE'::"text", 'FERMEE'::"text"])))"#))
    }
}
