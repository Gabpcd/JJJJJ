import Foundation

/// Textes de la complétion du profil soignant (lot 3, T8 ; HARD STOP n°4) : chacun repris **mot pour mot** du web
/// (`src/pages/InscriptionSoignant.tsx` en mode « parcours », `src/components/inscription/DeclarationEtudiant.tsx`,
/// `src/lib/inscriptionProgressive.ts`), à sa ligne source (`// source: fichier:ligne`), épinglé par
/// `CompletionVerbatimTests`. Tutoiement ou vouvoiement : ceux du web (décision du 9 novembre 2026 : le natif suit le web
/// mot pour mot). Apostrophes droites ou typographiques : celles du web, ligne par ligne. Les fragments d'une phrase
/// assemblée (type d'exercice unique, liste des informations à vérifier) sont recomposés comme le rendu React
/// (`phraseTypeUnique`, `messageManques`). Les messages de `register-soignant` ne sont pas ici : ils arrivent du serveur
/// et sont affichés tels quels (`ResultatFinalisation.refusee`).
public enum CompletionTextes {
    // MARK: En-tête

    // source: src/pages/InscriptionSoignant.tsx:440
    public static let titre = "Vos informations professionnelles"
    // source: src/pages/InscriptionSoignant.tsx:539
    public static let sousTitre = "Ces informations permettent de vérifier votre profil avant de candidater."

    // MARK: Identité et coordonnées

    // source: src/pages/InscriptionSoignant.tsx:542
    public static let prenom = "Prénom *"
    // source: src/pages/InscriptionSoignant.tsx:546
    public static let nom = "Nom *"
    // source: src/pages/InscriptionSoignant.tsx:550
    public static let telephone = "Téléphone *"
    // source: src/pages/InscriptionSoignant.tsx:550
    public static let telephonePlaceholder = "+33 6 ..."
    // source: src/pages/InscriptionSoignant.tsx:551
    public static let telephoneInvalide = "Numéro de téléphone invalide"
    // source: src/pages/InscriptionSoignant.tsx:552
    public static let telephoneAide = "Nécessaire pour qu'un établissement puisse vous joindre (missions urgentes)."
    // source: src/pages/InscriptionSoignant.tsx:554
    public static let dateNaissance = "Date de naissance *"
    // source: src/pages/InscriptionSoignant.tsx:555
    public static let dateNaissanceObligatoire = "La date de naissance est obligatoire"
    // source: src/pages/InscriptionSoignant.tsx:556
    public static let dateNaissanceMineur = "Vous devez avoir 18 ans révolus pour vous inscrire"
    /// Profession du parcours, affichée en lecture seule (le web la laisse modifiable ; blueprint §3 T8 : « profession
    /// figée du parcours », principe « État dérivé »).
    // source: src/pages/InscriptionSoignant.tsx:559
    public static let profession = "Profession *"

    // MARK: RPPS (correction 20, décision 11)

    // source: src/pages/InscriptionSoignant.tsx:582
    public static let numeroRpps = "Numéro RPPS"
    /// Suffixe du libellé quand le numéro est obligatoire (`{rppsObligatoireInscription ? ' *' : ''}`).
    // source: src/pages/InscriptionSoignant.tsx:582
    public static let suffixeObligatoire = " *"
    // source: src/pages/InscriptionSoignant.tsx:586
    public static let aideRppsAideSoignant = "Optionnel pour les aides-soignants : si vous disposez déjà d’une identité RPPS, nous la vérifions dans l’Annuaire Santé. Votre diplôme reste obligatoire."
    // source: src/pages/InscriptionSoignant.tsx:587
    public static let aideRppsOptionnel = "Vous ne le connaissez pas par cœur ? Vous pouvez laisser vide et le compléter plus tard — la vérification se fera à ce moment-là."
    // source: src/pages/InscriptionSoignant.tsx:591
    public static let aideRppsAnnuaire = "Les 11 chiffres ne suffisent pas : Jolene interroge l’Annuaire Santé officiel et recoupe l’identité, la profession et la situation active."
    // source: src/pages/InscriptionSoignant.tsx:594
    public static let rppsPlaceholderObligatoire = "11 chiffres"
    // source: src/pages/InscriptionSoignant.tsx:594
    public static let rppsPlaceholderOptionnel = "11 chiffres (optionnel)"
    // source: src/pages/InscriptionSoignant.tsx:658
    public static let aucunRpps = "ℹ️ Aucun RPPS n'est demandé pour ce profil. Votre diplôme et votre carte d'identité restent vérifiés avant toute mission."

