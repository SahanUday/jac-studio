# 0076 — Resolve chat file attachments server-side before sending

- **Date**: 2026-09-15
- **Status**: accepted

## Decision

`claude_code_client.jac`'s `_build_prompt_with_attachments` reads each attached file's real content
and prepends it to the prompt server-side, before the launcher ever sees it — never a client-side
`@file` marker the launcher would have to parse out of raw text. Each file is capped at
`_ATTACHMENT_MAX_CHARS`, truncated with a visible note. `ai_chat.jac`'s own message log still shows
the user's original, unaugmented prompt.

## Why

Matches real VS Code's own file-attachment picker (`chatDynamicVariables.ts`/
`chatAttachmentModel.ts`, confirmed against a real checkout): a picked file becomes a resolved
attachment before the request goes out, never a hope that inline text gets specially parsed
downstream. An unbounded attachment is a real risk (a large file can blow out a turn's context) the
picker itself has no reason to prevent a user from triggering.

## Consequences

Any future attachment-like input (a pasted URL, a directory) should resolve to real content at the
same point in the pipeline — server-side, capped, before the launcher call — rather than growing a
second parsing convention. The visible chat log staying unaugmented is deliberate: don't let
attachment size make the conversation history unreadable.
