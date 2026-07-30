# amd-notes

Daily working notes for AMD compiler/runtime work: what I did, what broke, and
the commands worth keeping.

## Layout

```text
daily/YYYY-MM-DD.md   one file per working day
topics/<name>.md      longer-lived notes that outgrow a daily entry
```

## Daily entry

Each day gets one file in `daily/`, named by date:

```bash
$EDITOR daily/$(date +%F).md
```

Rough shape of an entry:

```markdown
# 2026-07-30

## Done

## In progress

## Blocked / open questions

## Commands
```

Keep build/repro commands verbatim so they can be pasted back later. When a
topic keeps reappearing across days, move it into `topics/` and link to it from
the daily entries.
