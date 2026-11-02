import Foundation

/// Planning de publication d'une mission par date réelle, côté établissement (lot 5, T3).
///
/// Port **structurel** de `src/lib/planning-derive.ts` (vecteurs golden
/// `planning-derive.json`) et de la re-dérivation de `src/components/FormulaireRecurrence.tsx`
/// (l.60-67, l.164-280, l.395-402). Principe « état dérivé » (CLAUDE.md) : une période
/// [début, fin] dérive la liste des jours, chaque jour porte ses créneaux, et les créneaux datés
/// sont l'unique source de vérité ; une récurrence (« toutes les dates », « lundi–vendredi »,
/// « appliquer à tous ») n'est qu'un initialiseur. Re-dériver la période conserve un jour resté
/// dans la période (état et exceptions compris) et supprime un jour sorti.
///
/// Zéro règle juridique (blueprint lot 5 §2.9, D9) : ni plafond de 48 h par semaine, ni repos de
/// 11 h, ni recommandation de 12 h par jour, ni semaines civiles. `fn_valider_creneaux_mission_json`
/// les applique côté serveur et le natif affiche son refus mot pour mot. Seuls les contrôles
/// structurels sont portés : période, date travaillée, créneau manquant ou invalide (heure
/// inexistante ou ambiguë à Paris, fin avant début, durée hors de ]0, 24] h), chevauchement.
///
/// Les fonctions lèvent `DateHeureParisError` exactement là où le web lève une `RangeError`
/// (date civile impossible telle que `2026-02-30`, date illisible) ; une date issue d'un
/// sélecteur de date n'y mène jamais.
public enum PlanningDerive {
    /// Créneau saisi pour une date (`CreneauPlanningDate`).
    public struct Creneau: Equatable, Hashable, Sendable {
        /// Identifiant local, stable pendant la saisie.
        public var clientId: String
        /// Identifiant persisté (`mission_creneaux.id`), absent pour un créneau nouveau.
        public var id: String?
        /// `HH:mm`, heure murale de Paris.
        public var heureDebut: String
        public var heureFin: String
        /// La fin tombe le lendemain de la date du créneau (garde de nuit).
        public var finJourSuivant: Bool
        /// Instants contractuels chargés depuis la base : ils conservent l'occurrence exacte
        /// d'une heure murale répétée au passage à l'heure d'hiver tant que la borne visible
        /// correspondante n'a pas été modifiée.
        public var debutInitial: String?
        public var finInitial: String?

        public init(clientId: String, id: String? = nil, heureDebut: String, heureFin: String, finJourSuivant: Bool,
                    debutInitial: String? = nil, finInitial: String? = nil) {
            self.clientId = clientId; self.id = id; self.heureDebut = heureDebut; self.heureFin = heureFin
            self.finJourSuivant = finJourSuivant; self.debutInitial = debutInitial; self.finInitial = finInitial
        }
    }

    /// Date de la période, travaillée ou non, avec ses créneaux (`JourPlanningDate`).
    public struct Jour: Equatable, Hashable, Sendable {
        /// `YYYY-MM-DD`, jour civil de Paris.
        public var date: String
        public var actif: Bool
        public var creneaux: [Creneau]

        public init(date: String, actif: Bool, creneaux: [Creneau]) {
            self.date = date; self.actif = actif; self.creneaux = creneaux
        }
    }

    /// Créneau converti en instants (`CreneauPlanningMaterialise`).
    public struct CreneauMaterialise: Equatable, Hashable, Sendable {
        public var clientId: String
        public var id: String?
        public var date: String
        public var dateFin: String
        /// Instant ISO : l'instant initial chargé s'il est conservé, sinon `toISOString()` (UTC).
        public var debut: String
        public var fin: String
        public var dureeHeures: Double

        public init(clientId: String, id: String?, date: String, dateFin: String, debut: String, fin: String, dureeHeures: Double) {
            self.clientId = clientId; self.id = id; self.date = date; self.dateFin = dateFin
            self.debut = debut; self.fin = fin; self.dureeHeures = dureeHeures
        }
    }

    /// Résultat de `materialiserCreneau` : une valeur, ou le message d'erreur du web.
    public struct Materialisation: Equatable, Sendable {
        public var valeur: CreneauMaterialise?
        public var erreur: String?