    // MARK: Type d'exercice (`ExerciceTypeSection`, l.53-99 ; HARD STOP n°4 : affichage seul, jamais transmis)

    // source: src/pages/InscriptionSoignant.tsx:65
    public static let typeExercice = "Type d'exercice"
    /// Phrase du type unique, fragments du JSX l.68 (`phraseTypeUnique`).
    // source: src/pages/InscriptionSoignant.tsx:68
    public static let typeUniqueDebut = "En tant que"
    // source: src/pages/InscriptionSoignant.tsx:68
    public static let typeUniqueMilieu = ", votre type d'exercice est automatiquement défini comme"
    // source: src/pages/InscriptionSoignant.tsx:68
    public static let typeUniqueSalarie = "salarié"
    // source: src/pages/InscriptionSoignant.tsx:68
    public static let typeUniqueLiberal = "libéral"
    // source: src/pages/InscriptionSoignant.tsx:68
    public static let typeUniqueMixte = "mixte"
    // source: src/pages/InscriptionSoignant.tsx:77
    public static let questionSalarie = "Êtes-vous actuellement salarié(e) d'un établissement de santé ?"
    // source: src/pages/InscriptionSoignant.tsx:79
    public static let oui = "Oui"
    // source: src/pages/InscriptionSoignant.tsx:80
    public static let non = "Non"
    // source: src/pages/InscriptionSoignant.tsx:84
    public static let exclusivite = "ℹ️ Vous pourrez effectuer des missions sur Jolene en complément de votre activité salariée. Vérifiez que votre contrat de travail n'inclut pas de clause d'exclusivité."
    // source: src/pages/InscriptionSoignant.tsx:94
    public static let referentielIndisponible = "Le référentiel est momentanément indisponible. Vous pouvez poursuivre votre inscription ; le mode libéral pourra être activé après contrôle."

    // MARK: Étudiant (renvoi web, D11)

    /// Libellé du bandeau « étudiant » du web, repris pour le renvoi vers la complétion web (le parcours étudiant et
    /// ses conditions réglementaires ne sont pas portés, D11).
    // source: src/components/inscription/DeclarationEtudiant.tsx:105
    public static let etudiant = "🎓 Je suis étudiant(e) en santé"

    // MARK: Validation (`handleSubmit`, l.354-357)

    // source: src/pages/InscriptionSoignant.tsx:355
    public static let manquePrenom = "prénom"
    // source: src/pages/InscriptionSoignant.tsx:355
    public static let manqueNom = "nom"
    // source: src/pages/InscriptionSoignant.tsx:355
    public static let manqueTelephone = "téléphone valide"
    // source: src/pages/InscriptionSoignant.tsx:355
    public static let manqueDateNaissance = "date de naissance (18 ans minimum)"
    // source: src/pages/InscriptionSoignant.tsx:355
    public static let manqueProfession = "profession"
    // source: src/pages/InscriptionSoignant.tsx:355
    public static let manqueModeExercice = "mode d’exercice"
    // source: src/pages/InscriptionSoignant.tsx:355
    public static let manqueRpps = "numéro RPPS à 11 chiffres"
    /// `Vérifiez les informations suivantes : ${manque.join(', ')}.` (`messageManques`).
    // source: src/pages/InscriptionSoignant.tsx:356
    public static let manqueDebut = "Vérifiez les informations suivantes :"

    // MARK: Actions

