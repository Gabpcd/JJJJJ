import Foundation

/// Ton d'un badge ou d'un message de l'écran Justificatifs (couleurs de `BadgeY2K` côté app ; jamais la couleur seule).
public enum TonJustificatif: Equatable, Sendable {
    case succes, attention, erreur, info, neutre
}

/// Texte affiché avec son ton (message de carte, issue d'envoi ou d'action).
public struct TexteJustificatif: Equatable, Sendable {
    public var texte: String
    public var ton: TonJustificatif

    public init(texte: String, ton: TonJustificatif) {
        self.texte = texte; self.ton = ton
    }
}

/// Badge de statut d'une carte (`document-statut-<TYPE>`) ; `enCours` : vérification en cours (indicateur animé).
public struct BadgeJustificatif: Equatable, Sendable {
    public var texte: String
    public var ton: TonJustificatif
    public var enCours: Bool

    public init(texte: String, ton: TonJustificatif, enCours: Bool) {
        self.texte = texte; self.ton = ton; self.enCours = enCours
    }
}

/// Bouton d'une carte, dans l'ordre du web.
public struct ActionJustificatif: Equatable, Sendable {
    public enum Genre: Equatable, Sendable {
        /// Consultation (copie protégée, QuickLook).
        case voir
        /// Revérification manuelle (jamais automatique).
        case reverifier
        /// Demande de revue humaine (`fn_demander_revue_document`).
        case demanderRevue
        /// Ouvre la feuille de téléversement pour ce type.
        case televerser
    }

    public var genre: Genre
    public var libelle: String
    public var enCours: Bool
    /// Bouton plein (`btn-primary` du web) ; sinon lien.
    public var principale: Bool

    public init(genre: Genre, libelle: String, enCours: Bool, principale: Bool) {
        self.genre = genre; self.libelle = libelle; self.enCours = enCours; self.principale = principale
    }
}

/// Carte d'une exigence (`DocumentsSoignant.tsx` l.678-811).
public struct CarteJustificatif: Equatable, Sendable, Identifiable {
    public var id: String { typeDocument }
    public var typeDocument: String
    public var titre: String
    public var obligatoire: Bool
    /// `documents_requis_par_profession.description` (table paramétrée), affichée telle quelle.
    public var description: String?
    /// Première exigence optionnelle après les critiques : séparateur « Documents optionnels » (l.667-675).
    public var ouvreLesOptionnels: Bool
    /// Pièce retenue (la plus récente du type), nil si manquante.
    public var document: DocumentSoignant?
    /// « 📎 <nom> (téléversé le <date>) » (l.693), pièce présente seulement.
    public var fichier: String?
    public var badge: BadgeJustificatif?
    public var messages: [TexteJustificatif]
    /// « Délivré le … », « Valide jusqu'au … » (l.721-726).
    public var dates: [String]
    public var actions: [ActionJustificatif]
}

/// En-tête de progression (l.558-598), affiché seulement quand la profession est connue.
public enum EnteteJustificatifs: Equatable, Sendable {
    case aCompleter(titre: String, prochaineEtape: String?, bouton: String?, typeProchaine: String?, valides: Int, total: Int, note: String)
    case aJour(titre: String, detail: String)
    case aucuneExigence(titre: String, detail: String)
}

/// Bandeau « expire bientôt » (l.601-609) : texte et type à mettre à jour (« Mettre à jour → »).
public struct ExpirationProche: Equatable, Sendable, Identifiable {
    public var id: String { document.id }
    public var document: DocumentSoignant
    public var typeDocument: String { document.typeDocument }
    public var texte: String
}

/// Bandeau d'un profil incomplet (l.530-555). Le bouton du web (`/soignant/profil`) n'est pas repris : le Profil natif
/// ne modifie ni la profession ni le mode d'exercice (aucun bouton sans effet).
public struct BandeauProfil: Equatable, Sendable {
    public var titre: String
    public var texte: String

    public init(titre: String, texte: String) {
        self.titre = titre; self.texte = texte
    }
}