        public init(valeur: CreneauMaterialise?, erreur: String?) {
            self.valeur = valeur; self.erreur = erreur
        }
    }

    /// Erreur structurelle bloquante (`ErreurPlanning` restreinte aux types structurels).
    public struct Erreur: Equatable, Hashable, Sendable {
        public enum TypeErreur: String, Sendable, CaseIterable {
            case plageInvalide = "PLAGE_INVALIDE"
            case creneauManquant = "CRENEAU_MANQUANT"
            case creneauInvalide = "CRENEAU_INVALIDE"
            case chevauchement = "CHEVAUCHEMENT"
        }

        /// Toutes les erreurs structurelles du web sont bloquantes.
        public static let gravite = "bloquant"

        public var type: TypeErreur
        public var message: String
        public var datesAffectees: [String]?
        public var creneauxAffectes: [String]?

        public init(type: TypeErreur, message: String, datesAffectees: [String]? = nil, creneauxAffectes: [String]? = nil) {
            self.type = type; self.message = message; self.datesAffectees = datesAffectees; self.creneauxAffectes = creneauxAffectes
        }
    }

    // MARK: - Messages repris du web (non juridiques)

    // source: src/lib/planning-derive.ts:139
    public static let messageHeuresInvalides = "Renseignez une heure de début et une heure de fin valides."
    // source: src/lib/planning-derive.ts:153
    public static let messageHeureAmbigue = "Cette heure existe deux fois à Paris lors du passage à l’heure d’hiver. Choisissez un horaire non ambigu."
    // source: src/lib/planning-derive.ts:154 (échappements ’ du web)
    public static let messageHeureInexistante = "Cette heure n\u{2019}existe pas à Paris en raison du passage à l\u{2019}heure d’été."
    // source: src/lib/planning-derive.ts:164
    public static let messageFinAvantDebut = "La fin doit être après le début. Pour une garde de nuit, choisissez « lendemain »."
    // source: src/lib/planning-derive.ts:168
    public static let messageDureeHorsBornes = "Un créneau doit durer plus de 0 h et au maximum 24 h."
    // source: src/components/FormulaireRecurrence.tsx:187
    public static let messagePeriodeInvalide = "Choisissez une période valide."
    // source: src/components/FormulaireRecurrence.tsx:199
    public static let messagePeriodeTropLongue = "Une mission ne peut pas couvrir plus de 366 dates."
    // source: src/components/FormulaireRecurrence.tsx:211
    public static let messageAucuneDateTravaillee = "Sélectionnez au moins une date travaillée."

    /// Nombre maximal de dates d'une période (`FormulaireRecurrence.tsx` l.166, l.193).
    public static let maximumDates = 366

    // MARK: - Dates (planning-derive.ts l.78-116)

