# Usage Statistics

The statistics button in the title bar opens this page. It answers specific questions: how many calls did I make, how many failed, how many tokens did I burn, which project costs the most, and how much plan quota is left.

## Where the numbers come from

Zeta doesn't estimate and doesn't do its own metering. Every number on this page comes from one of two places:

1. **The history each assistant keeps on your machine** — Codex under `~/.codex`, Grok under `~/.grok`, Claude Code in its own directory. Zeta scans those files and aggregates them.
2. **Quota information the assistant reports** — plan name, usage windows, reset times.

Because it reads the assistants' own history, the statistics **include calls you made in the terminal**, not just ones you started from Zeta.

Anything an assistant doesn't provide, Zeta doesn't invent. If an assistant reports no token counts, the page says "not supported" rather than showing an estimate.

## Filters

Three controls at the top:

- **Time range** — today, last 7 days, last 30 days, last 90 days, this month, last month, or a custom range.
- **Agent** — one assistant, or all of them.
- **Model** — one model, or all of them.

The last-updated time and a refresh button sit in the top right.

## Overview

Four figures across the top:

- **Calls** — total for the period, compared against the previous period of the same length.
- **Success rate**
- **Token usage** — tokens are how models meter and bill work, roughly a fragment of text each. Shown as a total, broken down into input, output and reasoning.
- **Average response time** — from sending the request to receiving the first token.

### How the success rate is calculated

- One **turn** counts as one call.
- The denominator only includes calls that finished: completed, failed, or cancelled. **Running and unknown states are excluded.**
- The numerator is "completed". Both "failed" and "cancelled" count against you.

If this number disagrees with what you see elsewhere, the denominator is usually why.

### Response time sample count

Only calls where the assistant explicitly reported a time-to-first-token are counted; missing samples are not approximated. The page shows how many valid samples there were — with a small sample count, treat the average with caution.

## Trend chart

The chart in the middle adjusts its granularity to the range you selected (hourly for a single day, daily for 90 days). You can switch which metric it plots: calls, success rate, token spend, average response time, or task duration.

## Detail tabs

Four tabs below the chart.

**Agent statistics** — calls, success rate, tokens, failures and average duration per assistant.

**Model statistics** — tokens consumed per model and its share of the total, broken down into total, input, cached input, output and reasoning.

**Projects** — totals per project with last-used times. Click a project to focus the whole page on it.

**Tasks** — every call, listed and paginated. Click one for its details:

- Project name and full path
- Source — which client started the call
- Start time, duration, time to first response
- Token breakdown: total, input, cached, output, reasoning
- Status; on failure, an **error category** (account / runtime / network / timeout / cancelled / other), the specific reason, and a **suggested next step**

The task list shows **statistics metadata only** — never your prompts, the assistant's replies, or tool output. Zeta doesn't store those at all (see [Data and Privacy](data-and-privacy.md)).

## Plan quota

There's a quota panel at the bottom of the left column and on the statistics page, showing the current assistant's plan and remaining allowance.

It shows only what the assistant actually reports: plan type, percentage used per window, reset times, and an optional balance. Zeta **does not extrapolate** absolute token allowances or guess at expiry dates the assistant didn't provide.

Assistants report at different granularities. Claude Code, for instance, exposes a five-hour window and weekly windows plus optional extra quota, with the weekly window broken out per model. Reading those details requires turning on the quota detail switch — see [Connecting AI Assistants](agents.md#claude-codes-quota-detail-switch).

When quota can't be read (not signed in, no network, the assistant doesn't offer it), the panel keeps whatever it could read and marks the rest as temporarily unavailable rather than showing zero.

## Partial data

Statistics rely on scanning local history files, and occasionally something can't be read. Zeta's approach is to **show what it can** and state what's missing:

- A conversation directory couldn't be fully enumerated — showing what was readable
- Some conversation files failed to read — showing the rest
- Some history lines were corrupt — skipped, statistics continue

None of these affect the correctness of the other numbers.

## The statistics index

So it doesn't have to rescan everything each time, Zeta caches the aggregated result in an index file. You can delete it whenever you like; the next visit rescans, just more slowly.

What that file does and doesn't contain is covered in [Data and Privacy](data-and-privacy.md#whats-in-the-statistics-index).
