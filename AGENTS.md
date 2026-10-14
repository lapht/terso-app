# AGENTS.md — Istruzioni per agenti AI che lavorano su Terso

Leggi questo file per intero prima di toccare qualsiasi file. Il design document
è `docs/design.md` e prevale su ogni tua interpretazione.

## Progetto
Terso: cleaner macOS open source, GPL-3.0, Swift 6 + SwiftUI, macOS 13+.
Tutta la logica vive nel Swift Package `CoreKit`. L'app GUI è solo presentazione.

## Le 8 invarianti di sicurezza (NON negoziabili — da docs/design.md §5)
1. Deletion targets only paths under per-module allowlisted roots.
2. Resolve every path; verify resolved target stays inside the allowlist; never
   follow symlinks into unknown locations.
3. Hard deny: SIP-protected volumes, `/System`, `/private/var/db`, Desktop,
   Documents, Downloads roots, active app bundles.
4. Trash-first: default op is `FileManager.trashItem`. Permanent delete solo
   con opt-in esplicito per item, disattivato di default.
5. Dry-run available for every clean action; Smart Scan first run is dry-run only.
6. GUI confirmation with total size + item count before any execution.
7. Missing Full Disk Access disables only affected modules, with clear UI.
8. Every deletion logged locally (timestamp, rule id, size); logs exportable.

## Regole di ingaggio
- Nessuna API di cancellazione file fuori da `Sources/CoreKit/Safety/`. La CI
  blocca le violazioni: non cercare workaround, segnala e basta.
- Non allargare lo scope di un issue. Se serve altro lavoro, proponi un nuovo
  issue invece di implementarlo.
- Ogni modifica a `Safety/` o `Rules/` richiede review umana: segnalalo
  esplicitamente nella PR description con il flag `[SAFETY]`.
- Codice conforme a SwiftLint; esegui i test prima di proporre la PR.
- Commit in formato Conventional Commits (`feat:`, `fix:`, `test:`...).
- Un issue = una PR. PR piccole e leggibili.

## Test obbligatori
- Rule engine: validazione schema e pattern con fixture in `Tests/`.
- Ogni nuovo modulo: fixture tree con contenuto noto + test su risultato esatto
  di scan e deletion set. Includi un caso symlink-attack quando rilevante.
