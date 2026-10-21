# The flag inventory: what this engine actually accepts

`llama-server --help` at the pinned commit, dumped to
`evidence/help-fce9e70e875bcb69cb0b3cf358f41ddcefa41c00c4a4a5cf157386c5d593ef70.txt`
(35 option lines). Every future ticket may only use flags from that file.

## The flags this round guessed at

| flag | at this pin | note |
|---|---|---|
| `--moe-cache-mib` | **absent** | Strata's headline feature is not in this engine |
| `--load-mode` | exists | this is what replaced `--no-mmap` |
| `--spec-type` | exists | |
| `--spec-draft-n-max` | exists | this is what replaced `--draft-max` |
| `--n-cpu-moe` | exists | |
| `-ot` | exists | per-tensor placement by regex |
| `-cmoe` | exists | |
| `--no-mmap` | **absent** | it was removed; `--load-mode` is the replacement |
| `--draft-max` | present only as removed | the engine errors on it and names `--spec-draft-n-max` |

## Two consequences

**Strata's headline feature is not here.** `--moe-cache-mib` does not exist at this pin, so
Strata's SSD expert cache is not a preset away -- the tiering work stays a real piece of work
rather than collapsing into a flag.

**Two flag errors cost two cycles this round.** `--draft-max` and `--no-mmap` were both
recalled from memory and both were rejected by the engine. The engine is the only authority and
its help text is now committed, so a flag can be checked before it is used rather than after it
fails a run.

## Still owed

The diff between this inventory and what `Sources/Servers/Server.swift` can emit. A flag the
engine has and the app cannot set is a UI gap; a flag the app sets and the engine lacks is a
bug. That diff is worth more than another benchmark.
