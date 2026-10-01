#!/usr/bin/env python3
"""Offline structural inventory. Uses pglast; it is NOT a PL/pgSQL compiler.
Does not construct DDL or execute a DB connection. Public-only always refuses.
"""
import sys,json,re,hashlib,collections,pathlib
from pglast import parser
SCHEMAS=('private','auth','storage','extensions','cron','net','vault','supabase_functions')
ALLOWED={'VariableSetStmt','SelectStmt','CreateSchemaStmt','AlterOwnerStmt','CreateEnumStmt','CreateStmt','AlterTableStmt','CommentStmt','CreateFunctionStmt','ViewStmt','IndexStmt','CreateTrigStmt','CreatePolicyStmt','GrantStmt','AlterDefaultPrivilegesStmt','CreateSeqStmt','AlterSeqStmt','CreateRangeStmt','CompositeTypeStmt','CreateDomainStmt'}
def audit(text):
    tree=json.loads(parser.parse_sql_json(text))['stmts']
    kinds=collections.Counter(next(iter(s['stmt'])) for s in tree)
    schemas=sorted({s['stmt']['CreateSchemaStmt']['schemaname'] for s in tree if 'CreateSchemaStmt' in s['stmt']})
    forbidden=sorted(set(kinds)-ALLOWED)
    # pg_dump's single set_config(search_path,'',false) is allowed, no arbitrary SELECT.
    for s in tree:
        if 'SelectStmt' in s['stmt']:
            part=text[s.get('stmt_location',0):s.get('stmt_location',0)+s.get('stmt_len',len(text))]
            if not re.fullmatch(r"\s*(?:--[^\n]*\n\s*)*SELECT pg_catalog\.set_config\('search_path', '', false\)\s*;?\s*",part):
                forbidden.append('NON_DUMP_SELECT')
    refs={schema:sorted(set(re.findall(r'\b'+schema+r'\s*\.\s*"?([A-Za-z_][A-Za-z_0-9]*)',text))) for schema in SCHEMAS}
    blockers=[]
    if 'private' not in schemas: blockers.append('PRIVATE_SCHEMA_MISSING')
    if forbidden: blockers.append('TOP_LEVEL_STATEMENT_REQUIRES_REVIEW')
    # Managed customizations, reference rows and registry are separate official exports.
    blockers+=['MANAGED_CUSTOMIZATIONS_BUNDLE_REQUIRED','REFERENTIAL_DATA_ALLOWLIST_REQUIRED','MIGRATION_REGISTRY_BUNDLE_REQUIRED','SECURITY_INVENTORY_BUNDLE_REQUIRED','RUNTIME_IMPORT_NOT_EXECUTED']
    return {'sha256':hashlib.sha256(text.encode()).hexdigest(),'bytes':len(text.encode()),'statement_count':len(tree),'statement_kinds':dict(kinds),'created_schemas':schemas,'lexical_references_not_dependency_closure':refs,'unapproved_statement_types':sorted(set(forbidden)),'blockers':blockers,'import_ready':False}
if __name__=='__main__':
    try:
        report=audit(pathlib.Path(sys.argv[1]).read_text());print(json.dumps(report,indent=2));sys.exit(3)
    except Exception:
        print(json.dumps({'result':'REFUSED','code':'SCHEMA_PARSE_OR_INPUT_FAILED'}));sys.exit(1)
