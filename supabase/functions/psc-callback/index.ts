// Pro Santé Connect — étape 2 : échange le code, vérifie le JWT, crée ou lie le soignant,
// et redirige vers le frontend avec un token de session magique.
import { createClient } from "npm:@supabase/supabase-js@2";
import { jwtVerify, createRemoteJWKSet } from "npm:jose@5.9.6";

const PSC_ENDPOINTS = {
  sandbox: {
    issuer: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet",
    token: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/token",
    jwks: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/certs",
    userinfo: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/userinfo",
  },
  production: {
    issuer: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet",
    token: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/token",
    jwks: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/certs",
    userinfo: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/userinfo",
  },
};