    // source: src/pages/InscriptionSoignant.tsx:685
    public static let enregistrerPlusTard = "Enregistrer et continuer plus tard"
    // source: src/pages/InscriptionSoignant.tsx:688
    public static let enregistrement = "Enregistrement…"
    // source: src/pages/InscriptionSoignant.tsx:688
    public static let enregistrerMonProfil = "Enregistrer mon profil"

    // MARK: Finalisation (`finaliserProfil`)

    // source: src/lib/inscriptionProgressive.ts:177
    public static let sessionAbsente = "Reconnectez-vous pour reprendre votre inscription."
    /// Repli d'un refus de `register-soignant` sans `message` ni `error` lisible.
    // source: src/lib/inscriptionProgressive.ts:224
    public static let saisieConservee = "Votre saisie est conservée. Réessayez."
    /// Profil créé mais session non rafraîchie (ou espace non relu) : reconnexion.
    // source: src/lib/inscriptionProgressive.ts:236
    public static let profilEnregistreReconnecter = "Votre profil est enregistré. Reconnectez-vous pour ouvrir votre espace."
}

/// Règles pures de la complétion soignant (lot 3, T8), portées de `src/pages/InscriptionSoignant.tsx` (mode
/// `parcours`) et de `finaliserProfil` (`src/lib/inscriptionProgressive.ts` l.169-238). Aucune règle de mode
/// d'exercice en dur (HARD STOP n°4) : les modes proposés viennent de `fn_types_exercice_autorises` (table paramétrée
/// `regles_exercice_profession`) ; les listes RPPS sont celles du web et de `register-soignant` (`ProfessionsRpps`,
/// vecteur golden). L'âge est contrôlé par le serveur (`UNDERAGE`, message verbatim) ; la règle locale ne fait que
/// reprendre la garde du formulaire web (`dateNaissanceMajeur`, l.214-220) et la borne du sélecteur (l.554).
public enum CompletionRules {
    /// `/^[+]?[0-9\s]{8,15}$/` sur `form.telephone.trim()` (l.228). `\s` : blanc Unicode, comme en JavaScript.
    private static let motifTelephone = #"^[+]?[0-9\s]{8,15}$"#
    /// Clés du brouillon envoyées par le natif (liste blanche de `fn_enregistrer_parcours_inscription`, fiche
    /// `CONTRATS_RPC_SOIGNANT.md`) : jamais email, mot de passe, jeton, coordonnées ni profession (figée du parcours).
    public static let clesBrouillon: Set<String> = ["prenom", "nom", "telephone", "dateNaissance", "typesContrat", "rpps", "rayon"]
    /// Clés du corps de `register-soignant` envoyées par le natif (lues par l'edge, l.230) : ni `lat`/`lng`, ni
    /// `est_etudiant`/`etudiant_details` (parcours étudiant en renvoi web, D11), ni `navigateur`, ni `attribution`.
    public static let clesFinalisation: Set<String> = ["prenom", "nom", "telephone", "dateNaissance", "profession", "typesContrat",
                                                       "rpps", "rayon"]
    /// 18 années de 365,25 jours (l.219).
    static let dureeMajorite: TimeInterval = 18 * 365.25 * 86_400

    private static let calendrierUTC: Calendar = {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendrier
    }()

    public static func telephoneValide(_ telephone: String) -> Bool {
        let saisi = telephone.trimmingCharacters(in: .whitespacesAndNewlines)
        return saisi.range(of: motifTelephone, options: .regularExpression) != nil
    }

    /// `afficherChampRpps = !!rppsRequis || form.profession === 'AS'` avec `rppsRequis = profession && !SANS_RPPS` (l.221-222).
    public static func afficheRpps(profession: String) -> Bool {
        guard !profession.isEmpty else { return false }
        return !ProfessionsRpps.estSansRpps(profession) || profession == "AS"
    }

    /// `PROFESSIONS_RPPS_REQUIS.includes(form.profession)` (l.225).
    public static func rppsObligatoire(profession: String) -> Bool {
        !profession.isEmpty && ProfessionsRpps.exigeRpps(profession)
    }

