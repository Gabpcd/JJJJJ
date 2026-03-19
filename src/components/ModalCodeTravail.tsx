import React, { useState } from 'react';
import { Lock, ChevronDown, ChevronUp, X } from 'lucide-react';
import { obtenirExplicationArticle, extraireCodeArticle, type ArticleLoi } from '@/constantes/loi';
import { extraireMessageErreur } from '@/lib/erreurs';

interface ModalCodeTravailProps {
  erreur: any;
  onFermer: () => void;
}

export function ModalCodeTravail({ erreur, onFermer }: ModalCodeTravailProps) {
  const [detailsOuvert, setDetailsOuvert] = useState(false);
  const message = extraireMessageErreur(erreur);
  const article = obtenirExplicationArticle(erreur?.message || message);
  const codeArticle = extraireCodeArticle(erreur?.message || message);

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={onFermer} />
      <div className="relative bg-card rounded-2xl shadow-2xl max-w-lg w-full p-6 max-h-[90vh] overflow-y-auto">
        <button onClick={onFermer} className="absolute top-4 right-4 text-muted-foreground hover:text-foreground">
          <X className="h-5 w-5" />
        </button>

        <div className="text-center mb-5">
          <Lock className="h-12 w-12 text-destructive mx-auto mb-3" />
          <h2 className="text-xl font-bold text-foreground">Mission bloquée par le Code du Travail</h2>
        </div>

        <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-4 mb-5">
          <p className="text-sm text-destructive font-medium">{message}</p>
        </div>

        {article && (
          <>
            <button
              onClick={() => setDetailsOuvert(!detailsOuvert)}
              className="flex items-center gap-2 text-sm font-medium text-primary hover:underline mb-3"
            >
              ℹ️ En savoir plus
              {detailsOuvert ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
            </button>

            {detailsOuvert && (
              <div className="bg-muted/50 rounded-xl p-4 space-y-3 mb-5">
                <h3 className="font-semibold text-sm text-foreground">
                  Article {article.code} du Code du Travail
                </h3>
                <p className="text-xs text-muted-foreground italic">"{article.texteOfficiel}"</p>
                <div>
                  <p className="text-xs font-semibold text-foreground mb-1">Ce que cela signifie :</p>
                  <p className="text-xs text-muted-foreground">{article.explicationSimple}</p>
                </div>
                <div>
                  <p className="text-xs font-semibold text-foreground mb-1">💡 Conseil :</p>
                  <p className="text-xs text-muted-foreground">{article.conseil}</p>
                </div>
                <div>
                  <p className="text-xs font-semibold text-destructive mb-1">⚠️ Sanction encourue :</p>
                  <p className="text-xs text-muted-foreground">{article.sanction}</p>
                </div>
              </div>
            )}
          </>
        )}

        <div className="flex gap-3 justify-end">
          <button onClick={onFermer} className="btn-primary text-sm px-6 py-2.5">
            Fermer
          </button>
        </div>
      </div>
    </div>
  );
}