/// Bandeau RCP de l'exercice libéral ou mixte (`DocumentsSoignant.tsx` l.611-640), textes verbatim de
/// `TextesWeb.Justificatifs` (HARD STOP n°4 tranché par délégation le 8 novembre 2026, tranche L2-TJ) : RCP expirée → deux
/// lignes (l.623-624, encre `destructive`) ; RCP absente ou non vérifiée → une ligne (l.634, ton ambre).
public struct BandeauRcp: Equatable, Sendable {
    public var alerte: AlerteRcp
    /// Lignes dans l'ordre du web ; la première est en gras pour une RCP expirée (`font-medium`, l.623).
    public var textes: [String]

    public init(alerte: AlerteRcp, textes: [String]) {
        self.alerte = alerte; self.textes = textes
    }

    /// `text-destructive` (expirée) ou `text-amber-700` (manquante).
    public var ton: TonJustificatif { alerte == .expiree ? .erreur : .attention }
}

/// Carte de la section « Étudiant / interne en santé » (l.852-903).
public struct CarteComplementaire: Equatable, Sendable, Identifiable {
    public var id: String { typeDocument }
    public var typeDocument: String
    public var titre: String
    /// Texte explicatif du web : condition d'accès verbatim (`TextesWeb.Justificatifs`, HARD STOP n°4 tranché par délégation
    /// le 8 novembre 2026) pour la scolarité et la licence, libellé vouvoyé pour la qualification.
    public var description: String?
    public var statut: String?
    public var bouton: String
}

/// Présentation de l'écran Justificatifs (lot 2 T7), portée du rendu de `src/pages/DocumentsSoignant.tsx`. État dérivé :
/// tout se recalcule depuis `DossierDocuments` (lignes serveur) et l'horloge passée par l'écran ; aucune règle locale dans
/// les vues. Dates `d MMM yyyy` en français (`DateHeureParis`, heure de Paris).
public enum PresentationJustificatifs {
    private typealias L = LibellesJustificatifs

    // MARK: - Bandeaux et en-tête

    public static func bandeauxProfil(_ dossier: DossierDocuments) -> [BandeauProfil] {
        guard let profil = dossier.profil else { return [] }
        guard let profession = profil.profession, !profession.isEmpty else {
            return [BandeauProfil(titre: L.professionNonDefinie, texte: L.professionNonDefinieTexte)]
        }
        guard let exercice = profil.typeExercice, !exercice.isEmpty else {
            return [BandeauProfil(titre: L.modeExerciceTitre, texte: L.modeExerciceTexte)]
        }
        return []
    }

    public static func entete(_ dossier: DossierDocuments, maintenant: Date) -> EnteteJustificatifs? {
        guard let profession = dossier.profil?.profession, !profession.isEmpty else { return nil }
        let total = dossier.exigencesCritiques.count
        let valides = dossier.exigencesValidees(maintenant: maintenant).count
        let manquants = total - valides
        if manquants > 0 {
            let titre = L.resteDebut + " " + String(manquants) + " " + L.resteDocument + (manquants > 1 ? "s" : "") + " " + L.resteFin
            let prochaine = dossier.prochaineExigence(maintenant: maintenant)
            let libelle = prochaine.map { L.libelleType($0.typeDocument) }
            return .aCompleter(titre: titre, prochaineEtape: libelle.map { L.prochaineEtape + " " + $0 },
                               bouton: libelle.map { L.televerserPrefixe + " " + $0 }, typeProchaine: prochaine?.typeDocument,
                               valides: valides, total: total, note: L.postulerDesMaintenant)
        }
        if total > 0 {
            let exercice = dossier.profil?.typeExercice ?? ""
            return .aJour(titre: exercice.isEmpty ? L.aJourSansExercice : L.aJourExercice, detail: L.retrouvezIci)
        }
        return .aucuneExigence(titre: L.vosJustificatifs, detail: L.aucunObligatoire)
    }

    // MARK: - Expirations et incohérence

