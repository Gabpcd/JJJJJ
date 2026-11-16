import Foundation

/// Présentation des contrats (lot 2, T9a ; `docs/mobile-swift/LOT2_PLAN.md` §3 T9a) : ce que les écrans
/// `ContratsListeView`, `ContratScreen` et `CertificatView` affichent, assemblé ici depuis les règles de
/// `ContratRules` et les textes verbatim de `TextesWeb` (HARD STOP n°4) et `LibellesWeb`. Aucun texte ni aucune
/// règle n'est écrit à l'écran ; aucune date n'est inventée (date illisible → valeur absente ou tiret, là où le web
/// lèverait une erreur de `format`). Les instants serveur sont affichés en heure de Paris (`DateHeureParis`), avec
/// les masques date-fns du web.
public enum ContratPresentation {
    // MARK: - Dates

    /// Instant serveur formaté en heure de Paris selon un masque date-fns du web ; `nil` si absent ou illisible.
    public static func date(_ iso: String?, masque: String) -> String? {
        guard let iso, !iso.isEmpty, let instant = try? DateHeureParis.instantJolene(iso) else { return nil }
        return DateHeureParis.format(instant, masque)
    }

    // MARK: - Liste

    /// Carte d'un contrat (`renduCarte`, `ListeContrats.tsx` l.205-226).
    public struct Carte: Equatable, Sendable, Identifiable {
        public var id: String
        public var numero: String
        public var statut: StatutContratAffiche
        public var badge: String
        public var mission: String
        public var typeEtDate: String
        public var action: String
        public var aSigner: Bool
    }

    public static func carte(_ contrat: ContratResume) -> Carte {
        let statut = ContratRules.statutAffiche(statut: contrat.statut)
        let aSigner = ContratRules.aSignerParMoi(contrat)
        let creation = date(contrat.creeLe, masque: LibellesWeb.Contrats.formatDateCreation) ?? LibellesWeb.Contrats.sansValeur
        return Carte(id: contrat.id, numero: LibellesWeb.Contrats.numero(contrat.numeroContrat), statut: statut,
                     badge: LibellesWeb.Contrats.badge(statut),
                     mission: LibellesWeb.Contrats.mission(intitule: contrat.mission?.intitule),
                     typeEtDate: LibellesWeb.Contrats.typeEtDate(type: contrat.typeContrat, dateFormatee: creation),
                     action: LibellesWeb.Contrats.action(aSigner: aSigner), aSigner: aSigner)
    }

    // MARK: - Contrat

    /// Texte du cadre de lecture quand l'original n'est pas affiché (`ContratMission.tsx` l.634-638) : document signé
    /// d'origine indisponible pour un contrat porteur d'une signature (aucune reconstitution), sinon contenu pas
    /// encore disponible. `nil` : l'original contrôlé est affiché par le lecteur.
    public static func messageContenu(motif: MotifOriginalIndisponible?, contrat: ContratDetail) -> String? {
        guard motif != nil else { return nil }
        return ContratMissionUi.contratPossedeSignature(contrat.preuve) ? TextesWeb.Contrat.originalIndisponible
            : TextesWeb.Contrat.contenuPasDisponible
    }

    /// Préparation du document final, affichée dans la zone « Votre signature » comme le web (l.713-717) : rendu
    /// serveur refusé (l.377, motif serveur verbatim) ou document encore incomplet après le rendu (l.388). Les autres
    /// motifs n'ont pas de message sur le web (bouton de signature seulement désactivé).
    public static func messagePreparation(motif: MotifOriginalIndisponible?) -> String? {
        switch motif {
        case .renduRefuse(let messageServeur): return LibellesWeb.Contrat.renduRefuse(messageServeur: messageServeur)
        case .variablesNonRendues: return LibellesWeb.Contrat.renduIncomplet
        default: return nil
        }
    }

    /// « Document officiel figé le <date> — empreinte <8>…<4> » (l.620-625), quand `contenu_html_rendu_le` est
    /// lisible ; `nil` sinon.
    public static func documentFige(_ contrat: ContratDetail) -> String? {
        guard let figeLe = date(contrat.contenuHtmlRenduLe, masque: LibellesWeb.Contrat.formatDateHeure) else { return nil }
        return TextesWeb.Contrat.documentOfficielFige(dateFormatee: figeLe, empreinte: contrat.hashDocument)
    }

    /// Ligne de la section Signatures (l.669-705).
    public struct LigneSignature: Equatable, Sendable {
        public var partie: LibellesWeb.Contrat.Partie
        public var signee: Bool
        public var texte: String
    }

