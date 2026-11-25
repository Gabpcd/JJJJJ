import Foundation

/// Filtres de la liste des contrats (`FILTRES_STATUT`, `ListeContrats.tsx` l.20). Le libellé affiché relève de
/// l'écran (T9a) ; la valeur brute est celle du paramètre `?statut=` du web.
public enum FiltreContrat: String, CaseIterable, Sendable {
    case tous = "Tous"
    case enAttenteSignatures = "EN_ATTENTE_SIGNATURES"
    case signeComplet = "SIGNE_COMPLET"
    case annule = "ANNULE"

    /// Filtre initial depuis `?statut=` (l.55-56, l.85-91) : une valeur de la liste, sinon « Tous ».
    public static func initial(statut: String?) -> FiltreContrat {
        guard let statut, let filtre = FiltreContrat(rawValue: statut) else { return .tous }
        return filtre
    }
}

/// Bandeau de statut du contrat (`ContratMission.tsx` l.552-576), texte dans `TextesWeb.Contrat`.
public enum BandeauContrat: Equatable, Sendable {
    case annule, expire, refuse, autrePartieASigne
}

/// Statut affiché dans l'en-tête (l.593-596) : le web n'en distingue que trois.
public enum StatutContratAffiche: Equatable, Sendable {
    case signe, annule, enAttente
}

/// Règles d'affichage des contrats côté soignant, portées du web ligne à ligne (aucune règle juridique : le
/// serveur fait foi pour toute signature, ces règles ne font qu'annoncer). L'utilisateur de l'app est toujours
/// le soignant du contrat (`soignant_id` vérifié par la gateway) : « déjà signé par moi » = `signature_soignant`.
public enum ContratRules {
    /// Statuts terminaux exclus du rendu, du compte à rebours et de la préparation (`ContratMission.tsx` l.65,
    /// l.362). `REFUSE` est absent du CHECK serveur (`contrats_mission_statut_check`) mais testé par le web.
    public static let statutsTerminaux: Set<String> = ["ANNULE", "EXPIRE", "REFUSE"]

    /// Identifiant de contrat au format UUID (casse indifférente) : sinon aucune requête n'est faite.
    public static func identifiantValide(_ id: String) -> Bool { AdmissionRecette.estUUID(id) }

    // MARK: - Liste

    /// `contratCorrespondAuFiltre` (`ListeContrats.tsx` l.22-27).
    public static func correspondAuFiltre(statut: String, filtre: FiltreContrat) -> Bool {
        switch filtre {
        case .tous: return true
        case .enAttenteSignatures:
            return statut != "SIGNE_COMPLET" && statut != "ANNULE" && statut != "EXPIRE" && statut != "REFUSE"
        case .signeComplet, .annule: return statut == filtre.rawValue
        }
    }

    /// Cartes affichées pour un filtre, dans l'ordre serveur (`cree_le` décroissant, l.71).
    public static func filtrer(_ contrats: [ContratResume], filtre: FiltreContrat) -> [ContratResume] {
        contrats.filter { correspondAuFiltre(statut: $0.statut, filtre: filtre) }
    }

    // MARK: - Contrat

    /// `cddSansOriginal` (l.62-66) : CDD sans preuve de signature ni original, hors statuts terminaux. Le contrat
    /// attend l'employeur (décision 19) : aucune action soignant, aucun rendu demandé.
    public static func cddSansOriginal(_ contrat: ContratDetail) -> Bool {
        contrat.typeContrat == "CDD" && !ContratMissionUi.contratPossedeSignature(contrat.preuve)
            && vide(contrat.storagePath) && vide(contrat.hashDocument) && vide(contrat.contenuHtmlRenduLe)
            && !statutsTerminaux.contains(contrat.statut)
    }

    /// `dejaSigneParMoi` du soignant (l.533 : `contrat.signature_soignant`).
    public static func dejaSigneParMoi(_ contrat: ContratDetail) -> Bool {
        dejaSigneParMoi(contrat, partie: .soignant)
    }

    // MARK: - DPAE côté employeur (revue B8 des textes de la vague D, M6)

    /// Statuts sans DPAE (`!['ANNULE', 'EXPIRE', 'REFUSE'].includes(contrat.statut)`, `ContratMission.tsx` l.645 et l.827).
    public static let statutsSansDPAE: Set<String> = ["ANNULE", "EXPIRE", "REFUSE"]