    /// `/^\d{4}-\d{2}-\d{2}$/` (chiffres ASCII seulement, comme `\d` en JavaScript).
    static func estDate(_ valeur: String) -> Bool {
        let o = Array(valeur.utf8)
        guard o.count == 10, o[4] == 0x2D, o[7] == 0x2D else { return false }
        return [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy { estChiffre(o[$0]) }
    }

    /// `/^(?:[01]\d|2[0-3]):[0-5]\d$/`.
    static func estHeure(_ valeur: String) -> Bool {
        let o = Array(valeur.utf8)
        guard o.count == 5, o[2] == 0x3A, estChiffre(o[0]), estChiffre(o[1]), estChiffre(o[3]), estChiffre(o[4]) else { return false }
        let heure = Int(o[0] - 0x30) * 10 + Int(o[1] - 0x30)
        return heure <= 23 && o[3] <= 0x35
    }

    private static func estChiffre(_ octet: UInt8) -> Bool { (0x30...0x39).contains(octet) }

    /// Comparaison de chaînes JavaScript (`a < b`, unités UTF-16).
    static func precede(_ a: String, _ b: String) -> Bool {
        a.utf16.lexicographicallyPrecedes(b.utf16)
    }

    /// Midi à Paris du jour `date` (`instantMidiParis`).
    private static func instantMidi(_ date: String) throws -> Date {
        try DateHeureParis.instantDepuisSaisie("\(date)T12:00")
    }

    /// Jour civil situé `nombre` jours après `date` (`ajouterJoursDate`).
    public static func ajouterJoursDate(_ date: String, _ nombre: Int) throws -> String {
        DateHeureParis.cleJour(DateHeureParis.ajouterJoursCivils(try instantMidi(date), nombre))
    }

    /// Chaque date réelle de [dateDebut, dateFin] (`datesDansPlage`). Vide si une borne est mal
    /// formée ou si la fin précède le début ; s'arrête à 367 dates, que la validation de période
    /// refuse ensuite (plus de 366).
    public static func datesDansPlage(_ dateDebut: String, _ dateFin: String) throws -> [String] {
        guard estDate(dateDebut), estDate(dateFin), !precede(dateFin, dateDebut) else { return [] }
        var dates: [String] = []
        var date = dateDebut
        while !precede(dateFin, date) && dates.count <= maximumDates {
            dates.append(date)
            date = try ajouterJoursDate(date, 1)
        }
        return dates
    }

    /// Jour ISO (1 = lundi … 7 = dimanche) d'une date `YYYY-MM-DD` (`jourSemaineISO`), avec la
    /// normalisation de `Date.UTC` (`2026-02-30` → lundi 2 mars). `nil` pour une date illisible
    /// (`NaN` côté web).
    public static func jourSemaineISO(_ date: String) -> Int? {
        let parties = date.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parties.count >= 3,
              var annee = entierJS(parties[0]), let mois = entierJS(parties[1]), let jour = entierJS(parties[2]) else { return nil }
        // `Date.UTC` lit une année de 0 à 99 comme 1900 à 1999.
        if (0...99).contains(annee) { annee += 1900 }
        guard abs(annee) <= 275_760, abs(mois) <= 3_400_000, abs(jour) <= 100_000_000 else { return nil }
        let js = CalendrierCivil.jourSemaine(annee: annee, mois: mois, jour: jour)
        return js == 0 ? 7 : js
    }

    /// `Number(chaine)` tronqué vers zéro (`ToIntegerOrInfinity` de `Date.UTC`) ; `nil` pour NaN
    /// ou l'infini.
    private static func entierJS(_ chaine: String) -> Int? {
        let nette = chaine.trimmingCharacters(in: .whitespacesAndNewlines)
        if nette.isEmpty { return 0 }
        guard nette.unicodeScalars.allSatisfy({ $0.isASCII }), let nombre = Double(nette), nombre.isFinite,
              abs(nombre) < 1e15 else { return nil }
        return Int(nombre.rounded(.towardZero))
    }

    /// `EEEE d MMMM yyyy` à Paris (`libelleDate`).
    public static func libelleDate(_ date: String) throws -> String {
        DateHeureParis.format(try instantMidi(date), "EEEE d MMMM yyyy")
    }

    /// `EEE d MMM` à Paris (`libelleDateCourte`).
    public static func libelleDateCourte(_ date: String) throws -> String {
        DateHeureParis.format(try instantMidi(date), "EEE d MMM")
    }

    /// Date de fin d'un créneau : la date elle-même, ou le lendemain (`dateFinCreneau`).
    public static func dateFinCreneau(_ date: String, finJourSuivant: Bool) throws -> String {
        finJourSuivant ? try ajouterJoursDate(date, 1) : date
    }

    // MARK: - Matérialisation (planning-derive.ts l.118-191)

    /// Instant d'une borne : l'instant initial s'il désigne toujours la même date et la même
    /// heure murale, sinon la saisie interprétée à Paris (`resoudreBorneCreneau`).
    private static func resoudreBorne(date: String, heure: String, instantInitial: String?) throws -> (instant: Date, valeur: String) {
        if let instantInitial, !instantInitial.isEmpty {
            let instant = try DateHeureParis.instantJolene(instantInitial)
            if DateHeureParis.cleJour(instant) == date && DateHeureParis.format(instant, "HH:mm") == heure {
                return (instant, instantInitial)
            }
        }
        let instant = try DateHeureParis.instantDepuisSaisie("\(date)T\(heure)")
        return (instant, DateHeureParis.isoUTC(instant))
    }

    /// Convertit un créneau saisi en instants (`materialiserCreneau`). Une heure inexistante ou
    /// ambiguë à Paris, une fin avant le début sans « lendemain » ou une durée hors de ]0, 24] h
    /// donnent le message du web ; une date civile impossible avec « lendemain » lève, comme le web.
    public static func materialiserCreneau(date: String, creneau: Creneau) throws -> Materialisation {
        guard estDate(date), estHeure(creneau.heureDebut), estHeure(creneau.heureFin) else {
            return Materialisation(valeur: nil, erreur: messageHeuresInvalides)
        }
        let dateFin = try dateFinCreneau(date, finJourSuivant: creneau.finJourSuivant)
        let debut: (instant: Date, valeur: String)
        let fin: (instant: Date, valeur: String)
        do {
            debut = try resoudreBorne(date: date, heure: creneau.heureDebut, instantInitial: creneau.debutInitial)
            fin = try resoudreBorne(date: dateFin, heure: creneau.heureFin, instantInitial: creneau.finInitial)
        } catch let erreur as DateHeureParisError {
            if case .ambigue = erreur { return Materialisation(valeur: nil, erreur: messageHeureAmbigue) }
            return Materialisation(valeur: nil, erreur: messageHeureInexistante)
        }
        let debutMs = DateHeureParis.millisecondes(debut.instant)
        let finMs = DateHeureParis.millisecondes(fin.instant)
        let dureeHeures = Double(finMs - debutMs) / 3_600_000

        if !creneau.finJourSuivant && finMs <= debutMs {
            return Materialisation(valeur: nil, erreur: messageFinAvantDebut)
        }
        if !dureeHeures.isFinite || dureeHeures <= 0 || dureeHeures > 24 {
            return Materialisation(valeur: nil, erreur: messageDureeHorsBornes)
        }
        return Materialisation(valeur: CreneauMaterialise(
            clientId: creneau.clientId, id: creneau.id, date: date, dateFin: dateFin,
            debut: debut.valeur, fin: fin.valeur, dureeHeures: dureeHeures
        ), erreur: nil)
    }

    /// Créneaux valides des jours travaillés, triés par début (`materialiserPlanning`). C'est la
    /// liste envoyée à la publication : dérivée des jours, jamais saisie à part.
    public static func materialiserPlanning(_ jours: [Jour]) throws -> [CreneauMaterialise] {
        var creneaux: [CreneauMaterialise] = []
        for jour in jours where jour.actif {
            for creneau in jour.creneaux {
                if let valeur = try materialiserCreneau(date: jour.date, creneau: creneau).valeur { creneaux.append(valeur) }
            }
        }
        return triParDebut(creneaux)
    }

    /// `new Date(iso).getTime()`, NaN si illisible (les comparaisons avec NaN sont fausses).
    private static func temps(_ iso: String) -> Double {
        guard let date = try? DateHeureParis.instantJolene(iso) else { return .nan }
        return Double(DateHeureParis.millisecondes(date))
    }

    /// Tri stable par début, comme `Array.prototype.sort`.
    private static func triParDebut(_ creneaux: [CreneauMaterialise]) -> [CreneauMaterialise] {
        creneaux.enumerated().sorted { a, b in
            let ta = temps(a.element.debut), tb = temps(b.element.debut)
            if ta < tb { return true }
            if tb < ta { return false }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: - Validation structurelle (validerPlanningDates l.269-324, sans les règles du travail)

    /// Erreurs `CRENEAU_MANQUANT`, `CRENEAU_INVALIDE` et `CHEVAUCHEMENT` de `validerPlanningDates`,
    /// dans l'ordre du web. L'avertissement de plus de 12 h, le repos de 11 h et le plafond de 48 h
    /// ne sont pas calculés (D9) : le planning est structurellement valide si la liste est vide.
    public static func erreursStructurelles(_ jours: [Jour]) throws -> [Erreur] {
        var erreurs: [Erreur] = []
        var valides: [CreneauMaterialise] = []

        for jour in jours where jour.actif {
            if jour.creneaux.isEmpty {
                erreurs.append(Erreur(type: .creneauManquant,
                                      message: "\(try libelleDate(jour.date)) est travaillé mais ne contient aucun créneau.",
                                      datesAffectees: [jour.date]))
                continue
            }
            for creneau in jour.creneaux {
                let resultat = try materialiserCreneau(date: jour.date, creneau: creneau)
                guard let valeur = resultat.valeur else {
                    erreurs.append(Erreur(type: .creneauInvalide,
                                          message: "\(try libelleDate(jour.date)) : \(resultat.erreur ?? "")",
                                          datesAffectees: [jour.date], creneauxAffectes: [creneau.clientId]))
                    continue
                }
                valides.append(valeur)
            }
        }

        let tries = triParDebut(valides)
        if tries.count > 1 {
            for index in 1..<tries.count {
                let precedent = tries[index - 1], courant = tries[index]
                if temps(courant.debut) < temps(precedent.fin) {
                    erreurs.append(Erreur(
                        type: .chevauchement,
                        message: "Chevauchement entre les créneaux des \(try libelleDateCourte(precedent.date)) et \(try libelleDateCourte(courant.date)).",
                        datesAffectees: [precedent.date, courant.date],
                        creneauxAffectes: [precedent.clientId, courant.clientId]
                    ))
                }
            }
        }
        return erreurs
    }

    /// Validation de la saisie complète (`FormulaireRecurrence.tsx` l.180-218) : période, nombre de
    /// dates, au moins une date travaillée, puis erreurs structurelles. Une liste vide autorise le
    /// récapitulatif ; le serveur reste juge des règles du travail. (Le web n'affiche une erreur
    /// `PLAGE_INVALIDE` qu'après une première saisie de dates, l.433 : choix d'écran de T9.)
    public static func validerPeriode(dateDebut: String, dateFin: String, jours: [Jour]) throws -> [Erreur] {
        if dateDebut.isEmpty || dateFin.isEmpty || precede(dateFin, dateDebut) {
            return [Erreur(type: .plageInvalide, message: messagePeriodeInvalide)]
        }
        if try datesDansPlage(dateDebut, dateFin).count > maximumDates {
            return [Erreur(type: .plageInvalide, message: messagePeriodeTropLongue)]
        }
        if !jours.contains(where: \.actif) {
            return [Erreur(type: .creneauManquant, message: messageAucuneDateTravaillee)]
        }
        return try erreursStructurelles(jours)
    }

    // MARK: - Re-dérivation et actions de saisie (FormulaireRecurrence.tsx)

    /// Créneau proposé à un jour nouveau ou ajouté : 07:00 → 19:00 le même jour (l.60-67).
    public static func creneauDefaut(clientId: String) -> Creneau {
        Creneau(clientId: clientId, heureDebut: "07:00", heureFin: "19:00", finJourSuivant: false)
    }

    /// Jours de la période [dateDebut, dateFin] (l.164-178) : un jour déjà connu dont la date reste
    /// dans la période est repris tel quel (travaillé ou non, créneaux et exceptions compris) ; un
    /// jour nouveau est **non travaillé** avec le créneau par défaut ; un jour sorti disparaît. Une
    /// période vide ou de plus de 366 dates ne garde aucun jour.
    public static func rederiver(dateDebut: String, dateFin: String, precedents: [Jour],
                                 nouvelIdClient: () -> String) throws -> [Jour] {
        let dates = try datesDansPlage(dateDebut, dateFin)
        if dates.isEmpty || dates.count > maximumDates { return [] }
        var parDate: [String: Jour] = [:]
        // `new Map(precedents.map(...))` : la dernière entrée d'une même date l'emporte.
        for jour in precedents { parDate[jour.date] = jour }
        return dates.map { date in
            parDate[date] ?? Jour(date: date, actif: false, creneaux: [creneauDefaut(clientId: nouvelIdClient())])
        }
    }

    /// Bascule travaillé / repos d'une date (`toggleDate`, l.237-243). Activer un jour sans créneau
    /// lui donne le créneau par défaut ; désactiver garde les créneaux saisis.
    public static func basculer(_ jours: [Jour], date: String, nouvelIdClient: () -> String) -> [Jour] {
        jours.map { jour in
            guard jour.date == date else { return jour }
            var suivant = jour
            suivant.actif = !jour.actif
            if !jour.actif && jour.creneaux.isEmpty { suivant.creneaux = [creneauDefaut(clientId: nouvelIdClient())] }
            return suivant
        }
    }

    /// Ajoute un créneau par défaut à une date, qui devient travaillée (`ajouterCreneau`, l.245-247).
    public static func ajouterCreneau(_ jours: [Jour], date: String, nouvelIdClient: () -> String) -> [Jour] {
        jours.map { jour in
            guard jour.date == date else { return jour }
            var suivant = jour
            suivant.actif = true
            suivant.creneaux.append(creneauDefaut(clientId: nouvelIdClient()))
            return suivant
        }
    }

    /// Remplace, à une date, le créneau de même `clientId` (l.395-398).
    public static func modifierCreneau(_ jours: [Jour], date: String, creneau: Creneau) -> [Jour] {
        jours.map { jour in
            guard jour.date == date else { return jour }
            var suivant = jour
            suivant.creneaux = jour.creneaux.map { $0.clientId == creneau.clientId ? creneau : $0 }
            return suivant
        }
    }

    /// Retire, à une date, le créneau de `clientId` donné (l.399-402).
    public static func retirerCreneau(_ jours: [Jour], date: String, clientId: String) -> [Jour] {
        jours.map { jour in
            guard jour.date == date else { return jour }
            var suivant = jour
            suivant.creneaux = jour.creneaux.filter { $0.clientId != clientId }
            return suivant
        }
    }

    /// Initialiseur de sélection (`appliquerSelection`, l.249-258) : chaque jour devient travaillé
    /// selon `predicat(jour, index)` ; un jour activé sans créneau reçoit le créneau par défaut.
    public static func appliquerSelection(_ jours: [Jour], nouvelIdClient: () -> String,
                                          _ predicat: (Jour, Int) throws -> Bool) rethrows -> [Jour] {
        var resultat: [Jour] = []
        resultat.reserveCapacity(jours.count)
        for (index, jour) in jours.enumerated() {
            var suivant = jour
            suivant.actif = try predicat(jour, index)
            if suivant.actif && jour.creneaux.isEmpty { suivant.creneaux = [creneauDefaut(clientId: nouvelIdClient())] }
            resultat.append(suivant)
        }
        return resultat
    }

    /// « Toutes les dates ».
    public static func toutesLesDates(_ jours: [Jour], nouvelIdClient: () -> String) -> [Jour] {
        appliquerSelection(jours, nouvelIdClient: nouvelIdClient) { _, _ in true }
    }

    /// « Lundi–vendredi » (`jourSemaineISO(date) <= 5`).
    public static func lundiAuVendredi(_ jours: [Jour], nouvelIdClient: () -> String) -> [Jour] {
        appliquerSelection(jours, nouvelIdClient: nouvelIdClient) { jour, _ in (jourSemaineISO(jour.date) ?? Int.max) <= 5 }
    }

    /// « Aucune ».
    public static func aucuneDate(_ jours: [Jour], nouvelIdClient: () -> String) -> [Jour] {
        appliquerSelection(jours, nouvelIdClient: nouvelIdClient) { _, _ in false }
    }

    /// « 1 semaine civile sur 2 » (`appliquerUneSemaineSurDeux`, l.277-280) : semaines de la
    /// période dans l'ordre d'apparition, une sur deux à partir de la première.
    public static func uneSemaineSurDeux(_ jours: [Jour], nouvelIdClient: () -> String) throws -> [Jour] {
        let cle = { (jour: Jour) in DateHeureParis.cleSemaine(try DateHeureParis.instantJolene("\(jour.date)T12:00")) }
        var semaines: [String] = []
        for jour in jours {
            let semaine = try cle(jour)
            if !semaines.contains(semaine) { semaines.append(semaine) }
        }
        return try appliquerSelection(jours, nouvelIdClient: nouvelIdClient) { jour, _ in
            (semaines.firstIndex(of: try cle(jour)) ?? -1) % 2 == 0
        }
    }

    /// « Appliquer le premier créneau à toutes les dates travaillées » (l.260-275) : le premier
    /// créneau du premier jour travaillé remplace les créneaux de chaque jour travaillé, copié sans
    /// identifiant persisté et sous un nouvel identifiant local. Sans jour travaillé, rien ne change.
    public static func appliquerPremierCreneauATous(_ jours: [Jour], nouvelIdClient: () -> String) -> [Jour] {
        guard let modele = jours.first(where: \.actif)?.creneaux.first else { return jours }
        return jours.map { jour in
            guard jour.actif else { return jour }
            var copie = modele
            copie.id = nil
            copie.clientId = nouvelIdClient()
            var suivant = jour
            suivant.creneaux = [copie]
            return suivant
        }
    }
}
