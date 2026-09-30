# People mine: LibreFinTech-Claude-Code

What people who use the product said in its own public places: issues, issue comments, discussions, pull requests, and forks that changed something. Optional third pantry source; a product with no outside voices yet leaves the Hits table empty and says so.

## How this fills

1. List the product's own repos (the kitchen law names them).
2. Read what people outside the maintainers wrote since the last run: issues (the `feedback` label first), issue comments, discussions and their comments, pull requests, and forks with commits ahead of the default branch.
3. One row per voice. Quote a short snippet and link the exact issue, comment, discussion, PR or commit. Say whether they gave credit consent when the source has a consent box.
4. Tag each row with the capability it is about, in the same words as the competitor map's matrix, so the queue can cite it next to competitor and X rows.
5. Never count stars as feedback, never infer sentiment the person did not state, never paraphrase a number. Maintainers' own issues are not voices.
6. Save as `YYYY-MM-DD-people-mine.md` beside the other dated files (keep this TEMPLATE).

## Hits

| Repo | Kind (bug/feature/question/praise/contribution) | Snippet | Link | Theme (matrix capability) | Credit consent |
|------|--------------------------------------------------|---------|------|---------------------------|----------------|

No outside voices. Every issue, comment and pull request in the repo is by the maintainer (HermeticOrmus), and no fork carries a change, so this table is empty on purpose.

## Read log (what we read)

- Repo metadata (`gh api repos/HermeticOrmus/LibreFinTech-Claude-Code`), read 2026-09-30: 1 star, 1 fork, Discussions disabled. Stars are not feedback and are recorded only for context.
- Issues and pull requests, all states (`gh api "repos/HermeticOrmus/LibreFinTech-Claude-Code/issues?state=all"`): #1 (issue, closed), #2 (PR, closed), #3 (issue, open). All three opened by HermeticOrmus, the maintainer. No `feedback`-labeled issues exist.
- Issue comments (`gh api repos/HermeticOrmus/LibreFinTech-Claude-Code/issues/comments`): 1 comment (5914882849, on #1), by HermeticOrmus.
- Pull request review comments (`gh api repos/HermeticOrmus/LibreFinTech-Claude-Code/pulls/comments`): none.
- Discussions (GraphQL `hasDiscussionsEnabled`, `discussions`): disabled, 0 discussions.
- Forks (`gh api repos/HermeticOrmus/LibreFinTech-Claude-Code/forks`): 1 fork. `gh api repos/HermeticOrmus/LibreFinTech-Claude-Code/compare/main...<fork-owner>:LibreFinTech-Claude-Code:main` reports 0 commits ahead and 18 behind, so it changed nothing and is not a voice.
- Bots: none seen in any of the above.
