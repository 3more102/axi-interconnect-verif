# Bug-Injection (Mutation) Audit — Results

Companion to [VERIF_PLAN.md](VERIF_PLAN.md) §7. Run with:

```bash
cd mutation && ./run_mutations.sh
```

Each row applies **one single-line change** to a scratch copy of `rtl/` and runs
the tests that are supposed to catch it. The point is not to collect a score —
it is to find out which defects the suite cannot see.

## Why the score is trustworthy

A mutation score is only meaningful if the harness cannot fake a kill. Three
guards:

- **The clean tree is run first.** Every target must PASS unmutated before the
  mutation is applied, so a "kill" can never be a pre-existing failure taking
  the credit.
- **The edit must actually land.** The RTL file is hashed before and after the
  `sed`; a pattern that matches nothing is reported as `NO-OP`, never silently
  counted as a survivor or a kill.
- **Failures are read from files, not pipes.** `vvp`'s output is redirected and
  then inspected. A pipeline's exit status is its last stage's, so `run | tail`
  reports success even when the run failed.

## Results

**14/14 killed, 0 survived, 0 no-op.**

| ID | Tier | File | Defect injected | Caught by |
|----|------|------|-----------------|-----------|
| M01 | sim | `axi4_lite_slave` | write-strobe lane 0 dropped | lite_slave: strobes, random |
| M02 | sim | `axi4_lite_slave` | SLVERR index threshold off by one | lite_slave: errors, random |
| M03 | sim | `axi4_mem_slave` | write valid-range threshold off by one | mem_slave: errors, boundary |
| M04 | sim | `axi4_mem_slave` | read valid-range threshold off by one | mem_slave: errors, boundary |
| M05 | sim | `axi4_lite_interconnect` | decode sends S1 traffic to the default slave | lite_ic: targeted, random |
| M06 | sim | `axi4_lite_interconnect` | default slave answers OKAY instead of DECERR | lite_ic: decerr, random |
| M07 | sim | `axi4_lite_interconnect` | round-robin priority never alternates | lite_ic: **fairness** |
| M08 | sim | `axi4_lite_interconnect` | write grant released at W instead of at B | lite_ic: contention, parallel, random |
| M09 | sim | `axi4_interconnect` | B response routed by an inverted ID bit | ic: targeted, random |
| M10 | sim | `axi4_interconnect` | R beats routed by an inverted ID bit | ic: targeted, random |
| M11 | sim | `axi4_mem_slave` | write burst never terminates on WLAST | mem_slave: incr, smoke |
| M12 | formal | `axi4_lite_interconnect` | decode boundary moved | formal `lite_ic:decode` |
| M13 | formal | `axi4_lite_interconnect` | reset gating removed from a master-port READY | formal `lite_ic:reset` |
| M14 | formal | `axi4_lite_interconnect` | write grant released early | formal `lite_ic:stable`, `outstanding` |

M12–M14 exist to check the **formal tier itself**. A proof engine that only ever
prints PASS is worth nothing; these confirm it reports FAIL on a real defect.

## What the first run found

The audit's first pass scored **11/14**, with three survivors. All three were
real gaps, and closing them changed the design's verification — which is the
entire point of running it.

### M03 — write range off-by-one (was: SURVIVED)

`wr_in_range = (addr[11:0] < MEM_BYTES)` mutated to `<=`, letting offset `0xC00`
count as writable.

Every existing error test straddled the boundary with bursts like
`0xBFC, 0xC00, 0xC04`. Because `0xC04` is out of range regardless, BRESP was
still SLVERR and the mutation hid behind the *other* failing beat. The check
resolution was coarser than the defect.

**Fixed** by adding two bursts to `tb_axi4_mem_slave:errors` in which `0xC00` is
the *only* out-of-range beat, so an off-by-one flips BRESP from SLVERR to OKAY
and is caught.

### M07 — round-robin never alternates (was: SURVIVED)

The arbiter's priority pointer update `w_rr_m0 <= ~wgrant_owner_m0` mutated to
`<= wgrant_owner_m0`.

The `contention` test — two masters hammering one slave — could not see this at
all, and not by accident. Each master is single-outstanding, so at the moment a
grant is released the master that just finished has no AW pending yet, and the
other one wins **by default whatever the pointer says**. The pointer is only
consulted on a genuine tie, and no test produced one.

**Fixed** with a new `fairness` test that launches both masters at the same
instant with zero inter-phase delay, so both AWs really are pending and the
pointer alone decides.

Writing that test surfaced a second, subtler trap. The intuitive assertion —
"a fair arbiter splits the wins evenly" — is exactly **backwards** here, and it
failed against the *correct* RTL. Each round contains two completions (the tie
winner, then the loser), so the pointer flips twice and returns to where it
started; the same master correctly wins every tie, while the loser still
completes every round. It is a stuck pointer that produces the even split. The
test now models the SPEC §3 rule explicitly instead of asserting a plausible-
sounding statistic.

### M13 — reset gating removed from a READY (was: SURVIVED)

`s0_axi_awready = aresetn && !wr_active0` mutated to drop the `aresetn` term.

Invisible to every tier, because SPEC §0 only constrains **VALID** outputs during
reset and the protocol checkers' PC12 follows it. Nothing said anything about
READY.

**Fixed** by extending the formal reset property to require that every
DUT-driven READY is also low in reset. All of them already are — the RTL was
written that way — so requiring it costs nothing and closes the hole.

## Reading this table

A survivor is a verification hole, not a curiosity: it means a real defect of
that shape could ship. The three above were closed by strengthening the
stimulus and the properties, never by weakening a check or deleting a mutation.
