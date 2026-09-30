"""Contrôle local structurel des rôles de cette seule recette (pglast requis).

Le parsing ne remplace pas PostgreSQL : il vérifie que le déplacement des
assertions ACL ne convertit aucun appel métier en appel privilégié.
"""
from pathlib import Path
import subprocess
import unittest
from pglast import parse_plpgsql, parse_sql
from pglast.visitors import Visitor

ROOT = Path(__file__).resolve().parents[2]
PATH = 'tests/security/contrat-service-v11.test.sql'
AVANT = 'fd5be1218b561780f45143405d7dc541a1290471'
RPC = {'fn_preparer_contrat_service_v11', 'fn_signer_contrat_service_v11',
       'fn_signer_contrat_service', 'fn_lire_contrat_service_signe', 'fn_supprimer_mon_compte_etablissement'}


class Appels(Visitor):
    def __init__(self):
        super().__init__()
        self.noms = []

    def visit_FuncCall(self, ancestors, node):
        self.noms.append(tuple(part.sval for part in node.funcname))


def contexte_appels(sql):
    evenements = []

    def parcourir(objet, ligne=0):
        if isinstance(objet, list):
            for enfant in objet:
                parcourir(enfant, ligne)
        elif isinstance(objet, dict):
            ligne = objet.get('lineno', ligne)
            if 'PLpgSQL_stmt_dynexecute' in objet:
                statement = objet['PLpgSQL_stmt_dynexecute']
                query = statement['query']['PLpgSQL_expr']['query']
                roles = {"'RESET ROLE'": 'postgres', "'SET LOCAL ROLE authenticated'": 'authenticated',
                         "'SET LOCAL ROLE anon'": 'anon', "'SET LOCAL ROLE service_role'": 'service_role'}
                if query not in roles:
                    raise AssertionError('Commande dynamique inconnue dans la recette')
                evenements.append((statement['lineno'], 'role', roles[query]))
                return
            if 'PLpgSQL_expr' in objet:
                expr = objet['PLpgSQL_expr']
                query = expr['query']
                if expr.get('parseMode') == 3:
                    query = query.split(':=', 1)[1]
                if not query.lstrip().upper().startswith(('SELECT ', 'INSERT ', 'UPDATE ', 'DELETE ')):
                    query = 'SELECT ' + query
                appels = Appels()
                appels(parse_sql(query))
                evenements.extend((ligne, 'appel', nom) for nom in appels.noms)
                return
            for enfant in objet.values():
                parcourir(enfant, ligne)

    for fonction in parse_plpgsql(sql):
        parcourir(fonction['PLpgSQL_function']['action'])
    role, observations = 'postgres', []
    for ligne, type_evenement, valeur in sorted(evenements, key=lambda e: e[0]):
        if type_evenement == 'role':
            role = valeur
        else:
            observations.append((valeur, role))
    return observations


class RolesRecette(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.apres = contexte_appels((ROOT / PATH).read_text())
        cls.avant = contexte_appels(subprocess.check_output(['git', 'show', f'{AVANT}:{PATH}'], cwd=ROOT, text=True))

    def test_catalogue_sous_postgres_et_temoin_ancien_refuse(self):
        acl = lambda observations: [role for nom, role in observations if nom[-1] in {'has_table_privilege', 'has_function_privilege'}]
        self.assertTrue(acl(self.apres))
        self.assertEqual(set(acl(self.apres)), {'postgres'})
        self.assertEqual(set(acl(self.avant)), {'authenticated'})

    def test_tous_appels_metier_et_roles_inchanges(self):
        metier = lambda observations: [(nom, role) for nom, role in observations if len(nom) == 2 and nom[0] == 'public' and nom[1] in RPC]
        appels = metier(self.apres)
        self.assertEqual(appels, metier(self.avant))
        self.assertGreater(len(appels), 15)
        self.assertEqual({role for _, role in appels}, {'authenticated', 'anon'})
        self.assertEqual([nom for nom, role in appels if role == 'anon'], [('public', 'fn_lire_contrat_service_signe')])


if __name__ == '__main__':
    unittest.main()
