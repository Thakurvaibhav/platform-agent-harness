# Confluence (Atlassian MCP) Editing Learnings

Surgical-edit mechanics for approved Confluence pages via the Atlassian MCP.

See also: `learnings-code-review.md`, `learnings-agent-workflow.md`

## Edit mechanic

1. **`updateConfluencePage` REPLACES the entire body** (it is not a patch). Safe surgical-edit flow: `getConfluencePage contentFormat=html` -> write the fetched body to a temp file -> `cp` to an `_edited` copy -> make unique-string Edits per change -> update with `contentFormat=html`. On the update call pass ONLY `cloudId`, `pageId`, `body`, `contentFormat=html`, `versionMessage` -- OMIT `title`/`parentId`/`spaceId` so you cannot accidentally rename or reparent (version auto-increments). HTML round-trip is safe for tables/code/panels/mentions/inline-comment annotation spans IF you pass the EXACT fetched HTML back.

2. **Confluence storage stores newlines inside `<pre><code>` blocks as the LITERAL two-character sequence backslash-n, not a real newline.** On round-trip html->html edits you MUST preserve that exact form, or you get phantom diffs / corrupted code blocks. Apply a backslash-n -> real-newline normalization to BOTH sides before diffing, and re-emit the literal form on write.

## Proving the edit (verification integrity)

3. **The structural diff MUST run on BYTES THE SERVER RETURNED, not on your submission.** Trap: `cp page_edited.html page_live.html` then diffing = comparing the submission to itself (circular, proves nothing). Correct: write BOTH the first-fetch body (true vN) AND a RE-FETCH body (true vN+1) to files, apply the same normalization to each, and diff true-vN+1 vs true-vN.

4. **`diff` is useless on a Confluence body -- it is ONE line with no newlines.** Use Python `difflib.SequenceMatcher` on `re.split(r'(?<=>)')` tokens for a structural region diff. Verify round-trip safety for rich content by counting `data-annotation-id` / `data-type=mention` / `data-type=status` / `<table` / `<pre` occurrences before vs after -- they must match.

## Collision-safe anchoring

5. **NEVER replace a bare substring whose text ALSO appears in an already-corrected region.** Anchor each `old_string` on full surrounding context and assert match-count == 1 in Python before `replace()`. When a status word is non-unique (e.g. "Not Started" appears 12 times), combine a row's task + status cells into ONE contiguous `old_string`. Post-edit guard: assert the PROTECTED-string count is unchanged rather than global-absence (which falsely flags the kept copy).

## MCP tool availability

6. **Atlassian/Confluence MCP tools (create AND update) only work in the PARENT agent context -- sub-agents prepare the page body and return it for the parent to make the call.** This is an instance of the general MCP-parent-only rule; canonical statement in `learnings-agent-workflow.md` #31.
