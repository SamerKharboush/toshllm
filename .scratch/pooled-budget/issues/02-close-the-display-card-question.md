# 02: Close the display-card question with an alternating A/B

Type: task
Status: open
Blocked by:

## Question

Does the slow mode and prefill stall (ticket 72) belong to the display card only?

Run 12 servers that alternate card 0 and card 1, with the request pattern of the thread A/B.
Count the servers that show the slow mode or a stall on each card.

The result fixes which card every later gate is measured on. It also confirms or retracts
the app's "most free VRAM" choice. Card 0 so far: 4 of 12. Card 1: 0 of 6, which would happen
by chance about 9% of the time.

This needs both cards free: HITL only for stopping the user's own server.
