# Adventure for Omarchy

A keyboard-first, AI-powered text adventure for Omarchy. Begin in any place and time, explore a living world, talk with memorable characters, uncover clues, and shape the story through your choices.

Requires an OpenAI API key with API billing; a ChatGPT subscription alone does not provide API access.

![Adventure gameplay preview](preview.png)

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
