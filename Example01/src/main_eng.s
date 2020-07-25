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
	; * Зальём первую видеостраницу расходящимся веером символов начиная с '0' *
	; **************************************************************************
	fill_ppu_addr $2000	; Будем писать в видеостраницу $2000
	; Нам нужны переменные текущей строки (cur_y) и текущего столбца (cur_x)
	; сиволов экрана - для самоописуемости назначаем их как синонимы ячеек
	; памяти в локальных переменных zero page.
cur_x	= arg0b			; текущий столбец (0-31)
cur_y	= arg1b			; текущая строка (0-29) (всего 32*30 символов/тайлов)
	store cur_x, # 0	; cur_x = 0
	store cur_y, # 0	; cur_y = 0
loop_fill:
	lda cur_x		; Сравниваем loc_x (помещённый в A)
	cmp cur_y		; с loc_y и если loc_y > loc_x, то
	bcc cur_y_bigger	; флас Carry будет 0 и тогда мы пропустим
	lda cur_y		; загрузку loc_y в A, т.е. A = min( loc_x, loc_y )
cur_y_bigger:
	clc			; Перед сложением надо сбросить Carry
	adc # $30		; $30 - это символ '0', сложение A даст расходящийся 
				; веер символов вдоль осей.
	sta PPU_DATA		; Сохраним итоговый символ в VRAM
	inc cur_x		; Увеличиваем loc_x
	lda # 32		; и сравниваем его
	cmp cur_x		; с 32 (концом столбцов в текущей строке)
	bne loop_fill		; и если не равны, то новая итерация.
	store cur_x, # 0	; Обнуляем loc_x (сброс итераций по этой переменной)
	inc cur_y		; и увеличиваем loc_y
	lda # 30		; сравнивая его с
	cmp cur_y		; 30 (концом строк)
	bne loop_fill		; и если конец не достигнут - новая итерация.
	
	lda # 0			; атрибуты цвета в палитру 0
	jsr fill_attribs	; заполним оставшуюся область цветовых атрибутов

	; *************************************************************************
	; * Зальём вторую видеостраницу нарастающими по алфавиту символами текста *
	; *************************************************************************
	fill_ppu_addr $2400	; настроим PPU_ADDR на $2400
	ldy # $20		; $20 - это ASCII код пробела в таблице символов
				; и в тестом банке CHR он же номер тайла пробела
	ldx # 32 * 30 / 4	; нужно залить 32*30 тайлов, но чтобы счётчик цикла
				; влез в байт будем сразу лить порциями по 4 тайла
loop_tiles:
	.repeat 4		; код между .repeat и .endrep размножится 4 раза подряд...
	sty PPU_DATA		; сохраняем код символа в VRAM
	iny			; и переходим к следующему символу
	.endrep
	cpy # 80		; сравниваем с концом таблицы символов
	bne loop_skip		; и если конец символов не достигнут, то пропускаем...
	ldy # $20		; сброс опять на ASCII-код пробела
loop_skip:
	dex			; декрементируем счётчик
	bne loop_tiles		; и если он не ноль, то повторяем цикл

	lda # %01010101		; атрибуты цвета в палитру 1
	jsr fill_attribs	; заполним область цветовых атрибутов
	
	; **********************************************
	; * Стартуем видеочип и запускаем все процессы *
	; **********************************************
	; Включим отображение заднего фона (отложим в ppu_ctrl_last)
	store ppu_ctrl_last, # PPU_VBLANK_NMI | PPU_BGR_TBL_1000
	; Обновив ppu_ctrl_last теперь записываем его в PPU_CTRL для применения
	store PPU_CTRL, ppu_ctrl_last
	; Включим отображение заднего фона и левой колонки его пикселей на экране
	store PPU_MASK, # PPU_SHOW_BGR | PPU_SHOW_LEFT_BGR
	cli			; Разрешаем прерывания
	
	store xscroll, # 0	; скроллинг по X и Y инициализируем в 0
	store yscroll, # 0
	store_addr update_addr, $2400	; начальный адрес инкрементации VRAM
	
	; ***************************
	; * Основной цикл программы *
	; ***************************
main_loop:
	jsr wait_nmi		; ждём наступления VBlank

	; ********************************************************************************
	; * Каждый кадр увеличим символ во второй видеостранице и переходим к следующему *
	; ********************************************************************************
	; выставим в PPU_ADDR адрес update_addr для считывания номера тайла
	store PPU_ADDR, update_addr + 1	; сперва старший байт
	store PPU_ADDR, update_addr + 0
	; (!) Заметьте, что выше мы не могли использовать fill_ppu_addr update_addr, т.к.
	; надо чётко понимать разницу между адресом и значением которое по адресу лежит.
	ldx PPU_DATA		; первое чтение из PPU_DATA после смены PPU_ADDR надо игнорировать
	ldx PPU_DATA		; читаем номер тайла/символа в X
	inx			; увеличиваем его
	cpx # $80		; проверяем на выход за максимальный символ (ASCII $80)
	bne skip_x20		; если не вышел - идём дальше
	ldx # $20		; иначе откатываем символ в пробел
skip_x20:			; снова выставляем адрес PPU_DATA т.к. он ушёл вперёд
	store PPU_ADDR, update_addr + 1
	store PPU_ADDR, update_addr + 0
	stx PPU_DATA		; сохраняем инкрементированный символ в VRAM
	
	inc update_addr + 0	; увеличиваем младший байт адреса update_addr
	bne skip_inc_high	; если он не обнулился, то пропускаем
	inc update_addr + 1	; увеличение старшего адреса update_addr
