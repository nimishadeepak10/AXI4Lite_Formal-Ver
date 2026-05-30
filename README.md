# AXI4-Lite Slave — Formal Verification

SystemVerilog AXI4-Lite slave controller verified with **SymbiYosys** (BMC + k-induction). Includes write and read paths, 27+ immediate assertions, and counterexample debug via GTKWave.

## Overview

| Item | Detail |
|------|--------|
| DUT | `axi_lite_slave` — single 32-bit memory word |
| Write | 4-state FSM; AW/W in any order |
| Read | 2-state FSM; AR → RDATA from `mem` |
| Properties | `module_properties.sv` (instantiated inside DUT) |
| Tool | OSS CAD Suite — Yosys + SymbiYosys + Yices |
| Status | **BMC depth 30: PASS** · **Unbounded prove: PASS** |

## Project structure

```
axi4lite_slave.sv      # DUT + properties instance
module_properties.sv   # Assumptions, assertions, covers
axi4lite_bmc.sby       # Bounded model check (depth 30)
axi4lite_prove.sby     # Unbounded proof (basecase + induction)
yosys_test/            # Small Yosys syntax experiments (optional)
```

## Prerequisites

Install [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite) and ensure **both** `bin` and `lib` are on `PATH`:

```powershell
& "C:\oss-cad-suite\environment.ps1"
# Or manually:
$env:PATH = "C:\oss-cad-suite\bin;C:\oss-cad-suite\lib;" + $env:PATH
```

Verify:

```powershell
yosys -V
sby --version
```

## Run verification

From the project root:

```powershell
# Bounded check (30 cycles from reset)
sby -f axi4lite_bmc.sby

# Unbounded proof (BMC basecase + k-induction)
sby -f axi4lite_prove.sby
```

**PASS** → no `trace.vcd` generated.  
**FAIL** → open the trace in GTKWave:

```powershell
gtkwave axi4lite_bmc\engine_0\trace.vcd
# or for induction failures:
gtkwave axi4lite_prove\engine_0\trace_induct.vcd
```

Check `logfile.txt` (or `logfile_induction.txt`) for the failing assertion line number.

## Property summary

Properties use **immediate assertions** (`always @(posedge ACLK) assert(...)`) because OSS Yosys does not fully support concurrent SVA. The *property thinking* is the same as industry formal tools.

| Group | Count | Examples |
|-------|-------|----------|
| Master assumptions | 6 | AW/W/AR valid held; addr/data stable while stalled |
| Write B channel | 6 | BVALID/BRESP stability, no write during B pending |
| Write functional | 2 | BVALID ordering, mem update only on complete write |
| Write FSM | 4 | Idle / GOT_AW / GOT_W / WAIT_B encoding |
| Read R channel | 6 | RVALID/RRESP/RDATA stability, RDATA == mem |
| Read FSM | 2 | RD_IDLE / RD_WAIT_R encoding |
| Mutual exclusion | 2 | No AR during write; no AW/W during read |
| Cover | 4 | Full write, B handshake, AR handshake, R handshake |

**Induction tip:** Stability checks use `$past(VALID && !READY)` in the antecedent so they apply during a **stall**, not on the first cycle `VALID` rises.

## Design notes

- **Properties are instantiated inside the DUT** — `bind` was dropped by Yosys as unused, which caused false PASS results earlier.
- **Ready signals are combinational** (`always_comb`) to avoid same-cycle NBA timing holes between write/read FSMs.
- **Mutual exclusion:** one transaction at a time; write channel has priority when both are requested at idle.
- Address ports (`AWADDR`, `ARADDR`) are latched but not decoded — single-word slave only.

## Legacy filenames

Older runs may reference `axi4lite_write_bmc.sby` / `axi4lite_write.sby`. Use `axi4lite_bmc.sby` and `axi4lite_prove.sby` instead.

## License

MIT — see [LICENSE](LICENSE).

## Publish to GitHub

Git is initialized and the initial commit is on `main`. To create the repo and push (one-time login required):

```powershell
# Install GitHub CLI if needed (already installed on this machine)
# winget install GitHub.cli

gh auth login
cd "C:\Users\Nimisha\AXI4Lite_Formal Ver"
gh repo create AXI4Lite_Formal-Ver --public --source=. --remote=origin --push
# Or run: .\push_to_github.ps1
```

After push, the project will be at [github.com/nimishadeepak10/AXI4Lite_Formal-Ver](https://github.com/nimishadeepak10/AXI4Lite_Formal-Ver).