    public static func expirations(_ dossier: DossierDocuments, maintenant: Date) -> [ExpirationProche] {
        dossier.expirantBientot(maintenant: maintenant).compactMap { document in
            guard let jours = DossierDocuments.joursRestants(document, maintenant: maintenant),
                  let fin = date(document.valideJusqua) else { return nil }
            let texte = L.expirePrefixe + " " + L.libelleType(document.typeDocument) + " " + L.expireDans + " " + String(jours) + " "
                + L.jour + (jours > 1 ? "s" : "") + " (" + fin + ")."
            return ExpirationProche(document: document, texte: texte)
        }
    }

    /// Bandeau d'incohérence (l.287-306, l.643-650) : alerte locale « RCP vérifiée expirée », puis les problèmes du serveur
    /// quand il déclare le dossier incohérent ; aucun contrôle sans pièce. Lecture serveur en échec (`coherence` nil) :
    /// alertes locales seules, comme le web.
    public static func incoherence(_ dossier: DossierDocuments, coherence: CoherenceDocuments?, maintenant: Date) -> String? {
        guard !dossier.documents.isEmpty else { return nil }
        var alertes: [String] = []
        if let rcp = dossier.documents.first(where: { $0.typeDocument == "RCP_ASSURANCE" && $0.statutVerification == "VERIFIE" }),
           let fin = rcp.valideJusqua, !fin.isEmpty, DisponibilitePointage.temps(fin) < DisponibilitePointage.temps(maintenant) {
            alertes.append(L.rcpExpireeCoherence)
        }
        let message: String?
        if let coherence, !coherence.coherent, !coherence.problemes.isEmpty {
            let tous = (alertes + [coherence.problemes.joined(separator: ". ")]).filter { !$0.isEmpty }
            message = tous.isEmpty ? nil : tous.joined(separator: ". ")
        } else {
            message = alertes.isEmpty ? nil : alertes.joined(separator: ". ") + "."
        }
        return message.map { L.incoherencePrefixe + " " + $0 + " " + L.incoherenceFin }
    }

    /// Bandeau RCP (l.611-640), après les expirations proches et avant l'incohérence, comme le web. Règle de T6
    /// (`DossierDocuments.alerteRcp` : libéral ou mixte seulement, date passée quel que soit le statut, sinon RCP absente ou
    /// non vérifiée) ; textes verbatim, tutoiement du web compris (décision déléguée du 8 novembre 2026, DECISIONS_LOT2).
    public static func bandeauRcp(_ dossier: DossierDocuments, maintenant: Date) -> BandeauRcp? {
        switch dossier.alerteRcp(maintenant: maintenant) {
        case .expiree?:
            return BandeauRcp(alerte: .expiree, textes: [TextesWeb.Justificatifs.rcpExpiree,
                                                        TextesWeb.Justificatifs.rcpExpireeRestriction])
        case .manquante?:
            return BandeauRcp(alerte: .manquante, textes: [TextesWeb.Justificatifs.rcpObligatoire])
        case nil:
            return nil
        }
    }

    // MARK: - Cartes

