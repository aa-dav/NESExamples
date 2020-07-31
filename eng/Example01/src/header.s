.segment "HEADER"	; Segment of iNES cartridge header

			; Common options
MAPPER		= 0	; 0 = no mapper (NROM)
MIRRORING	= 1	; videomemory mirroring: 0 - horizontal, 1 - vertical
HAS_SRAM	= 0	; 1 - has SRAM (usually battery-powered) at addresses $6000-7FFF

.byte "NES", $1A	; iNES header 'magic'
.byte 2 		; number of 16Kb banks of code/data for CPU ROM (PRG)
.byte 1 		; number of 8Kb banks of graphics data (CHR)
; Mirroring, SRAM and lower four bits of mapper
.byte MIRRORING | (HAS_SRAM << 1) | ((MAPPER & $0F) << 4)
.byte MAPPER & $F0	; high four bits of mapper
.res 8, 0		; eight zero bytes of unused fields
