# The assistant's prompts

Two different things live under `prompts/`.

## `prompts/system/` - the shipped system prompt

The prompt the assistant runs with, one file per section. `Config.qml` lists them
in `promptSectionFiles`, reads them at load and joins them with a blank line
between each; the result is `Config.options.ai.systemPrompt`. Editing a file here
changes the prompt on this install, and the sections are numbered so a diff shows
which part of the assistant's behaviour moved.

`{AINAME}`, `{OWNER}`, `{KERNEL}` and the rest are filled in per request from
`promptSubstitutions` in `services/Ai.qml`. `{MEMORY}` expands to the memory
instructions plus whatever was recalled for the turn, and to nothing at all when
the memory daemon is off - so never write a section that assumes memory exists.

`tests/test_ai_prompt_compose.sh` rebuilds the prompt the same way and compares it
against a committed digest. Changing a section fails that test on purpose: the
prompt is retested against the local `gemma4-e4b` before the digest moves, because
this model is 4 billion parameters and does not forgive a sloppy instruction. It
also holds the prompt under 4000 characters. Every byte here shares a context
window with a 3900-byte tool array, and past roughly 1461 bytes of tools the model
starts dropping digits out of the numbers it repeats back - including the kernel
version and battery percentage this prompt hands it.

## `prompts/*.md` - whole-prompt replacements

What `/prompt` in the sidebar offers. Picking one replaces the composed prompt
entirely and writes the result into `~/.config/koompi/config.json`, where it then
shadows everything in `prompts/system/`. Settings > AI says which of the two is
live and offers the shipped one back.

- `NoPrompt.md` - empty. The raw model, no instructions at all.
- `Minimal.md` - four lines. For when the tool array needs the context more than
  the instructions do.

Your own go in `~/.config/koompi/ai/prompts/`; they show up in the same list.

The prompts that used to sit here came from
[illogical-impulse](https://github.com/end-4/dots-hyprland) by end-4, plus two
personas copied from other assistants. None of them knew about this machine, the
tools or the memory system, so they were removed rather than kept as decoration.
