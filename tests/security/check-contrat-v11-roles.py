"""Contrôle local structurel des rôles de cette seule recette (pglast requis).

Le parsing ne remplace pas PostgreSQL : il vérifie que le déplacement des
assertions ACL ne convertit aucun appel métier en appel privilégié.
"""
from pathlib import Path
import subprocess
import unittest
from pglast import ast, parse_plpgsql, parse_sql
from pglast.stream import RawStream
from pglast.visitors import Visitor

ROOT = Path(__file__).resolve().parents[2]
PATH = 'tests/security/contrat-service-v11.test.sql'
AVANT = 'fd5be1218b561780f45143405d7dc541a1290471'
AVANT_CLAIMS = '4009da54f65395e311f2e543eaf6cc822333680f'
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


def contexte_ecritures(sql):
    """Observe rôle SQL ET deux claims séparément, y compris après RESET ROLE.

    Les expressions sont parcourues dans leur ordre lexical ; aucune branche
    métier n'est exécutée. La suite SQL porte les assertions réelles de refus.
    """
    events = []

    def identite(node):
        while isinstance(node, ast.TypeCast):
            node = node.arg
        if isinstance(node, ast.ColumnRef):
            return node.fields[0].sval
        if isinstance(node, ast.A_Const):
            return None  # identité vide ou claims service sans sub
        if isinstance(node, ast.FuncCall) and node.funcname[-1].sval == 'jsonb_build_object':
            for i in range(0, len(node.args), 2):
                if node.args[i].val.sval == 'sub':
                    return identite(node.args[i + 1])
            return None
        raise AssertionError('Expression identité inconnue')

    class Effets(Visitor):
        def __init__(self, line):
            super().__init__()
            self.line = line

        def visit_FuncCall(self, ancestors, node):
            if node.funcname[-1].sval == 'set_config':
                key = node.args[0].val.sval
                if key in {'request.jwt.claim.sub', 'request.jwt.claims'}:
                    events.append((self.line, key, identite(node.args[1])))

        def visit_UpdateStmt(self, ancestors, node):
            events.append((self.line, 'ecriture', RawStream()(node)))

        visit_DeleteStmt = visit_UpdateStmt

    def walk(obj, line=0):
        if isinstance(obj, list):
            for child in obj:
                walk(child, line)
        elif isinstance(obj, dict):
            line = obj.get('lineno', line)
            if 'PLpgSQL_stmt_dynexecute' in obj:
                stmt = obj['PLpgSQL_stmt_dynexecute']
                query = stmt['query']['PLpgSQL_expr']['query']
                events.append((stmt['lineno'], 'role', query.strip("'").replace('RESET ROLE', 'postgres').replace('SET LOCAL ROLE ', '')))
                return
            if 'PLpgSQL_expr' in obj:
                expr = obj['PLpgSQL_expr']
                query = expr['query'].split(':=', 1)[-1] if expr.get('parseMode') == 3 else expr['query']
                if not query.lstrip().upper().startswith(('SELECT ', 'INSERT ', 'UPDATE ', 'DELETE ')):
                    query = 'SELECT ' + query
                Effets(line)(parse_sql(query))
                return
            for child in obj.values():
                walk(child, line)

    for function in parse_plpgsql(sql):
        walk(function['PLpgSQL_function']['action'])
    state = {'role': 'postgres', 'request.jwt.claim.sub': None, 'request.jwt.claims': None}
    writes = []
    for _, kind, value in sorted(events, key=lambda e: e[0]):
        if kind == 'ecriture':
            writes.append((value, state['role'], state['request.jwt.claim.sub'], state['request.jwt.claims']))
        else:
            state[kind] = value
    return writes


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

    def test_refus_lecture_seule_puis_edition_proprietaire(self):
        apres = contexte_ecritures((ROOT / PATH).read_text())
        avant = contexte_ecritures(subprocess.check_output(['git', 'show', f'{AVANT_CLAIMS}:{PATH}'], cwd=ROOT, text=True))
        noms = lambda writes: [w for w in writes if w[0].startswith('UPDATE public.etablissements SET nom =')]
        self.assertEqual(len(noms(avant)), 1)
        self.assertEqual(noms(avant)[0][1:], ('postgres', 'lecture', 'lecture'))
        self.assertEqual(len(noms(apres)), 2)
        self.assertEqual(noms(apres)[0][1:], ('postgres', 'lecture', 'lecture'))
        self.assertEqual(noms(apres)[1][1:], ('postgres', 'etab', 'etab'))
        # Le négatif immédiatement suivant vise désormais une préparation du
        # propriétaire : son trigger doit rester immuable même pour cet acteur.
        preparation = lambda writes: [w for w in writes if w[0].startswith('UPDATE public.contrats_service_preparations SET contenu_texte =')]
        self.assertEqual(len(preparation(apres)), 1)
        self.assertEqual(preparation(apres)[0][1:], ('postgres', 'etab', 'etab'))
        self.assertEqual(preparation(avant)[0][1:], ('postgres', 'lecture', 'lecture'))
        # Tous les autres UPDATE/DELETE gardent leur contexte exact.
        sans_nom = lambda writes: [w for w in writes if w not in noms(writes) + preparation(writes)]
        self.assertEqual(sans_nom(apres), sans_nom(avant))
        self.assertGreater(len(sans_nom(apres)), 10)
        self.assertTrue(all(sub == claims for _, _, sub, claims in apres))


if __name__ == '__main__':
    unittest.main()
