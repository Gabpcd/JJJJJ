import Foundation
import ImageIO
import CoreGraphics

/// Photo de profil (lot 3, T10 ; blueprint `LOT3_PLAN.md` §3 T10, D14) : règles portées de
/// `src/components/AvatarUpload.tsx` (l.33-61, l.116-170). Écart assumé (D14, v2) : JPEG au lieu du WebP du web
/// (MIME autorisé par le bucket, migration `20260713222000` l.1342 ; encodage WebP non garanti par ImageIO en iOS 16),
/// sans effet sur la lecture par l'URL signée.
public enum AvatarProfil {
    /// Bucket privé des documents (`AvatarUpload.tsx` l.139).
    public static let bucket = "jolene-documents"
    public static let contentType = "image/jpeg"
    /// `const MAX = 256` (l.39) : plus grand côté, sans agrandissement.
    public static let dimensionMax = 256
    /// `canvas.toBlob(…, 'image/webp', 0.8)` (l.49-53).
    public static let qualiteJPEG = 0.8
    /// `maxBytes: 2 * 1024 * 1024` (l.123). Corrigé v2 : appliqué au JPEG ENVOYÉ, pas au fichier d'origine (une photo
    /// HEIC d'iPhone dépasse souvent 2 Mo ; la réduction se fait sans décoder l'original en pleine taille).
    public static let tailleMaxOctets = 2 * 1024 * 1024
    /// `createSignedUrl(path, 5 * 365 * 24 * 60 * 60)` (l.148) : 5 ans, l'URL est lue par les listes et la messagerie.
    public static let dureeURLSigneeSecondes = 5 * 365 * 24 * 60 * 60

    /// Étapes réseau d'un changement de photo, au plus (revue B8 de T10, m7) : relecture d'un reçu interrompu soldé
    /// d'abord, dépôt du JPEG (≤ 2 Mo), URL signée, `fn_modifier_mon_profil`, relecture `fn_mon_profil_soignant_complet`.
    /// Les écritures du reçu sont locales (trousseau).
    public static let etapesReseauEnvoi = 5

    /// Budget PROPRE à l'envoi (revue B8 de T10, m7) : une étape réseau = un délai de résolution
    /// (`SessionController.resolutionTimeout`, 15 s en production), soit 75 s pour toute la chaîne. Un seul délai de
    /// 15 s annulait sur réseau lent un envoi peut-être lié côté serveur ; la borne demeure (jamais d'attente infinie)
    /// et une issue inconnue reste relue avant toute annonce. Le web n'a pas de délai sur cet envoi.
    public static func delaiEnvoi(resolution: TimeInterval) -> TimeInterval {
        resolution * Double(etapesReseauEnvoi)
    }

    /// `${user.id}/avatar-${Date.now()}.jpg` (l.135-136, extension `.jpg` au lieu de `.webp`, D14). Le premier segment
    /// est l'identifiant de l'utilisateur : la politique `pol_storage_jolene_insert` (`fn_peut_gerer_objet_jolene`)
    /// n'autorise que ce dossier.
    public static func chemin(userId: String, instant: Date) -> String {
        let millisecondes = Int64((instant.timeIntervalSince1970 * 1000).rounded(.down))
        return "\(userId)/avatar-\(millisecondes).jpg"
    }

    /// Vrai si `avatarUrl` (URL signée relue dans `soignants.avatar_url`) désigne l'objet `chemin` du bucket : le
    /// chemin d'une URL signée Supabase est `/storage/v1/object/sign/<bucket>/<chemin>`. Comparaison sur le chemin
    /// décodé de l'URL, jamais sur le jeton (qui n'est ni lu ni journalisé).
    public static func urlDesigne(_ avatarUrl: String?, chemin: String) -> Bool {
        guard let avatarUrl, let url = URL(string: avatarUrl), !chemin.isEmpty else { return false }
        return url.path.hasSuffix("/\(bucket)/\(chemin)")
    }

    /// Textes affichés. Verbatim web (source en commentaire, garde `AvatarLocalisationVerbatimTests`).
    public enum Textes {
        /// `aria-label` du bouton (`AvatarUpload.tsx` l.179), aussi `AvatarView.changePhotoLabel` (L3-T1b).
        public static let changerPhoto = "Changer ma photo de profil"
        /// Toast de succès (l.164).
        public static let succes = "Photo mise à jour !"
        /// Toast d'échec (l.166) : tout envoi refusé, interrompu ou non confirmé.
        public static let echecEnvoi = "Une erreur est survenue lors de l'upload. Veuillez réessayer."
        /// `verifierFichierDocument` (`src/lib/documentUpload.ts`) : l.135, l.139 (`maxMo` = 2), l.174.
        public static let fichierVide = "Le fichier sélectionné est vide."
        public static let fichierTropLourd = "Le fichier ne doit pas dépasser 2 Mo."
        public static let fichierIllisible = "Impossible de lire le fichier sélectionné."
        /// Sans équivalent web (le web n'a qu'un sélecteur de fichier ; non juridiques, à relire par Gabrielle,
        /// `DECISIONS_LOT3.md` section T10) : choix de la source de la photo.
        public static let choisirPhototheque = "Choisir dans la photothèque"
        public static let prendrePhoto = "Prendre une photo"
        /// Bouton d'annulation des feuilles natives, repris tel quel (`ConfirmationSheet`, L1-T1b).
        public static let annuler = "Annuler"
    }
}

