# sleep-gate

Denies `sleep` when it is being used as a completion-wait for a script that
was launched in the background. A fixed sleep is a guess at a duration, not a
signal that the work finished: it either wastes the time it slept or returns
before the process is done. The gate catches that shape at the moment the Bash
tool call is made and tells you which of four real waits to reach for instead.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install sleep-gate@clam
```

No configuration required. The plugin is hooks-only and activates on install —
there is no setup command, no config file, and no prerequisite tooling beyond
`jq`, which the gate uses to read its input and without which it stays silent.

## What to expect

One PreToolUse hook starts firing on every Bash tool call in every session
where the plugin is installed. Subagent tool calls are gated too: PreToolUse
hooks fire for those as well, and the gate applies to them identically.

Two rules can deny a call, and either one matching is enough.

**Rule L — a leading bare sleep.** The command's first statement is `sleep`
with a single duration operand, and that duration is 2 seconds or longer. The
first statement is the command text up to the first `;`, `&&`, `||`, `|`, or
newline, so both of these are denied:

```bash
sleep 45
sleep 30 && cat /tmp/build.log
```

The floor is what keeps short waits out of scope: `sleep 1` and `sleep 0.25`
are allowed, as is any sleep that is not the first thing the command does.
This rule is what catches the two-turn shape — background a script in one tool
call, sleep in the next — without the hook keeping any state between calls.

**Rule B — a background launch followed by a sleep.** All three of these hold:
the command backgrounds something with a real `&` (an `&` that is not part of
`&&`, `>&`, `&>`, `<&`, or an escaped `\&`); a `sleep` appears after that `&`;
and the command contains none of the carve-out words. So this is denied:

```bash
./scripts/deploy.sh > deploy.log 2>&1 & sleep 60
```

The carve-out words are `while`, `until`, `for`, `break`, `wait`, and `trap`.
If any one of them appears anywhere in the command, Rule B stands down. That
is the list to read when a denial surprises you — adding a real wait to the
command is what makes the rule let it through, and the words are the marker of
one.

The gate keys on the shape of the wait, never on the word `sleep` alone, so a
poll loop that sleeps between probes, a SIGTERM grace period before a SIGKILL,
a wait for clock or mtime granularity to tick over, and a sleep standing in as
a test double for a slow process all pass untouched. It errs toward allowing:
a missed misuse costs nothing, while a wrong denial interrupts a session that
was doing the right thing.

No files are created and none are read. No settings are written, no context is
injected into your session, and nothing under your project is touched.

## Common workflows

### Replacing a denied sleep

The denial reason names the rule that matched and lists the same four
alternatives given here. Pick whichever fits the wait you actually have.

**Run it in the foreground** and let the Bash tool's own `timeout` parameter
bound it. The tool call returns when the command returns, not a fixed number
of seconds later.

```bash
./scripts/deploy.sh    # with timeout: 600000 on the Bash tool call
```

**Pass `run_in_background: true`** when you want to keep working while it
runs. The harness sends a notification when the process exits, so you are told
when it finished rather than guessing.

**Wait on the child pid** when the process is a child of the same shell:

```bash
./scripts/deploy.sh & pid=$!; wait "$pid"
```

**Poll the real condition** when the thing you care about is an event rather
than a process — a marker file, a health endpoint, a pid going away. A poll
loop sleeps between probes and is explicitly allowed:

```bash
until [ -f done.marker ]; do sleep 1; done
kill -0 "$pid" 2>/dev/null
```

### Getting the unrestricted sleep back

Uninstall it. There is no configuration surface and no environment escape
hatch — no setting to flip, no variable to export — so uninstalling is the
only opt-out.

## Commands

### Hooks

**sleep-gate.sh** (PreToolUse, matcher: `Bash`)

Reads the hook JSON on stdin, extracts `.tool_input.command`, and applies the
two rules above to that string. On a match it writes one single-line JSON
object to stdout carrying a `deny` permission decision, whose reason names the
rule that matched and lists the four alternatives. On no match it writes
nothing at all. It never writes to stderr, never reads or writes a file, and
is deterministic: the same command string always yields the same decision.

The script always exits 0. A nonzero exit from a PreToolUse hook is itself a
denial, so the whole posture rests on that invariant — the gate fails open,
and every failure path allows the call. If `jq` is absent, if stdin is empty
or closed, or if the hook JSON is unparseable, the call is allowed with no
output at all. It can never block a session by crashing.

There are no skills, no scripts you run by hand, and no gating environment
variables. The gate is unconditional while installed.

## Tests

```bash
bash plugins/sleep-gate/scripts/sleep-gate.test.sh
bash plugins/sleep-gate/scripts/structure.test.sh
bash plugins/sleep-gate/scripts/registration.test.sh
bash plugins/sleep-gate/scripts/readme.test.sh
```

## Update

```
/plugin marketplace update clam
claude plugin update sleep-gate@clam
```

Both commands are needed: refreshing the catalog never touches an installed
plugin, and updating one is CLI-only — there is no `/plugin update`.
Afterwards run `/reload-plugins` to pick the new version up in the current
session, or restart the session if this plugin ships hooks or agents.

Auto-update is off by default for third-party marketplaces. Even with it
enabled, a plugin that ships hooks stays pinned to the last explicitly
installed version until you run the update command yourself
(anthropics/claude-code#52218).

## Relationships to other plugins

None required. This plugin is fully standalone. It reads no shared artifacts,
writes none, and its behaviour does not change based on what else you have
installed.

## Uninstalling

```
/plugin uninstall sleep-gate@clam
```

Uninstalling is all there is to it: the gate creates no files, writes no
settings, and leaves no state behind.
