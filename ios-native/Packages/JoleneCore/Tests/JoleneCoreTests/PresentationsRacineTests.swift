import XCTest
@testable import JoleneCore

/// Présentations de la racine de la fenêtre (lot 3, T3b — revue fraîche B8, m1, m7 et M1) : feuille du renvoi web et
/// alerte du refus de réinitialisation, exécutées par `DeepLinkCoordinator` (app). Ce que ces tests prouvent (niveau 1) :
/// - l'anti-boucle et le libellé DEBUG `deeplink-route` ne sont posés qu'à l'**apparition effective** du contenu de la
///   feuille ; une feuille demandée mais jamais affichée (une autre feuille est ouverte, filtres d'Explorer) ne bloque
///   rien : le même lien est redemandé sous un nouvel item, un refus est présenté aussitôt ;
/// - un refus reçu pendant qu'un renvoi est affiché attend la fin de sa présentation (`onDismiss`), jamais dans la même
///   transaction que la fermeture ;
/// - chaque refus est un nouvel item numéroté : un refus jamais affiché ne fait pas taire les suivants ;
/// - le remplacement d'un renvoi affiché garde l'anti-boucle du nouveau, quel que soit l'ordre apparition/disparition ;
/// - pendant l'effacement des données web d'une fin d'identité (M1), un renvoi est différé jusqu'à sa fin ; une fin
///   d'identité abandonne un renvoi différé.
final class PresentationsRacineTests: XCTestCase {
    private let stripe = URL(string: "https://jolene.app/soignant/stripe-connect?success=true")!
    private let litiges = URL(string: "https://jolene.app/soignant/litiges")!

    func testAntiBoucleEtLibellePosesALApparitionEffective() throws {
        var etat = PresentationsRacine()
        etat.demanderRenvoi(.safari(stripe))
        let renvoi = try XCTUnwrap(etat.renvoi)
        XCTAssertEqual(renvoi.url, stripe)
        XCTAssertNil(etat.renvoiAffiche, "demandé n'est pas affiché")
        XCTAssertNil(etat.apparition(renvoi.id + 1), "contenu d'une autre feuille : rien")
        XCTAssertEqual(etat.apparition(renvoi.id), .safari(stripe), "anti-boucle et libellé posés ici")
        XCTAssertEqual(etat.renvoiAffiche, renvoi)
        XCTAssertTrue(etat.disparition(renvoi.id), "fin de l'affichage : anti-boucle levé")
        XCTAssertNil(etat.renvoiAffiche)
        XCTAssertFalse(etat.disparition(renvoi.id), "une seule fois")
    }

    /// Revue B8 de T8, M1 : chaque fermeture d'un renvoi effectivement affiché est comptée (`fermetures`), pour qu'un
    /// écran qui l'a ouvert (complétion web d'un étudiant) relise le rôle au retour ; une feuille jamais affichée, ou une
    /// disparition répétée, ne compte pas.
    func testChaqueFermetureDUnRenvoiAfficheEstComptee() throws {
        var etat = PresentationsRacine()
        XCTAssertEqual(etat.fermetures, 0)
        etat.demanderRenvoi(.safari(litiges))
        let premier = try XCTUnwrap(etat.renvoi)
        etat.fermerRenvoi()
        XCTAssertFalse(etat.disparition(premier.id), "feuille jamais affichée")
        XCTAssertEqual(etat.fermetures, 0)
        etat.demanderRenvoi(.safari(litiges))
        let second = try XCTUnwrap(etat.renvoi)
        _ = etat.apparition(second.id)
        etat.fermerRenvoi()
        XCTAssertTrue(etat.disparition(second.id))
        XCTAssertEqual(etat.fermetures, 1)
        XCTAssertFalse(etat.disparition(second.id))
        XCTAssertEqual(etat.fermetures, 1, "une seule fois par renvoi affiché")
    }

    func testRouteNativeNeDemandeAucunRenvoi() {
        var etat = PresentationsRacine()
        etat.demanderRenvoi(.accueil)
        XCTAssertNil(etat.renvoi)
        XCTAssertEqual(etat, PresentationsRacine())
    }

    /// m1, premier cas : la racine ne peut pas présenter (feuille des filtres ouverte). Rien ne reste collé.
    func testFeuilleJamaisApparueNeBloqueNiLeMemeLienNiUnRefus() throws {
        var etat = PresentationsRacine()
        etat.demanderRenvoi(.safari(stripe))
        let premier = try XCTUnwrap(etat.renvoi)
        etat.demanderRenvoi(.safari(stripe)) // même lien universel revenu : redemandé, jamais ignoré
        let second = try XCTUnwrap(etat.renvoi)
        XCTAssertNotEqual(second.id, premier.id, "nouvel item : nouvelle tentative de présentation")
        XCTAssertNil(etat.apparition(premier.id), "l'ancienne feuille ne pose plus rien")
        etat.refuser()
        XCTAssertNil(etat.renvoi, "le refus ferme la feuille demandée")
        XCTAssertNotNil(etat.refus, "aucun renvoi affiché : refus présenté aussitôt")
        XCTAssertFalse(etat.refusApresRenvoi)
    }

