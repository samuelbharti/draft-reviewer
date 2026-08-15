library(shiny)
library(bslib)
source("helpers.R")
source("review_tools.R")
source("modules/byok_chat_mod.R")

STATUS_COLORS <- c(
  pending = "secondary",
  accepted = "success",
  rejected = "danger",
  changes_requested = "warning"
)

status_badge <- function(status) {
  cls <- STATUS_COLORS[[status]]
  if (is.null(cls)) cls <- "secondary"
  span(class = paste("badge", paste0("bg-", cls)), status)
}

# The assistant is a dedicated, closed-by-
# default bslib sidebar with an id, toggled from a navbar button via
# bslib::sidebar_toggle() in the server -- not a plain always-visible column.
# Organic theme: warm cream background, clay/terracotta primary, sage-green
# secondary, a rounded humanist sans for body text and a soft organic serif
# for headings, generous rounding on cards/sidebars instead of square corners.
organic_theme <- bs_theme(
  version = 5,
  bg = "#FBF7F0",
  fg = "#3A2E26",
  primary = "#8C6A4E",
  secondary = "#7A8450",
  success = "#6B8E4E",
  info = "#6E8B8A",
  warning = "#D98E4A",
  danger = "#B5533C",
  base_font = font_google("Nunito"),
  heading_font = font_google("Fraunces", wght = "300..700"),
  "border-radius" = "0.9rem",
  "card-border-radius" = "1rem"
) |>
  bs_add_rules(c(
    ".card, .sidebar, .navbar { box-shadow: 0 2px 10px rgba(58, 46, 38, 0.08); }",
    # The page's <main> is a flex column with a 1rem gap and 1rem bottom
    # padding, so the footer needs negative margins to sit tight instead of
    # floating in a ~60px band.
    ".app-footer { font-size: 0.75rem; line-height: 1.4; padding: 0;",
    "  margin-top: -0.75rem; margin-bottom: -0.5rem; }"
  ))

ui <- page_navbar(
  title = "Content review",
  theme = organic_theme,
  sidebar = sidebar(width = 340, uiOutput("draft_list")),
  header = tags$style(HTML(
    # Belt-and-braces: bslib's
    # own sidebar layout already keeps this pinned, this just guarantees it
    # even if a parent container's fill behavior doesn't fully cooperate.
    ".review-chat-sidebar { position: sticky; top: 0.5rem; }"
  )),
  nav_panel(
    title = "Drafts",
    value = "drafts",
    layout_sidebar(
      fillable = FALSE,
      sidebar = sidebar(
        id = "assistant_dock",
        position = "right",
        width = 600,
        open = "closed",
        title = "Review assistant",
        class = "review-chat-sidebar",
        byok_chat_ui(
          "review_chat",
          title = NULL,
          subtitle = paste(
            "Reads the draft you have open. Comments and suggested rewrites",
            "land under the paragraph; suggestions need your Apply click."
          ),
          providers = c("gemini", "openai", "anthropic"),
          height = "75vh",
          placeholder = "Ask about this draft, or ask for a change..."
        )
      ),
      uiOutput("main_panel")
    )
  ),
  nav_spacer(),
  nav_item(
    actionButton(
      "toggle_assistant",
      "Assistant",
      icon = icon("comments"),
      class = "btn-sm btn-outline-primary my-1"
    )
  ),
  footer = div(
    class = "app-footer text-center text-muted",
    HTML("&copy; 2026 "),
    tags$a(
      href = "https://samuelbharti.com",
      target = "_blank",
      rel = "noopener",
      class = "link-secondary",
      "Samuel Bharti"
    ),
    " · ",
    tags$a(
      href = "https://github.com/samuelbharti/draft-reviewer/blob/main/LICENSE",
      target = "_blank",
      rel = "noopener",
      class = "link-secondary",
      "MIT license"
    )
  )
)

