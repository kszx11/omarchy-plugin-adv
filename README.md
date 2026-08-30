# Adventure for Omarchy

A keyboard-first, AI-powered text adventure for Omarchy. Begin in any place and time, explore a living world, talk with memorable characters, uncover clues, and shape the story through your choices.

Requires an OpenAI API key with API billing; a ChatGPT subscription alone does not provide API access.

![Adventure gameplay preview](preview.png)

## Exploration

Every new adventure opens in a broad named region with at least three meaningful routes. As you travel, the game reveals connected settlements, wilderness, landmarks, and other named locations; the map records routes you have discovered. Ordinary scenes keep at least two ways forward, while true endings and temporary defeats are the only intentional exceptions.

## Requirements and privacy

- Omarchy 4.0 (Quattro) with Quickshell plugin support.
- Internet access and an OpenAI API key with API billing.
- No elevated privileges, install hooks, or external local services.

The game sends player commands and game context directly to the OpenAI API. It reads `OPENAI_API_KEY` when available; otherwise, an entered key is stored locally in `~/.local/state/omarchy-adventure/api-key.json`, inside an owner-only directory. Game saves are stored locally in `~/.local/state/omarchy-adventure.json`.

## Install

Validate the checked-out plugin:

```bash
omarchy plugin validate .
```

After pushing this directory to a trusted Git repository, install it with:

```bash
omarchy plugin add https://github.com/YOUR-ACCOUNT/omarchy-plugin-adv.git --enable
```

After installation, enable **Adventure** in the bar widget chooser, or open it directly:

```bash
omarchy-shell shell summon io.github.kszx11.adventure '{}'
```

The panel looks first for `OPENAI_API_KEY` in the Omarchy shell environment. If it is not set, an API key entered in the panel is remembered locally at `~/.local/state/omarchy-adventure/api-key.json`; that directory is created with owner-only access. Saves remain associated with a non-secret fingerprint of the key, so reopening the panel restores that key's adventure.

To make the key available through the environment, launch the Omarchy shell from a session that exports `OPENAI_API_KEY`. A key entered in the panel is the practical fallback when the shell was not launched with that variable.

## Verify core logic

The save migration, NPC matching, exit validation, and transcript serialization checks need only Node.js:

```bash
node tests/adventure-logic.test.js
```

## Remove

```bash
omarchy plugin remove io.github.kszx11.adventure
```

Removing the plugin leaves your local key and saves intact. To erase that data as well, remove `~/.local/state/omarchy-adventure/` and `~/.local/state/omarchy-adventure.json` yourself.
