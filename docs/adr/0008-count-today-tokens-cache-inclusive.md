# Count today's tokens cache-inclusive, so the two products are comparable

The panel footer's today-token figure uses one measure for both products: every input processed, cache reads included, plus output.

Codex takes `dailyUsageBuckets[].tokens` from `account/usage/read`. Its measure is verifiable against the CLI rollout's `token_count` events: across 11,806 records `total_tokens = input_tokens + output_tokens` held for 11,679, `cached_input_tokens` never exceeded `input_tokens`, and `reasoning_output_tokens` never exceeded `output_tokens` — so cache reads are already counted inside input, and `total_tokens` is read directly rather than re-summed. Claude Code reports the same quantity split apart: `input_tokens` covers only input that missed the cache, and `cache_creation_input_tokens` and `cache_read_input_tokens` are peer addends, so the matching measure is the sum of all four.

Two smaller measures were rejected — "input plus output", and "input plus output plus cache writes". On one machine on one day the three come to `4.0M`, `22.6M` and `949.2M`: a factor of 237 between them, for two numbers that sit side by side on one line. An inconsistent measure there is an invitation to make a meaningless comparison. Aligned, roughly 95% of both is cache reads and the magnitudes agree (measured 2026-08-15: Codex `310.1M`, Claude Code `208.6M`).

Still unmeasured: whether the server's `dailyUsageBuckets.tokens` uses the same measure as the CLI's `total_tokens`. Summing one day of rollout `total_tokens` against that day's bucket would confirm it; until then the figure rests on inference.
