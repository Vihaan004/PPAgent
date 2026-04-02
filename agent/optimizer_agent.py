#!/usr/bin/env python3
"""
PPA Optimization Agent — extends mini-swe-agent with simulate/synthesize tools.

Runs inside the Docker container (ppagent-env) with Icarus Verilog and Yosys.

Usage:
  python3 agent/optimizer_agent.py --task benchmark/tasks/task_02
  python3 agent/optimizer_agent.py --task benchmark/tasks/task_02 \\
      --model openai/gpt-5-mini --steps 20 --output results/agent_task_02.json
"""

import argparse
import json
import logging
import os
import sys

# ── Runtime path setup ────────────────────────────────────────────────────────
sys.path.insert(0, "/workspace/mini-swe-agent/src")   # mini-swe-agent (not pip-installed)
sys.path.insert(0, "/workspace")                        # harness imports

os.environ.setdefault("MSWEA_SILENT_STARTUP", "1")

# ── Framework imports ─────────────────────────────────────────────────────────
import litellm
from minisweagent.agents.default import DefaultAgent
from minisweagent.environments.local import LocalEnvironment
from minisweagent.exceptions import FormatError, InterruptAgentFlow
from minisweagent.models.litellm_model import LitellmModel
from minisweagent.models.utils.actions_toolcall import BASH_TOOL

# ── Harness imports ───────────────────────────────────────────────────────────
from harness.evaluate import compute_deltas, load_task, simulate, synthesize

# ── Console output ────────────────────────────────────────────────────────────
sys.path.insert(0, os.path.dirname(__file__))   # ensure agent/ dir is on path
from console import (
    print_assistant, print_exit, print_final_evaluation, print_format_error,
    print_no_solution, print_run_header, print_system_prompt, print_tool_call,
    print_tool_result, print_user_message,
)


# =============================================================================
# Tool Definitions  (OpenAI function-calling format)
# =============================================================================

SIMULATE_TOOL = {
    "type": "function",
    "function": {
        "name": "simulate",
        "description": (
            "Compile and simulate a Verilog solution against the task testbench "
            "using Icarus Verilog. Returns pass/fail and any error output."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "solution_file": {"type": "string", "description": "Path to the candidate .v file"},
                "task_dir":      {"type": "string", "description": "Path to the task directory"},
            },
            "required": ["solution_file", "task_dir"],
        },
    },
}

SYNTHESIZE_TOOL = {
    "type": "function",
    "function": {
        "name": "synthesize",
        "description": (
            "Synthesize a Verilog solution with Yosys and return PPA metrics "
            "(cells, FFs, wires) plus percentage deltas vs the task baseline."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "solution_file": {"type": "string", "description": "Path to the candidate .v file"},
                "task_dir":      {"type": "string", "description": "Path to the task directory"},
            },
            "required": ["solution_file", "task_dir"],
        },
    },
}

ALL_TOOLS = [BASH_TOOL, SIMULATE_TOOL, SYNTHESIZE_TOOL]
PPA_TOOL_NAMES = {"simulate", "synthesize"}


# =============================================================================
# Tool Execution
# =============================================================================

def execute_simulate(args: dict) -> dict:
    tb_path = os.path.join(args["task_dir"], "testbench.v")
    result = simulate(args["solution_file"], tb_path)
    return {
        "output": json.dumps(result, indent=2),
        "returncode": 0 if result["pass"] else 1,
        "exception_info": "",
    }


def execute_synthesize(args: dict) -> dict:
    task = load_task(args["task_dir"])
    metrics = synthesize(args["solution_file"], task["top_module"])
    if "error" not in metrics:
        deltas = compute_deltas(task["baseline"], metrics)
        metrics.update(deltas)
        metrics["baseline"] = task["baseline"]
    return {"output": json.dumps(metrics, indent=2), "returncode": 0, "exception_info": ""}


PPA_EXECUTORS = {
    "simulate":  execute_simulate,
    "synthesize": execute_synthesize,
}


# =============================================================================
# Action Parser  (accepts bash + simulate + synthesize)
# =============================================================================

def parse_ppa_actions(tool_calls: list) -> list[dict]:
    """Parse tool calls from the LLM response into structured action dicts."""
    if not tool_calls:
        raise FormatError({
            "role": "user",
            "content": "No tool calls found. Every response MUST include at least one tool call.",
            "extra": {"interrupt_type": "FormatError"},
        })

    actions = []
    for tc in tool_calls:
        try:
            args = json.loads(tc.function.arguments)
        except Exception as e:
            raise FormatError({
                "role": "user",
                "content": f"Error parsing tool call arguments: {e}",
                "extra": {"interrupt_type": "FormatError"},
            }) from e

        name = tc.function.name
        if name == "bash":
            if "command" not in args:
                raise FormatError({
                    "role": "user",
                    "content": "Missing 'command' argument in bash tool call.",
                    "extra": {"interrupt_type": "FormatError"},
                })
            actions.append({"command": args["command"], "tool_call_id": tc.id})
        elif name in PPA_TOOL_NAMES:
            actions.append({"tool": name, "args": args, "tool_call_id": tc.id})
        else:
            raise FormatError({
                "role": "user",
                "content": f"Unknown tool '{name}'. Available: bash, simulate, synthesize.",
                "extra": {"interrupt_type": "FormatError"},
            })

    return actions


