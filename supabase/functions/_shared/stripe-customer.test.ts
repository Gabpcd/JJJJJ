import {
  ensureCanonicalEtablissementCustomer,
  mapStripeCustomerConfigurationError,
  StripeCustomerConfigurationError,
} from "./stripe-customer.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(
      `${message}: attendu=${String(expected)} obtenu=${String(actual)}`,
    );
  }
}

type CustomerRecord = {
  id: string;
  deleted: boolean;
  name: string;
  email: string;
  metadata: Record<string, string>;
};

class FakeStripe {
  readonly records = new Map<string, CustomerRecord>();
  readonly idsByIdempotencyKey = new Map<string, string>();
  readonly createCalls: Array<
    { params: Record<string, unknown>; key: string }
  > = [];
  updateCalls = 0;

  readonly customers = {
    create: async (
      params: Record<string, unknown>,
      options: { idempotencyKey: string },
    ) => {
      this.createCalls.push({ params, key: options.idempotencyKey });
      let id = this.idsByIdempotencyKey.get(options.idempotencyKey);
      if (!id) {
        id = `cus_${this.idsByIdempotencyKey.size + 1}`;
        this.idsByIdempotencyKey.set(options.idempotencyKey, id);
        this.records.set(id, {
          id,
          deleted: false,
          name: String(params.name),
          email: String(params.email),
          metadata: { ...(params.metadata as Record<string, string>) },
        });
      }
      return this.records.get(id)!;
    },
    retrieve: async (id: string) => {
      const customer = this.records.get(id);
      if (!customer) {
        throw Object.assign(new Error("missing"), { code: "resource_missing" });
      }
      return customer;
    },
    update: async (id: string, params: Record<string, unknown>) => {
      const customer = this.records.get(id);
      if (!customer || customer.deleted) {
        throw Object.assign(new Error("missing"), { code: "resource_missing" });
      }
      this.updateCalls += 1;
      customer.name = String(params.name);
      customer.email = String(params.email);
      customer.metadata = { ...(params.metadata as Record<string, string>) };
      return customer;
    },
  };
}

class FakeSupabaseAdmin {
  readonly customerIds = new Map<string, string | null>();
  claimAttempts = 0;

  from(table: string) {
    assertEquals(table, "etablissements", "table CAS inattendue");
    return {
      update: (values: { stripe_customer_id: string }) => {
        const state: { id?: string; expected?: string | null } = {};
        const builder = {
          eq: (column: string, value: string) => {
            if (column === "id") state.id = value;
            if (column === "stripe_customer_id") state.expected = value;
            return builder;
          },
          is: (column: string, value: null) => {
            assertEquals(
              column,
              "stripe_customer_id",
              "colonne CAS inattendue",
            );
            state.expected = value;
            return builder;
          },
          select: (column: string) => {
            assertEquals(
              column,
              "stripe_customer_id",
              "projection claim inattendue",
            );
            return {
              maybeSingle: async () => {
                this.claimAttempts += 1;
                const id = state.id!;
                const current = this.customerIds.get(id) ?? null;
                if (current !== state.expected) {
                  return { data: null, error: null };
                }
                this.customerIds.set(id, values.stripe_customer_id);
                return {
                  data: { stripe_customer_id: values.stripe_customer_id },
                  error: null,
                };
              },
            };
          },
        };
        return builder;
      },
      select: (column: string) => {
        if (column === "id") {
          let customerId = "";
          let excludedId = "";
          const lookup = {
            eq: (filterColumn: string, value: string) => {
              assertEquals(
                filterColumn,
                "stripe_customer_id",
                "filtre unicité inattendu",
              );
              customerId = value;
              return lookup;
            },
            neq: (filterColumn: string, value: string) => {
              assertEquals(filterColumn, "id", "exclusion unicité inattendue");
              excludedId = value;
              return lookup;
            },
            limit: async () => ({
              data: [...this.customerIds.entries()]
                .filter(([id, storedCustomerId]) =>
                  id !== excludedId && storedCustomerId === customerId
                )
                .slice(0, 1)
                .map(([id]) => ({ id })),
              error: null,
            }),
          };
          return lookup;
        }
        assertEquals(
          column,
          "stripe_customer_id",
          "projection relecture inattendue",
        );
        let id = "";
        return {
          eq: (filterColumn: string, value: string) => {
            assertEquals(filterColumn, "id", "filtre relecture inattendu");
            id = value;
            return {
              maybeSingle: async () => ({
                data: { stripe_customer_id: this.customerIds.get(id) ?? null },
                error: null,
              }),
            };
          },
        };
      },
    };
  }
}

