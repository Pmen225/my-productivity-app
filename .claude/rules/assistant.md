# Assistant rules

- Use `AssistantConversationRunner` through its injectable `AssistantTransport`.
- Enforce the fixed turn/tool/context/timeout/retry/circuit limits in code, not
  in prompts. Process tool calls in order and feed each result back.
- Pause destructive calls for confirmation and resume the same exchange after
  confirmation. Never bypass the existing confirmation path.
- Keep diagnostics bounded and content-free: provider, latency, retries,
  tool count, and outcome only.
