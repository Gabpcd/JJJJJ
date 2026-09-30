#!/usr/bin/env python3
"""Offline scanner, NOT a proof that arbitrary code contains no secret/effect. No execution/import."""
import json,re,sys,pathlib,hashlib,collections
from pglast import parser
ALLOWED={'CommentStmt','VariableSetStmt','SelectStmt','CreateSchemaStmt','AlterOwnerStmt','CreateEnumStmt','CreateStmt','AlterTableStmt','CreateFunctionStmt','ViewStmt','IndexStmt','CreateTrigStmt','CreatePolicyStmt','GrantStmt','AlterDefaultPrivilegesStmt','CreateSeqStmt','AlterSeqStmt','CreateRangeStmt','CompositeTypeStmt','CreateDomainStmt','RuleStmt','CreateExtensionStmt','AlterExtensionStmt','CreateCastStmt','CreateTransformStmt','CreateCollationStmt'}
GUC={'statement_timeout','lock_timeout','idle_in_transaction_session_timeout','transaction_timeout','client_encoding','standard_conforming_strings','check_function_bodies','xmloption','client_min_messages','row_security','default_tablespace','default_table_access_method'}
class Refused(Exception):pass
def audit(text):
    if len(text.encode())>32*1024*1024: raise Refused('DDL_TOO_LARGE')
    if re.search(r'-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(?:sk_live_|sk_test_|sb_secret_|sbp_)[A-Za-z0-9_-]{8,}|\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|(?:postgres(?:ql)?|https?)://[^\s/\'\"]+:[^\s/\'\"]+@',text):raise Refused('SECRET_PATTERN_REFUSED')
    # Parse-only normalization of official pg_dump's paired restrict metacommands. The DDL file is not rewritten.
    meta=re.findall(r'(?m)^\\(\w+)(?: ([^\r\n]+))?\r?$',text)
    if meta:
        if len(meta)!=2 or meta[0][0]!='restrict' or meta[1]!=('unrestrict',meta[0][1]) or not re.fullmatch(r'[A-Za-z0-9]{20,100}',meta[0][1]):raise Refused('PSQL_COMMAND_REFUSED')
        text=re.sub(r'(?m)^\\(?:un)?restrict [A-Za-z0-9]{20,100}\r?$',lambda m:' '*len(m[0]),text)
    if re.search(r'(?m)^\s*\\',text):raise Refused('PSQL_COMMAND_REFUSED')
    tree=json.loads(parser.parse_sql_json(text))['stmts'];kinds=collections.Counter()
    for raw in tree:
        stmt=raw['stmt'];kind=next(iter(stmt));kinds[kind]+=1
        if kind not in ALLOWED:raise Refused('TOP_LEVEL_STATEMENT_REFUSED')
        if kind=='VariableSetStmt' and stmt[kind].get('name') not in GUC:raise Refused('GUC_REFUSED')
        if kind=='SelectStmt':
            start=raw.get('stmt_location',0);part=text[start:start+raw.get('stmt_len',len(text)-start)]
            part=re.sub(r'--[^\n]*','',part).strip().rstrip(';').strip()
            if not re.fullmatch(r"SELECT pg_catalog\.set_config\('search_path', '', false\)",part):raise Refused('TOP_LEVEL_SELECT_REFUSED')
    return {'result':'DDL_STRUCTURALLY_SCANNED','statements':len(tree),'statement_kinds':dict(kinds),'known_secret_patterns_only':True,'manual_review_required':True,'release_authorized':False,'import_ready':False}
if __name__=='__main__':
    try:print(json.dumps(audit(pathlib.Path(sys.argv[1]).read_text())))
    except Refused as e:print(json.dumps({'result':'REFUSED','code':str(e)}));sys.exit(1)
    except Exception:print(json.dumps({'result':'REFUSED','code':'DDL_PARSE_OR_INPUT_REFUSED'}));sys.exit(1)