# =============================================================================
# PPAModel  —  LitellmModel extended with PPA tools
# =============================================================================

class PPAModel(LitellmModel):
    """Extends LitellmModel to advertise simulate/synthesize alongside bash."""

    def _query(self, messages, **kwargs):
        return litellm.completion(
            model=self.config.model_name,
            messages=messages,
            tools=ALL_TOOLS,
            **(self.config.model_kwargs | kwargs),
        )

    def _parse_actions(self, response):
        tool_calls = response.choices[0].message.tool_calls or []
        if not tool_calls:
            # Preserve the raw assistant text so the agent can print it even on FormatError.
            assistant_content = response.choices[0].message.content or ""
            raise FormatError({
                "role": "user",
                "content": "No tool calls found. Every response MUST include at least one tool call.",
                "extra": {
                    "interrupt_type": "FormatError",
                    "model_response": assistant_content,
                },
            })
        return parse_ppa_actions(tool_calls)


# =============================================================================
# PPAAgent  —  DefaultAgent with PPA tool dispatch and console output
# =============================================================================

class PPAAgent(DefaultAgent):
    """
    Extends DefaultAgent with two behaviours:
      1. Dispatches simulate/synthesize tool calls to Python harness functions.
      2. Prints a clean, structured console log of the entire conversation.
    """

    def run(self, task: str = "", **kwargs) -> dict:
        """Initialize messages, print preamble, then drive the step loop."""
        self.extra_template_vars |= {"task": task, **kwargs}
        self.messages = []

        system_content  = self._render_template(self.config.system_template)
        instance_content = self._render_template(self.config.instance_template)

        self.add_messages(
            self.model.format_message(role="system", content=system_content),
            self.model.format_message(role="user",   content=instance_content),
        )

        print_system_prompt(system_content)
        print_user_message(instance_content)

        while True:
            try:
                self.step()
            except InterruptAgentFlow as e:
                # FormatError, LimitsExceeded, Submitted, etc.
                for msg in e.messages:
                    if msg.get("role") == "user":
                        extra = msg.get("extra", {})
                        model_response = extra.get("model_response", "")
                        if model_response:
                            if not isinstance(model_response, str):
                                model_response = json.dumps(model_response, indent=2)
                            print_assistant(model_response, self.n_calls)
                        print_format_error(msg.get("content", ""))
                self.add_messages(*e.messages)
            except Exception as e:
                self.handle_uncaught_exception(e)
                raise
            finally:
                self.save(self.config.output_path)

            if self.messages[-1].get("role") == "exit":
                break

        exit_extra = self.messages[-1].get("extra", {})
        print_exit(exit_extra.get("exit_status", "unknown"), self.n_calls, self.cost)
        return exit_extra

    def query(self) -> dict:
        """Call the LLM, then print assistant content and planned tool calls."""
        message = super().query()
        print_assistant(message.get("content") or "", self.n_calls)

        for action in message.get("extra", {}).get("actions", []):
            if action.get("tool") in PPA_TOOL_NAMES:
                print_tool_call(action["tool"], action.get("args", {}))
            else:
                print_tool_call("bash", {"command": action.get("command", "")})

        return message

    def execute_actions(self, message: dict) -> list[dict]:
        """Execute each action, routing PPA tools to harness and bash to env."""
        actions = message.get("extra", {}).get("actions", [])
        outputs = []

        for action in actions:
            tool_name = action.get("tool")
            if tool_name in PPA_EXECUTORS:
                try:
                    result = PPA_EXECUTORS[tool_name](action["args"])
                except Exception as e:
                    result = {"output": f"Error: {e}", "returncode": 1, "exception_info": str(e)}
                print_tool_result(tool_name, result["output"], result["returncode"])
            else:
                result = self.env.execute(action)
                print_tool_result("bash", result.get("output", ""), result.get("returncode", -1))
            outputs.append(result)

        return self.add_messages(
            *self.model.format_observation_messages(message, outputs, self.get_template_vars())
        )


# =============================================================================
# Prompts
# =============================================================================