type StripeArg = Parameters<typeof ensureCanonicalEtablissementCustomer>[0];
type AdminArg = Parameters<typeof ensureCanonicalEtablissementCustomer>[1];

Deno.test("Customer établissement: deux courses convergent sur le même ID canonique", async () => {
  const stripe = new FakeStripe();
  const admin = new FakeSupabaseAdmin();
  const etab = {
    id: "etab-a",
    nom: "Clinique A",
    email_contact: "FACTURATION@A.EXAMPLE",
    stripe_customer_id: null,
  };
  admin.customerIds.set(etab.id, null);

  const [first, second] = await Promise.all([
    ensureCanonicalEtablissementCustomer(
      stripe as unknown as StripeArg,
      admin as unknown as AdminArg,
      etab,
    ),
    ensureCanonicalEtablissementCustomer(
      stripe as unknown as StripeArg,
      admin as unknown as AdminArg,
      etab,
    ),
  ]);

  assertEquals(first, second, "les appels concurrents divergent");
  assertEquals(
    admin.customerIds.get(etab.id),
    first,
    "le gagnant CAS n'est pas persisté",
  );
  assertEquals(
    stripe.records.size,
    1,
    "plusieurs Customers ont été matérialisés",
  );
  assert(
    stripe.createCalls.every((call) =>
      call.key === "customer_etablissement_etab-a"
    ),
    "la clé d'idempotence n'est pas canonique",
  );
  assert(
    stripe.createCalls.every((call) =>
      Object.keys(call.params).join(",") === "metadata"
    ),
    "les paramètres idempotents de création dépendent du profil mutable",
  );
  assertEquals(
    stripe.records.get(first)?.name,
    "Clinique A",
    "nom canonique non synchronisé",
  );
  assertEquals(
    stripe.records.get(first)?.email,
    "facturation@a.example",
    "email canonique non synchronisé",
  );
});

Deno.test("Customer établissement: un ID d'un autre tenant est refusé sans overwrite", async () => {
  const stripe = new FakeStripe();
  const admin = new FakeSupabaseAdmin();
  stripe.records.set("cus_a", {
    id: "cus_a",
    deleted: false,
    name: "Clinique A",
    email: "a@example.test",
    metadata: { etablissement_id: "etab-a" },
  });
  admin.customerIds.set("etab-b", "cus_a");

  let rejected: unknown;
  try {
    await ensureCanonicalEtablissementCustomer(
      stripe as unknown as StripeArg,
      admin as unknown as AdminArg,
      {
        id: "etab-b",
        nom: "Clinique B",
        email_contact: "b@example.test",
        stripe_customer_id: "cus_a",
      },
    );
  } catch (error) {
    rejected = error;
  }

  assert(
    rejected instanceof StripeCustomerConfigurationError,
    "mauvais type d'erreur",
  );
  assertEquals(
    rejected.code,
    "CUSTOMER_TENANT_MISMATCH",
    "mauvais motif cross-tenant",
  );
  assertEquals(
    admin.customerIds.get("etab-b"),
    "cus_a",
    "l'ID suspect a été écrasé",
  );
  assertEquals(
    admin.claimAttempts,
    0,
    "un CAS a été tenté malgré le mismatch metadata",
  );
  assertEquals(
    stripe.createCalls.length,
    0,
    "un nouveau Customer a été créé malgré le mismatch",
  );
});

