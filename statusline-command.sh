#!/bin/bash
# Claude Code statusline — pretty single-line status.
# Reads the JSON payload Claude Code pipes on stdin (see docs for schema).

input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd="$PWD"
dir_name=$(basename "$cwd")

model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
style=$(printf '%s' "$input" | jq -r '.output_style.name // empty')
used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
vim_mode=$(printf '%s' "$input" | jq -r '.vim.mode // empty')
pr_number=$(printf '%s' "$input" | jq -r '.pr.number // empty')
pr_kind=$(printf '%s' "$input" | jq -r '.pr.kind // empty')
five_h=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_h_resets_at=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
weekly=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
weekly_resets_at=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Formats a Unix epoch reset timestamp as a short "until reset" countdown
# ("2d 3h" / "45m" / "now"). Never fails loudly on a stale/absent timestamp --
# an empty/unparseable value just yields no countdown, same fail-open posture
# as every other optional field here.
_countdown() {
  local resets_at="$1" now remaining d h m
  # Hard numeric check before arithmetic: $(( )) would expand a $(cmd) inside
  # the value, so refuse anything that is not a plain integer up front.
  [[ "$resets_at" =~ ^[0-9]+$ ]] || return
  now=$(date +%s)
  remaining=$((resets_at - now))
  [ "$remaining" -le 0 ] && { printf 'now'; return; }
  d=$((remaining / 86400)); h=$(((remaining % 86400) / 3600)); m=$(((remaining % 3600) / 60))
  if [ "$d" -gt 0 ]; then printf '%dd %dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

# --- persist the rate-limit window so a session can READ ITS OWN limits ---
# Operator ask 2026-09-21: "gostaria mesmo que houvesse uma forma de vocês administrarem
# o próprio limite semanal e de 5 horas -- é um gate necessário para a autonomia".
#
# The harness pipes these four fields here on every render, but a Claude session cannot
# reach them from inside a tool call -- the statusline is the only place they surface.
# Writing them to a known path turns a human-only display into something a session can
# query with a plain file read, which is what lets it pace itself instead of discovering
# the wall by hitting a 429 mid-round.
#
# Fail-open on purpose: a broken write must never take the operator's statusline with it,
# the same posture every other optional field in this script already takes.
{
  limits_out="$HOME/.claude/rate_limits.json"
  printf '%s' "$input" | jq -c \
    --arg captured_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{captured_at: $captured_at,
      five_hour: (.rate_limits.five_hour // null),
      seven_day: (.rate_limits.seven_day // null),
      model: (.model.display_name // null),
      session_id: (.session_id // null)}' \
    > "${limits_out}.tmp" 2>/dev/null && mv -f "${limits_out}.tmp" "$limits_out" 2>/dev/null
} || true

# --- git info (skip optional locks so this never fights a running git op) ---
branch=""
dirty=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    dirty="*"
  fi
fi

# --- colors (dimmed palette; terminal renders these dim regardless) ---
CYAN=$(tput setaf 6); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
RED=$(tput setaf 1); BLUE=$(tput setaf 4); MAGENTA=$(tput setaf 5)
GRAY=$(tput setaf 8); RESET=$(tput sgr0)

segments=()

segments+=("${CYAN}📁 ${dir_name}${RESET}")

if [ -n "$branch" ]; then
  branch_color="$MAGENTA"
  [ -n "$dirty" ] && branch_color="$YELLOW"
  segments+=("${branch_color}🌿 ${branch}${dirty}${RESET}")
fi

if [ -n "$model" ]; then
  segments+=("${BLUE}🤖 ${model}${RESET}")
fi

if [ -n "$used_pct" ]; then
  pct_int=${used_pct%.*}
  if [ "$pct_int" -ge 85 ]; then ctx_color="$RED"
  elif [ "$pct_int" -ge 60 ]; then ctx_color="$YELLOW"
  else ctx_color="$GREEN"; fi
  ctx_size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty')
  ctx_label="${pct_int}%"
  # Same reason as _countdown: only enter the arithmetic branch for a plain integer.
  if [[ "$ctx_size" =~ ^[0-9]+$ ]]; then
    if [ "$ctx_size" -ge 1000000 ]; then ctx_lim="$((ctx_size / 1000000))M"
    else ctx_lim="$((ctx_size / 1000))k"; fi
    ctx_label="${pct_int}%/${ctx_lim}"
  fi
  segments+=("${ctx_color}📊 ${ctx_label}${RESET}")
fi

if [ -n "$five_h" ]; then
  five_int=${five_h%.*}
  if [ "$five_int" -ge 85 ]; then five_color="$RED"
  elif [ "$five_int" -ge 60 ]; then five_color="$YELLOW"
  else five_color="$GREEN"; fi
  five_cd=$(_countdown "$five_h_resets_at")
  if [ -n "$five_cd" ]; then
    five_label="⏱ ${five_cd} (${five_int}%)"
  else
    five_label="⏱ ${five_int}%"
  fi
  segments+=("${five_color}${five_label}${RESET}")
fi

if [ -n "$weekly" ]; then
  weekly_int=${weekly%.*}
  if [ "$weekly_int" -ge 85 ]; then weekly_color="$RED"
  elif [ "$weekly_int" -ge 60 ]; then weekly_color="$YELLOW"
  else weekly_color="$GREEN"; fi
  weekly_cd=$(_countdown "$weekly_resets_at")
  if [ -n "$weekly_cd" ]; then
    weekly_label="📅 ${weekly_cd} (${weekly_int}%)"
  else
    weekly_label="📅 ${weekly_int}%"
  fi
  segments+=("${weekly_color}${weekly_label}${RESET}")
fi

if [ -n "$pr_number" ]; then
  label="PR #"
  [ "$pr_kind" = "mr" ] && label="MR !"
  segments+=("${GREEN}🔀 ${label}${pr_number}${RESET}")
fi

if [ -n "$style" ] && [ "$style" != "default" ]; then
  segments+=("${YELLOW}${style}${RESET}")
fi

if [ -n "$vim_mode" ]; then
  segments+=("${GRAY}[${vim_mode}]${RESET}")
fi

out=""
for s in "${segments[@]}"; do
  if [ -z "$out" ]; then
    out="$s"
  else
    out="$out ${GRAY}│${RESET} $s"
  fi
done

printf '%s' "$out"