server <- function(input, output, session) {
  refresh <- reactiveVal(0)
  selected <- reactiveVal(NULL)
  edit_mode <- reactiveVal(FALSE)
  comment_target <- reactiveVal(NULL)

  drafts <- reactive({
    refresh()
    list_drafts()
  })

  current_row <- reactive({
    df <- drafts()
    cid <- selected()
    if (is.null(cid) || !(cid %in% df$content_id)) return(NULL)
    df[df$content_id == cid, , drop = FALSE][1, ]
  })

  observeEvent(input$toggle_assistant, {
    bslib::sidebar_toggle("assistant_dock", session = session)
  })

  # The review assistant: a stable module instance outside main_panel's
  # renderUI, so switching drafts or saving edits doesn't reset the
  # conversation. Its tools read the CURRENT selection live on every call.
  byok_chat_server(
    "review_chat",
    system_prompt = REVIEW_CHAT_SYSTEM_PROMPT,
    tools = review_chat_tools(selected, current_row, refresh),
    providers = c("gemini", "openai", "anthropic")
  )

  # --- Sidebar: draft list grouped by project, clickable via inline JS -----

  output$draft_list <- renderUI({
    df <- drafts()
    if (nrow(df) == 0) return(div(class = "text-muted small", "No drafts found in drafts/."))
    if (is.null(selected()) || !(selected() %in% df$content_id)) selected(df$content_id[1])

    projects <- unique(df$project)
    tagList(lapply(projects, function(proj) {
      sub <- df[df$project == proj, , drop = FALSE]
      tagList(
        h6(proj, class = "mt-3 text-muted text-uppercase small"),
        lapply(seq_len(nrow(sub)), function(i) {
          row <- sub[i, ]
          review <- load_review(row$content_id, row$path)
          is_sel <- identical(selected(), row$content_id)
          div(
            class = paste("p-2 rounded mb-1", if (is_sel) "border border-primary" else "border"),
            style = "cursor:pointer;",
            onclick = sprintf(
              "Shiny.setInputValue('select_draft', '%s', {priority: 'event'})",
              row$content_id
            ),
            div(
              class = "d-flex justify-content-between align-items-center",
              span(class = "small fw-semibold", paste0(row$content_id, " · ", row$platform)),
              status_badge(review$overall_status)
            ),
            div(class = "small text-truncate", style = "max-width: 280px;", row$title)
          )
        })
      )
    }))
  })

  observeEvent(input$select_draft, {
    selected(input$select_draft)
    edit_mode(FALSE)
  })

  # --- Main panel: header, actions, body (view or edit) --------------------

  output$main_panel <- renderUI({
    row <- current_row()
    if (is.null(row)) return(div(class = "text-muted", "Select a draft from the sidebar."))

    review <- load_review(row$content_id, row$path)
    fb <- read_fm_body(row$path)

    header <- div(
      class = "d-flex justify-content-between align-items-start mb-3",
      div(
        h4(row$title),
        p(class = "text-muted mb-0", paste(row$project, "·", row$platform, "·", row$content_id))
      ),
      status_badge(review$overall_status)
    )

    actions <- div(
      class = "mb-3 d-flex gap-2",
      actionButton("btn_accept", "Accept", class = "btn-success btn-sm"),
      actionButton("btn_reject", "Reject", class = "btn-danger btn-sm"),
      actionButton("btn_changes", "Request changes", class = "btn-warning btn-sm"),
      actionButton("btn_edit", if (edit_mode()) "Cancel edit" else "Edit", class = "btn-outline-secondary btn-sm")
    )

    body_ui <- if (edit_mode()) {
      tagList(
        textAreaInput("edit_box", NULL, value = fb$body, rows = 24, width = "100%"),
        actionButton("btn_save", "Save", class = "btn-primary btn-sm mt-2")
      )
    } else {
      paras <- split_paragraphs(fb$body)
      if (length(paras) == 0) {
        div(class = "text-muted", "This draft has no body text.")
      } else {
        tagList(lapply(seq_along(paras), function(i) {
          para_comments <- Filter(function(c) identical(c$anchor, paras[i]), review$comments)
          has_open <- any(vapply(para_comments, function(c) identical(c$status, "open"), logical(1)))
          div(
            class = "mb-3 p-2 border-start",
            style = paste0("border-width: 3px !important; border-color: ",
                            if (has_open) "#f0ad4e" else "transparent", ";"),
            div(markdown_inline(paras[i])),
            tags$a(
              href = "#", class = "small text-muted",
              onclick = sprintf(
                "Shiny.setInputValue('comment_click', %d, {priority: 'event'}); return false;", i
              ),
              "\U0001F4AC comment"
            ),
            if (length(para_comments) > 0) {
              tagList(lapply(para_comments, function(c) {
                if (!is.null(c$suggested_text) && identical(c$status, "open")) {
                  div(
                    class = "small mt-1 ms-3 p-2 bg-light rounded",
                    div(class = "text-muted", c$comment),
                    div(class = "fst-italic", paste0("Suggested: ", c$suggested_text)),
                    tags$a(
                      href = "#", class = "small",
                      onclick = sprintf(
                        "Shiny.setInputValue('apply_click', %s, {priority: 'event'}); return false;",
                        c$id
                      ),
                      "✅ Apply"
                    ),
                    " · ",
                    tags$a(
                      href = "#", class = "small text-muted",
                      onclick = sprintf(
                        "Shiny.setInputValue('resolve_click', %s, {priority: 'event'}); return false;",
                        c$id
                      ),
                      "dismiss"
                    )
                  )
                } else {
                  div(
                    class = "small mt-1 ms-3",
                    paste0(if (identical(c$status, "open")) "\U0001F7E1 " else "✅ ", c$comment)
                  )
                }
              }))
            }
          )
        }))
      }
    }

    tagList(header, actions, hr(), body_ui)
  })

  # --- Action buttons --------------------------------------------------------

  observeEvent(input$btn_edit, edit_mode(!edit_mode()))

  observeEvent(input$btn_save, {
    row <- current_row()
    if (is.null(row)) return()
    save_draft_body(row$path, input$edit_box)
    edit_mode(FALSE)
    refresh(refresh() + 1)
    showNotification(paste("Saved", row$content_id), type = "message", duration = 2)
  })

  observeEvent(input$btn_accept, {
    row <- current_row()
    if (is.null(row)) return()
    set_overall_status(row$content_id, row$path, "accepted")
    refresh(refresh() + 1)
  })

  observeEvent(input$btn_reject, {
    row <- current_row()
    if (is.null(row)) return()
    set_overall_status(row$content_id, row$path, "rejected")
    refresh(refresh() + 1)
  })

  observeEvent(input$btn_changes, {
    row <- current_row()
    if (is.null(row)) return()
    set_overall_status(row$content_id, row$path, "changes_requested")
    refresh(refresh() + 1)
  })

  # --- Comment modal (manual, human-typed comments) --------------------------

  observeEvent(input$comment_click, {
    comment_target(input$comment_click)
    showModal(modalDialog(
      title = "Add a comment",
      textAreaInput("comment_text", "What should change, and why", rows = 4, width = "100%"),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("btn_submit_comment", "Submit", class = "btn-primary")
      )
    ))
  })

  observeEvent(input$btn_submit_comment, {
    row <- current_row()
    idx <- comment_target()
    if (is.null(row) || is.null(idx) || is.null(input$comment_text) || trimws(input$comment_text) == "") {
      removeModal()
      return()
    }
    fb <- read_fm_body(row$path)
    paras <- split_paragraphs(fb$body)
    if (idx <= length(paras)) {
      add_comment(row$content_id, row$path, paras[idx], input$comment_text)
    }
    removeModal()
    refresh(refresh() + 1)
  })

  # --- Suggested-rewrite apply / dismiss (from the assistant) -----------------

  observeEvent(input$apply_click, {
    row <- current_row()
    if (is.null(row)) return()
    applied <- apply_suggestion(row$content_id, row$path, input$apply_click)
    if (isTRUE(applied)) {
      showNotification("Suggestion applied.", type = "message", duration = 2)
    } else {
      showNotification(
        "Couldn't apply -- that paragraph may have already changed.",
        type = "warning", duration = 3
      )
    }
    refresh(refresh() + 1)
  })

  observeEvent(input$resolve_click, {
    row <- current_row()
    if (is.null(row)) return()
    resolve_comment(row$content_id, row$path, input$resolve_click)
    refresh(refresh() + 1)
  })
}

shinyApp(ui, server)