    /// - Parameters:
    ///   - enVerification: pièces dont le verdict est suivi en ligne (`DocumentsModel.enVerification`).
    ///   - reverification: pièce en cours de revérification ; elle compte aussi comme « en vérification » (l.664).
    ///   - demandeRevue: pièce dont la demande de revue est en cours (« Demande en cours… »).
    public static func cartes(_ dossier: DossierDocuments, maintenant: Date, enVerification: Set<String>,
                              reverification: String?, demandeRevue: String?) -> [CarteJustificatif] {
        let ordonnees = dossier.exigencesOrdonnees
        return ordonnees.enumerated().map { index, exigence in
            let critique = exigence.estCritique == true
            let ouvre = index > 0 && !critique && ordonnees[index - 1].estCritique == true
            var carte = CarteJustificatif(typeDocument: exigence.typeDocument, titre: L.libelleType(exigence.typeDocument),
                                          obligatoire: critique, description: exigence.description.flatMap { $0.isEmpty ? nil : $0 },
                                          ouvreLesOptionnels: ouvre, document: nil, fichier: nil, badge: nil, messages: [], dates: [],
                                          actions: [])
            let etat = dossier.etat(de: exigence, maintenant: maintenant)
            let enCours: (DocumentSoignant) -> Bool = { enVerification.contains($0.id) || reverification == $0.id }
            let reverif: (DocumentSoignant) -> ActionJustificatif = {
                ActionJustificatif(genre: .reverifier, libelle: L.reverifier, enCours: reverification == $0.id, principale: false)
            }
            let revue: (DocumentSoignant) -> ActionJustificatif = {
                let demande = demandeRevue == $0.id
                return ActionJustificatif(genre: .demanderRevue, libelle: demande ? L.demandeEnCours : L.demanderRevue,
                                          enCours: demande, principale: false)
            }
            switch etat {
            case let .presente(document, aConfirmer):
                carte.document = document
                carte.fichier = fichier(document)
                let verification = enCours(document)
                switch document.statutVerification {
                case "VERIFIE"? where !aConfirmer:
                    carte.badge = BadgeJustificatif(texte: L.verifie, ton: .succes, enCours: false)
                case "EN_ATTENTE"?:
                    carte.badge = BadgeJustificatif(texte: verification ? L.verificationAutomatiqueEnCours : L.analyseNonConclue,
                                                    ton: .attention, enCours: verification)
                case "REVUE_MANUELLE_REQUISE"?:
                    carte.badge = BadgeJustificatif(texte: L.demandeRecue, ton: .info, enCours: false)
                case "API_INDISPONIBLE"?:
                    carte.badge = BadgeJustificatif(texte: L.verificationIndisponible, ton: .neutre, enCours: false)
                default:
                    break
                }
                if aConfirmer {
                    let profession = dossier.profil?.profession ?? ""
                    carte.messages = [TexteJustificatif(texte: L.qualificationDebut + " " + profession + " " + L.qualificationFin,
                                                        ton: .attention)]
                }
                carte.dates = [date(document.valideDepuis).map { L.delivreLe + " " + $0 },
                               date(document.valideJusqua).map { L.valideJusquau + " " + $0 }].compactMap { $0 }
                carte.actions = [ActionJustificatif(genre: .voir, libelle: L.voirLeDocument, enCours: false, principale: false)]
                if document.statutVerification != "VERIFIE" || aConfirmer { carte.actions.append(reverif(document)) }
                if ["EN_ATTENTE", "API_INDISPONIBLE"].contains(document.statutVerification ?? ""), !verification {
                    carte.actions.append(revue(document))
                }
                carte.actions.append(ActionJustificatif(genre: .televerser, libelle: L.remplacer, enCours: false, principale: false))
            case let .rejetee(document):
                carte.document = document
                if enCours(document) {
                    carte.badge = BadgeJustificatif(texte: L.verificationEnCours, ton: .attention, enCours: true)
                } else {
                    let motif = document.motifRejet.flatMap { $0.isEmpty ? nil : " — " + $0 } ?? ""
                    carte.messages = [TexteJustificatif(texte: L.documentNonValide + motif + L.documentNonValideFin, ton: .erreur)]
                    carte.badge = BadgeJustificatif(texte: L.rejete, ton: .erreur, enCours: false)
                }
                carte.actions = [ActionJustificatif(genre: .televerser, libelle: L.reessayer, enCours: false, principale: true),
                                 ActionJustificatif(genre: .voir, libelle: L.voir, enCours: false, principale: false),
                                 reverif(document), revue(document)]
            case let .expiree(document):
                carte.document = document
                let fin = date(document.valideJusqua) ?? (document.valideJusqua ?? "")
                carte.messages = [TexteJustificatif(texte: L.expireDepuis + " " + fin + L.expireDepuisFin, ton: .attention)]
                carte.badge = BadgeJustificatif(texte: L.expire, ton: .attention, enCours: false)
                carte.actions = [ActionJustificatif(genre: .televerser, libelle: L.televerserNouveau, enCours: false, principale: true),
                                 reverif(document)]
            case .manquante:
                carte.messages = [TexteJustificatif(texte: L.aTeleverser, ton: .attention)]
                carte.actions = [ActionJustificatif(genre: .televerser, libelle: L.plusTeleverser, enCours: false, principale: true)]
            }
            return carte
        }
    }

