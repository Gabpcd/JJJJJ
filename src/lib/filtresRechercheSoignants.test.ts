import { describe, expect, it } from 'vitest';
import { normaliserFiltresRechercheSoignants } from './filtresRechercheSoignants';

describe('reprise des filtres de l’annuaire', () => {
  it('restaure les valeurs stockées comme nombres ou chaînes et les booléens explicites', () => {
    expect(normaliserFiltresRechercheSoignants({ profession:'IDE', type_exercice:'SALARIE', ville:'Paris', distance_max_km:30, note_min:'4.5', score_min:80, experience_min:'3', disponible_urgence:true, documents_valides:true, recherche_texte:'gériatrie', champ_inconnu:'ignoré' })).toEqual({ profession:'IDE', type_exercice:'SALARIE', ville:'Paris', distance_max_km:'30', note_min:'4.5', score_min:'80', experience_min:'3', disponible_urgence:true, documents_valides:true, recherche_texte:'gériatrie' });
  });
  it('rejette types, professions et nombres invalides sans produire de NaN pour la recherche', () => {
    const vide = normaliserFiltresRechercheSoignants(null);
    expect(normaliserFiltresRechercheSoignants({ profession:'ADMIN',type_exercice:'AUTRE',ville:[],distance_max_km:501,note_min:-1,score_min:'NaN',experience_min:1.5,disponible_urgence:'false',documents_valides:1,recherche_texte:{} })).toEqual(vide);
    expect(normaliserFiltresRechercheSoignants([])).toEqual(vide);
  });
  it('conserve zéro et les limites du formulaire', () => {
    expect(normaliserFiltresRechercheSoignants({ distance_max_km:500,note_min:5,score_min:100,experience_min:0 })).toMatchObject({distance_max_km:'500',note_min:'5',score_min:'100',experience_min:'0'});
  });
});