    /// m1, second cas : lien `?code=` reçu pendant un renvoi affiché.
    func testRefusPendantUnRenvoiAfficheAttendLaFinDeSaPresentation() throws {
        var etat = PresentationsRacine()
        etat.demanderRenvoi(.safari(litiges))
        let renvoi = try XCTUnwrap(etat.renvoi)
        _ = etat.apparition(renvoi.id)
        etat.refuser()
        XCTAssertNil(etat.renvoi, "la feuille est fermée d'abord")
        XCTAssertNil(etat.refus, "jamais dans la même transaction que la fermeture")
        XCTAssertTrue(etat.refusApresRenvoi)
        XCTAssertTrue(etat.disparition(renvoi.id))
        XCTAssertNil(etat.refus, "présenté après `onDismiss`, pas à la disparition du contenu")
        etat.congediement()
        let refus = try XCTUnwrap(etat.refus)
        XCTAssertFalse(etat.refusApresRenvoi)
        etat.congediement()
        XCTAssertEqual(etat.refus, refus, "un seul refus")
    }

    func testCongediementAvantLaDisparitionPresenteAussiLeRefus() throws {
        var etat = PresentationsRacine()
        etat.demanderRenvoi(.safari(litiges))
        let renvoi = try XCTUnwrap(etat.renvoi)
        _ = etat.apparition(renvoi.id)
        etat.refuser()
        etat.congediement() // `onDismiss` reçu avant `onDisappear` du contenu
        XCTAssertNotNil(etat.refus)
        XCTAssertTrue(etat.disparition(renvoi.id), "l'anti-boucle est levé ensuite")
    }

    func testChaqueRefusEstUnNouvelItemEtSAcquitteParSonNumero() throws {
        var etat = PresentationsRacine()
        etat.refuser()
        let premier = try XCTUnwrap(etat.refus)
        etat.refuser() // le premier n'a peut-être jamais été affiché : nouvelle présentation
        let second = try XCTUnwrap(etat.refus)
        XCTAssertNotEqual(second.id, premier.id)
        etat.refusAcquitte(premier.id)
        XCTAssertEqual(etat.refus, second, "acquittement périmé : sans effet")
        etat.refusAcquitte(second.id)
        XCTAssertNil(etat.refus)
        etat.refuser()
        XCTAssertNotNil(etat.refus, "toujours présentable dans la session")
    }

    func testNouveauRenvoiAnnuleLeRefusEnAttenteDeFermeture() throws {
        var etat = PresentationsRacine()
        etat.demanderRenvoi(.safari(litiges))
        _ = etat.apparition(try XCTUnwrap(etat.renvoi).id)
        etat.refuser()
        etat.demanderRenvoi(.safari(stripe)) // le dernier lien reçu reste visible
        XCTAssertFalse(etat.refusApresRenvoi)
        etat.congediement()
        XCTAssertNil(etat.refus)
        XCTAssertEqual(etat.renvoi?.url, stripe)
    }

    func testRemplacementDUnRenvoiAfficheGardeLAntiBoucleDuNouveau() throws {
        // Apparition du nouveau avant la disparition de l'ancien.
        var etat = PresentationsRacine()
        etat.demanderRenvoi(.safari(litiges))
        let ancien = try XCTUnwrap(etat.renvoi)
        _ = etat.apparition(ancien.id)
        etat.demanderRenvoi(.safari(stripe))
        let nouveau = try XCTUnwrap(etat.renvoi)
        XCTAssertEqual(etat.apparition(nouveau.id), .safari(stripe))
        XCTAssertFalse(etat.disparition(ancien.id), "l'ancien ne lève pas l'anti-boucle du nouveau")
        XCTAssertEqual(etat.renvoiAffiche, nouveau)

        // Disparition de l'ancien avant l'apparition du nouveau.
        var autre = PresentationsRacine()
        autre.demanderRenvoi(.safari(litiges))
        let a = try XCTUnwrap(autre.renvoi)
        _ = autre.apparition(a.id)
        autre.demanderRenvoi(.safari(stripe))
        let b = try XCTUnwrap(autre.renvoi)
        XCTAssertTrue(autre.disparition(a.id))
        XCTAssertEqual(autre.apparition(b.id), .safari(stripe))
        XCTAssertEqual(autre.renvoiAffiche, b)
    }

    // MARK: - Fin d'identité (M1)

    func testRenvoiDiffereJusquALaFinDeLEffacementDesDonneesWeb() throws {
        var etat = PresentationsRacine()
        etat.demanderRenvoi(.safari(litiges))
        let affiche = try XCTUnwrap(etat.renvoi)
        _ = etat.apparition(affiche.id)
        // Fin d'identité : la feuille est fermée, l'effacement commence.
        etat.fermerRenvoi()
        etat.debutEffacement()
        XCTAssertNil(etat.renvoi)
        etat.demanderRenvoi(.safari(stripe)) // lien reçu pendant l'effacement
        XCTAssertNil(etat.renvoi, "jamais présenté avant la fin de l'effacement")
        XCTAssertEqual(etat.renvoiDiffere, .safari(stripe))
        etat.debutEffacement() // seconde fin d'identité rapprochée
        etat.finEffacement()
        XCTAssertNil(etat.renvoi, "un effacement est encore en cours")
        etat.finEffacement()
        XCTAssertEqual(etat.renvoi?.url, stripe, "présenté une fois les données effacées")
        XCTAssertNil(etat.renvoiDiffere)
        etat.finEffacement()
        XCTAssertEqual(etat.effacementsEnCours, 0, "jamais négatif")
    }

    func testFinDIdentiteAbandonneLeRenvoiDiffere() {
        var etat = PresentationsRacine()
        etat.debutEffacement()
        etat.demanderRenvoi(.safari(stripe))
        etat.fermerRenvoi() // nouvelle fin d'identité : le renvoi demandé pour l'identité close n'est jamais présenté
        etat.finEffacement()
        XCTAssertNil(etat.renvoi)
        XCTAssertNil(etat.renvoiDiffere)
    }
}
