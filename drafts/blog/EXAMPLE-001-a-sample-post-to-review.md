---
content_id: EXAMPLE-001
project: example
platform: blog
title: A sample post to review
status: draft
---

This is a sample draft. It exists so the review app has something to show the
first time you run it. Replace it with your own drafts, or point the app at a
directory that already has some.

Each block of text separated by a blank line is a paragraph. The app renders
every paragraph with its own comment link, so feedback attaches to the exact
text it is about instead of a line number.

Try it: click the comment link under this paragraph and leave a note. The note
lands in reviews/EXAMPLE-001.yml, anchored to this paragraph's literal text.
Edit any other paragraph and the note stays attached to this one.

The Accept, Reject, and Request changes buttons set the overall review status
for the whole draft. Accept also flips the status field in
ideas/EXAMPLE-001.md to approved, if that file exists.

If you connect an API key in the assistant sidebar, you can also ask for a
rewrite of a paragraph. The assistant stages a suggestion under the paragraph
and waits. Nothing changes in this file until you click Apply.
