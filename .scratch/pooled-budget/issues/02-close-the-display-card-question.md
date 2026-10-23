# 02: Close the display-card question with an alternating A/B

Type: task
Status: resolved
Blocked by:

## Question

Does the slow mode and prefill stall (ticket 72) belong to the display card only?

Run 12 servers that alternate card 0 and card 1, with the request pattern of the thread A/B.
Count the servers that show the slow mode or a stall on each card.

The result fixes which card every later gate is measured on. It also confirms or retracts
the app's "most free VRAM" choice. Card 0 so far: 4 of 12. Card 1: 0 of 6, which would happen
by chance about 9% of the time.

This needs both cards free: HITL only for stopping the user's own server.

## Answer

The question is not closed: the run could not reproduce the slow mode on either card.
- **Setup:** 12 alternating servers, 6 per card, on 2026-10-23. Script `card_ab.sh`, written
  and run by OpenCode and checked by the orchestrator. Every server planned
  `PLAN_FULL_HOST_DMOE`.
- **Outcome:** no slow mode and no prefill stall in any server; all 84 answers coherent.

| card | short decode (N = 18) | long decode (N = 12) | long prompt | arena |
|---|---|---|---|---|
| 0 (display) | 12.7829 (sd 0.0240) | 12.1260 (sd 0.0403) | 73.1617 (sd 0.0505) | 885.98 MiB, plan saw 4.8 GiB free |
| 1 | 12.8712 (sd 0.0364) | 12.1333 (sd 0.0900) | 73.3144 (sd 0.1133) | 1082.85 MiB, plan saw 5.0 GiB free |

- **The display was asleep** during the run (IODisplayWrangler power state 0; display sleep
  is 10 minutes). The slow-mode servers of 2026-10-22 ran while the user may have been using
  the screen, which was not recorded then. So the open hypothesis narrows to an *awake*
  display drawing on card 0.
- **Card 0 is slightly behind card 1** on short decode, by 0.088 tok/s, against sds of 0.024
  and 0.036, with the display asleep. It also gets a smaller arena (886 against 1083 MiB) and
  a lower hit rate (31.3% against 33.5%).
- **The app's "most free VRAM" choice stands** on the VRAM evidence alone: the bigger arena,
  and the refusal or fallback at 3.8–3.9 GiB free. The slow mode is not needed to justify it.
- **Drift between days:** card 1's short decode was 12.8712 today against 13.1324 on
  2026-10-22 (sd 0.1129), with the same engine and launch. The cause was not determined.
  Compare rows within one session only.
