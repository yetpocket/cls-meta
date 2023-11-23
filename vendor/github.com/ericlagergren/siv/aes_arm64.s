// Copyright 2017 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build gc && !purego

#include "textflag.h"

DATA rotInvSRows<>+0x00(SB)/8, $0x080f0205040b0e01
DATA rotInvSRows<>+0x08(SB)/8, $0x00070a0d0c030609
GLOBL rotInvSRows<>(SB), (NOPTR+RODATA), $16

DATA invSRows<>+0x00(SB)/8, $0x0b0e0104070a0d00
DATA invSRows<>+0x08(SB)/8, $0x0306090c0f020508
GLOBL invSRows<>(SB), (NOPTR+RODATA), $16

// func encryptBlockAsm(nr int, xk *uint32, dst, src *byte)
TEXT ·encryptBlockAsm(SB), NOSPLIT, $0
	MOVD nr+0(FP), R9
	MOVD xk+8(FP), R10
	MOVD dst+16(FP), R11
	MOVD src+24(FP), R12

	VLD1 (R12), [V0.B16]

	CMP $12, R9
	BLT enc128
	BEQ enc196

enc256:
	VLD1.P 32(R10), [V1.B16, V2.B16]
	AESE   V1.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V2.B16, V0.B16
	AESMC  V0.B16, V0.B16

enc196:
	VLD1.P 32(R10), [V3.B16, V4.B16]
	AESE   V3.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V4.B16, V0.B16
	AESMC  V0.B16, V0.B16

enc128:
	VLD1.P 64(R10), [V5.B16, V6.B16, V7.B16, V8.B16]
	VLD1.P 64(R10), [V9.B16, V10.B16, V11.B16, V12.B16]
	VLD1.P 48(R10), [V13.B16, V14.B16, V15.B16]
	AESE   V5.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V6.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V7.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V8.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V9.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V10.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V11.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V12.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V13.B16, V0.B16
	AESMC  V0.B16, V0.B16
	AESE   V14.B16, V0.B16
	VEOR   V0.B16, V15.B16, V0.B16
	VST1   [V0.B16], (R11)
	RET

// func expandKeyAsm(nr int, key *byte, enc *uint32)
// Note that round keys are stored in uint128 format, not uint32
TEXT ·expandKeyAsm(SB), NOSPLIT, $0
	MOVD   nr+0(FP), R8
	MOVD   key+8(FP), R9
	MOVD   enc+16(FP), R10
	LDP    rotInvSRows<>(SB), (R0, R1)
	VMOV   R0, V3.D[0]
	VMOV   R1, V3.D[1]
	VEOR   V0.B16, V0.B16, V0.B16      // All zeroes
	MOVW   $1, R13
	TBZ    $1, R8, ks192
	TBNZ   $2, R8, ks256
	LDPW   (R9), (R4, R5)
	LDPW   8(R9), (R6, R7)
	STPW.P (R4, R5), 8(R10)
	STPW.P (R6, R7), 8(R10)
	MOVW   $0x1b, R14

ks128Loop:
	VMOV   R7, V2.S[0]
	VTBL   V3.B16, [V2.B16], V2.B16
	AESE   V0.B16, V2.B16           // Use AES to compute the SBOX
	EORW   R13, R4
	LSLW   $1, R13                  // Compute next Rcon
	ANDSW  $0x100, R13, ZR
	CSELW  NE, R14, R13, R13        // Fake modulo
	SUBS   $1, R8
	VMOV   V2.S[0], R0
	EORW   R0, R4
	EORW   R4, R5
	EORW   R5, R6
	EORW   R6, R7
	STPW.P (R4, R5), 8(R10)
	STPW.P (R6, R7), 8(R10)
	BNE    ks128Loop
	B      ksDone

ks192:
	LDPW   (R9), (R2, R3)
	LDPW   8(R9), (R4, R5)
	LDPW   16(R9), (R6, R7)
	STPW.P (R2, R3), 8(R10)
	STPW.P (R4, R5), 8(R10)
	SUB    $4, R8

ks192Loop:
	STPW.P (R6, R7), 8(R10)
	VMOV   R7, V2.S[0]
	VTBL   V3.B16, [V2.B16], V2.B16
	AESE   V0.B16, V2.B16
	EORW   R13, R2
	LSLW   $1, R13
	SUBS   $1, R8
	VMOV   V2.S[0], R0
	EORW   R0, R2
	EORW   R2, R3
	EORW   R3, R4
	EORW   R4, R5
	EORW   R5, R6
	EORW   R6, R7
	STPW.P (R2, R3), 8(R10)
	STPW.P (R4, R5), 8(R10)
	BNE    ks192Loop
	B      ksDone

ks256:
	LDP    invSRows<>(SB), (R0, R1)
	VMOV   R0, V4.D[0]
	VMOV   R1, V4.D[1]
	LDPW   (R9), (R0, R1)
	LDPW   8(R9), (R2, R3)
	LDPW   16(R9), (R4, R5)
	LDPW   24(R9), (R6, R7)
	STPW.P (R0, R1), 8(R10)
	STPW.P (R2, R3), 8(R10)
	SUB    $7, R8

ks256Loop:
	STPW.P (R4, R5), 8(R10)
	STPW.P (R6, R7), 8(R10)
	VMOV   R7, V2.S[0]
	VTBL   V3.B16, [V2.B16], V2.B16
	AESE   V0.B16, V2.B16
	EORW   R13, R0
	LSLW   $1, R13
	SUBS   $1, R8
	VMOV   V2.S[0], R9
	EORW   R9, R0
	EORW   R0, R1
	EORW   R1, R2
	EORW   R2, R3
	VMOV   R3, V2.S[0]
	VTBL   V4.B16, [V2.B16], V2.B16
	AESE   V0.B16, V2.B16
	VMOV   V2.S[0], R9
	EORW   R9, R4
	EORW   R4, R5
	EORW   R5, R6
	EORW   R6, R7
	STPW.P (R0, R1), 8(R10)
	STPW.P (R2, R3), 8(R10)
	BNE    ks256Loop

ksDone:
	RET