skip_inc_high:
	ldx # $C0		; чтобы проверить не равен ли update_addr адресу $27C0
	cpx update_addr + 0	; сперва сверяем нижний его байт с $C0
	bne end_of_updater	; если не равно - идём дальше
	ldx # $27		; иначе сверяем верхний байт с $27
	cpx update_addr + 1	
	bne end_of_updater	; и если не равно - идём дальше
	; если же update_addr стал равен $27C0 (конец тайлов экрана), то сбрасываем его в начало
	store_addr update_addr, $2400
end_of_updater:

	; *************************************************************
	; * Если нажат SELECT, то сбросим параметры прокрутки в (0,0) *
	; *************************************************************
	; С помощью макроса skip_if_key1_not пропускаем куски кода
	; если не нажата соответствующая кнопка. Здесь - KEY_SELECT
	jump_if_keys1_is_not_down KEY_SELECT, skip_scroll_reset
	store xscroll, # 0	; Занулили параметры прокрутки
	store yscroll, # 0	; в пределах текущего экрана...
	lda ppu_ctrl_last	; А верхние биты прокрутки (или они же - выбор
	and # %11111100		; текущего экрана из четырёх) надо занулить в PPU_CTRL
	sta ppu_ctrl_last	; для чего сбросим их битовой операцией в ppu_ctrl_last.
skip_scroll_reset:

	; *************************************************************
	; * Скроллимся в соответствии с нажатыми кнопками направлений *
	; *************************************************************
swap_x	= arg0b	; Сделаем псевдонимы для переменных: нужно ли изменить верхние биты 
swap_y	= arg1b	; параметров прокрутки по X и Y в ppu_ctrl_last после скроллинга
	store swap_x, # 0	; Верхний бит swap_x будет флагом по X
	store swap_y, # 0	; Верхний бит swap_y будет флагом по Y
	; Если нажата кнопка ВЛЕВО, то надо уменьшить скролл по X
	jump_if_keys1_is_not_down KEY_LEFT, skip_l	; Идём дальше если кнопка не нажата
	dec xscroll		; пока просто уменьшаем xscroll
	lda # $FF		; и проверяем не провернулся ли он через 0
	cmp xscroll		; и не стал ли тогда $FF
	bne skip_l		; если нет, то идём дальше
	store swap_x, # $80	; а если да, то взводим флаг проворота экрана по X
skip_l:	; Если нажата кнопка ВПРАВО, то надо увеличить скролл по X
	jump_if_keys1_is_not_down KEY_RIGHT, skip_r	; Идём дальше если кнопка не нажата
	inc xscroll		; Увеличим xscroll
	bne skip_r		; Сразу можно тестировать на 0 и если он им не стал, то идём дальше
	store swap_x, # $80	; Иначе значит он "провернулся" из $FF->0 и надо взвести флаг по X
skip_r:	; Если нажата кнопка ВНИЗ, то надо увеличить скролл по Y
	jump_if_keys1_is_not_down KEY_DOWN, skip_d
	inc yscroll		; Увеличим yscroll
	lda # 240		; и проверям не стал ли он равен 240
	cmp yscroll
	bne skip_d		; если нет, то идём дальше
	store yscroll, # 0	; а если да, то надо обнулить yscroll
	store swap_y, # $80	; И взвести флаг проворота экрана по Y
skip_d:	; Если нажата кнопка ВВЕРХ, то надо уменьшить скролл по Y
	jump_if_keys1_is_not_down KEY_UP, skip_u
	dec yscroll		; Уменьшим yscroll
	lda # $FF		; И проверяем не провернулся ли он через 0
	cmp yscroll		; и не стал равным $FF
	bne skip_u		; если нет, то идём дальше
	store yscroll, # 239	; иначе загружаем в yscroll 239
	store swap_y, # $80	; и взводим флаг необходимости проворота экрана по Y
skip_u:	; Теперь можно применить флаги проворота экрана по X и Y если они взведены
	lda ppu_ctrl_last	; Нижние 2 бита ppu_ctrl_last - это то что нам возможно надо поменять
	bit swap_x		; Тестируем зажжён ли старший бит в swap_x
	bpl skip_inv_x		; если нет, то идём дальше (флаг не взведён)
	eor # %001		; иначе инвертируем (через XOR) 0-ой бит ppu_ctrl_last в A
skip_inv_x:	
	bit swap_y		; Тестируем зажжён ли старший бит в swap_y
	bpl skip_inv_y		; если нет, то идём дальше
	eor # %010		; иначе инвертируем (через XOR) 1-ый бит ppu_ctrl_last в A
skip_inv_y:
	sta ppu_ctrl_last	; Сохраняем возможно изменённый ppu_ctrl_last из аккумулятора

	; **************************************************
	; * Применяем все накопленные параметры скроллинга *
	; **************************************************
	store PPU_CTRL, ppu_ctrl_last	; Загружаем состояние PPU из ppu_ctrl_last
	store PPU_SCROLL, xscroll	; Обновляем параметры скроллинга
	store PPU_SCROLL, yscroll

	; ************************************************************
	; * После работы с VRAM можно заняться другими вещами        *
	; * чтобы не занимать ценное время VBlank ничем кроме этого. *
	; * Теперь можно, например, обновить состояние кнопок.       *
	; ************************************************************
	jsr update_keys		; Обновим состояние кнопок опросив геймпады
	
	jmp main_loop		; И уходим ждать нового VBlank в бесконечном цикле
.endproc
