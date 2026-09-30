"""Contrôle local pglast, sans DB : records PL/pgSQL et alias du SELECT catalogue.

Ne remplace pas la prochaine exécution PostgreSQL sous ROLLBACK. Pglast valide
la grammaire mais ne résout pas seul la portée SQL/PLpgSQL à l'exécution.
"""
import json
from pathlib import Path
import subprocess
import unittest

from pglast import parse_plpgsql, parse_sql
from pglast.visitors import Visitor


ROOT = Path(__file__).resolve().parents[2]
SOURCES = json.loads(subprocess.check_output([
    "node", "--input-type=module", "-e", """
import {manifesteD,sqlCatalogueD} from './scripts/ci/candidatures-fixture-contract.mjs';
import {sqlAvantD,sqlSeedD,sqlEtatD} from './scripts/ci/candidatures-fixture-sql.mjs';
import {sqlRecetteRollbackD} from './scripts/ci/generate-candidatures-rollback.mjs';
const m=manifesteD('sql-d2-portee-locale','2026-10-07');
process.stdout.write(JSON.stringify({catalogue:sqlCatalogueD,blocs:{
avant:sqlAvantD(m),seed:sqlSeedD(m),etat:sqlEtatD(m),cleanup:sqlEtatD(m,true)},
preuve:sqlRecetteRollbackD('portee-locale','2026-10-07')}));
""",
], cwd=ROOT, text=True))


class Relations(Visitor):
    def __init__(self):
        super().__init__()
        self.tables = set()
        self.aliases = set()

    def visit_RangeVar(self, ancestors, node):
        self.tables.add(node.relname)
        if node.alias:
            self.aliases.add(node.alias.aliasname)


def relations(sql):
    visitor = Relations()
    visitor(parse_sql(sql))
    return visitor


def objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from objects(child)


def catalogue_scopes(plpgsql):
    """Intersections de noms issues des AST, indépendantes du nom du correctif."""
    results = []
    for compiled in parse_plpgsql(plpgsql):
        function = compiled['PLpgSQL_function']
        records = {d['PLpgSQL_rec']['refname'] for d in function.get('datums', [])
                   if 'PLpgSQL_rec' in d}
        for obj in objects(function['action']):
            statement = obj.get('PLpgSQL_stmt_execsql')
            if not statement:
                continue
            query = statement['sqlstmt']['PLpgSQL_expr']['query']
            catalog = relations(query)
            if {'pg_constraint', 'pg_proc', 'pg_trigger'} <= catalog.tables:
                results.append(records & catalog.aliases)
    return results


class CatalogueScope(unittest.TestCase):
    def test_each_real_guard_has_a_catalogue_select_without_record_alias_collision(self):
        for name, sql in SOURCES['blocs'].items():
            with self.subTest(bloc=name):
                self.assertEqual(catalogue_scopes(sql), [set()])

    def test_a_record_named_like_any_actual_catalogue_alias_is_rejected(self):
        aliases = relations(SOURCES['catalogue']).aliases
        self.assertTrue(aliases)
        for alias in aliases:
            with self.subTest(alias=alias):
                # Témoin négatif structurel : les noms viennent du catalogue,
                # pas d'une copie du nouveau nom choisi pour le record.
                sql = (f'DO $scope$ DECLARE {alias} record; BEGIN '
                       f'SELECT * INTO {alias} FROM ({SOURCES["catalogue"]}) resultat; '
                       'END $scope$;')
                self.assertEqual(catalogue_scopes(sql), [{alias}])

    def test_generated_rollback_remains_parseable(self):
        self.assertTrue(parse_sql(SOURCES['preuve']))
        self.assertTrue(parse_plpgsql(SOURCES['preuve']))


if __name__ == '__main__':
    unittest.main()
