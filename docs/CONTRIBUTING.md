# Contributing to Terso

Grazie per l'interesse! Terso è GPL-3.0, gratuito per sempre, e resta tale.

## Come contribuire
1. **Bug**: apri un issue col template "Bug report" (versione macOS, modulo,
   log esportato dall'app, passi per riprodurre).
2. **Nuova regola di pulizia**: apri un issue "Rule proposal" oppure manda PR
   che tocca solo `Rules/` con motivazione e fonte (es. doc Apple o nota del
   vendor dell'app target).
3. **Feature**: discuti prima in un issue "Module request", poi PR.

## Setup sviluppo
macOS 13+, Xcode 16+. `git clone`, apri `Package.swift`, build.
Prima della PR: SwiftLint pulito + tutti i test verdi.

## Regole d'oro
- Le invarianti di sicurezza in `docs/design.md` §5 non si toccano senza
  discussione esplicita con il maintainer.
- Cancellazione file SOLO in `Sources/CoreKit/Safety/`.
- Una PR = un cambiamento coeso. Conventional Commits.
- Le PR su `Safety/` e `Rules/` richiedono review del maintainer: marcala
  con `[SAFETY]` nel titolo.

## Codice di condotta
Sii gentile, preciso, senza FUD. Valido per issue, PR e discussioni.
