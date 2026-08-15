
# Data layer for the review app. Pure functions, no Shiny reactivity here.
# ROOT is the repo root; the app runs from it, with drafts/, ideas/, and
# reviews/ as siblings of app.R.

`%||%` <- function(x, y) if (is.null(x)) y else x # nolint: object_name_linter.

ROOT <- normalizePath(".")
DRAFTS_DIR <- file.path(ROOT, "drafts")
IDEAS_DIR <- file.path(ROOT, "ideas")
REVIEWS_DIR <- file.path(ROOT, "reviews")
if (!dir.exists(REVIEWS_DIR)) dir.create(REVIEWS_DIR, recursive = TRUE)

# --- Markdown frontmatter / body parsing -----------------------------------

read_fm_body <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (length(lines) == 0 || lines[1] != "---") {
    return(list(frontmatter = character(0), body = paste(lines, collapse = "\n")))
  }
  closing <- which(lines[-1] == "---")
  if (length(closing) == 0) {
    return(list(frontmatter = character(0), body = paste(lines, collapse = "\n")))
  }
  end_idx <- closing[1] + 1
  fm <- lines[2:(end_idx - 1)]
  body_lines <- if (end_idx < length(lines)) lines[(end_idx + 1):length(lines)] else character(0)
  # Drop a single leading blank line right after the closing "---", the
  # templates always have one; keep any further blank lines as real content.
  if (length(body_lines) > 0 && body_lines[1] == "") body_lines <- body_lines[-1]
  list(frontmatter = fm, body = paste(body_lines, collapse = "\n"))
}

get_fm_field <- function(fm_lines, key) {
  pattern <- paste0("^", key, ":\\s*(.*)$")
  hit <- grep(pattern, fm_lines, value = TRUE)
  if (length(hit) == 0) return(NA_character_)
  val <- sub(pattern, "\\1", hit[1])
  val <- trimws(val)
  if (val == "") return(NA_character_)
  val
}

set_fm_field_in_file <- function(path, key, new_value) {
  lines <- readLines(path, warn = FALSE)
  pattern <- paste0("^", key, ":\\s*.*$")
  idx <- grep(pattern, lines)
  if (length(idx) >= 1) {
    lines[idx[1]] <- paste0(key, ": ", new_value)
    writeLines(lines, path)
  }
  invisible(NULL)
}

save_draft_body <- function(path, new_body) {
  fb <- read_fm_body(path)
  out <- c("---", fb$frontmatter, "---", "", strsplit(new_body, "\n")[[1]])
  writeLines(out, path)
}

split_paragraphs <- function(body) {
  parts <- strsplit(body, "\n\\s*\n+")[[1]]
  parts <- trimws(parts)
  parts[parts != ""]
}

# --- Draft discovery ---------------------------------------------------------

list_drafts <- function() {
  files <- list.files(DRAFTS_DIR, pattern = "\\.md$", recursive = TRUE, full.names = TRUE)
  if (length(files) == 0) {
    return(data.frame(content_id = character(0), platform = character(0),
                       project = character(0), title = character(0),
                       path = character(0), stringsAsFactors = FALSE))
  }
  rows <- lapply(files, function(f) {
    fb <- read_fm_body(f)
    content_id <- get_fm_field(fb$frontmatter, "content_id")
    platform <- get_fm_field(fb$frontmatter, "platform")
    project <- get_fm_field(fb$frontmatter, "project")
    title <- get_fm_field(fb$frontmatter, "title")
    if (is.na(title)) {
      idea_path <- file.path(IDEAS_DIR, paste0(content_id, ".md"))
      if (file.exists(idea_path)) {
        idea_fb <- read_fm_body(idea_path)
        wt <- get_fm_field(idea_fb$frontmatter, "working_title")
        if (!is.na(wt)) title <- wt
      }
    }
    if (is.na(title)) title <- content_id
    data.frame(content_id = content_id, platform = platform, project = project,
               title = title, path = f, stringsAsFactors = FALSE)
  })
  df <- do.call(rbind, rows)
  df[order(df$project, df$content_id), ]
}

# --- Review state (reviews/<content_id>.yml) --------------------------------

review_path <- function(content_id) file.path(REVIEWS_DIR, paste0(content_id, ".yml"))

default_review <- function(content_id, draft_path) {
  list(content_id = content_id,
       file = sub(paste0(ROOT, "/"), "", draft_path, fixed = TRUE),
       overall_status = "pending",
       comments = list())
}

load_review <- function(content_id, draft_path) {
  p <- review_path(content_id)
  if (!file.exists(p)) return(default_review(content_id, draft_path))
  r <- yaml::read_yaml(p)
  if (is.null(r$comments)) r$comments <- list()
  r
}

save_review <- function(review) {
  yaml::write_yaml(review, review_path(review$content_id))
  invisible(review)
}

add_comment <- function(content_id, draft_path, anchor, text, suggested_text = NULL) {
  review <- load_review(content_id, draft_path)
  next_id <- if (length(review$comments) == 0) 1 else {
    max(vapply(review$comments, function(c) c$id, numeric(1))) + 1
  }
  entry <- list(
    id = next_id,
    anchor = anchor,
    comment = text,
    status = "open",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  )
  if (!is.null(suggested_text)) entry$suggested_text <- suggested_text
  review$comments[[length(review$comments) + 1]] <- entry
  save_review(review)
}

# Find a comment by id (yaml round-trips ids as numeric; compare numerically).
find_comment_idx <- function(review, comment_id) {
  which(vapply(review$comments, function(c) {
    isTRUE(as.numeric(c$id) == as.numeric(comment_id))
  }, logical(1)))
}

resolve_comment <- function(content_id, draft_path, comment_id) {
  review <- load_review(content_id, draft_path)
  idx <- find_comment_idx(review, comment_id)
  if (length(idx) == 0) return(invisible(NULL))
  review$comments[[idx[1]]]$status <- "resolved"
  save_review(review)
}

# Apply a suggested rewrite: replace the paragraph matching the comment's
# anchor with its suggested_text in the actual draft file, then mark the
# comment resolved. A no-op (returns FALSE) if the anchor paragraph no longer
# exists verbatim (already edited elsewhere) or the comment has no suggestion.
apply_suggestion <- function(content_id, draft_path, comment_id) {
  review <- load_review(content_id, draft_path)
  idx <- find_comment_idx(review, comment_id)
  if (length(idx) == 0) return(invisible(FALSE))
  entry <- review$comments[[idx[1]]]
  if (is.null(entry$suggested_text)) return(invisible(FALSE))
  fb <- read_fm_body(draft_path)
  paras <- split_paragraphs(fb$body)
  match_idx <- which(paras == entry$anchor)
  if (length(match_idx) == 0) return(invisible(FALSE))
  paras[match_idx[1]] <- entry$suggested_text
  save_draft_body(draft_path, paste(paras, collapse = "\n\n"))
  review$comments[[idx[1]]]$status <- "resolved"
  save_review(review)
  invisible(TRUE)
}

set_overall_status <- function(content_id, draft_path, status) {
  review <- load_review(content_id, draft_path)
  review$overall_status <- status
  save_review(review)
  if (status == "accepted") {
    idea_path <- file.path(IDEAS_DIR, paste0(content_id, ".md"))
    if (file.exists(idea_path)) set_fm_field_in_file(idea_path, "status", "approved")
  }
  invisible(review)
}

markdown_inline <- function(text) {
  HTML(commonmark::markdown_html(text))
}
