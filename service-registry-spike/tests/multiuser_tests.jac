"""Regression test for a real bug found after the fact: a cache keyed by a single bare value
(not by jid(root)) leaks one user's node into another user's request, because `root` is bound to
whoever is calling, not a process-wide constant. See docs/architecture.md and the linked tracker
entries for the full story. This must stay green through any future refactor of the caching
shape in src/config_service.jac."""

import tempfile;
import from jaclang.runtimelib.testing { JacTestClient }

test "a per-root-keyed cache does not leak one user's config into another user's request" {
    client = JacTestClient.from_file("server_check.jac", base_path=tempfile.mkdtemp());
    try {
        client.register_user("alice", "password123");
        client.login("alice", "password123");
        client.post("/walker/set_and_read_config", json={"value": "alice-value"});

        client.register_user("bob", "password123");
        client.login("bob", "password123");
        bob_first = client.post("/walker/set_and_read_config", json={"value": ""});
        assert bob_first.json()["data"]["reports"][0] == "unset", (
            "bob's request returned a value bob never set -- "
            "the config-service cache is leaking across users"
        );

        client.post("/walker/set_and_read_config", json={"value": "bob-value"});

        client.login("alice", "password123");
        alice_again = client.post("/walker/set_and_read_config", json={"value": ""});
        assert alice_again.json()["data"]["reports"][0] == "alice-value", (
            "alice's own value was overwritten by bob's request -- "
            "the config-service cache is leaking across users"
        );
    } finally {
        client.close();
    }
}
