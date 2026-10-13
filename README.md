# AOK gadgets

The gadget sources that more than one engine builds.

iSH-AOK's JIT is threaded code: a guest instruction becomes the address of
a *gadget*, a short piece of AArch64 assembly, followed by its operands, and
each gadget ends by jumping to the next. The same scheme runs guests inside
QEMU on hosts that may not generate code at run time (the *AOK gadgets*
plug-in of [emkey1/qemu](https://github.com/emkey1/qemu), the engine of the
AOK VM app). Where both translate the same guest instruction, they should
not each have their own copy of what it does. Those sources live here.

| Directory | What | Built by |
|-----------|------|----------|
| `riscv64/` | The RV64 integer gadgets, the bodies of its loads, stores and branches (`frag.h`), and the table of fused pairs (`pairs.h`) | iSH-AOK's riscv64 guest; the plug-in's RISC-V front end |
| `arm64/` | The bodies of the AArch64 guest's loads, stores and pairs (`frag.h`), and its operand-specialised integer gadgets (`alu_spec.S`) | iSH-AOK's arm64 guest; the plug-in's AArch64 front end |
| `x87/` | The x87: 80-bit arithmetic in integer registers, exact to the hardware, the register stack, every D8-DF instruction's register form, the transcendentals, and what the memory forms do once they have their operand | iSH-AOK's i386 and amd64 guests; the plug-in's x86 front end |

## The contract

A file here is assembled by each host with that host's own definitions
around it: which register is the CPU state and which the stream, how guest
memory is reached, how a block is left. What a shared body may assume is
written where it is defined: "A second host" in `riscv64/frag.h` and in
`arm64/frag.h`, and the head of each file in `x87/`. In short: a shared body
uses only the registers the contract gives it, does not call out, and
reaches state and memory only through the host's macros.

`tools/check.sh` assembles everything as a stand-in host whose registers
are deliberately not iSH-AOK's, and fails if a body needs something of one
engine's own. Run it after any change.

## How the engines take them

As copies, kept in step by script, because both engines are public
repositories and each must build from its own tree:

    tools/sync.sh ish-aok ~/git/ish-AOK       # then run iSH-AOK's tests
    tools/sync.sh qemu ~/git/qemu-aok         # then that fork's gates
    tools/sync.sh --check ish-aok ~/git/ish-AOK

A copy is never edited where it lands. The order matters: iSH-AOK's test
suites are the ones that execute these gadgets against known answers (for
the x87, 122,880 results from an AMD Ryzen), so a change goes there first.

## Where they came from

iSH-AOK, where they were written: `jit/guest-riscv64` and `jit/guest-arm64`
as of its commit `ca23e185`, and `jit/gadgets-aarch64/x87.S`.

## Licence

iSH-AOK's, unchanged (`LICENSE.md`, `LICENSE.IOS`): GPLv3, and GPLv2 as
well for what was contributed after iSH's commit `0e3a4144`, which
everything here was. That second grant is what lets QEMU, which is GPLv2,
build them.
