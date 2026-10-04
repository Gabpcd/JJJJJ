"""Lecture pure de l'ACL du claim, sans réécrire le SQL du dump."""
import re


def _identifier(value):
    return rf'(?:{value}|"{value}")'


_TARGET = _identifier('public') + r'\s*\.\s*' + _identifier('fn_stripe_payment_flow_claim_connect_v1')
_ARGUMENTS = r'\s*,\s*'.join(
    rf'(?:{_identifier(name)}\s+)?{_identifier(kind)}'
    for name, kind in [('p_flow', 'text'), ('p_owner_token', 'text'),
                       ('p_facture_id', 'uuid'), ('p_mission_id', 'uuid')]
)
_SIGNATURE = _TARGET + r'\s*\(\s*' + _ARGUMENTS + r'\s*\)'
_ACL = re.compile(
    rf'\s*(REVOKE|GRANT)\s+(ALL(?:\s+PRIVILEGES)?|EXECUTE)\s+ON\s+FUNCTION\s+'
    rf'{_SIGNATURE}\s+(FROM|TO)\s+(.+?)\s*;\s*'
)


def extract_claim_acl(snapshot):
    """Accepte les deux rendus pg_dump et exige un claim réservé au service.

    Les candidats visent le nom avant de valider la signature et les droits :
    une ACL supplémentaire ou mal formée ne doit pas disparaître du contrôle.
    Le dump écrit ces ACL sur une ligne ; un autre format est refusé.
    """
    candidates = re.findall(
        rf'(?m)^[ \t]*(?:REVOKE|GRANT)\b[^;]*?\bON\s+FUNCTION\s+'
        rf'{_TARGET}(?=\s|\()[^\n]*', snapshot
    )
    if len(candidates) != 2:
        raise ValueError('CLAIM_ACL_COUNT_REFUSED')
    for index, statement in enumerate(candidates):
        match = _ACL.fullmatch(statement)
        if '\n' in statement or not match:
            raise ValueError('CLAIM_ACL_STATEMENT_REFUSED')
        operation, _, direction, recipients = match.groups()
        roles = [value.strip() for value in recipients.split(',')]
        # PUBLIC est le pseudo-rôle SQL, jamais un identifiant cité "PUBLIC".
        allowed = {'PUBLIC', 'anon', '"anon"', 'authenticated', '"authenticated"',
                   'service_role', '"service_role"'}
        if any(role not in allowed for role in roles):
            raise ValueError('CLAIM_ACL_RECIPIENT_REFUSED')
        roles = [role.strip('"') for role in roles]
        if len(roles) != len(set(roles)):
            raise ValueError('CLAIM_ACL_RECIPIENT_REFUSED')
        if index == 0:
            if operation != 'REVOKE' or direction != 'FROM' or 'PUBLIC' not in roles:
                raise ValueError('CLAIM_ACL_PUBLIC_REVOKE_REQUIRED')
        elif operation != 'GRANT' or direction != 'TO' or roles != ['service_role']:
            raise ValueError('CLAIM_ACL_SERVICE_ONLY_REQUIRED')
    return candidates
