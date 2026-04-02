"""
console.py — Structured, colored console output for the PPA Optimization Agent.

All terminal printing is isolated here so optimizer_agent.py stays focused on logic.
"""

import json

COLORS = {
    "reset":   "\033[0m",
    "bold":    "\033[1m",
    "dim":     "\033[2m",
    "blue":    "\033[34m",
    "green":   "\033[32m",
    "yellow":  "\033[33m",
    "cyan":    "\033[36m",
    "magenta": "\033[35m",
    "red":     "\033[31m",
}


def _c(color: str, text: str) -> str:
    return f"{COLORS.get(color, '')}{text}{COLORS['reset']}"


def _header(label: str, color: str = "blue"):
    print(f"\n{'─' * 70}")
    print(_c("bold", _c(color, f"  {label}")))
    print(f"{'─' * 70}")


def _truncate(text: str, max_lines: int = 30) -> str:
    lines = text.splitlines()
    if len(lines) <= max_lines:
        return text
    half = max_lines // 2
    omitted = _c("dim", f"  ... ({len(lines) - max_lines} lines omitted) ...")
    return "\n".join(lines[:half] + [omitted] + lines[-half:])


# ---------------------------------------------------------------------------
# Message printers
# ---------------------------------------------------------------------------

def print_run_header(task_id: str, model: str, goal: str, baseline: dict, step_limit: int):
    _header(f"PPA AGENT: {task_id}", "blue")
    print(f"  Model:     {model}")
    print(f"  Goal:      {goal}")
    print(f"  Baseline:  cells={baseline['cells']}  ffs={baseline['ffs']}  wires={baseline['wires']}")
    print(f"  Steps:     {step_limit}")


def print_system_prompt(content: str):
    _header("SYSTEM PROMPT", "magenta")
    print(_c("dim", _truncate(content, 40)))


def print_user_message(content: str):
    _header("USER (instance)", "cyan")
    print(content.strip())


def print_assistant(content: str, step: int):
    _header(f"ASSISTANT  [step {step}]", "green")
    if content:
        print(content.strip())


def print_format_error(content: str):
    print(f"\n  {_c('red', '⚠ FORMAT ERROR:')} {_c('dim', content[:200])}")


# ---------------------------------------------------------------------------
# Tool call / result printers
# ---------------------------------------------------------------------------

def print_tool_call(name: str, args: dict):
    if name == "bash":
        cmd = args.get("command", "")
        first_line = cmd.split("\n")[0]
        if "\n" in cmd:
            n_lines = cmd.count("\n")
            print(f"\n  {_c('bold', _c('yellow', '▶ bash'))}  {_c('dim', first_line)}  {_c('dim', f'({n_lines} lines)')}")
        else:
            print(f"\n  {_c('bold', _c('yellow', '▶ bash'))}  {_c('dim', first_line[:200])}")
    else:
        args_short = {k: (v[:80] + "…" if isinstance(v, str) and len(v) > 80 else v) for k, v in args.items()}
        print(f"\n  {_c('bold', _c('yellow', f'▶ {name}'))}  {_c('dim', json.dumps(args_short))}")


def print_tool_result(name: str, output: str, returncode: int):
    status = _c("green", "OK") if returncode == 0 else _c("red", f"FAIL (rc={returncode})")
    print(f"  {_c('dim', '└─')} {status}")
    trimmed = _truncate(output.strip(), 20)
    if trimmed:
        for line in trimmed.splitlines():
            print(f"     {_c('dim', line)}")


# ---------------------------------------------------------------------------
# Final evaluation printer
# ---------------------------------------------------------------------------

def print_final_evaluation(solution_path: str, baseline: dict, sim: dict, metrics: dict | None, deltas: dict | None):
    _header("FINAL EVALUATION", "blue")
    if sim["pass"]:
        print(f"  Simulation: {_c('green', 'PASS')}")
        if metrics and deltas:
            for m in ["cells", "ffs", "wires"]:
                d = deltas[f"delta_{m}_pct"]
                color = "red" if d > 0 else ("green" if d < 0 else "dim")
                print(f"  {m:>5s}: {baseline[m]:>6d} → {metrics[m]:>6d}  ({_c(color, f'{d:+.1f}%')})")
    else:
        print(f"  Simulation: {_c('red', 'FAIL')}")
        print(f"  {_c('dim', sim['output'][:300])}")


def print_no_solution(solution_path: str):
    print(f"\n  {_c('red', f'No solution file found at {solution_path}')}")


def print_exit(status: str, steps: int, cost: float):
    _header("EXIT", "red" if "Error" in status else "blue")
    print(f"  Status: {status}")
    print(f"  Steps:  {steps}")
    print(f"  Cost:   ${cost:.4f}")
