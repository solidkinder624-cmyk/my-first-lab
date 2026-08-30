"""Daily AI news digest agent.

Implements the 4-layer design (Trigger / Workflow / Agent / Guardrail) with
externally persisted job state, idempotent steps, and typed error handling,
so a run can be safely interrupted and resumed instead of restarted from
scratch.
"""
