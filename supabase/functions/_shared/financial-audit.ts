type SupabaseLike = {
  rpc: (name: string, args: Record<string, unknown>) => PromiseLike<{
    data: unknown;
    error: { message?: string } | null;
  }>;
};

export async function writeRequiredFinancialAudit(
  supabase: SupabaseLike,
  args: Record<string, unknown>,
  context: string,
): Promise<void> {
  const { data, error } = await supabase.rpc("fn_ecrire_audit_safe", args);
  const result = data as { success?: boolean; error?: string } | null;
  if (error || result?.success !== true) {
    throw new Error(
      `${context}: ${error?.message || result?.error || "audit not persisted"}`,
    );
  }
}