    /// Statut DPAE affiché (l.644-655) : espace de l'établissement, contrat salarié (`estContratSalarie`, liste
    /// `TextesWeb.Contrat.typesMentionSalariee`) ni annulé, ni expiré, ni refusé.
    public static func dpaeConcernee(_ contrat: ContratDetail, partie: PartieContrat) -> Bool {
        partie == .etablissement && !statutsSansDPAE.contains(contrat.statut)
            && TextesWeb.Contrat.typesMentionSalariee.contains(contrat.typeContrat ?? "")
    }

    /// `saved` de `DPAEStatus` (l.34, `!!dpaeNumero`) : numéro DPAE enregistré.
    public static func dpaeNumeroEnregistre(_ contrat: ContratDetail) -> String? {
        guard let numero = contrat.dpaeNumero, !numero.isEmpty else { return nil }
        return numero
    }

    /// Rappel DPAE (l.826-829) : sous « Vous avez déjà signé ce contrat », côté établissement.
    public static func rappelDPAEVisible(_ contrat: ContratDetail, partie: PartieContrat) -> Bool {
        dpaeConcernee(contrat, partie: partie) && dejaSigneParMoi(contrat, partie: partie)
    }

    /// Titre du rappel « effectuée » (`BandeauRappelDPAE.tsx` l.25) : la date `d MMMM yyyy` suit quand elle est servie.
    public static func dpaeEffectueeTitre(_ contrat: ContratDetail) -> String {
        guard let iso = contrat.dpaeEffectueeLe, !iso.isEmpty, let instant = try? DateHeureParis.instantJolene(iso) else {
            return TextesWeb.DPAE.effectuee
        }
        return TextesWeb.DPAE.effectueeLe(dateFormatee: DateHeureParis.format(instant, "d MMMM yyyy"))
    }

    /// `dejaSigneParMoi` de la partie qui regarde (l.533-534 : `isSoignant ? signature_soignant :
    /// signature_etablissement` ; lot 5, T10).
    public static func dejaSigneParMoi(_ contrat: ContratDetail, partie: PartieContrat) -> Bool {
        switch partie {
        case .soignant: return contrat.signatureSoignant == true
        case .etablissement: return contrat.signatureEtablissement == true
        }
    }

    /// Bandeaux (l.552-576) : statut annulé, expiré, refusé ; « L'autre partie a déjà signé » quand une seule
    /// partie, pas moi, a signé un contrat encore ouvert.
    public static func bandeaux(_ contrat: ContratDetail) -> [BandeauContrat] {
        bandeaux(contrat, partie: .soignant)
    }

    /// Bandeaux pour la partie qui regarde (lot 5, T10 : mêmes conditions, `dejaSigneParMoi` de cette partie).
    public static func bandeaux(_ contrat: ContratDetail, partie: PartieContrat) -> [BandeauContrat] {
        var bandeaux: [BandeauContrat] = []
        switch contrat.statut {
        case "ANNULE": bandeaux.append(.annule)
        case "EXPIRE": bandeaux.append(.expire)
        case "REFUSE": bandeaux.append(.refuse)
        default: break
        }
        if !dejaSigneParMoi(contrat, partie: partie), contrat.signatureSoignant == true || contrat.signatureEtablissement == true,
           contrat.statut != "SIGNE_COMPLET", !statutsTerminaux.contains(contrat.statut) {
            bandeaux.append(.autrePartieASigne)
        }
        return bandeaux
    }

    /// Compte à rebours 72 h affiché (l.578-582) : contrat ni signé ni terminal, `cree_le` renseigné.
    public static func afficheCompteARebours(_ contrat: ContratDetail) -> Bool {
        contrat.statut != "SIGNE_COMPLET" && !statutsTerminaux.contains(contrat.statut) && !vide(contrat.creeLe)
    }

    /// Statut de l'en-tête (l.593-596).
    public static func statutAffiche(_ contrat: ContratDetail) -> StatutContratAffiche {
        statutAffiche(statut: contrat.statut)
    }

    /// Statut affiché depuis le code serveur : même correspondance pour l'en-tête du contrat (l.593-596) et la
    /// pastille de la liste (`ListeContrats.tsx` l.162-163, T9a).
    public static func statutAffiche(statut: String) -> StatutContratAffiche {
        switch statut {
        case "SIGNE_COMPLET": return .signe
        case "ANNULE": return .annule
        default: return .enAttente
        }
    }

    /// Appel à signer d'une carte de la liste (`aSigner`, `ListeContrats.tsx` l.156-159, branche soignant) : contrat
    /// non annulé que le soignant n'a pas signé. N'annonce qu'une action ; le serveur décide de toute signature.
    public static func aSignerParMoi(_ contrat: ContratResume) -> Bool {
        aSignerParMoi(contrat, partie: .soignant)
    }

