import React, { useState } from 'react';
import { X } from 'lucide-react';

const SUGGESTIONS_SPECIALITES = [
  'Bloc opératoire', 'Dialyse', 'Pédiatrie', 'Gériatrie', 'Réanimation',
  'Urgences', 'Psychiatrie', 'Oncologie', 'Chirurgie', 'Cardiologie',
  'Néonatologie', 'Soins palliatifs', 'Orthopédie', 'Neurologie', 'Dermatologie',
];

interface SectionBioProps {
  bio: string;
  onBioChange: (val: string) => void;
  anneesExperience: number;
  onAnneesChange: (val: number) => void;
  specialites: string[];
  onSpecialitesChange: (val: string[]) => void;
}

export function SectionBio({ bio, onBioChange, anneesExperience, onAnneesChange, specialites, onSpecialitesChange }: SectionBioProps) {
  const [tagInput, setTagInput] = useState('');

  const ajouterTag = (tag: string) => {
    const t = tag.trim();
    if (!t || specialites.includes(t)) return;
    if (specialites.length >= 10) return;
    onSpecialitesChange([...specialites, t]);
    setTagInput('');
  };

  const retirerTag = (tag: string) => {
    onSpecialitesChange(specialites.filter(s => s !== tag));
  };

  const suggestionsNonSelectionnees = SUGGESTIONS_SPECIALITES.filter(s => !specialites.includes(s));

  return (
    <div className="card-base">
      {!bio && (
        <div className="bg-primary/5 border border-primary/20 rounded-xl p-3 mb-4 text-center">
          <p className="text-sm text-primary font-medium">
            💡 Complétez votre présentation pour multiplier par 3 vos chances d'être sélectionné !
          </p>
        </div>
      )}

      <h2 className="text-base font-semibold text-foreground mb-4">Votre présentation</h2>

      <div className="space-y-4">
        {/* Bio */}
        <div>
          <label htmlFor="profil-bio" className="text-sm font-medium text-foreground mb-1.5 block">Bio</label>
          <textarea
            id="profil-bio"
            value={bio}
            onChange={e => onBioChange(e.target.value.slice(0, 500))}
            placeholder="Présentez-vous aux établissements : votre expérience, vos spécialités, vos préférences..."
            rows={4}
            className="input-base resize-none"
          />
          <p className={`text-[10px] mt-1 text-right ${bio.length >= 450 ? 'text-warning' : 'text-muted-foreground'}`}>
            {bio.length}/500
          </p>
        </div>

        {/* Années d'expérience */}
        <div>
          <label htmlFor="profil-annees-experience" className="text-sm font-medium text-foreground mb-1.5 block">
            Années d'expérience <span className="text-destructive">*</span>
          </label>
          <input
            id="profil-annees-experience"
            type="number"
            min={0}
            max={50}
            required
            value={anneesExperience || ''}
            onChange={e => onAnneesChange(Math.min(50, Math.max(0, parseInt(e.target.value) || 0)))}
            placeholder="Ex: 5"
            className="input-base w-32"
          />
        </div>

        {/* Spécialités */}
        <div>
          <label htmlFor="profil-specialite-libre" className="text-sm font-medium text-foreground mb-1.5 block">
            Spécialités ({specialites.length}/10)
          </label>

          {/* Tags actuels */}
          {specialites.length > 0 && (
            <div className="flex flex-wrap gap-1.5 mb-3">
              {specialites.map(s => (
                <span key={s} className="badge-base bg-primary/10 text-primary text-xs flex items-center gap-1 pr-1">
                  {s}
                  <button type="button" aria-label={`Retirer la spécialité ${s}`} onClick={() => retirerTag(s)} className="hover:text-destructive transition-colors">
                    <X className="h-3 w-3" aria-hidden="true" />
                  </button>
                </span>
              ))}
            </div>
          )}

          {/* Input libre */}
          <div className="flex gap-2">
            <input
              id="profil-specialite-libre"
              value={tagInput}
              onChange={e => setTagInput(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter') { e.preventDefault(); ajouterTag(tagInput); }
              }}
              placeholder="Tapez une spécialité…"
              className="input-base flex-1"
              maxLength={40}
            />
            <button
              type="button"
              onClick={() => ajouterTag(tagInput)}
              disabled={!tagInput.trim() || specialites.length >= 10}
              className="btn-secondary text-xs px-3 disabled:opacity-50"
            >
              Ajouter
            </button>
          </div>

          {/* Suggestions */}
          {suggestionsNonSelectionnees.length > 0 && specialites.length < 10 && (
            <div className="mt-2">
              <p className="text-[10px] text-muted-foreground mb-1">Suggestions :</p>
              <div className="flex flex-wrap gap-1">
                {suggestionsNonSelectionnees.slice(0, 8).map(s => (
                  <button
                    key={s}
                    type="button"
                    onClick={() => ajouterTag(s)}
                    className="text-[10px] px-2 py-0.5 rounded-full border border-border text-muted-foreground hover:bg-primary/5 hover:text-primary hover:border-primary/30 transition-colors"
                  >
                    + {s}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
