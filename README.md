# AXI4-Lite Slave Formal Verification

This is a small formal verification project built around an AXI4-Lite slave in SystemVerilog. The design handles both write and read transactions over a single 32-bit memory word. I wrote properties to check AXI handshake rules, FSM behavior, write/read mutual exclusion, and that reads return the right data from memory.

The flow uses SymbiYosys with OSS Yosys. Properties are written as immediate assertions (not concurrent SVA) because that is what the open source Yosys flow supports well. Both bounded model checking and unbounded k-induction proof pass.

## What's in the repo

- `axi4lite_slave.sv` - the DUT, with a write FSM (AW/W in any order) and a read FSM
- `module_properties.sv` - assumptions, assertions, and cover points
- `axi4lite_bmc.sby` - BMC run, depth 30
- `axi4lite_prove.sby` - full prove (basecase + induction)

Properties are instantiated inside the DUT. I tried `bind` first but Yosys dropped it as unused, so everything looked like it passed when it was not actually connected.

## How to run

You need OSS CAD Suite installed. On Windows, make sure both `bin` and `lib` are on your PATH, then from this folder:

```powershell
& "C:\oss-cad-suite\environment.ps1"
sby -f axi4lite_bmc.sby
sby -f axi4lite_prove.sby
```

If something fails, SymbiYosys writes a VCD trace you can open in GTKWave. The logfile tells you which assertion and which step failed.

## What gets checked

Roughly 27 assertions plus a few cover points. They cover things like:

- master holds AW/W/AR valid and stable while stalled
- B and R response channels stay stable until the handshake completes
- memory only updates after a full write
- RDATA matches mem on a read
- write and read do not overlap
- FSM states match the ready/valid behavior you expect

One thing I learned during induction: stability checks need `$past(VALID && !READY)` in the condition, not just `VALID && !READY`, or the first cycle the response goes high looks like a failure even when the RTL is fine.

## License

MIT. See LICENSE file. Standard open source license so anyone can use or learn from the code without worrying about usage rights.
