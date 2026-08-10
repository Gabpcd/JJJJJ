import { usePageTitle } from '@/hooks/usePageTitle';
import React from 'react';
import LayoutLegal from '@/components/LayoutLegal';

const TOC = [
  { id: 'editeur', label: '1. Éditeur du site' },
  { id: 'hebergeur', label: '2. Hébergement et infrastructure' },
  { id: 'domaine', label: '3. Nom de domaine' },
  { id: 'pi', label: '4. Propriété intellectuelle' },
  { id: 'contact', label: '5. Contact' },
];

export default function PageMentionsLegales() {
  usePageTitle('Mentions Légales');
  return (
    <LayoutLegal
      titre="Mentions Légales"
      dateMaj="10 août 2026"
      toc={TOC}
      seoDescription="Mentions légales de Jolene SAS. Éditeur, hébergeur, propriété intellectuelle et coordonnées de contact."
    >
      {/* Éditeur */}
      <section id="editeur">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">1. Éditeur du site</h2>
        <div className="bg-muted/50 border border-border rounded-xl p-5 space-y-2">
          <p><strong className="text-foreground">Raison sociale :</strong> Jolene</p>
          <p><strong className="text-foreground">Forme juridique :</strong> Société par Actions Simplifiée (SAS) à associé unique</p>
          <p><strong className="text-foreground">Présidente :</strong> Gabrielle Picard</p>
          <p><strong className="text-foreground">Siège social :</strong> 103 rue de Vaugirard, 75006 Paris, France</p>
          <p><strong className="text-foreground">RCS :</strong> 103 305 744 R.C.S. Paris</p>
          <p><strong className="text-foreground">SIREN :</strong> 103 305 744</p>
          <p><strong className="text-foreground">Capital social :</strong> 1 000 €</p>
          <p><strong className="text-foreground">Numéro TVA intracommunautaire :</strong> FR75 01103305744</p>
          <p><strong className="text-foreground">Date d'immatriculation :</strong> 7 avril 2026</p>
          <p><strong className="text-foreground">Directrice de la publication :</strong> Gabrielle Picard</p>
        </div>
      </section>

      {/* Hébergement et infrastructure */}
      <section id="hebergeur">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">2. Hébergement et infrastructure</h2>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="bg-muted/50 border border-border rounded-xl p-5 space-y-2">
            <p className="font-semibold text-foreground">Application web et réseau de diffusion</p>
            <p><strong className="text-foreground">Prestataire :</strong> Vercel Inc.</p>
            <p><strong className="text-foreground">Adresse :</strong> 440 N Barranca Ave #4133, Covina, CA 91723, États-Unis</p>
            <p><strong className="text-foreground">Site web :</strong> <a href="https://vercel.com" target="_blank" rel="noopener noreferrer" className="text-primary underline">vercel.com</a></p>
          </div>
          <div className="bg-muted/50 border border-border rounded-xl p-5 space-y-2">
            <p className="font-semibold text-foreground">Authentification, base de données et stockage</p>
            <p><strong className="text-foreground">Prestataire :</strong> Supabase Pte. Ltd.</p>
            <p><strong className="text-foreground">Adresse :</strong> 65 Chulia Street #38-02/03, OCBC Centre, Singapour 049513</p>
            <p><strong className="text-foreground">Région du projet :</strong> eu-west-3 (Paris, France)</p>
            <p><strong className="text-foreground">Site web :</strong> <a href="https://supabase.com" target="_blank" rel="noopener noreferrer" className="text-primary underline">supabase.com</a></p>
          </div>
        </div>
        <p className="mt-3 text-muted-foreground">Les prestataires, catégories de données, transferts éventuels et garanties applicables sont détaillés dans la politique de confidentialité. Jolene ne demande pas de dossier médical, mais enregistre certaines déclarations de conformité professionnelle liées aux vaccinations et à la médecine du travail avec un accès restreint.</p>
      </section>

      {/* Nom de domaine */}
      <section id="domaine">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">3. Nom de domaine</h2>
        <div className="bg-muted/50 border border-border rounded-xl p-5 space-y-2">
          <p><strong className="text-foreground">Nom de domaine :</strong> jolene.app</p>
          <p><strong className="text-foreground">Registrar :</strong> Squarespace Domains LLC</p>
          <p><strong className="text-foreground">Titulaire :</strong> Jolene SAS</p>
        </div>
      </section>

      {/* Propriété intellectuelle */}
      <section id="pi">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">4. Propriété intellectuelle</h2>
        <p className="mb-3">L'ensemble des contenus présents sur le site jolene.app (textes, graphismes, images, logos, icônes, logiciels, bases de données) est protégé par le droit d'auteur et le droit des marques.</p>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p>La marque « <strong>Jolene</strong> » est déposée auprès de l'Institut National de la Propriété Industrielle (INPI) sous le <strong>numéro 5186614</strong>.</p>
        </div>
        <p>Toute reproduction, représentation, modification, publication, adaptation ou exploitation de tout ou partie des éléments du site, quel que soit le moyen ou le procédé utilisé, est interdite sauf autorisation écrite préalable de Jolene SAS. Toute exploitation non autorisée constitue une contrefaçon au sens des articles L.335-2 et suivants du Code de la propriété intellectuelle.</p>
      </section>

      {/* Contact */}
      <section id="contact">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">5. Contact</h2>
        <div className="bg-muted/50 border border-border rounded-xl p-5 space-y-2">
          <p><strong className="text-foreground">Contact général :</strong> <a href="mailto:support@jolene.app" className="text-primary underline">support@jolene.app</a></p>
          <p><strong className="text-foreground">Délégué à la protection des données (DPO) :</strong> <a href="mailto:support@jolene.app" className="text-primary underline">support@jolene.app</a></p>
        </div>
        <p className="mt-4 text-muted-foreground">Pour toute question relative au fonctionnement de la Plateforme, à la protection de vos données personnelles ou à l'exercice de vos droits, n'hésitez pas à nous contacter aux adresses ci-dessus.</p>
      </section>
    </LayoutLegal>
  );
}
