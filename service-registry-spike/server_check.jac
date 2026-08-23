"""A tiny served app, used only by tests/multiuser_tests.jac to exercise the service accessors
through a real per-user `root` (JacTestClient), the way jac-studio's actual served app will.
Not part of the CLI demo (main.jac) -- kept separate so main.jac stays a plain script."""

import from src.config_service { config_get, config_set }

walker:pub set_and_read_config {
    has key: str = "probe.value";
    has value: str = "";

    can run with Root entry {
        if self.value {
            config_set(self.key, self.value);
        }
        report config_get(self.key, "unset");
    }
}
