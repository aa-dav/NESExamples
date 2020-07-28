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
	lda # $01		; После записи в порт 1 состояния кнопок начинают в геймпадах
	sta JOY_PAD1		; постоянно записываться в регистры-защёлки...
	sta keys2_is_down	; Этот же единичный бит используем для остановки цикла ниже
	lsr a			; Обнуляем аккумулятор (тут быстрее всего сделать это сдвигом вправо)
	sta JOY_PAD1		; Запись 0 в JOY_PAD1 фиксирует регистры-защёлки и их можно считывать
	
loop:	lda JOY_PAD1		; Грузим очередную кнопку от первого контроллера
	and # %00000011		; Нижний бит - стандартный контроллер, следующий - от порта расширения
	cmp # $01		; Бит Carry установится в 1 только если в аккумуляторе не 0 (т.е. нажатие)
	rol keys1_is_down	; Прокрутка keys1_pressed через Carry, если Ki - это i-ый бит, то:
				; NewCarry <- K7 <- K6 <- ... <- K1 <- K0 <- OldCarry
	lda JOY_PAD2		; Делаем всё то же самое для второго геймпада...
	and # %00000011
	cmp # $01
	rol keys2_is_down	; Однако на прокрутке keys2_pressed в восьмой раз в Carry выпадет
	bcc loop		; единица которую мы положили в самом начале и цикл завершится.
	; Далее обновляем keysX_was_pressed - логический AND нового состояния кнопок с NOT предыдущего,
	; т.е. "то что было отжато ранее, но нажато сейчас".
	lda keys1_prev		; берём предыдущее состояние,
	eor # $FF		; инвертируем (через A XOR $FF),
	and keys1_is_down	; накладываем по AND на новое состояние,
	sta keys1_was_pressed	; и сохраняем в keys_was_pressed
	
	lda keys2_prev		; и всё то же самое для второго геймпада...
	eor # $FF
	and keys2_is_down
	sta keys2_was_pressed
	rts			; возвращаемся из процедуры
.endproc

; clear_ram - очистка памяти zero page и участка $0200-07FF
; портит: arg0w
.proc clear_ram
	; Очистка zero page
	lda # $00		; a = 0
	ldx # $00		; x = 0
loop1:	sta $00, x		; [ $00 + x ] = y
	inx			; x++
	bne loop1		; if ( x != 0 ) goto loop1
	; Очищаем участок памяти с $200-$7FF
	store_addr arg0w, $0200	; arg0w = $2000
	lda # $00		; a = 0
	ldx # $08		; x = 8
	ldy # $00		; y = 0
loop2:	sta (arg0w), y		; [ [ arg0w ] + y ] = a
	iny			; y++
	bne loop2		; if ( y != 0 ) goto loop2
	inc arg0w + 1		; увеличиваем старший байт arg0w
	cpx arg0w + 1		; и если он не достиг границы в X
	bne loop2		; то повторяем цикл
	rts			; возврат из процедуры
.endproc

; warm_up - "разогрев" - после включения дождаться пока PPU дойдёт
; до рабочего состояния после чего с ним можно работать.
.proc warm_up
	lda # 0			; a = 0
	sta PPU_CTRL		; Отключим прерывание NMI по VBlank
	sta PPU_MASK		; Отключим вывод графики (фона и спрайтов)
	sta APU_DMC_0		; Отключить прерывание IRQ цифрового звука
	bit APU_STATUS		; Тоже как то влияет на отключение IRQ
	sta APU_CONTROL		; Отключить все звуковые каналы
	; Отключить IRQ FRAME_COUNTER (звук)
	store APU_FRAME_COUNTER, # APU_FC_IRQ_OFF	
	cld			; Отключить десятичный режим (который на Ricoh 2A03 и не работает)

	; Ждём наступления первого VBlank от видеочипа
	bit PPU_STATUS		; Первый надо пропустить из-за ложного состояния при включении
wait1:	bit PPU_STATUS		; Инструкция bit записывает старший бит аргумента во флаг знака
	bpl wait1		; Поэтому bpl срабатывает при нулевом бите PPU_STAT_VBLANK

	; Пока ждём второго VBlank - занулим RAM
	jsr clear_ram

	; Ждём еще одного VBlank
wait2:	bit PPU_STATUS
	bpl wait2	
	rts			; Выходим из процедуры
.endproc