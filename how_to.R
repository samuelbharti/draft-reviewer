# The "How to" page: static help content for the navbar. Plain bslib/shiny
# tags only, so it renders with the same packages the rest of the UI needs.

how_to_step <- function(...) tags$li(class = "mb-2", ...)

how_to_card <- function(title, ...) {
  bslib::card(
    class = "mb-4",
    bslib::card_header(h5(title, class = "mb-0")),
    bslib::card_body(...)
  )
}

how_to_page <- function() {
  div(
    class = "mx-auto py-4 px-3",
    style = "max-width: 760px;",
    h3("How I use this app"),
    p(
      "I write blog posts and social posts as Markdown files. I built this",
      "app to review those drafts in the browser, one paragraph at a time.",
      "Everything is a local file that I can commit. There is no server and",
      "no database."
    ),

    how_to_card(
      "Add a draft",
      tags$ol(
        how_to_step(
          "Create a Markdown file in ", tags$code("drafts/<project>/"), "."
        ),
        how_to_step(
          "Add YAML frontmatter with at least a ", tags$code("content_id"),
          ". Copy the frontmatter from the sample draft to start."
        ),
        how_to_step(
          "Reload the app. The draft appears in the left sidebar, grouped",
          " by project."
        )
      )
    ),

    how_to_card(
      "Review a draft",
      tags$ol(
        how_to_step("Click a draft in the left sidebar to open it."),
        how_to_step(
          "Click ", tags$em("comment"), " under a paragraph to leave a note.",
          " The note anchors to that paragraph's exact text, not a line",
          " number, so it survives edits elsewhere in the file."
        ),
        how_to_step(
          "Click ", tags$strong("Accept"), ", ", tags$strong("Reject"),
          ", or ", tags$strong("Request changes"),
          " to set the overall status. Accept also flips the matching ",
          tags$code("ideas/<ID>.md"), " file to approved, if that file exists."
        )
      )
    ),

    how_to_card(
      "Edit a draft",
      tags$ol(
        how_to_step(
          "Click ", tags$strong("Edit"),
          " to see the raw body text. The frontmatter stays intact."
        ),
        how_to_step(
          "Click ", tags$strong("Save"),
          " to write the text back to the draft file."
        )
      )
    ),

    how_to_card(
      "Use the assistant",
      tags$ol(
        how_to_step(
          "Click ", tags$strong("Assistant"), " in the navbar to open the chat."
        ),
        how_to_step(
          "Open ", tags$strong("Model & key"),
          " and paste an API key from Google Gemini, OpenAI, or Anthropic.",
          " An environment variable such as ", tags$code("GEMINI_API_KEY"),
          " also works."
        ),
        how_to_step("Click ", tags$strong("Connect"), "."),
        how_to_step(
          "Ask for a rewrite of a paragraph. The assistant stages a",
          " suggestion under that paragraph and waits."
        ),
        how_to_step(
          "Click ", tags$strong("Apply"),
          " to accept the suggestion, or dismiss it. Nothing changes in the",
          " file until I click Apply."
        )
      ),
      p(
        class = "text-muted small mb-0",
        "The key stays in this session's server memory. It is never written",
        " to disk. The assistant can only call the same functions the UI",
        " buttons call."
      )
    ),

    how_to_card(
      "Find the review data",
      p(
        "Every review lives in ", tags$code("reviews/<content_id>.yml"),
        " as plain YAML. These files are the durable record. I commit them",
        " like anything else. See ", tags$code("reviews/README.md"),
        " for the format."
      )
    )
  )
}
