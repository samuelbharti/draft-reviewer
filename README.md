# draft-review-app

A local Shiny app for reviewing Markdown drafts in the browser instead of in
an editor. Drafts live in `drafts/`, reviews are written to `reviews/` as
plain YAML, and everything is a file you can commit. No server, no database.

The repo ships with one sample draft (`drafts/blog/EXAMPLE-001-...`) so the
app has something to show on first run. Replace it with your own.

## Run it

From the repo root:

```bash
R -e "shiny::runApp('.', launch.browser = TRUE)"
```

Requires `shiny`, `bslib`, `yaml`, `commonmark` (all on CRAN). The optional
AI assistant additionally needs `ellmer` and `shinychat`; without them the
app still runs and the assistant panel shows setup instructions instead.

## What it does

- Lists every file in `drafts/*/*.md`, grouped by project, with a status
  badge. Drafts need YAML frontmatter with at least a `content_id`; see the
  sample draft for the full set of fields.
- Click a draft to see it rendered, split into paragraphs.
- Click "comment" under any paragraph to leave a note. Comments are anchored
  to the paragraph's exact text, not a line number, so they survive edits
  elsewhere in the file.
- **Accept** / **Reject** / **Request changes** set the draft's overall
  review status. Accept also flips the matching `ideas/<ID>.md` file's
  `status:` field to `approved`, if that file exists.
- **Edit** swaps the rendered view for the raw body text (frontmatter is kept
  intact automatically); **Save** writes it back to the actual draft file.

## The assistant

The Assistant button in the navbar opens a chat sidebar. Bring your own API
key (Google Gemini, OpenAI, or Anthropic), pasted in the chat settings or set
as an environment variable (`GEMINI_API_KEY`, `OPENAI_API_KEY`,
`ANTHROPIC_API_KEY`). Keys are held only in the session's server memory and
never written to disk.

The assistant can read the open draft, leave comments, and propose rewrites,
but only through the same functions the UI buttons call, so it can never do
anything a human click in this app could not. A suggested rewrite is staged
under the paragraph and changes nothing until you click Apply.

## Where the data goes

Every review lives in `reviews/<content_id>.yml`. See `reviews/README.md`
for the format. These files are the durable record; commit them like anything
else.