Deno.test("Customer établissement: un ID Stripe obsolète est remplacé par CAS", async () => {
  const stripe = new FakeStripe();
  const admin = new FakeSupabaseAdmin();
  admin.customerIds.set("etab-a", "cus_supprime");

  const customerId = await ensureCanonicalEtablissementCustomer(
    stripe as unknown as StripeArg,
    admin as unknown as AdminArg,
    {
      id: "etab-a",
      nom: "Clinique A",
      email_contact: "a@example.test",
      stripe_customer_id: "cus_supprime",
    },
  );

  assertEquals(
    admin.customerIds.get("etab-a"),
    customerId,
    "le CAS stale n'a pas gagné",
  );
  assertEquals(
    stripe.records.get(customerId)?.metadata.etablissement_id,
    "etab-a",
    "metadata invalide",
  );
  assertEquals(
    stripe.createCalls[0]?.key,
    "customer_etablissement_etab-a_after_cus_supprime",
    "la recréation stale ne versionne pas sa clé",
  );
});

Deno.test("Customer établissement: un replay idempotent supprimé est versionné puis remplacé", async () => {
  const stripe = new FakeStripe();
  const admin = new FakeSupabaseAdmin();
  admin.customerIds.set("etab-a", "cus_supprime");
  const replayKey = "customer_etablissement_etab-a_after_cus_supprime";
  stripe.idsByIdempotencyKey.set(replayKey, "cus_rejoue_supprime");
  stripe.records.set("cus_rejoue_supprime", {
    id: "cus_rejoue_supprime",
    deleted: true,
    name: "Clinique A",
    email: "a@example.test",
    metadata: { etablissement_id: "etab-a" },
  });

  const customerId = await ensureCanonicalEtablissementCustomer(
    stripe as unknown as StripeArg,
    admin as unknown as AdminArg,
    {
      id: "etab-a",
      nom: "Clinique A",
      email_contact: "a@example.test",
      stripe_customer_id: "cus_supprime",
    },
  );

  assert(
    customerId !== "cus_rejoue_supprime",
    "le Customer supprimé a été conservé",
  );
  assertEquals(
    stripe.createCalls.length,
    2,
    "le replay supprimé n'a pas été remplacé",
  );
  assertEquals(
    stripe.createCalls[0]?.key,
    replayKey,
    "mauvaise clé de replay initiale",
  );
  assertEquals(
    stripe.createCalls[1]?.key,
    `${replayKey}_after_cus_rejoue_supprime`,
    "la deuxième clé ne versionne pas le Customer supprimé rejoué",
  );
  assertEquals(
    admin.customerIds.get("etab-a"),
    customerId,
    "le remplaçant n'est pas persisté",
  );
});

Deno.test("Customer établissement: metadata legacy bloquée même si nom et email concordent", async () => {
  const stripe = new FakeStripe();
  const admin = new FakeSupabaseAdmin();
  stripe.records.set("cus_legacy", {
    id: "cus_legacy",
    deleted: false,
    name: "Clinique A",
    email: "facturation@a.example",
    metadata: {},
  });
  admin.customerIds.set("etab-a", "cus_legacy");

  let exactMatchRejected: unknown;
  try {
    await ensureCanonicalEtablissementCustomer(
      stripe as unknown as StripeArg,
      admin as unknown as AdminArg,
      {
        id: "etab-a",
        nom: "Clinique A",
        email_contact: "FACTURATION@A.EXAMPLE",
        stripe_customer_id: "cus_legacy",
      },
    );
  } catch (error) {
    exactMatchRejected = error;
  }
  assert(
    exactMatchRejected instanceof StripeCustomerConfigurationError,
    "legacy sans metadata non refusé malgré une identité concordante",
  );
  assertEquals(
    exactMatchRejected.code,
    "CUSTOMER_TENANT_MISMATCH",
    "mauvais motif legacy sans metadata",
  );
  assertEquals(
    stripe.updateCalls,
    0,
    "metadata legacy modifiée sans audit manuel",
  );

  stripe.records.set("cus_suspect", {
    id: "cus_suspect",
    deleted: false,
    name: "Clinique A",
    email: "autre@example.test",
    metadata: {},
  });
  admin.customerIds.set("etab-b", "cus_suspect");
  let rejected: unknown;
  try {
    await ensureCanonicalEtablissementCustomer(
      stripe as unknown as StripeArg,
      admin as unknown as AdminArg,
      {
        id: "etab-b",
        nom: "Clinique A",
        email_contact: "facturation@a.example",
        stripe_customer_id: "cus_suspect",
      },
    );
  } catch (error) {
    rejected = error;
  }
  assert(
    rejected instanceof StripeCustomerConfigurationError,
    "legacy suspect non refusé",
  );
  assertEquals(
    rejected.code,
    "CUSTOMER_TENANT_MISMATCH",
    "mauvais motif legacy suspect",
  );
});

