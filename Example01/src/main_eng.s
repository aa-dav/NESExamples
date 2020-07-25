; Include header for Famicom/NES library
.include "src/neslib.inc"

; Segment of vectors of interrupts and reset vector is located
; in last six bytes of CPU address space ($FFFA-FFFF).
.segment "VECTORS"	
	.addr nmi	; Vector of NMI interrupt (see procedure nmi below)
	.addr reset	; Vector of reset (start) address of code (procedure reset below)
	.addr irq	; Vector of IRQ interrupt (procedure irq below)

.segment "ZPAGE": zp	; Zero page segment (because of non-standard naming must be marked as ": zp"
vblank_counter:	.byte 0	; VBlank interrupt counter

.segment "RAM"		; Segment of uninitialized data in RAM
ppu_ctrl_last:	.byte 0	; Last value written to port PPU_CTRL
xscroll:	.byte 0	; X scrolling value (inside base videopage)
yscroll:	.byte 0	; Y scrolling value (inside base videopage)
update_addr:	.word 0	; Current address in VRAM of symbol updating procedure

.segment "ROM_L"	; Segment of data in cartridge ROM (pages $C000-$FFFF)
palettes:		; Palette sets (identical for background and sprites)
	; Repeat data two times for background and sprites
	.repeat 2	
	.byte $0F, $00, $10, $20	; Black, gray, light-gray and white
	.byte $0F, $16, $1A, $11	; Black, red, green and blue
	.byte $0F, $00, $10, $20	; Others are not used
	.byte $0F, $00, $10, $20
	.endrep
  
.segment "ROM_H"	; Segment of code in cartridge ROM (pages $C000-$FFFF)

; irq - IRQ interrupt processing routine
; For this example it's just dummy code doing nothing
.proc irq
	rti		; Return from interrupt
.endproc

; nmi - NMI interrupt processing routine
; It processes VBlank event from PPU (see procedure wait_nmi below)
.proc nmi
	inc vblank_counter	; Just increase vblank_counter byte
	rti			; Return from interrupt
.endproc

; wait_nmi - waiting of VBlank event from PPU
; According to article https://wiki.nesdev.com/w/index.php/NMI waiting for VBlank
; via continous reading of high bit of PPU_STATUS could skip events
; because of specific race conditions. So one of correct ways of waiting for VBlank is to
; increase VBlank counter in guaranteed irq and wait for it's change in code below.
.proc wait_nmi
	lda vblank_counter	; remember old vblank_counter value in accumulator
notYet:	cmp vblank_counter	; compare accumulator with vblank_counter
	beq notYet		; if they are equal - repeat comparison
	rts			; return from interrupt
.endproc

; fill_palettes - fill all palettes with data from memory
; input:
;	arg0w - address of palettes set (2 * 4 * 4 bytes long)
.proc fill_palettes
	fill_ppu_addr $3F00	; pallettes in VRAM are located at address $3F00
	ldy # 0			; set counter and index to zero
loop:
	lda (arg0w), y		; complex addressing mode: sum of word in zero-page
				; (arg0w) and Y is used as address of byte which
				; is loaded into A
	sta PPU_DATA		; save it in VRAM
	iny			; increment Y
	cpy # 2 * 4 * 4		; ckeck it for loop upper bound
	bne loop		; and repeat loop if it's not reached
	rts			; exit from procedure
.endproc

; fill_attribs - fill color attributes in videopage with byte in A
; input:
;	Address in PPU_ADDR must be already set to videopage color attributes
;	and PPU_ADDR incrementing value must be set to 1.
;	A - byte to fill in
.proc fill_attribs
	ldx # 64		; color attributes have size of 64 bytes, load 64 in X
loop_colors:
	sta PPU_DATA		; write accumulator into VRAM
	dex			; decrement X
	bne loop_colors		; loop for counter in X
	rts			; exit from procedure
.endproc

; reset - startinf address of program (set up in VECTORS segment).
; It uses .proc keyword for convenience, but it's not returnable procedure (nowhere to return).
.proc reset
	; **********************************************
	; * At start we need to initialize all systems *
	; **********************************************
	sei			; disable interrupts
	ldx # $FF		; to initialize stack we need write $FF to X
	txs			; and transfer it to stack register
	; Now we can call procedures
	jsr warm_up		; call warm up procedure (see neslib.s)
	
	store_addr arg0w, palettes	; save address of palettes set in arg0w word
	jsr fill_palettes	; call copying of palettes into PPU
	
	; **************************************************************************
	; * ������ ������ ������������� ������������ ������ �������� ������� � '0' *
	; **************************************************************************
	fill_ppu_addr $2000	; ����� ������ � ������������� $2000
	; ��� ����� ���������� ������� ������ (cur_y) � �������� ������� (cur_x)
	; ������� ������ - ��� ��������������� ��������� �� ��� �������� �����
	; ������ � ��������� ���������� zero page.
cur_x	= arg0b			; ������� ������� (0-31)
cur_y	= arg1b			; ������� ������ (0-29) (����� 32*30 ��������/������)
	store cur_x, # 0	; cur_x = 0
	store cur_y, # 0	; cur_y = 0
loop_fill:
	lda cur_x		; ���������� loc_x (���������� � A)
	cmp cur_y		; � loc_y � ���� loc_y > loc_x, ��
	bcc cur_y_bigger	; ���� Carry ����� 0 � ����� �� ���������
	lda cur_y		; �������� loc_y � A, �.�. A = min( loc_x, loc_y )
cur_y_bigger:
	clc			; ����� ��������� ���� �������� Carry
	adc # $30		; $30 - ��� ������ '0', �������� A ���� ������������ 
				; ���� �������� ����� ����.
	sta PPU_DATA		; �������� �������� ������ � VRAM
	inc cur_x		; ����������� loc_x
	lda # 32		; � ���������� ���
	cmp cur_x		; � 32 (������ �������� � ������� ������)
	bne loop_fill		; � ���� �� �����, �� ����� ��������.
	store cur_x, # 0	; �������� loc_x (����� �������� �� ���� ����������)
	inc cur_y		; � ����������� loc_y
	lda # 30		; ��������� ��� �
	cmp cur_y		; 30 (������ �����)
	bne loop_fill		; � ���� ����� �� ��������� - ����� ��������.
	
	lda # 0			; �������� ����� � ������� 0
	jsr fill_attribs	; �������� ���������� ������� �������� ���������

	; *************************************************************************
	; * ������ ������ ������������� ������������ �� �������� ��������� ������ *
	; *************************************************************************
	fill_ppu_addr $2400	; �������� PPU_ADDR �� $2400
	ldy # $20		; $20 - ��� ASCII ��� ������� � ������� ��������
				; � � ������ ����� CHR �� �� ����� ����� �������
	ldx # 32 * 30 / 4	; ����� ������ 32*30 ������, �� ����� ������� �����
				; ���� � ���� ����� ����� ���� �������� �� 4 �����
loop_tiles:
	.repeat 4		; ��� ����� .repeat � .endrep ����������� 4 ���� ������...
	sty PPU_DATA		; ��������� ��� ������� � VRAM
	iny			; � ��������� � ���������� �������
	.endrep
	cpy # 80		; ���������� � ������ ������� ��������
	bne loop_skip		; � ���� ����� �������� �� ���������, �� ����������...
	ldy # $20		; ����� ����� �� ASCII-��� �������
loop_skip:
	dex			; �������������� �������
	bne loop_tiles		; � ���� �� �� ����, �� ��������� ����

	lda # %01010101		; �������� ����� � ������� 1
	jsr fill_attribs	; �������� ������� �������� ���������
	
	; **********************************************
	; * �������� �������� � ��������� ��� �������� *
	; **********************************************
	; ������� ����������� ������� ���� (������� � ppu_ctrl_last)
	store ppu_ctrl_last, # PPU_VBLANK_NMI | PPU_BGR_TBL_1000
	; ������� ppu_ctrl_last ������ ���������� ��� � PPU_CTRL ��� ����������
	store PPU_CTRL, ppu_ctrl_last
	; ������� ����������� ������� ���� � ����� ������� ��� �������� �� ������
	store PPU_MASK, # PPU_SHOW_BGR | PPU_SHOW_LEFT_BGR
	cli			; ��������� ����������
	
	store xscroll, # 0	; ��������� �� X � Y �������������� � 0
	store yscroll, # 0
	store_addr update_addr, $2400	; ��������� ����� ������������� VRAM
	
	; ***************************
	; * �������� ���� ��������� *
	; ***************************
main_loop:
	jsr wait_nmi		; ��� ����������� VBlank

	; ********************************************************************************
	; * ������ ���� �������� ������ �� ������ ������������� � ��������� � ���������� *
	; ********************************************************************************
	; �������� � PPU_ADDR ����� update_addr ��� ���������� ������ �����
	store PPU_ADDR, update_addr + 1	; ������ ������� ����
	store PPU_ADDR, update_addr + 0
	; (!) ��������, ��� ���� �� �� ����� ������������ fill_ppu_addr update_addr, �.�.
	; ���� ����� �������� ������� ����� ������� � ��������� ������� �� ������ �����.
	ldx PPU_DATA		; ������ ������ �� PPU_DATA ����� ����� PPU_ADDR ���� ������������
	ldx PPU_DATA		; ������ ����� �����/������� � X
	inx			; ����������� ���
	cpx # $80		; ��������� �� ����� �� ������������ ������ (ASCII $80)
	bne skip_x20		; ���� �� ����� - ��� ������
	ldx # $20		; ����� ���������� ������ � ������
skip_x20:			; ����� ���������� ����� PPU_DATA �.�. �� ���� �����
	store PPU_ADDR, update_addr + 1
	store PPU_ADDR, update_addr + 0
	stx PPU_DATA		; ��������� ������������������ ������ � VRAM
	
	inc update_addr + 0	; ����������� ������� ���� ������ update_addr
	bne skip_inc_high	; ���� �� �� ���������, �� ����������
	inc update_addr + 1	; ���������� �������� ������ update_addr
skip_inc_high:
	ldx # $C0		; ����� ��������� �� ����� �� update_addr ������ $27C0
	cpx update_addr + 0	; ������ ������� ������ ��� ���� � $C0
	bne end_of_updater	; ���� �� ����� - ��� ������
	ldx # $27		; ����� ������� ������� ���� � $27
	cpx update_addr + 1	
	bne end_of_updater	; � ���� �� ����� - ��� ������
	; ���� �� update_addr ���� ����� $27C0 (����� ������ ������), �� ���������� ��� � ������
	store_addr update_addr, $2400
end_of_updater:

	; *************************************************************
	; * ���� ����� SELECT, �� ������� ��������� ��������� � (0,0) *
	; *************************************************************
	; � ������� ������� skip_if_key1_not ���������� ����� ����
	; ���� �� ������ ��������������� ������. ����� - KEY_SELECT
	jump_if_keys1_is_not_down KEY_SELECT, skip_scroll_reset
	store xscroll, # 0	; �������� ��������� ���������
	store yscroll, # 0	; � �������� �������� ������...
	lda ppu_ctrl_last	; � ������� ���� ��������� (��� ��� �� - �����
	and # %11111100		; �������� ������ �� ������) ���� �������� � PPU_CTRL
	sta ppu_ctrl_last	; ��� ���� ������� �� ������� ��������� � ppu_ctrl_last.
skip_scroll_reset:

	; *************************************************************
	; * ���������� � ������������ � �������� �������� ����������� *
	; *************************************************************
swap_x	= arg0b	; ������� ���������� ��� ����������: ����� �� �������� ������� ���� 
swap_y	= arg1b	; ���������� ��������� �� X � Y � ppu_ctrl_last ����� ����������
	store swap_x, # 0	; ������� ��� swap_x ����� ������ �� X
	store swap_y, # 0	; ������� ��� swap_y ����� ������ �� Y
	; ���� ������ ������ �����, �� ���� ��������� ������ �� X
	jump_if_keys1_is_not_down KEY_LEFT, skip_l	; ��� ������ ���� ������ �� ������
	dec xscroll		; ���� ������ ��������� xscroll
	lda # $FF		; � ��������� �� ����������� �� �� ����� 0
	cmp xscroll		; � �� ���� �� ����� $FF
	bne skip_l		; ���� ���, �� ��� ������
	store swap_x, # $80	; � ���� ��, �� ������� ���� ��������� ������ �� X
skip_l:	; ���� ������ ������ ������, �� ���� ��������� ������ �� X
	jump_if_keys1_is_not_down KEY_RIGHT, skip_r	; ��� ������ ���� ������ �� ������
	inc xscroll		; �������� xscroll
	bne skip_r		; ����� ����� ����������� �� 0 � ���� �� �� �� ����, �� ��� ������
	store swap_x, # $80	; ����� ������ �� "�����������" �� $FF->0 � ���� ������� ���� �� X
skip_r:	; ���� ������ ������ ����, �� ���� ��������� ������ �� Y
	jump_if_keys1_is_not_down KEY_DOWN, skip_d
	inc yscroll		; �������� yscroll
	lda # 240		; � �������� �� ���� �� �� ����� 240
	cmp yscroll
	bne skip_d		; ���� ���, �� ��� ������
	store yscroll, # 0	; � ���� ��, �� ���� �������� yscroll
	store swap_y, # $80	; � ������� ���� ��������� ������ �� Y
skip_d:	; ���� ������ ������ �����, �� ���� ��������� ������ �� Y
	jump_if_keys1_is_not_down KEY_UP, skip_u
	dec yscroll		; �������� yscroll
	lda # $FF		; � ��������� �� ����������� �� �� ����� 0
	cmp yscroll		; � �� ���� ������ $FF
	bne skip_u		; ���� ���, �� ��� ������
	store yscroll, # 239	; ����� ��������� � yscroll 239
	store swap_y, # $80	; � ������� ���� ������������� ��������� ������ �� Y
skip_u:	; ������ ����� ��������� ����� ��������� ������ �� X � Y ���� ��� ��������
	lda ppu_ctrl_last	; ������ 2 ���� ppu_ctrl_last - ��� �� ��� ��� �������� ���� ��������
	bit swap_x		; ��������� ����� �� ������� ��� � swap_x
	bpl skip_inv_x		; ���� ���, �� ��� ������ (���� �� ������)
	eor # %001		; ����� ����������� (����� XOR) 0-�� ��� ppu_ctrl_last � A
skip_inv_x:	
	bit swap_y		; ��������� ����� �� ������� ��� � swap_y
	bpl skip_inv_y		; ���� ���, �� ��� ������
	eor # %010		; ����� ����������� (����� XOR) 1-�� ��� ppu_ctrl_last � A
skip_inv_y:
	sta ppu_ctrl_last	; ��������� �������� ��������� ppu_ctrl_last �� ������������

	; **************************************************
	; * ��������� ��� ����������� ��������� ���������� *
	; **************************************************
	store PPU_CTRL, ppu_ctrl_last	; ��������� ��������� PPU �� ppu_ctrl_last
	store PPU_SCROLL, xscroll	; ��������� ��������� ����������
	store PPU_SCROLL, yscroll

	; ************************************************************
	; * ����� ������ � VRAM ����� �������� ������� ������        *
	; * ����� �� �������� ������ ����� VBlank ����� ����� �����. *
	; * ������ �����, ��������, �������� ��������� ������.       *
	; ************************************************************
	jsr update_keys		; ������� ��������� ������ ������� ��������
	
	jmp main_loop		; � ������ ����� ������ VBlank � ����������� �����
.endproc
