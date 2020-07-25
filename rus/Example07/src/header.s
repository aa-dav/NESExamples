.segment "HEADER"	; Переключимся на сегмент заголовка образа картриджа iNES

MAPPER		= 4	; 4 = MMC3
MIRRORING	= 0	; зеркалирование видеопамяти: 0 - горизонтальное, 1 - вертикальное
HAS_SRAM	= 0	; 1 - есть SRAM (как правило на батарейке) по адресам $6000-7FFF

.byte "NES", $1A	; заголовок
.byte 4 		; число 16-килобайтных банков кода/данных
.byte 1 		; число 8-килобайтных банков графики (битмапов тайлов)
; флаги зеркалирования, наличия SRAM и нижние 4 бита номера маппера
.byte MIRRORING | (HAS_SRAM << 1) | ((MAPPER & $0F) << 4)
.byte (MAPPER & $F0) | %1000	; верхние 4 бита номера маппера и признак iNES 2.0
.byte 0			; mapper/submapper numbers
.byte 0			; prg/chr high bits
.byte 0			; prg-ram size
.byte 0			; chr-ram size
.byte 0			; cpu/ppu timings
.byte 0 		; extended console type
.byte 0			; misc roms count
.byte 0			; default expansion device