    /// Établissement puis soignant(e), signés dès que le contrat est complet ou que leur drapeau est vrai (l.672,
    /// l.691), avec la date de signature quand elle est lisible.
    public static func lignesSignatures(_ contrat: ContratDetail) -> [LigneSignature] {
        let etablissement = ContratRules.signatureEtablissementAffichee(contrat)
        let soignant = ContratRules.signatureSoignantAffichee(contrat)
        let masque = LibellesWeb.Contrat.formatDateHeure
        return [
            LigneSignature(partie: .etablissement, signee: etablissement,
                           texte: LibellesWeb.Contrat.ligneSignature(.etablissement, signee: etablissement,
                                                                     dateFormatee: date(contrat.signatureEtablissementLe, masque: masque))),
            LigneSignature(partie: .soignant, signee: soignant,
                           texte: LibellesWeb.Contrat.ligneSignature(.soignant, signee: soignant,
                                                                     dateFormatee: date(contrat.signatureSoignantLe, masque: masque))),
        ]
    }

    // MARK: - Certificat

    /// Ligne « libellé / valeur » d'un signataire du certificat (`CertificatSignature.tsx` l.125-166).
    public struct LigneCertificat: Equatable, Sendable {
        public var libelle: String
        public var valeur: String

        public init(libelle: String, valeur: String) {
            self.libelle = libelle; self.valeur = valeur
        }
    }

    /// Signataire du certificat, variante « résumé » du soignant (l.110-167) : rôle, statut, date, OTP, RPPS, PSC.
    /// L'adresse IP, le navigateur et l'empreinte par signature ne relèvent que de la variante « détail » (admin).
    public struct Signataire: Equatable, Sendable, Identifiable {
        public var id: String
        public var role: String
        public var statut: String
        public var signe: Bool
        public var lignes: [LigneCertificat]
    }

    public static func signataires(_ lignes: [SignatureCertificat]) -> [Signataire] {
        lignes.map { ligne in
            let signe = ligne.statutSignature == "signe"
            var details: [LigneCertificat] = []
            if let quand = date(ligne.signeA, masque: LibellesWeb.Certificat.formatDateHeure) {
                details.append(LigneCertificat(libelle: TextesWeb.Certificat.dateHeure, valeur: quand))
            }
            if !(ligne.otpValideA ?? "").isEmpty {
                details.append(LigneCertificat(libelle: TextesWeb.Certificat.otpValide, valeur: TextesWeb.Certificat.codeSmsVerifie))
            }
            details.append(LigneCertificat(libelle: TextesWeb.Certificat.rppsVerifie,
                                           valeur: TextesWeb.Certificat.rpps(verifie: ligne.rppsVerifie == true)))
            details.append(LigneCertificat(libelle: TextesWeb.Certificat.pscActif,
                                           valeur: TextesWeb.Certificat.psc(actif: ligne.pscSessionActive == true)))
            return Signataire(id: ligne.id, role: roleAffiche(ligne.signataireRole),
                              statut: TextesWeb.Certificat.statut(estSigne: signe, codeBrut: ligne.statutSignature ?? ""),
                              signe: signe, lignes: details)
        }
    }

    /// Rôle du signataire tel que le web l'affiche (`capitalize` du CSS, l.113) : première lettre de chaque mot en
    /// majuscule, le reste inchangé.
    public static func roleAffiche(_ role: String?) -> String {
        guard let role, !role.isEmpty else { return "" }
        return role.split(separator: " ", omittingEmptySubsequences: false)
            .map { mot in mot.isEmpty ? "" : mot.prefix(1).uppercased() + mot.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: - Renvois web

    /// Page web du contrat, où se signe le contrat tant que T9b n'est pas mergée (décision 18). Toujours un renvoi
    /// Safari, même quand `/contrat/:id` deviendra natif (T10) ; `nil` pour un identifiant hors `[A-Za-z0-9-]`.
    public static func renvoiSignature(contratId: String) -> JoleneRoute? {
        renvoi("/contrat/" + contratId, contratId: contratId)
    }

    /// Page web du certificat, pour son export PDF (jsPDF, non porté : `LOT2_PLAN.md` §1.2).
    public static func renvoiCertificat(contratId: String) -> JoleneRoute? {
        renvoi("/contrat/" + contratId + "/certificat", contratId: contratId)
    }

    private static func renvoi(_ chemin: String, contratId: String) -> JoleneRoute? {
        guard !contratId.isEmpty, contratId.unicodeScalars.allSatisfy({
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
        }), let url = JoleneLink.canonicalURL(link: chemin) else { return nil }
        return .safari(url)
    }
}
