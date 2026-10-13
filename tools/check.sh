#!/bin/sh
# check.sh [RISCV64_DIR [ARM64_DIR]] -- do the gadget sources keep the
# contract every host builds them under?
#
# riscv64/alu.S, frag.h and pairs.h are built by iSH-AOK and by the QEMU
# plug-in (frag.h, "A second host"). This assembles alu.S the way a second
# host does, with stand-in definitions of everything the contract makes the
# host's (registers deliberately not AOK's, a memory model and a way out of
# a block of its own), and fails if the shared code
#   - does not assemble without gadgets.h (it used something of AOK's own),
#   - refers to a symbol outside itself (it calls out or reads AOK's state),
#   - touches a host register the contract does not give it.
# Run it after editing those files. It needs nothing but the C compiler.
# With a directory, it checks the copies of the three files there instead.
#
# Then the same for arm64/alu_spec.S and frag.h, the AArch64 guest's (a
# second argument names another directory), and for the four files of x87/
# (a third), whose host supplies the x87 state's layout (x87-arith.S) and its
# way to guest memory (x87-mem.S).
set -e
src=$(cd "${1:-$(dirname "$0")/../riscv64}" && pwd)
src64=$(cd "${2:-$(dirname "$0")/../arm64}" && pwd)
srcx87=$(cd "${3:-$(dirname "$0")/../x87}" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# The second host's file, on stdout, with HOST_<gadget> 1 for the names
# in $have (none on the first pass).
probe() {
    cat <<'EOF'
#define RV_GADGET_HOST check
_cpu  .req x20
_ip   .req x28
_addr .req x5
_sav  .req x6
_savw .req w6
.macro .gadget name
    .balign 16
    .globl shared_gadget_\name
shared_gadget_\name:
.endm
.macro gret pop=0
    ldr x9, [_ip, #(\pop * 8)]
    add _ip, _ip, #(\pop * 8 + 8)
    br x9
.endm
.macro gret_ahead
    ldr x9, [_ip, #-8]
    br x9
.endm
// Memory: a host whose guest addresses are host addresses plus a word of
// its state, and whose slow path is its own code.
.macro read_prep size, id, ahead=0
    ldr x9, [_cpu]
    tbnz _addr, #63, handle_miss_\id
    add _addr, _addr, x9
back_\id:
.endm
.macro write_prep size, id, ahead=0
    read_prep \size, \id, \ahead
.endm
.macro write_done size, id
.endm
.macro read_bullshit size, id, ahead=0
handle_miss_\id:
    ldr x9, [_ip, #-(\ahead + 8)]
    add _addr, _cpu, x9
    b back_\id
.endm
.macro write_bullshit size, id, ahead=0
    read_bullshit \size, \id, \ahead
.endm
// Ways out: two words each, and code addresses relative to one in x21.
#define F_WAY_WORDS 2
.macro branch_leave off
    ldp x9, x10, [_ip, #\off]
    add _ip, x10, x9
    gret
.endm
.macro pc_param reg
    add \reg, x21, \reg
.endm
EOF
    for n in $(sed -n 's/^#define F_\([A-Za-z0-9_]*\) 1$/\1/p' "$src/pairs.h"); do
        case " $have " in
        *" $n "*) echo "#define HOST_$n 1" ;;
        *) echo "#define HOST_$n 0" ;;
        esac
    done
    cat <<EOF
    .text
#include "$src/alu.S"
f_gadget mov_const
f_gadget addi
f_gadget b
.irp n, lb, lbu, lh, lhu, lw, lwu, ld, sb, sh, sw, sd
f_gadget \\n
.endr
EOF
}

# first without pairs, to learn which gadgets a second host gets
have=
probe > "$tmp/probe.S"
cc -arch arm64 -c -o "$tmp/probe.o" "$tmp/probe.S"
have=$(nm "$tmp/probe.o" | sed -n 's/.* T _*shared_gadget_//p' | tr '\n' ' ')
# then with every pair both of whose gadgets it has
probe > "$tmp/host.S"
cc -arch arm64 -c -o "$tmp/host.o" "$tmp/host.S"

undefined=$(nm -u "$tmp/host.o")
[ -z "$undefined" ] || { echo "shared gadget code refers outside itself:"; echo "$undefined"; exit 1; }
# x0, x9-x15 and the registers the host named (x5, x6, x20, x28, and x21 inside
# its own pc_param); anything else is not the shared code's to use
bad=$(objdump -d --no-show-raw-insn "$tmp/host.o" |
      grep -oE '\<([xw](1[6-9]|2[2-79]|30|[1-478])|sp)\>' | sort -u | tr '\n' ' ')
[ -z "$bad" ] || { echo "shared gadget code uses registers outside the contract: $bad"; exit 1; }
echo "shared riscv64 gadgets: $(echo $have | wc -w | tr -d ' ') gadgets and" \
     "$(nm "$tmp/host.o" | grep -c 'shared_gadget_f2_') pairs keep the contract"

# ---- arm64: alu_spec.S and the bodies of frag.h, under a host that is
# neither AOK nor QEMU. The contract (frag.h, "A second host"): the host names
# _cpu, _ip, _addr and the six registers a memory body keeps across its
# access, gives the flags and guest memory, and the bodies use x8-x14, x16
# and x17 besides.
cat > "$tmp/a64.S" <<EOF
#define A64_GADGET_HOST check
_cpu    .req x26
_ip     .req x27
_addr   .req x0
_fofs   .req x1
_fslot1 .req x2
_fslot2 .req x3
_fnewb  .req x4
_frn    .req x5
_fval2  .req x6
.macro .gadget name
    .balign 16
    .globl shared_gadget_\\name
shared_gadget_\\name:
.endm
.macro gret pop=0
    ldr x9, [_ip, #(\\pop * 8)]
    add _ip, _ip, #(\\pop * 8 + 8)
    br x9
.endm
.macro gret_ahead
    ldr x9, [_ip, #-8]
    br x9
.endm
.macro store_flags
    mrs x17, nzcv
    str x17, [_cpu, #8]
.endm
.macro load_flags
    ldr x17, [_cpu, #8]
    msr nzcv, x17
.endm
.macro read_prep size, id, ahead=0
    ldr x9, [_cpu]
    tbnz _addr, #63, handle_miss_\\id
    add _addr, _addr, x9
back_\\id:
.endm
.macro write_prep size, id, ahead=0
    read_prep \\size, \\id, \\ahead
.endm
.macro write_done size, id
.endm
.macro read_bullshit size, id, ahead=0
handle_miss_\\id:
    ldr x9, [_ip, #-(\\ahead + 8)]
    add _addr, _cpu, x9
    b back_\\id
.endm
.macro write_bullshit size, id, ahead=0
    read_bullshit \\size, \\id, \\ahead
.endm
    .text
#include "$src64/alu_spec.S"
f_gadget mov_const, f_mov_const, _, _, _, _, _
f_gadget umov64, f_umov, ldr, x12, _, _, _
f_gadget load64, f_load, 64, ldr, x17, _, _
f_gadget loads8_32, f_load, 8, ldrsb, w17, _, _
f_gadget store16, f_store, 16, strh, w17, _, _
.irp ext, 0, 1, 2
f_gadget load32_rx\\ext, f_load_rx, 32, ldr, w17, \\ext, _
f_gadget store64_rx\\ext, f_store_rx, 64, str, x17, \\ext, _
.endr
f_gadget ldp64, f_ldp, 128, 8, x17, _fval2, _
f_gadget stp32, f_stp, 64, 4, w17, w6, _
.irp pre, 0, 1
f_gadget ldp64_wb\\pre, f_ldp_wb, 128, 8, x17, _fval2, \\pre
f_gadget stp64_wb\\pre, f_stp_wb, 128, 8, x17, _fval2, \\pre
.endr
EOF
cc -arch arm64 -c -o "$tmp/a64.o" "$tmp/a64.S"
undefined=$(nm -u "$tmp/a64.o")
[ -z "$undefined" ] || { echo "shared arm64 gadget code refers outside itself:"; echo "$undefined"; exit 1; }
# x8-x14, x16, x17 and the registers this host named (x0-x6, x26, x27)
bad=$(objdump -d --no-show-raw-insn "$tmp/a64.o" |
      grep -oE '\<([xw](7|15|1[89]|2[0-589]|30)|sp)\>' | sort -u | tr '\n' ' ')
[ -z "$bad" ] || { echo "shared arm64 gadget code uses registers outside the contract: $bad"; exit 1; }
echo "shared arm64 gadgets: $(nm "$tmp/a64.o" | grep -c ' T _*shared_gadget_') gadgets keep the contract"

# The x87: a host whose CPU state and stream are not iSH-AOK's registers,
# whose status word keeps TOP elsewhere and whose tags are a byte each, so
# that the four access macros are real work and use their two registers.
cat > "$tmp/x87.S" <<EOF
_cpu .req x21
_ip  .req x27
#define CPU_fp 0x400
#define CPU_fcw 0x3f0
.macro .gadget name
    .balign 16
    .globl shared_gadget_\\name
shared_gadget_\\name:
.endm
.macro gret_nomem pop=0
    ldr x9, [_ip, #(\\pop * 8)]
    add _ip, _ip, #(\\pop * 8 + 8)
    br x9
.endm
.macro x87_ld_fsw r
    ldrh \\r, [_cpu, 0x3f2]
    ldr w16, [_cpu, 0x3f4]
    bfi \\r, w16, 11, 3
.endm
.macro x87_st_fsw r
    and w16, \\r, 0xffffc7ff
    strh w16, [_cpu, 0x3f2]
    ubfx w16, \\r, 11, 3
    str w16, [_cpu, 0x3f4]
.endm
.macro x87_ld_valid r
    ldr x16, [_cpu, 0x3f8]
    mov x17, 0x4080
    movk x17, 0x1020, lsl 16
    movk x17, 0x0408, lsl 32
    movk x17, 0x0102, lsl 48
    mul x16, x16, x17
    lsr x16, x16, 56
    eor \\r, w16, 0xff
.endm
.macro x87_st_valid r
    mvn w16, \\r
    and x16, x16, 0xff
    str x16, [_cpu, 0x3f8]
.endm
.macro x87_wait
    x87_ld_fsw w8
    tbz w8, 7, 1f
    brk 0
1:
.endm
.macro x87_comi_flags
    str w9, [_cpu, 0x3e0]
.endm
.macro host_flag dst, which
    ldr \\dst, [_cpu, 0x3e0]
    .ifc \\which,c
        and \\dst, \\dst, 1
    .endif
    .ifc \\which,z
        ubfx \\dst, \\dst, 6, 1
    .endif
    .ifc \\which,p
        ubfx \\dst, \\dst, 2, 1
    .endif
.endm
    .text
#include "$srcx87/x87-arith.S"
#include "$srcx87/x87-stack.S"
x87_pop1_here
#include "$srcx87/x87-reg.S"
x87_fcmov_all x87_fcmov, host_flag
x87_wp .req x2
.macro x87m_gadget arch, name
.gadget m_\\name
.endm
.macro x87m_wait arch
    x87_wait
.endm
.macro x87m_rprep arch, bits, id
    add x9, _cpu, 0x3c0
.endm
.macro x87m_rtail arch, bits, id
.endm
.macro x87m_wprep arch, bits, id
    add x87_wp, _cpu, 0x3c0
.endm
.macro x87m_wdone arch, bits, id
.endm
.macro x87m_wtail arch, bits, id
.endm
.macro x87m_ret arch
    gret_nomem 1
.endm
#include "$srcx87/x87-mem.S"
x87m_arith_all h, f32, 32, x87_ld_f32
x87m_arith_all h, f64, 64, x87_ld_f64
x87m_arith_all h, i16, 16, x87_ld_int
x87m_arith_all h, i32, 32, x87_ld_int
x87m_loads h
x87m_stores h
#include "$srcx87/x87-trans.S"
EOF
cc -arch arm64 -c -o "$tmp/x87.o" "$tmp/x87.S"
undefined=$(nm -u "$tmp/x87.o")
[ -z "$undefined" ] || { echo "shared x87 code refers outside itself:"; echo "$undefined"; exit 1; }
# x0, x3-x17, x30 and sp are the code's, and x19 where a frame saves and restores it
# (x87-trans.S's BF_ENTER and BF_LEAVE). Read off the source: the object has tables
# in its text, which a disassembler reads as instructions.
bad=$(sed -e 's/#.*//' -e 's|//.*||' "$srcx87"/x87-*.S |
      grep -v 'str x19, \[sp\|ldr x19, \[sp' |
      grep -oE '\<[xw](1|2|1[89]|2[0-9])\>' | sort -u | tr '\n' ' ')
[ -z "$bad" ] || { echo "shared x87 code names registers outside the contract: $bad"; exit 1; }
echo "shared x87: $(nm "$tmp/x87.o" | grep -c ' T _*shared_gadget_') gadgets keep the contract"
