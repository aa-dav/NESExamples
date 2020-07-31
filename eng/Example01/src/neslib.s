.include "neslib.inc"	; include header neslib.inc

; Zero-page segment (because of non-standard for CA65 name we need to mark it as :zp)
.segment "ZPAGE": zp

; Temporary variables and procedure's parameters with overall size of 8 bytes.
; If procedures use them as inputs or use as vars it should be mentioned in comments.
; Define four words (2 bytes each):
arg0w:		.word 0
arg1w:		.word 0
arg2w:		.word 0
arg3w:		.word 0
; ...and eight bytes which are located in words in ascending order...
; (that is arg2w and arg4b/arg5b are located in the same space in zero-page)
arg0b		= arg0w + 0
arg1b		= arg0w + 1
arg2b		= arg1w + 0
arg3b		= arg1w + 1
arg4b		= arg2w + 0
arg5b		= arg2w + 1
arg6b		= arg3w + 0
arg7b		= arg3w + 1

; Bit flags of state of gamepads (procedure update_keys updates them).
keys1_is_down:	.byte 0
keys2_is_down:	.byte 0

; Segment of uninitialized data in console's RAM.
; All data here must be filled with zeroes in code, otherwise
; linker will generate error. 
; But we do not know their actual values at the start of console!
; So we need to zero them in procedure warm_up.
.segment "RAM"			
				
; Bit flags of previous state of gamepads (procedure update_keys updates them).
keys1_prev:	.byte 0
keys2_prev:	.byte 0
; Bit flags of gamepads keys which were not set in keys1_prev and are set in keys_is_down
; (procedure update_keys updates them)..
keys1_was_pressed:	.byte 0
keys2_was_pressed:	.byte 0

; Segment of cartridge ROM - last of it's 16 Кб ($C000-FFFF).
.segment "ROM_H"

; update_keys - reread state of gampad keys from both of them.
; previous keysX_is_down -> keysX_prev
; keys which are down now -> keysX_is_down
; keys which were pressed between prev and now -> keyX_was_pressed
; This code is based on article: https://wiki.nesdev.com/w/index.php/Controller_reading_code
; Alert! This code will be unstable with activated DPCM sound channel! Read article!
.proc update_keys
	; Save previous key states in keysX_prev
	store keys1_prev, keys1_is_down
	store keys2_prev, keys1_is_down
	; Initiate gamepad reading by writing 1 into lowest bit of JOY_PAD1
	lda # $01		; Load 1 into A
	sta JOY_PAD1		; save it to JOY_PAD1
	sta keys2_is_down	; save 1 to keys2_is_down - we'll use it as stop bit in carry flag
	lsr a			; This shift to right will zero accumulator
	sta JOY_PAD1		; Writing 0 to JOY_PAD1 will fix gamepad state in it's internal shift register
	
loop:	lda JOY_PAD1		; Load state of next button from shift register
	and # %00000011		; Bit 0 is for standard gamepad, bit 1 is for gamepad in extension port
	cmp # $01		; Carry flag will be set to 1 if A is not 0 (that is button is pressed)
	rol keys1_is_down	; Rotate keys1_pressed through carry flag. That is, if Ki is i-th bit, then:
				; NewCarry <- K7 <- K6 <- ... <- K1 <- K0 <- OldCarry

	lda JOY_PAD2		; Repeat all above for the second gamepad...
	and # %00000011
	cmp # $01
	rol keys2_is_down	; But after 8-th ROL carry flag will be filled with 1
	bcc loop		; which we had placed in the start and loop will be over.
	; Update keysX_was_pressed - this is logical AND of new state with NOT of previous one,
	; that is "bits which were 0 before and became 1 now".
	lda keys1_prev		; Load previous state in A,
	eor # $FF		; invert it's bits ('A XOR $FF' works as 'NOT A'),
	and keys1_is_down	; apply AND with new state,
	sta keys1_was_pressed	; and save result to keys_was_pressed.
	
	lda keys2_prev		; Repeat all above for the second gamepad...
	eor # $FF
	and keys2_is_down
	sta keys2_was_pressed
	rts			; return from procedure
.endproc

; clear_ram - fill by 0 zero-page and memory region $0200-07FF
; destroys: arg0w
.proc clear_ram
	; Zeroing of zero-page
	lda # $00		; a = 0
	ldx # $00		; x = 0
loop1:	sta $00, x		; [ $00 + x ] = y
	inx			; x++
	bne loop1		; if ( x != 0 ) goto loop1
	; Zeroing of $200-$7FF
	store_addr arg0w, $0200	; arg0w = $2000
	lda # $00		; a = 0
	ldx # $08		; x = 8
	ldy # $00		; y = 0
loop2:	sta (arg0w), y		; [ [ arg0w ] + y ] = a
	iny			; y++
	bne loop2		; if ( y != 0 ) goto loop2
	inc arg0w + 1		; increment high byte of arg0w
	cpx arg0w + 1		; check if it becomes equal to X (8)
	bne loop2		; if not - repeat
	rts			; return from procedure
.endproc

; warm_up - wait for PPU to warm up
.proc warm_up
	lda # 0			; a = 0
	sta PPU_CTRL		; Disable NMI interrupt (VBlank)
	sta PPU_MASK		; Disable video out (background and sprites)
	sta APU_DMC_0		; Disable IRQ of digital sound generator
	bit APU_STATUS		; Reading APU_STATUS disables frame interrupt flag
	sta APU_CONTROL		; Disable all sound channels
	; Disable IRQ FRAME_COUNTER IRQ
	store APU_FRAME_COUNTER, # APU_FC_IRQ_OFF	
	cld			; Disable decimal mode (Ricoh 2A03 doesn't have it, so just for debuggers)

	; Wait for first VBlank form PPU by reading PPU_STATUS
	bit PPU_STATUS		; This instruction is needed because possible false condition on startup
wait1:	bit PPU_STATUS		; BIT writes highest bit of argument into sign flag
	bpl wait1		; so bpl (branch on plus) branches if bit PPU_STAT_VBLANK is zero

	; Clear RAM while waiting for second VBlank (we have a lot of time)...
	jsr clear_ram

	; Wait for next VBlank
wait2:	bit PPU_STATUS
	bpl wait2	
	rts			; return from procedure
.endproc