SYSTEM_PROMPT = """\
You are an expert RTL (Verilog) optimization engineer. Your task is to optimize \
a Verilog module for better PPA (Power, Performance, Area) metrics while \
preserving functional correctness.

## Tools

- **bash**: Read/write files, explore the workspace, run any shell command (do not use applypatch).
- **simulate**: Compile and test your solution against the task testbench (iverilog). \
  ALWAYS call this before synthesize.
- **synthesize**: Run Yosys synthesis to get PPA metrics (cells, FFs, wires) and \
  percentage deltas vs the baseline.

## Workflow

1. Read the task description with `bash` (cat description.md).
2. Read the original RTL code with `bash` (cat original.v).
3. Analyze and identify optimization opportunities based on the goal.
4. Write your optimized Verilog to the solution file using `bash` (heredoc).
5. Call `simulate` — if it fails, read errors, fix, and retry.
6. Once simulation passes, call `synthesize` to measure PPA improvement.
7. Iterate if you can improve further, then submit.

To finish: `echo "COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT"`

## Rules

- The solution must be a **complete, self-contained Verilog module**.
- Do NOT change the module interface (port names, widths, directions).
- Always simulate before synthesizing — broken code wastes synthesis time.
- You have a limited number of steps — be strategic, not trial-and-error.

## Optimization Strategies

- **minimize_area**: Reduce cell count — simplify logic, remove redundant registers, \
  use narrower operands, eliminate dead code.
- **minimize_power**: Reduce FF count — replace shift registers with counters, \
  gate clocks, reduce switching activity.
- **minimize_timing**: Reduce critical-path depth — use parallelism, \
  logarithmic reduction trees, pipelining.
"""

INSTANCE_TEMPLATE = """\
Optimize the RTL for task: **{{ task_id }}**

- Task directory:   `{{ task_dir }}`
- Original RTL:     `{{ task_dir }}/original.v`
- Task description: `{{ task_dir }}/description.md`
- Solution output:  `{{ solution_path }}`
- Top module:       `{{ top_module }}`
- Optimization goal: `{{ goal }}`

### Baseline PPA Metrics
- Cells: {{ baseline_cells }}
- FFs:   {{ baseline_ffs }}
- Wires: {{ baseline_wires }}

Start by reading the task description and original code, then propose your optimization.
"""


# =============================================================================
# CLI Entry Point
# =============================================================================

def run_agent(task_dir: str, model_name: str, step_limit: int, output_path: str | None):
    task     = load_task(task_dir)
    task_id  = task["task_id"]
    baseline = task["baseline"]

    solution_dir  = "/workspace/benchmark/solutions/agent"
    os.makedirs(solution_dir, exist_ok=True)
    solution_path = os.path.join(solution_dir, f"{task_id}.v")

    # Infer optimization goal from description
    desc_path = os.path.join(task_dir, "description.md")
    with open(desc_path) as f:
        description = f.read()

    goal = "minimize_area"
    for line in description.splitlines():
        if "optimization goal" in line.lower():
            if "power"   in line.lower(): goal = "minimize_power"
            elif "timing" in line.lower() or "performance" in line.lower(): goal = "minimize_timing"
            break

    # Build agent
    model = PPAModel(model_name=model_name, cost_tracking="ignore_errors")
    env   = LocalEnvironment(cwd="/workspace", timeout=120)
    agent = PPAAgent(
        model, env,
        system_template=SYSTEM_PROMPT,
        instance_template=INSTANCE_TEMPLATE,
        step_limit=step_limit,
        cost_limit=10.0,
        output_path=output_path,
    )

    print_run_header(task_id, model_name, goal, baseline, step_limit)

    agent.run(
        task="",
        task_id=task_id,
        task_dir=task_dir,
        solution_path=solution_path,
        top_module=baseline["top_module"],
        goal=goal,
        baseline_cells=baseline["cells"],
        baseline_ffs=baseline["ffs"],
        baseline_wires=baseline["wires"],
    )

    # Post-run evaluation
    if os.path.isfile(solution_path):
        sim     = simulate(solution_path, task["testbench"])
        metrics = synthesize(solution_path, task["top_module"]) if sim["pass"] else None
        deltas  = compute_deltas(baseline, metrics) if (metrics and "error" not in metrics) else None
        print_final_evaluation(solution_path, baseline, sim, metrics, deltas)
    else:
        print_no_solution(solution_path)


def main():
    parser = argparse.ArgumentParser(description="PPA Optimization Agent")
    parser.add_argument("--task",    required=True,                          help="Path to task directory")
    parser.add_argument("--model",   default="openai/gpt-5-mini",            help="LLM model (litellm format)")
    parser.add_argument("--steps",   type=int, default=20,                   help="Max agent steps")
    parser.add_argument("--output", "-o",                                    help="Trajectory JSON output path")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(level=logging.WARNING, format="%(name)s | %(message)s")
    if args.verbose:
        logging.getLogger("ppa_agent").setLevel(logging.DEBUG)
    litellm.suppress_debug_info = True

    run_agent(args.task, args.model, args.steps, args.output)


if __name__ == "__main__":
    main()