    // MARK: - Documents complémentaires

    /// Cartes « Étudiant / interne en santé » visibles (`ComplementairesVisibles`, ordre du web). Les textes qui énoncent une
    /// condition d'accès (pré-éligibilité étudiante l.867-868, remplacements de médecin l.882-883) sont affichés verbatim
    /// (`TextesWeb.Justificatifs`, HARD STOP n°4 tranché par délégation le 8 novembre 2026, tranche L2-TJ).
    public static func complementaires(_ dossier: DossierDocuments) -> [CarteComplementaire] {
        guard let profil = dossier.profil else { return [] }
        let visibles = ComplementairesVisibles(profil: profil)
        var cartes: [CarteComplementaire] = []
        let libelleStatut: (DocumentSoignant?) -> String? = { document in
            document.flatMap { L.statutsVerification[$0.statutVerification ?? ""] }
        }
        if visibles.scolarite {
            let document = dossier.document(pour: "ATTESTATION_SCOLARITE")
            cartes.append(CarteComplementaire(typeDocument: "ATTESTATION_SCOLARITE", titre: L.titreScolarite,
                                              description: TextesWeb.Justificatifs.accesScolarite,
                                              statut: libelleStatut(document), bouton: document == nil ? L.plusTeleverser : L.remplacer))
        }
        if visibles.licence {
            let document = dossier.document(pour: "LICENCE_REMPLACEMENT")
            cartes.append(CarteComplementaire(typeDocument: "LICENCE_REMPLACEMENT", titre: L.titreLicence,
                                              description: TextesWeb.Justificatifs.accesLicence,
                                              statut: libelleStatut(document), bouton: document == nil ? L.plusTeleverser : L.remplacer))
        }
        if visibles.qualification {
            let document = dossier.document(pour: "CARTE_ORDRE")
            let statut = document.map { ($0.nomFichier ?? "") + " · " + (libelleStatut($0) ?? L.statutAActualiser) }
            cartes.append(CarteComplementaire(typeDocument: "CARTE_ORDRE", titre: L.titreQualification,
                                              description: L.descriptionQualification, statut: statut,
                                              bouton: document == nil ? L.ajouterAttestation : L.remplacerAttestation))
        }
        return cartes
    }

    // MARK: - Attestation, fichier, dates

    /// « ✅ Attestation signée le <d MMMM yyyy> » (l.118) ; valeur serveur illisible : affichée telle quelle, jamais une date
    /// supposée.
    public static func attestationSigneeLe(_ dossier: DossierDocuments) -> String? {
        guard let valeur = dossier.attestationSanteSigneeLe, !valeur.isEmpty else { return nil }
        guard let instant = try? DateHeureParis.instantJolene(valeur) else {
            return TextesWeb.AttestationSante.signeeLe(dateFormatee: valeur)
        }
        return TextesWeb.AttestationSante.signeeLe(dateFormatee: DateHeureParis.format(instant, "d MMMM yyyy"))
    }

    /// « 📎 <nom> » (`ModalTeleversement.tsx` l.194).
    public static func fichierChoisi(nom: String) -> String {
        L.fichierChoisi + " " + nom
    }

    /// `(taille / 1024).toFixed(0) Ko` (l.195).
    public static func taille(octets: Int) -> String {
        String(Int((Double(max(0, octets)) / 1024).rounded(.toNearestOrAwayFromZero))) + " " + L.ko
    }

    /// `format(new Date(valeur), 'd MMM yyyy', { locale: fr })` ; nil sans valeur lisible.
    public static func date(_ valeur: String?) -> String? {
        guard let valeur, !valeur.isEmpty, let instant = try? DateHeureParis.instantJolene(valeur) else { return nil }
        return DateHeureParis.format(instant, "d MMM yyyy")
    }

    static func fichier(_ document: DocumentSoignant) -> String {
        var texte = L.fichierChoisi
        if let nom = document.nomFichier, !nom.isEmpty { texte += " " + nom }
        if let le = date(document.televerseLe) { texte += " " + L.televerseLe + " " + le + ")" }
        return texte
    }

    // MARK: - Issues

