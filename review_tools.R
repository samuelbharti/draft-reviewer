# Tools for the review assistant. The rule:
# every write tool calls the exact function the matching UI
# control calls (add_comment / set_overall_status), so the assistant can
# never do anything a human click in this app couldn't also do. It never
# writes the draft file directly -- suggest_rewrite only stages a suggestion
# next to the paragraph; applying it still takes a click (see app.R).
#
# `selected` and `current_row_fn` are the server's own reactiveVal/reactive
# for "which draft is open right now"; reads are wrapped in isolate() since
# tool calls run outside a normal reactive context. `refresh` is the
# reactiveVal that forces the UI to re-render after a tool call changes data.

REVIEW_CHAT_SYSTEM_PROMPT <- paste(
  "You are a review assistant inside a personal tool for reviewing drafts",
  "of blog posts, LinkedIn posts, and Bluesky posts about the user's own",
  "software projects.",
  "Always call get_current_draft first, every turn, to see the current",
  "paragraphs and any existing comments before doing anything else --",
  "paragraph numbers can shift between turns if the user has edited or",
  "applied a suggestion.",
  "When the user asks you to fix, shorten, clarify, or otherwise change a",
  "specific piece of text, call suggest_rewrite with the exact paragraph",
  "number and your proposed replacement text. Do not just describe the",
  "change in prose -- propose the actual replacement.",
  "When the user leaves feedback that is not a specific rewrite (a note,",
  "a question, a flag), use add_review_comment instead.",
  "Only call set_review_status when the user explicitly asks you to accept,",
  "reject, or request changes on the draft as a whole, not as a side effect",
  "of leaving a comment.",
  "Never invent facts, numbers, or claims about the underlying project that",
  "are not already present in the draft. If a requested change would",
  "require a fact the draft does not contain, say so instead of making one",
  "up."
)

review_chat_tools <- function(selected, current_row_fn, refresh) {
  get_ctx <- function() {
    row <- shiny::isolate(current_row_fn())
    if (is.null(row)) return(NULL)
    review <- load_review(row$content_id, row$path)
    fb <- read_fm_body(row$path)
    paras <- split_paragraphs(fb$body)
    list(row = row, review = review, paras = paras)
  }

  bump_refresh <- function() refresh(shiny::isolate(refresh()) + 1)

  tool_get_draft <- ellmer::tool(
    function() {
      ctx <- get_ctx()
      if (is.null(ctx)) return("No draft is currently selected in the app.")
      numbered <- paste0(seq_along(ctx$paras), ". ", ctx$paras)
      comments <- if (length(ctx$review$comments) == 0) {
        "No comments yet."
      } else {
        paste(vapply(ctx$review$comments, function(c) {
          extra <- if (!is.null(c$suggested_text)) {
            paste0(" | suggested: ", c$suggested_text)
          } else {
            ""
          }
          sprintf(
            "[id %s, %s] on \"%s...\": %s%s",
            c$id, c$status, substr(c$anchor, 1, 40), c$comment, extra
          )
        }, character(1)), collapse = "\n")
      }
      paste0(
        "Draft ", ctx$row$content_id, " (", ctx$row$project, ", ",
        ctx$row$platform, ")\n",
        "Title: ", ctx$row$title, "\n",
        "Overall status: ", ctx$review$overall_status, "\n\n",
        "Paragraphs:\n", paste(numbered, collapse = "\n\n"), "\n\n",
        "Existing comments:\n", comments
      )
    },
    paste(
      "Read the currently selected draft: its numbered paragraphs, overall",
      "review status, and any existing comments. Call this first, every",
      "turn, before commenting, suggesting a change, or changing status."
    ),
    name = "get_current_draft"
  )

  tool_add_comment <- ellmer::tool(
    function(paragraph_number, comment) {
      ctx <- get_ctx()
      if (is.null(ctx)) return("No draft is currently selected.")
      idx <- suppressWarnings(as.integer(paragraph_number))
      if (is.na(idx) || idx < 1 || idx > length(ctx$paras)) {
        return(paste0(
          "Invalid paragraph number. This draft has ", length(ctx$paras),
          " paragraphs."
        ))
      }
      add_comment(ctx$row$content_id, ctx$row$path, ctx$paras[idx], comment)
      bump_refresh()
      paste0("Comment added to paragraph ", idx, ".")
    },
    paste(
      "Leave a review comment on a specific paragraph of the currently",
      "selected draft, exactly like clicking the comment button in the UI.",
      "Use this for feedback that is not a specific rewrite."
    ),
    arguments = list(
      paragraph_number = ellmer::type_integer(
        "The 1-based paragraph number from get_current_draft's list."
      ),
      comment = ellmer::type_string("What should change, and why.")
    ),
    name = "add_review_comment"
  )

  tool_suggest_rewrite <- ellmer::tool(
    function(paragraph_number, new_text, reason) {
      ctx <- get_ctx()
      if (is.null(ctx)) return("No draft is currently selected.")
      idx <- suppressWarnings(as.integer(paragraph_number))
      if (is.na(idx) || idx < 1 || idx > length(ctx$paras)) {
        return(paste0(
          "Invalid paragraph number. This draft has ", length(ctx$paras),
          " paragraphs."
        ))
      }
      add_comment(
        ctx$row$content_id, ctx$row$path, ctx$paras[idx], reason,
        suggested_text = new_text
      )
      bump_refresh()
      paste0(
        "Suggestion added to paragraph ", idx, ". This does not change the",
        " file -- the user has to click Apply in the draft view."
      )
    },
    paste(
      "Propose exact replacement text for one paragraph. This does NOT",
      "change the file: it shows the suggestion under that paragraph with",
      "an Apply button the user clicks to actually accept it."
    ),
    arguments = list(
      paragraph_number = ellmer::type_integer(
        "The 1-based paragraph number from get_current_draft's list."
      ),
      new_text = ellmer::type_string(
        "The exact replacement text for this paragraph."
      ),
      reason = ellmer::type_string("One short sentence on why.")
    ),
    name = "suggest_rewrite"
  )

  tool_set_status <- ellmer::tool(
    function(status) {
      ctx <- get_ctx()
      if (is.null(ctx)) return("No draft is currently selected.")
      valid <- c("pending", "accepted", "rejected", "changes_requested")
      if (!status %in% valid) {
        return(paste0("status must be one of: ", paste(valid, collapse = ", ")))
      }
      set_overall_status(ctx$row$content_id, ctx$row$path, status)
      bump_refresh()
      paste0("Overall status set to ", status, ".")
    },
    paste(
      "Set the overall review status of the currently selected draft,",
      "exactly like clicking Accept / Reject / Request changes in the UI.",
      "Only call this when the user explicitly asks for a status change."
    ),
    arguments = list(
      status = ellmer::type_string(
        "One of: pending, accepted, rejected, changes_requested."
      )
    ),
    name = "set_review_status"
  )

  list(tool_get_draft, tool_add_comment, tool_suggest_rewrite, tool_set_status)
}