    /// Aide du champ RPPS optionnel (l.584-589) ; nil quand il est obligatoire.
    public static func aideRpps(profession: String) -> String? {
        guard !rppsObligatoire(profession: profession) else { return nil }
        return profession == "AS" ? CompletionTextes.aideRppsAideSoignant : CompletionTextes.aideRppsOptionnel
    }

    /// Saisie du RPPS : `e.target.value.replace(/\D/g, '').slice(0, 11)` (l.594).
    public static func filtrerRpps(_ saisie: String) -> String {
        String(saisie.unicodeScalars.filter { ("0"..."9").contains($0) }.map(Character.init).prefix(11))
    }

    /// `new Date(form.dateNaissance)` (minuit UTC pour `AAAA-MM-JJ`) ; nil si la chaîne n'est pas une date.
    public static func date(_ chaine: String) -> Date? {
        let parties = chaine.split(separator: "-", omittingEmptySubsequences: false)
        guard chaine.count == 10, parties.count == 3, let annee = Int(parties[0]), let mois = Int(parties[1]),
              let jour = Int(parties[2]) else { return nil }
        let composantes = DateComponents(year: annee, month: mois, day: jour)
        guard composantes.isValidDate(in: calendrierUTC) else { return nil }
        return calendrierUTC.date(from: composantes)
    }

    /// `dateNaissanceMajeur` (l.214-220) : date lisible et `Date.now() - d >= 18 × 365,25 jours`.
    public static func majeur(dateNaissance: String?, maintenant: Date) -> Bool {
        guard let dateNaissance, let date = date(dateNaissance) else { return false }
        return maintenant.timeIntervalSince(date) >= dureeMajorite
    }

    /// Borne haute du sélecteur (`max` l.554 : aujourd'hui moins 18 ans, même jour civil).
    public static func dateMaximale(maintenant: Date, calendrier: Calendar = .current) -> Date {
        calendrier.date(byAdding: .year, value: -18, to: maintenant) ?? maintenant
    }

    /// Informations à vérifier, dans l'ordre du web (l.355) ; vide = formulaire envoyable. La cohérence RPPS en temps
    /// réel (`verify-rpps`) n'est pas portée (D11) : `register-soignant` seul la contrôle et refuse verbatim.
    public static func manques(prenom: String, nom: String, telephone: String, dateNaissance: String?, profession: String,
                               typesContrat: [String], rpps: String, maintenant: Date) -> [String] {
        var manques: [String] = []
        if prenom.isEmpty { manques.append(CompletionTextes.manquePrenom) }
        if nom.isEmpty { manques.append(CompletionTextes.manqueNom) }
        if !telephoneValide(telephone) { manques.append(CompletionTextes.manqueTelephone) }
        if !majeur(dateNaissance: dateNaissance, maintenant: maintenant) { manques.append(CompletionTextes.manqueDateNaissance) }
        if profession.isEmpty { manques.append(CompletionTextes.manqueProfession) }
        if typesContrat.isEmpty { manques.append(CompletionTextes.manqueModeExercice) }
        if rppsObligatoire(profession: profession) && rpps.count != 11 { manques.append(CompletionTextes.manqueRpps) }
        return manques
    }

    /// `Vérifiez les informations suivantes : ${manque.join(', ')}.` (l.356).
    public static func messageManques(_ manques: [String]) -> String {
        "\(CompletionTextes.manqueDebut) \(manques.joined(separator: ", "))."
    }

    /// `uniqueType` (`useTypesExerciceAutorises.ts` l.57) : un seul type autorisé.
    public static func typeUnique(_ typesAutorises: [String]?) -> String? {
        guard let typesAutorises, typesAutorises.count == 1 else { return nil }
        return typesAutorises[0]
    }

