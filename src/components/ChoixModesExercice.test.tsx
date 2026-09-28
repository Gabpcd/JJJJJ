import React, { useState } from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { ChoixModesExercice } from './ChoixModesExercice';

function Formulaire({ initial = ['VACATION'], types = ['SALARIE'], indisponible = false, reessayer = vi.fn() }: { initial?:string[];types?:string[]|null;indisponible?:boolean;reessayer?:()=>void }) {
  const [valeur,onChange] = useState(initial);
  return <><ChoixModesExercice valeur={valeur} onChange={onChange} typesAutorises={types} loading={false} indisponible={indisponible} reessayer={reessayer}/><output aria-label="Codes enregistrés">{valeur.join(',')}</output></>;
}

describe('choix de modes d’exercice', () => {
  it('affiche une vacation existante comme salariée même sans éligibilité libérale', () => {
    render(<Formulaire/>);
    expect(screen.getByRole('checkbox',{name:'Salarié (CDD compris)'})).toBeChecked();
    expect(screen.queryByRole('checkbox',{name:'Libéral'})).not.toBeInTheDocument();
    expect(screen.getByLabelText('Codes enregistrés')).toHaveTextContent('VACATION');
  });
  it('autorise les deux modes et conserve les anciennes valeurs lorsqu’on ajoute le libéral', () => {
    render(<Formulaire types={['SALARIE','LIBERAL','MIXTE']}/>);
    fireEvent.click(screen.getByRole('checkbox',{name:'Libéral'}));
    expect(screen.getByLabelText('Codes enregistrés')).toHaveTextContent('VACATION,LIBERAL');
    fireEvent.click(screen.getByRole('checkbox',{name:'Salarié (CDD compris)'}));
    expect(screen.getByLabelText('Codes enregistrés')).toHaveTextContent(/^LIBERAL$/);
  });
  it('propose de réessayer sans perdre les choix ni autoriser un nouvel ajout libéral pendant une panne', () => {
    const reessayer = vi.fn();
    const vue = render(<Formulaire types={null} indisponible reessayer={reessayer}/>);
    expect(screen.queryByRole('checkbox',{name:'Libéral'})).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button',{name:'Réessayer la vérification'}));
    expect(reessayer).toHaveBeenCalledOnce();
    vue.rerender(<Formulaire types={['SALARIE','LIBERAL']} reessayer={reessayer}/>);
    expect(screen.getByRole('checkbox',{name:'Salarié (CDD compris)'})).toBeChecked();
    expect(screen.getByRole('checkbox',{name:'Libéral'})).not.toBeChecked();
    expect(screen.getByLabelText('Codes enregistrés')).toHaveTextContent('VACATION');
  });
});