Deno.test("Customer établissement: nom et email_contact existants sont synchronisés", async () => {
  const stripe = new FakeStripe();
  const admin = new FakeSupabaseAdmin();
  stripe.records.set("cus_a", {
    id: "cus_a",
    deleted: false,
    name: "Ancien nom",
    email: "ancien@example.test",
    metadata: { etablissement_id: "etab-a" },
  });
  admin.customerIds.set("etab-a", "cus_a");

  const customerId = await ensureCanonicalEtablissementCustomer(
    stripe as unknown as StripeArg,
    admin as unknown as AdminArg,
    {
      id: "etab-a",
      nom: "Nouveau nom",
      email_contact: "NOUVEAU@EXAMPLE.TEST",
      stripe_customer_id: "cus_a",
    },
  );

  assertEquals(
    customerId,
    "cus_a",
    "le Customer existant n'a pas été conservé",
  );
  assertEquals(
    stripe.records.get("cus_a")?.name,
    "Nouveau nom",
    "nom non synchronisé",
  );
  assertEquals(
    stripe.records.get("cus_a")?.email,
    "nouveau@example.test",
    "email non synchronisé",
  );
  assertEquals(stripe.updateCalls, 1, "mise à jour Stripe inattendue");
});

Deno.test("Customer établissement: la metadata tenant est réécrite sous sa forme canonique", async () => {
  const stripe = new FakeStripe();
  const admin = new FakeSupabaseAdmin();
  stripe.records.set("cus_a", {
    id: "cus_a",
    deleted: false,
    name: "Clinique A",
    email: "a@example.test",
    metadata: { etablissement_id: " etab-a " },
  });
  admin.customerIds.set("etab-a", "cus_a");

  const customerId = await ensureCanonicalEtablissementCustomer(
    stripe as unknown as StripeArg,
    admin as unknown as AdminArg,
    {
      id: "etab-a",
      nom: "Clinique A",
      email_contact: "a@example.test",
      stripe_customer_id: "cus_a",
    },
  );

  assertEquals(customerId, "cus_a", "le Customer canonique a été remplacé");
  assertEquals(
    stripe.records.get("cus_a")?.metadata.etablissement_id,
    "etab-a",
    "la metadata tenant n'a pas été normalisée",
  );
  assertEquals(stripe.updateCalls, 1, "normalisation Stripe absente");
});

Deno.test("Customer établissement: le mapping public ne divulgue jamais le diagnostic DB", () => {
  const mapped = mapStripeCustomerConfigurationError(
    new StripeCustomerConfigurationError(
      "CUSTOMER_PERSISTENCE_FAILED",
      "duplicate key value violates unique constraint secret_internal",
    ),
  );

  assert(mapped, "erreur Customer non mappée");
  assertEquals(mapped.status, 503, "mauvais statut de persistance");
  assertEquals(mapped.retryable, true, "la persistance doit être réessayable");
  assert(
    !mapped.userMessage.includes("duplicate") &&
      !mapped.userMessage.includes("secret_internal"),
    "le diagnostic DB est exposé au client",
  );
});
