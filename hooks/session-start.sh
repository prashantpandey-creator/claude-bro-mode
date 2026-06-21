#!/usr/bin/env bash
# Orchestrator-First pre-flight: run doc_path_audit and inject findings as
# additionalContext so the agent knows the stale-path state before its first action.

REPO_ROOT="$(cd "$(dirname "$0")/../../purangpt" 2>/dev/null && pwd)"

if [ ! -d "$REPO_ROOT" ]; then
  # Silent exit — don't break session startup if the backend repo isn't found
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}'
  exit 0
fi

# Run doc_path_audit — outputs JSON envelope
RESULT=$(cd "$REPO_ROOT" && venv/bin/python -m tools.doc_path_audit.check --json 2>/dev/null)

if [ -z "$RESULT" ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}'
  exit 0
fi

# Extract missing paths that look like real code files (.py .ts .md)
MISSING=$(echo "$RESULT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
if not d.get('success'):
    print('')
    sys.exit(0)
CROSS_REPO_PREFIXES = ('purangpt-next/', 'purangpt/')
HISTORICAL_MENTIONS = ('webhook.py',)  # disabled services referenced in prose
items = [
    m for m in d['data']['missing']
    if any(m['path'].endswith(ext) for ext in ('.py', '.ts', '.md', '.js', '.tsx'))
    and not any(m['path'].startswith(p) for p in CROSS_REPO_PREFIXES)
    and m['path'] not in HISTORICAL_MENTIONS
]
if not items:
    print('All doc path claims verified against disk.')
else:
    lines = ['STALE DOC PATHS (claimed in docs but missing on disk):']
    for m in items:
        lines.append(f'  {m[\"doc\"]}:{m[\"line\"]}  {m[\"path\"]}')
    lines.append('Verify these before acting on any claim about them.')
    print('\n'.join(lines))
" 2>/dev/null)

# Build additionalContext
if [ -z "$MISSING" ]; then
  CONTEXT="Pre-flight doc_path_audit: all claimed paths verified on disk."
else
  CONTEXT="## Pre-flight doc_path_audit\n\n$MISSING"
fi

# Output the SessionStart hook envelope
python3 -c "
import json, sys
context = sys.argv[1]
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': context
    }
}))
" "$CONTEXT"

exit 0
