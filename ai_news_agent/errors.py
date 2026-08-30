"""Error taxonomy used to decide retry behavior (design principle 5).

Each class maps to one row of the "retry / ask human / never retry" table:
  TransientError -> retry up to a bounded number of times
  AuthError      -> stop immediately, needs a human
  ValidationError -> retry a small, separate number of times (regeneration)
"""


class TransientError(Exception):
    """Temporary failure (network, rate limit, timeout). Safe to retry."""


class AuthError(Exception):
    """Invalid credentials / permission denied. Never retry automatically."""


class ValidationError(Exception):
    """Output failed schema validation. Retry only the generation step."""


class GuardrailStop(Exception):
    """A guardrail condition tripped (cost cap, zero articles, ...)."""

    def __init__(self, reason: str, warning: bool = False):
        super().__init__(reason)
        self.reason = reason
        self.warning = warning