    /// Message d'un état d'envoi (consignes T7 de `docs/mobile-swift/DECISIONS_LOT2.md`) ; nil sans message (inactif, envoi
    /// en vol, verdict déjà rendu : le badge suffit).
    public static func messageEnvoi(_ etat: DocumentsModel.EtatEnvoi) -> TexteJustificatif? {
        switch etat {
        case .inactif, .enCours:
            return nil
        case let .termine(issue):
            switch issue {
            case .verificationDemandee: return TexteJustificatif(texte: L.verificationDemandee, ton: .succes)
            case .enregistre: return TexteJustificatif(texte: L.verificationManuelle, ton: .info)
            case .verdictRendu: return nil
            case let .refuse(code): return TexteJustificatif(texte: messageRefus(code: code), ton: .erreur)
            case .incertain: return TexteJustificatif(texte: L.envoiAVerifier, ton: .attention)
            case .nonEnvoye: return TexteJustificatif(texte: L.envoiNonRecu, ton: .attention)
            }
        case let .refuseAvantEnvoi(message):
            return TexteJustificatif(texte: message, ton: .erreur)
        case .recuEnCours:
            return TexteJustificatif(texte: L.envoiPrecedentAVerifier, ton: .attention)
        case .suiviIllisible:
            return TexteJustificatif(texte: L.suiviIllisible, ton: .erreur)
        case let .erreur(message):
            return TexteJustificatif(texte: message, ton: .erreur)
        }
    }

    /// Issue annoncée en tête de l'écran : celle de `messageEnvoi`, sauf « vérification en cours » une fois le verdict relu
    /// (la pièce a quitté le suivi en ligne : son badge porte le verdict, comme le toast du web qui disparaît).
    public static func issueAffichee(_ etat: DocumentsModel.EtatEnvoi, enVerification: Set<String>) -> TexteJustificatif? {
        if case let .termine(.verificationDemandee(documentId)) = etat, !enVerification.contains(documentId) { return nil }
        return messageEnvoi(etat)
    }

    /// La feuille de téléversement se ferme quand le document est enregistré ou en cours de vérification (web : la modale
    /// se ferme après l'enregistrement, l.429) ; elle reste ouverte sur un refus, pour une nouvelle sélection.
    public static func fermeLeTeleversement(_ etat: DocumentsModel.EtatEnvoi) -> Bool {
        switch etat {
        case .termine(.verificationDemandee), .termine(.enregistre), .termine(.verdictRendu), .termine(.incertain): return true
        default: return false
        }
    }

    /// Refus d'enregistrement (l.399-404) : chemin ou métadonnées → message du web ; Storage → « Téléversement impossible : »
    /// et le repli de `extraireMessageErreur` (le natif ne transporte pas le message brut de Storage) ; tout autre code (dont
    /// le trigger des pièces de santé) → repli générique, jamais un texte serveur non relu.
    public static func messageRefus(code: String) -> String {
        if code == "CHEMIN_DOCUMENT_INVALIDE" || code == "METADONNEES_DOCUMENT_INVALIDES" {
            return MessagesDocuments.enregistrementImpossible
        }
        if code.hasPrefix("STOCKAGE_") { return L.televersementImpossible + " " + MessagesDocuments.erreurGenerique }
        return MessagesDocuments.erreurGenerique
    }

    /// Toasts de la revérification (l.317-325) ; motif : celui de la pièce relue (le web lit celui de l'analyse).
    public static func messageReverification(_ verdict: VerdictDocument, motif: String?) -> TexteJustificatif {
        switch verdict {
        case .verifie:
            return TexteJustificatif(texte: L.reverificationVerifie, ton: .succes)
        case .rejete:
            let raison = motif.flatMap { $0.isEmpty ? nil : $0 } ?? L.reverificationNonConforme
            return TexteJustificatif(texte: L.reverificationRejete + " " + raison, ton: .erreur)
        case .revueManuelleRequise:
            return TexteJustificatif(texte: L.reverificationRevue, ton: .info)
        case .enAttente:
            return TexteJustificatif(texte: L.reverificationAttente, ton: .info)
        }
    }
}
