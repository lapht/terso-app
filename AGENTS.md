# AGENTS.md — Istruzioni per agenti AI che lavorano su Terso

Leggi questo file per intero prima di toccare qualsiasi file. Il design document
è `docs/design.md` e prevale su ogni tua interpretazione.

## Progetto
Terso: cleaner macOS open source, GPL-3.0, Swift 6 + SwiftUI, macOS 13+.
L'app vive nel progetto Xcode; `Package.swift` contiene solo CoreKit e i test.

## Aprire, eseguire e testare
- Apri `Terso.xcodeproj` in Xcode e seleziona lo schema `TersoApp`.
- Avvia l'app e le SwiftUI Preview con Xcode. `CoreKit` è fornito dal package
  locale definito in `Package.swift`.
- Esegui i test del package dalla root con `swift test`.
- Esegui i test UI/ViewModel con `xcodebuild test -project Terso.xcodeproj -scheme TersoApp`.

## Avvio di una nuova chat o issue
All'inizio di ogni nuova chat che deve modificare il codice, e prima di iniziare
l'implementazione di una issue, prepara il repository da `main` aggiornato:

1. Controlla branch corrente e `git status`. Se ci sono modifiche non salvate,
   non cambiare branch né sovrascriverle: fermati e chiedi all'utente come
   procedere.
2. Esegui `git fetch origin --prune`, poi `git switch main` e
   `git pull --ff-only origin main`. Se `main` non esiste, il pull fallisce o
   l'aggiornamento richiede una risoluzione manuale, fermati e segnala il
   problema; non usare reset o force-push per aggirarlo.
3. Esamina `git branch -vv` e rimuovi i branch locali il cui upstream risulta
   `[gone]`, dopo esserti assicurato che non contengano lavoro locale unico.
   Usa `git branch -d`; non forzare la cancellazione con `-D`. Se un branch
   contiene commit non integrati, conservalo e chiedi all'utente prima di
   eliminarlo.
4. Crea un nuovo branch dedicato alla chat/issue a partire dal `main`
   aggiornato, ad esempio con `git switch -c <nome-issue> main`. Scegli un nome
   non già in uso e non riutilizzare o sovrascrivere un branch esistente.

Non iniziare l'implementazione finché il branch di lavoro non è stato creato
da `main` aggiornato. Non eliminare o scartare modifiche dell'utente durante
questa preparazione.

## Mappa dell'architettura (da docs/design.md §3)
```
terso-app/
  Sources/
    CoreKit/
      Engine/        # scanner, rule evaluation, size accounting
      Safety/        # the guarded deletion pipeline (see §5)
      Rules/         # rule DB loader + validation
      Modules/       # one Swift file per cleanup module
    TersoApp/        # SwiftUI views, minimal logic
  Rules/             # rules/vYYYY.N.json — versioned rule database
  Tests/             # fixtures: fake home dirs with known trees
  docs/              # this file, CONTRIBUTING.md, CODE_OF_CONDUCT.md
  AGENTS.md          # instructions for AI agents (see §8)
```

## Le 8 invarianti di sicurezza (NON negoziabili — verbatim da docs/design.md §5)
1. **Allowlist-only roots.** Deletion may only target paths under allowlisted roots defined per module (e.g. `~/Library/Caches`). Everything else = refusal.
2. **Symlink discipline.** Resolve every path; verify the resolved target is still inside the allowlist root; never follow symlinks into unknown locations.
3. **Protected paths.** Hard deny: SIP-protected volumes, `/System`, `/private/var/db`, the user's Desktop/Documents/Downloads roots, and any active application bundle.
4. **Trash-first.** Default destructive op is `FileManager.trashItem` (real Trash, recoverable). Permanent delete requires an explicit per-item opt-in checkbox, off by default.
5. **Dry-run everywhere.** First run of "Smart Scan" never deletes; every clean action has a dry-run mode reporting byte counts.
6. **Confirmation + recap.** GUI must show total size and item count before executing; admin escalation (sandboxed helper) is separate and logged.
7. **Graceful TCC.** Missing Full Disk Access disables only the modules that need it, with clear onboarding — never silently scans less than displayed.
8. **No silent failures.** Every deletion is logged (locally) with timestamp, rule id, and size; logs are exportable for bug reports.

## Regole di ingaggio
- **Divieto assoluto:** nessuna logica né API di cancellazione file fuori da `Sources/CoreKit/Safety/`. La CI blocca le violazioni: non cercare workaround, segnala e basta.
- Non allargare lo scope di un issue. Se serve altro lavoro, proponi un nuovo issue invece di implementarlo.
- Ogni modifica a `Safety/` o `Rules/` richiede review umana obbligatoria: segnalalo esplicitamente nella PR description con il flag `[SAFETY]`.
- Codice conforme a SwiftLint; esegui i test prima di proporre la PR.
- Commit in formato Conventional Commits (`feat:`, `fix:`, `test:`...).
- Un issue = una PR. PR piccole e leggibili.

## Test obbligatori per modifica
- Rule engine: validazione schema e pattern con fixture in `Tests/`.
- Ogni nuovo modulo: fixture tree con contenuto noto + test su risultato esatto di scan e deletion set. Includi un caso symlink-attack quando rilevante.
