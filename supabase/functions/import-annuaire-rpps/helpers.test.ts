import { erreurRppsReprenable, peutPublierStatutSource } from "./helpers.ts";

function assertEquals<T>(obtenu: T, attendu: T, message: string): void {
  if (obtenu !== attendu) {
    throw new Error(
      `${message}: attendu ${String(attendu)}, obtenu ${String(obtenu)}`,
    );
  }
}

Deno.test("RPPS: les erreurs de lecture du corps HTTP et EOF sont reprenables", () => {
  for (
    const message of [
      "error reading a body from connection",
      "request body error: end of file before message length reached",
      "TypeError: unexpected EOF",
      "The signal has been aborted",
    ]
  ) {
    assertEquals(erreurRppsReprenable(message), true, message);
  }
  assertEquals(
    erreurRppsReprenable("Acces admin refuse"),
    false,
    "erreur fonctionnelle",
  );
});

Deno.test("RPPS: seul le run le plus récent publie le statut de la source", () => {
  assertEquals(
    peutPublierStatutSource("run-recent", "run-recent"),
    true,
    "run courant",
  );
  assertEquals(
    peutPublierStatutSource("run-ancien", "run-recent"),
    false,
    "run ancien",
  );
  assertEquals(
    peutPublierStatutSource(null, "run-recent"),
    true,
    "erreur avant creation du run",
  );
});