/// Issue d'un sélecteur de photo (photothèque `PHPickerViewController`, appareil photo `UIImagePickerController`), rendue
/// par la cible app à `AvatarProfilModel.recevoir` (revue B8 de T10, M1) : une ANNULATION n'est jamais confondue avec un
/// fichier choisi mais ILLISIBLE.
public enum SelectionPhotoAvatar: Equatable, Sendable {
    /// Aucun résultat (feuille fermée sans choix, « Annuler » de l'appareil photo) : ni message ni envoi.
    case annulee
    /// Une photo est choisie et ses octets sont en cours de lecture (photo iCloud à télécharger…) : la feuille se
    /// ferme et l'écran montre un indicateur jusqu'à `octets` ou `illisible`.
    case lectureEnCours
    /// Octets d'origine lus (HEIC d'iPhone compris), convertis puis envoyés.
    case octets(Data)
    /// Une photo était choisie mais ses octets n'ont pas pu être lus (photo iCloud indisponible hors ligne,
    /// représentation illisible, prise de vue non encodable) : « Impossible de lire le fichier sélectionné. » (web
    /// `documentUpload.ts` l.174), rien n'est envoyé.
    case illisible
}

/// Description sans les octets de l'image (jamais journalisés) : leur nombre seul.
extension SelectionPhotoAvatar: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .annulee: return "SelectionPhotoAvatar.annulee"
        case .lectureEnCours: return "SelectionPhotoAvatar.lectureEnCours"
        case let .octets(donnees): return "SelectionPhotoAvatar.octets(\(donnees.count) octets)"
        case .illisible: return "SelectionPhotoAvatar.illisible"
        }
    }

    public var debugDescription: String { description }
}

/// Refus CERTAIN d'un changement de photo : rien n'a été lié au profil (fichier refusé avant l'envoi, stockage ou
/// `fn_modifier_mon_profil` en refus, reçu impossible à écrire). Le message est affiché tel quel, sans relecture.
public struct RefusAvatar: Error, Equatable, Sendable, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Issue de la réconciliation d'un reçu d'avatar laissé par un envoi interrompu (arrêt de l'app, coupure) : relecture
/// de `avatar_url`, jamais de second envoi automatique (PRINCIPES §4).
public enum ReconciliationAvatar: Equatable, Sendable {
    /// Aucun reçu en attente (ou reçu d'un envoi encore en cours dans ce processus).
    case aucune
    /// L'envoi interrompu a bien été lié au profil : URL relue.
    case confirmee(URL)
    /// L'envoi interrompu n'est pas lié au profil : la photo n'a pas changé, l'utilisateur peut recommencer.
    case nonConfirmee
}

/// Conversion d'une photo choisie (HEIC, JPEG, PNG… : tout format lu par ImageIO) en JPEG de profil : plus grand côté
/// réduit à 256 px sans agrandissement, orientation EXIF appliquée, qualité 0,8, fond blanc sous la transparence, AUCUNE
/// métadonnée recopiée (ni position GPS, ni appareil, ni date de prise de vue). Réduction par
/// `CGImageSourceCreateThumbnailAtIndex` : l'original n'est jamais décodé en pleine taille. Systématique, même pour un
/// JPEG (CLAUDE.md : le HEIC n'est pas un format d'échange accepté partout ; ici, il n'est jamais envoyé).
public enum ConversionAvatar {
    public enum Erreur: Error, Equatable, Sendable {
        case vide
        case illisible
        case tropLourd
    }

    /// Message web de l'erreur (`AvatarProfil.Textes`).
    public static func message(_ erreur: Erreur) -> String {
        switch erreur {
        case .vide: return AvatarProfil.Textes.fichierVide
        case .illisible: return AvatarProfil.Textes.fichierIllisible
        case .tropLourd: return AvatarProfil.Textes.fichierTropLourd
        }
    }

    public static func jpeg(depuis source: Data, dimensionMax: Int = AvatarProfil.dimensionMax,
                            qualite: Double = AvatarProfil.qualiteJPEG,
                            tailleMax: Int = AvatarProfil.tailleMaxOctets) throws -> Data {
        guard !source.isEmpty else { throw Erreur.vide }
        guard let image = CGImageSourceCreateWithData(source as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(image) > 0 else { throw Erreur.illisible }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: dimensionMax,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let reduite = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary),
              let opaque = surFondBlanc(reduite) else { throw Erreur.illisible }
        let sortie = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(sortie, "public.jpeg" as CFString, 1, nil) else {
            throw Erreur.illisible
        }
        CGImageDestinationAddImage(destination, opaque, [kCGImageDestinationLossyCompressionQuality: qualite] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Erreur.illisible }
        let jpeg = sortie as Data
        guard !jpeg.isEmpty else { throw Erreur.illisible }
        guard jpeg.count <= tailleMax else { throw Erreur.tropLourd }
        return jpeg
    }

    /// Image opaque sRGB (le JPEG n'a pas de canal alpha : une zone transparente serait noire sans ce fond).
    private static func surFondBlanc(_ image: CGImage) -> CGImage? {
        guard let espace = CGColorSpace(name: CGColorSpace.sRGB),
              let contexte = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: espace,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let cadre = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        contexte.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        contexte.fill(cadre)
        contexte.draw(image, in: cadre)
        return contexte.makeImage()
    }
}