    /// Phrase du type unique (l.68) : `En tant que <label>, votre type d'exercice est automatiquement défini comme
    /// <salarié|libéral|mixte>.` (le web rend « mixte » pour toute autre valeur).
    public static func phraseTypeUnique(profession: String, type: String) -> String {
        let mode: String
        switch type {
        case "SALARIE": mode = CompletionTextes.typeUniqueSalarie
        case "LIBERAL": mode = CompletionTextes.typeUniqueLiberal
        default: mode = CompletionTextes.typeUniqueMixte
        }
        let libelle = MissionPresentation.professionLabel(profession)
        return "\(CompletionTextes.typeUniqueDebut) \(libelle)\(CompletionTextes.typeUniqueMilieu) \(mode)."
    }

    /// Modes après la lecture du référentiel (l.191-199, profession figée) : `LIBERAL` retiré quand le référentiel est
    /// connu et ne propose ni `LIBERAL` ni `MIXTE` ; conservé tant que le référentiel est inconnu (chargement,
    /// indisponibilité : « Vos choix sont conservés ; l’ajout du libéral nécessite une vérification »,
    /// `ChoixModesExercice.tsx` l.43), sans jamais pouvoir être ajouté (option masquée, `ChoixModesExercice.presenter`).
    public static func contratsApresReferentiel(_ contrats: [String], typesAutorises: [String]?) -> [String] {
        guard let typesAutorises else { return contrats }
        let liberalPossible = typesAutorises.contains { $0 == "LIBERAL" || $0 == "MIXTE" }
        return liberalPossible ? contrats : contrats.filter { $0 != "LIBERAL" }
    }

    /// Brouillon serveur (`donneesFormulaire`, l.152-167) réduit aux clés de `clesBrouillon` : un champ nil n'est pas
    /// transmis, une chaîne vide l'est (effacement saisi par l'utilisateur, `donnees || p_donnees`).
    public static func donneesBrouillon(_ formulaire: FormulaireInscription) -> [String: ValeurJSON] {
        var donnees: [String: ValeurJSON] = ["typesContrat": .tableau(formulaire.typesContrat.map(ValeurJSON.chaine))]
        if let prenom = formulaire.prenom { donnees["prenom"] = .chaine(prenom) }
        if let nom = formulaire.nom { donnees["nom"] = .chaine(nom) }
        if let telephone = formulaire.telephone { donnees["telephone"] = .chaine(telephone) }
        if let dateNaissance = formulaire.dateNaissance { donnees["dateNaissance"] = .chaine(dateNaissance) }
        if let rpps = formulaire.rpps { donnees["rpps"] = .chaine(rpps) }
        if let rayon = formulaire.rayon { donnees["rayon"] = .nombre(Double(rayon)) }
        return donnees
    }

    /// Corps de `register-soignant` (l.181-192) : `telephone || null`, `rpps || null` ; `rayon` seulement s'il vient du
    /// brouillon (sinon le serveur applique ses 30 km, l.295 : aucun défaut figé côté app) ; `profession` du parcours.
    public static func corpsFinalisation(_ formulaire: FormulaireInscription) -> [String: ValeurJSON] {
        let texteOuNull: (String?) -> ValeurJSON = { valeur in
            guard let valeur, !valeur.isEmpty else { return .null }
            return .chaine(valeur)
        }
        var corps: [String: ValeurJSON] = [
            "prenom": .chaine(formulaire.prenom ?? ""),
            "nom": .chaine(formulaire.nom ?? ""),
            "telephone": texteOuNull(formulaire.telephone),
            "dateNaissance": .chaine(formulaire.dateNaissance ?? ""),
            "profession": .chaine(formulaire.profession ?? ""),
            "typesContrat": .tableau(formulaire.typesContrat.map(ValeurJSON.chaine)),
            "rpps": texteOuNull(formulaire.rpps),
        ]
        if let rayon = formulaire.rayon { corps["rayon"] = .nombre(Double(rayon)) }
        return corps
    }

    /// Code machine de `register-soignant` qui impose la déconnexion locale (503, l.365-367).
    public static let codeFinalisationEnAttente = "ACCOUNT_FINALIZATION_PENDING"
}
