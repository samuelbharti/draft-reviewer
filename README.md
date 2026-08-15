# draft-review-app

I write blog posts and social posts as Markdown files. I built this local
Shiny app to review those drafts in the browser instead of in an editor.
Drafts live in `drafts/`. Reviews go to `reviews/` as plain YAML. Everything
is a file I can commit. There is no server and no database.

The repo ships with one sample draft (`drafts/blog/EXAMPLE-001-...`) so the
app has something to show on first run. Replace it with your own.

## Run it

From the repo root:

```bash
R -e "shiny::runApp('.', launch.browser = TRUE)"
```

You need `shiny`, `bslib`, `yaml`, and `commonmark`, all on CRAN. The
optional AI assistant also needs `ellmer` and `shinychat`. Without those two,
the app still runs and the assistant panel shows setup instructions instead.

The **How to** page in the navbar walks through every step inside the app.

## What it does

- It lists every file in `drafts/*/*.md`, grouped by project, with a status
  badge. A draft needs YAML frontmatter with at least a `content_id`. The
  sample draft shows the full set of fields.
- Click a draft to see it rendered, split into paragraphs.
- Click "comment" under any paragraph to leave a note. Comments anchor to
  the paragraph's exact text, not a line number, so they survive edits
  elsewhere in the file.
- **Accept**, **Reject**, and **Request changes** set the draft's overall
  review status. Accept also flips the matching `ideas/<ID>.md` file's
  `status:` field to `approved`, if that file exists.
- **Edit** swaps the rendered view for the raw body text. The frontmatter
  stays intact. **Save** writes the text back to the draft file.

## The assistant

The Assistant button in the navbar opens a chat sidebar. Bring your own API
key for Google Gemini, OpenAI, or Anthropic. Paste it in the chat settings,
or set the matching environment variable (`GEMINI_API_KEY`, `OPENAI_API_KEY`,
`ANTHROPIC_API_KEY`). The key stays in the session's server memory and is
never written to disk.

The assistant can read the open draft, leave comments, and propose rewrites.
It works only through the same functions the UI buttons call, so it can never
do anything a human click in this app could not. A suggested rewrite stays
staged under the paragraph and changes nothing until I click Apply.

## Where the data goes

Every review lives in `reviews/<content_id>.yml`. See `reviews/README.md`
for the format. These files are the durable record. I commit them like
anything else.

## Development

I use [pre-commit](https://pre-commit.com) to keep secrets and clutter out of
the repo. After cloning, run:

```bash
pre-commit install
```

The hooks run [gitleaks](https://github.com/gitleaks/gitleaks) plus basic
hygiene checks on every commit. New features go on a branch, with a pull
request titled `feat: ...`.

## License

MIT. See [LICENSE](LICENSE).
