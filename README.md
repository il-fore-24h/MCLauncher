# Minecraft Launcher TUI (Git Bash)

Launcher testuale per Minecraft Java, offline, con la versione già installata.

## Come si usa

1. Estrai lo zip.
2. Tasto destro nella cartella estratta → **Open Git Bash here** (Apri Git Bash qui).
3. Esegui:

   ```bash
   bash mclauncher-tui.sh
   ```

4. Dal menu scegli **Play**.

## Comandi

| Tasto | Azione |
|---|---|
| ↑ / ↓ oppure W / S | Muovi la selezione |
| PgUp / PgDn / Home / End | Salta nella lista |
| Invio | Seleziona |
| Esc | Indietro |

## Note

- Usa la finestra normale di Git Bash (mintty): in altri terminali i tasti freccia potrebbero non funzionare.
- Java 8 e `jq` sono già inclusi nella cartella `Minecraft/` (`java/` e `tools/`), non serve installare nulla.
- Il nome giocatore, la memoria e il server si cambiano da **Settings**.
- I mondi e le opzioni sono in `Minecraft/instances/<versione>`.