    /// `aSigner` (l.156-159) pour la partie qui regarde : contrat non annulé que cette partie n'a pas signé (lot 5,
    /// T10 ; branche `ADMIN_ETABLISSEMENT` : `!c.signature_etablissement`).
    public static func aSignerParMoi(_ contrat: ContratResume, partie: PartieContrat) -> Bool {
        guard contrat.statut != "ANNULE" else { return false }
        switch partie {
        case .soignant: return contrat.signatureSoignant != true
        case .etablissement: return contrat.signatureEtablissement != true
        }
    }

    /// `texteEmployeur` (l.535-537) : CDD dont l'original porte le cadre « texte de l'employeur ».
    public static func texteEmployeur(_ contrat: ContratDetail) -> Bool {
        let html = contrat.contenuHtml ?? ""
        return contrat.typeContrat == "CDD" && contientAttribut("data-jolene-cdd", valeur: "employeur-v1", dans: html)
            && contientAttribut("data-cadre", valeur: "TEXTE_EMPLOYEUR", dans: html)
    }

    /// Mention du pied de page (l.834-837), texte dans `TextesWeb.Contrat.piedDePage(_:)` : la liste des types salariés
    /// est `TextesWeb.Contrat.typesMentionSalariee` (`TYPES_CONTRAT_SALARIES` / `estContratSalarie` de `src/lib/typesContrat.ts` depuis #1123, #1122 : CDD, SALARIE, CDDU,
    /// VACATION), gardée type par type contre le web par la garde TL ; aucune liste locale.
    public static func mentionPiedDePage(_ contrat: ContratDetail) -> TextesWeb.Contrat.MentionPiedDePage {
        if texteEmployeur(contrat) { return .cadreEmployeur }
        return TextesWeb.Contrat.typesMentionSalariee.contains(contrat.typeContrat ?? "") ? .salarieEcrit : .prestationLiberale
    }

    /// Certificat des signatures affiché (l.656) : une des deux parties a signé.
    public static func certificatVisible(_ contrat: ContratDetail) -> Bool {
        contrat.signatureSoignant == true || contrat.signatureEtablissement == true
    }

    /// Ligne « Établissement : ✅ Signé » de la section Signatures (l.672).
    public static func signatureEtablissementAffichee(_ contrat: ContratDetail) -> Bool {
        contrat.statut == "SIGNE_COMPLET" || contrat.signatureEtablissement == true
    }

    /// Ligne « Soignant(e) : ✅ Signé » (l.691).
    public static func signatureSoignantAffichee(_ contrat: ContratDetail) -> Bool {
        contrat.statut == "SIGNE_COMPLET" || contrat.signatureSoignant == true
    }

    /// Zone « Votre signature » (l.709) : ni CDD à préparer, ni déjà signé par moi, ni signé, annulé ou expiré.
    public static func zoneSignatureVisible(_ contrat: ContratDetail) -> Bool {
        zoneSignatureVisible(contrat, partie: .soignant)
    }

    /// Zone « Votre signature » (l.709) pour la partie qui regarde (lot 5, T10).
    public static func zoneSignatureVisible(_ contrat: ContratDetail, partie: PartieContrat) -> Bool {
        !cddSansOriginal(contrat) && !dejaSigneParMoi(contrat, partie: partie)
            && !["SIGNE_COMPLET", "ANNULE", "EXPIRE"].contains(contrat.statut)
    }

    /// Rendu serveur à demander (l.359-364) : ni CDD à préparer ni statut terminal, et `contratNecessiteRenduServeur`
    /// (aucun original stocké, aucune preuve de signature). Une seule demande, jamais de `donnees_cdd`.
    public static func renduServeurADemander(_ contrat: ContratDetail) -> Bool {
        !cddSansOriginal(contrat) && !statutsTerminaux.contains(contrat.statut)
            && ContratMissionUi.contratNecessiteRenduServeur(storagePath: contrat.storagePath, contrat: contrat.preuve)
    }

    // MARK: - Outils

    private static func vide(_ valeur: String?) -> Bool { (valeur ?? "").isEmpty }

    /// `/<nom>=["']<valeur>["']/` : guillemets simples ou doubles, indépendamment de chaque côté.
    private static func contientAttribut(_ nom: String, valeur: String, dans html: String) -> Bool {
        let guillemets = ["\"", "'"]
        for ouvrant in guillemets {
            for fermant in guillemets where html.contains(nom + "=" + ouvrant + valeur + fermant) {
                return true
            }
        }
        return false
    }
}
