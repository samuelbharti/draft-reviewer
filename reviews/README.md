# reviews/

One YAML file per content id (`<ID>.yml`, matching `ideas/<ID>.md`), written
by the app. Not hand-edited under normal use, but plain YAML, safe to read or
fix by hand if needed.

```yaml
content_id: EXAMPLE-001
file: drafts/blog/EXAMPLE-001-a-sample-post-to-review.md
overall_status: pending   # pending | accepted | rejected | changes_requested
comments:
  - id: 1
    anchor: "the exact paragraph text this comment is attached to"
    comment: "what to change, and why"
    status: open           # open | resolved
    created_at: "2026-08-11T10:03:00"
```

`anchor` is the paragraph's literal text, not a line number, so a comment
stays attached to the right spot even after unrelated edits shift line
numbers around it. It only breaks if that exact paragraph itself gets
rewritten, at which point the comment is presumably resolved anyway.

To act on open comments: read every file here with an `open` comment or an
`overall_status` of `changes_requested`, apply the requested change to the
draft named in `file`, then set that comment's `status` to `resolved`.
