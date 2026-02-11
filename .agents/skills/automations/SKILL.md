---
name: automations
description: Create and manage recurring Flux automations.
metadata:
  short-description: Manage recurring automations
---

# Automations

## Overview

Use this skill when the user wants recurring workflows, reminders, periodic checks, or scheduled follow-ups. Automations run on a schedule and execute an agent prompt.

## Required Workflow

1. Clarify intent:
- What should run.
- How often it should run.
- Which timezone to use.

2. Create an automation:
- Use `create_automation` with `prompt`, `scheduleExpression`, and optional `name`/`timezone`.

3. Confirm the outcome:
- Immediately call `list_automations`.
- Share the new automation `id`, status, and next run time.

4. Maintain lifecycle:
- Use `update_automation` for prompt/schedule edits.
- Use `pause_automation` / `resume_automation` to control execution.
- Use `run_automation_now` for immediate execution.
- Use `delete_automation` only when explicitly requested.

## Schedule Format

Use a 5-field schedule expression:

`minute hour day month weekday`

Examples:
- `0 9 * * 1-5` -> weekdays at 9:00
- `*/30 * * * *` -> every 30 minutes
- `15 8 1 * *` -> first day of month at 08:15

## Guardrails

- Do not guess timezone if the user specifies one.
- Keep automation prompts explicit and self-contained.
- Prefer pausing over deleting unless the user asks to remove it.
