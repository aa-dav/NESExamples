; Подключаем заголовок библиотеки Famicom/NES/Денди
.include "src/neslib.inc"
; Подключаем заголовок библиотеки маппера MMC3
.include "src/mmc3.inc"

; Сегмент векторов прерываний и сброса/включения - находится в самых
; последних шести байтах адресного пространства процессора ($FFFA-FFFF)
; и содержит адреса по которым процессор переходит при наступлении события
.segment "VECTORS"	
	.addr nmi	; Вектор прерывания NMI (процедура nmi ниже)
	.addr reset	; Вектор сброса/включения (процедура reset ниже)
	.addr irq	; Вектор прерывания IRQ (процедура irq ниже)

.segment "ZPAGE": zp	; Сегмент zero page, это надо пометить через ": zp"
vblank_counter:	.byte 0	; Счётчик прерываний VBlank

; Для бесшовного скроллинга надо еще до входа в прерывание IRQ иметь четыре байтовых величины:
scroll_top:	.byte 0	; Верхние биты X и Y сдвинутые на 2 бита влево (%0000YX00), пойдут первыми в PPU_ADDR
scroll_y:	.byte 0	; Нижние 8 бит Y, пойдут вторыми в PPU_SCROLL
scroll_x:	.byte 0	; Нижние 8 бит X, пойдут на третьем шаге в PPU_SCROLL
scroll_bottom:	.byte 0	; На четвёртом шаге в PPU_ADDR надо записать ((Y & $F8) << 2) | (X >> 3) - эту величину надо вычислить


.segment "RAM"		; Сегмент неинициализированных данных в RAM

.segment "ROM_0"	; Страница данных 0 (первые 8Кб из 64 ROM картриджа) для адреса $8000
.segment "ROM_1"	; Страница данных 1 (вторые 8Кб из 64 ROM картриджа) для адреса $8000
.segment "ROM_2"	; Страница данных 2...
.segment "ROM_3"	; Страница данных 3...
.segment "ROM_4"	; Страница кода 4 (пятые 8Кб из 64 ROM картриджа) для адреса $A000
.segment "ROM_5"	; Страница кода 5 (шестые 8Кб из 64 ROM картриджа) для адреса $A000

; С MMC3 в сегменте ROM_H у нас располагаются последние страницы ROM картриджа
; т.е. в данной конфигурации с 64Кб ROM - 6 и 7 по порядку.
.segment "ROM_H"	; Сегмент данных в ПЗУ картриджа (страницы $C000-$FFFF)
palettes:		; Подготовленные наборы палитр (для фона и для спрайтов)
	; Повторяем наборы 2 раза - первый для фона и второй для спрайтов
	.repeat 2
	.byte $0F, $00, $10, $20	; Черный, серый, светло-серый, белый
	.byte $0F, $16, $1A, $11	; -, красный, зеленый, синий
	.byte $0F, $1A, $11, $16	; -, зеленый, синий, красный
	.byte $0F, $11, $16, $1A	; -, синий, красный, зеленый
	.endrep
  
; nmi - процедура обработки прерывания NMI
; Обрабатывает наступление прерывания VBlank от PPU (см. процедуру wait_nmi)
.proc nmi
	inc vblank_counter	; Просто увеличим vblank_counter
	rti			; Возврат из прерывания
.endproc

; wait_nmi - ожидание наступления прерывания VBlank от PPU
; Согласно статье https://wiki.nesdev.com/w/index.php/NMI ожидание VBlank
; опросом верхнего бита PPU_STATUS в цикле может пропускать целые кадры из-за
; специфической гонки состояний, поэтому правильнее всего перехватывать прерывание,
; в нём наращивать счётчик (процедура nmi выше) и ожидать его изменения как в коде ниже.
.proc wait_nmi
	lda vblank_counter
notYet:	cmp vblank_counter
	beq notYet
	rts
.endproc

; fill_palettes - заполнить все наборы палитр данными из адреса в памяти
; вход:
;	arg0w - адрес таблицы с набором палитр (2 * 4 * 4 байта)
.proc fill_palettes
	fill_ppu_addr $3F00	; палитры в VRAM находятся по адресу $3F00
	ldy # 0			; зануляем счётчик и одновременно индекс
loop:
	lda (arg0w), y		; сложный режим адресации - к слову лежащему в zero page
				; по однобайтовому адресу arg0w прибавляется Y и 
				; в A загружается байт из полученного адреса
	sta PPU_DATA		; сохраняем в VRAM
	iny			; инкрементируем Y
	cpy # 2 * 4 * 4		; проверяем на выход за границу цикла
	bne loop		; и зацикливаемся если она еще не достигнута
	rts			; выходим из процедуры
.endproc

; fill_attribs - заполнить область цетовых атрибутов байтом в аккумуляторе
; адрес в PPU_ADDR уже должен быть настроен на эту область атрибутов!
.proc fill_attribs
	ldx # 64		; надо залить 64 байта цветовых атрибутов
loop:	sta PPU_DATA		; записываем в VRAM аккумулятор
	dex			; декрементируем X
	bne loop		; цикл по счётчику в X
	rts			; возврат из процедуры
.endproc

; num_to_spr - сконвертировать число в arg0b в шестнадцитиричное представление
; и записать старшую цифру как код ASCII по адресу { SPR_TBL, x }, а младшую
; по адресу на 4 байта больше. Т.е. X должен быть настроен на поле TILE
; первого спрайта.
.proc num_to_spr
	lda # $F0		; Оставляем только 4 верхних бита
	and arg0b		; из arg0b в аккумуляторе и...
	lsr
	lsr
	lsr			; сдвигаем их на 4 бита правее так что
	lsr			; в A теперь лежит верхняя цифра
	cmp # 10		; проверяем не меньше ли она чем 10
	bcs ten1		; и если нет, то идём на код букв A-F
	clc			; иначе складываем с кодом '0' чтобы
	adc # '0'		; получить ASCII-код цифры 0-9
	jmp next1		; и идём на продолжение
ten1:	clc			; В случае буквы надо сложить цифру
	adc # 'A' - 10		; с кодом 'A' за вычетом десяти
next1:	sta SPR_TBL, x		; Сохраняем результат в память спрайтов
	inx
	inx
	inx			; И увеличиваем x на 4 чтобы перейти
	inx			; к следующему спрайту

	lda # $0F		
	and arg0b		; Оставляем в аккумуляторе 4 нижних бита цифры
	cmp # 10		; проверяем не меньше ли она чем 10
	bcs ten2		; и если нет, то идём на код букв A-F
	clc			; иначе складываем с кодом '0' чтобы
	adc # '0'		; получить ASCII-код цифры 0-9
	jmp next2		; и идём на продолжение
ten2:	clc			; В случае буквы надо сложить цифру
	adc # 'A' - 10		; с кодом 'A' за вычетом десяти
next2:	sta SPR_TBL, x		; Сохраняем результат в память спрайтов
	rts			; Возвращаемся из подпрограммы
.endproc

; irq - процедура обработки прерывания IRQ.
; Она вызывается при наступлении прерывания от MMC3, т.е. по счётчику строк.
.proc irq
	pha		; сохраняем аккумулятор в стек
	txa		; помещаем X в A
	pha		; сохраняем снова A (т.е. X) в стек
	; выключаем прерывание MMC3 и одновременно этим сбрасываем флаг
	; наступившего прерывания, иначе прерывание будет генерироваться
	; каждый сканлайн!
	sta MMC3_IRQ_OFF
	; подождать следующего HBlank искуственной паузой
	ldx SPR_FLD_X( 0 )	; в качестве величины паузы берём координату X спрайта 0
loop2:	dex
	bne loop2
	
	store PPU_ADDR, scroll_top	; как можно быстрее сохраняем 
	store PPU_SCROLL, scroll_y	; заранее вычисленные величины
	store PPU_SCROLL, scroll_x	; в регистры PPU ADDR/SCROLL/SCROLL/ADDR
	store PPU_ADDR, scroll_bottom	; для полноценной подмены скроллинга

	;sta MMC3_IRQ_ON	; здесь не включим прерывания MMC3
	
	pla		; восстановим A из стека
	tax		; и скопируем в X, т.к. это был он
	pla		; а теперь восстановим A
	rti		; Инструкция возврата из прерывания
.endproc

; reset - стартовая точка всей программы - диктуется вторым адресом в сегменте 
; VECTORS оформлена как процедура, но вход в неё происходит при включении консоли 
; или сбросу её по кнопке RESET, поэтому ей некуда "возвращаться" и она 
; принудительно инициализирует память и стек чтобы работать с чистого листа.
.proc reset
	; ***********************************************************
	; * Первым делом нужно привести систему в рабочее состояние *
	; ***********************************************************
	sei			; запрещаем прерывания
	ldx # $FF		; чтобы инициализировать стек надо записать $FF в X
	txs			; и передать его в регистр вершины стека командой 
				; Transfer X to S (txs)
	
	sta MMC3_IRQ_OFF	; Выключим IRQ маппера
	
	; Теперь можно пользоваться стеком, например вызывать процедуры
	jsr warm_up		; вызовем процедуру "разогрева" (см. neslib.s)

	store MMC3_MIRROR, # MMC3_MIRROR_V	; Выставим вертикальное зеркалирование
	store MMC3_RAM_PROTECT, # 0		; Отключим RAM (если бы она даже была)

	store_addr arg0w, palettes	; параметр arg0w = адрес наборов палитр
	jsr fill_palettes		; вызовем процедуру копирования палитр в PPU
	
	; **********************
	; * Прячем все спрайты *
	; **********************
	lda # $FF		; Запоминаем в аккумуляторе $FF - координату по Y
	ldx # 0			; X настраиваем на начало таблицы спрайтов
loop1:	sta SPR_TBL, x		; Записываем $FF в координату Y текущего спрайта
	inx
	inx
	inx
	inx			; Увеличиваем X на 4
	bne loop1		; И повторяем цикл пока X не станет равен 0
	
	; Нулевой спрайт '|' в позицию ( 12, 24 ) с палитрой 1
	set_sprite 0, # 12, # 24, # '|', # 1
	; 4 спрайта под 4 шестнадцатиричных цифры разделенные пустым местом
	set_sprite 1, # 8 * 10, # 100, # '0', # 2
	set_sprite 2, # 8 * 11, # 100, # '0', # 2
	set_sprite 3, # 8 * 10, # 108, # '0', # 2
	set_sprite 4, # 8 * 11, # 108, # '0', # 2
	; 4 "подкладочных" спрайта залитых белым цветом под цифрами чтобы 
	; из под них не просвечивал задний фон и они чётко выделялись.
	set_sprite 5, # 8 * 10, # 100, # 3, # 0
	set_sprite 6, # 8 * 11, # 100, # 3, # 0
	set_sprite 7, # 8 * 10, # 108, # 3, # 0
	set_sprite 8, # 8 * 11, # 108, # 3, # 0

	fill_page_by PPU_SCR0, # $16	; Сперва целиком зальём экранные 
	fill_page_by PPU_SCR1, # $16	; области символом небольшого кружка.
	
frame_top	= 3		; Верхняя координата в тайлах рамки
frame_btm	= 28		; Нижняя координата в тайлах рамки

	; Первые 3 строки PPU_SCR0 зальём символом из вертикальных полос
	fill_vpage_line PPU_SCR0, 0, 0, # 3 * 32, # $07
	; Краевые уголки рамки
	poke_vpage PPU_SCR0, 0, frame_top, # $10
	poke_vpage PPU_SCR0, 0, frame_btm, # $12
	poke_vpage PPU_SCR1, 31, frame_top, # $11
	poke_vpage PPU_SCR1, 31, frame_btm, # $13
	; Горизонтальные линии сверху и снизу рамки в обеих экранных областях
	fill_vpage_line PPU_SCR0, 1, frame_top, # 31, # $15
	fill_vpage_line PPU_SCR0, 1, frame_btm, # 31, # $15
	fill_vpage_line PPU_SCR1, 0, frame_top, # 31, # $15
	fill_vpage_line PPU_SCR1, 0, frame_btm, # 31, # $15
	; Включим инкремент PPU_ADD на 32 чтобы рисовать вертикальные линии
	store PPU_CTRL, # PPU_ADDR_INC32
	; Две вертикальных линии рамки
	fill_vpage_line PPU_SCR0,  0,  frame_top + 1, # (frame_btm - frame_top - 1), # $14
	fill_vpage_line PPU_SCR1, 31,  frame_top + 1, # (frame_btm - frame_top - 1), # $14
	store PPU_CTRL, # 0		; Вернёмся обратно в режим инкремента PPU_ADDR на 1
	
	; Зальём цветовые атрибуты обеих экранных областей нулевой палитрой
	fill_ppu_addr PPU_SCR0_ATTRS
	lda # 0
	jsr fill_attribs
	fill_ppu_addr PPU_SCR1_ATTRS
	lda # 0
	jsr fill_attribs

	; И первый и второй банки CHR настроим на страницы 4-7
	mmc3_set_bank_page # MMC3_CHR_H0, # 4
	mmc3_set_bank_page # MMC3_CHR_H1, # 6
	
	mmc3_set_bank_page # MMC3_CHR_Q0, # 4
	mmc3_set_bank_page # MMC3_CHR_Q1, # 5
	mmc3_set_bank_page # MMC3_CHR_Q2, # 6
	mmc3_set_bank_page # MMC3_CHR_Q3, # 7
	
	store scroll_y, # 24	; скроллинг по Y инициализируем в 24 (а по X будет 0 от зануления памяти)

	; **********************************************
	; * Стартуем видеочип и запускаем все процессы *
	; **********************************************
	; Включим генерацию прерываний по VBlank и источником тайлов для спрайтов
	; сделаем второй банк видеоданных
	store PPU_CTRL, # PPU_VBLANK_NMI | PPU_SPR_TBL_1000
	; Включим отображение спрайтов и то что они отображаются в левых 8 столбцах пикселей
	store PPU_MASK, # PPU_SHOW_BGR | PPU_SHOW_LEFT_BGR | PPU_SHOW_SPR | PPU_SHOW_LEFT_SPR
	cli		; Разрешаем прерывания
	
	; ***************************
	; * Основной цикл программы *
	; ***************************
main_loop:
	jsr wait_nmi		; ждём наступления VBlank

	; Чтобы обновить таблицу спрайтов в видеочипе надо записать в OAM_ADDR ноль
	store OAM_ADDR, # 0
	; И активировать DMA записью верхнего байта адреса страницы с описаниями
	store OAM_DMA, # >SPR_TBL

	; Обновим на экране числа координат нулевого спрайта
	store arg0b, SPR_FLD_X( 0 )	; Сохраним в arg0b координату X спрайта 0
	ldx # 1 * 4 + SPR_TILE		; в регистре X нацелимся на номер тайла спрайта 1
	jsr num_to_spr			; сконвертируем arg0b в число с записью цифр в спрайты 1 и 2
	store arg0b, SPR_FLD_Y( 0 )	; Сохраним в arg0b координату Y спрайта 0
	ldx # 3 * 4 + SPR_TILE		; в регистре X нацелимся на номер тайла спрайта 3
	jsr num_to_spr			; сконвертируем arg0b в число с записью цифр в спрайты 3 и 4
	
	; PPU_CTRL надо обновить чтобы выставить в 0 верхние биты 
	; скроллинга содержащиеся в этом регистре...
	store PPU_CTRL, # PPU_VBLANK_NMI | PPU_SPR_TBL_1000
	store PPU_SCROLL, # 0	; Перед началом кадра выставим скроллинг
	store PPU_SCROLL, # 0	; в (0, 0) чтобы панель рисовалась фиксированно
	
	; ********************************************************
	; * После работы с VRAM можно заняться другими вещами... *
	; ********************************************************
	
	; Инициализирующим значением для счётчика сканлайнов делаем координату Y нулевого спрайта
	store MMC3_IRQ_COUNTER, SPR_FLD_Y( 0 )
	; Выставим флаг того, что на следующем сканлайне надо перезагрузить
	; счётчик сканлайнов значением из IRQ_COUNTER
	sta MMC3_IRQ_RELOAD
	; Включим генерацию прерывания IRQ маппером
	sta MMC3_IRQ_ON
	
	jsr update_keys		; Обновим состояние кнопок опросив геймпады

	; Здесь будет полезен макрос "перейти если кнопка нажата", который
	; в отличие от привычного уже делает прыжок по условию без 'НЕ'.
.macro jump_if_keys1_is_down key_code, label
	lda keys1_is_down
	and # key_code
	bne label
.endmacro	

	; Если нажата кнопка (A), то идём на непрерывное изменение координат спрайта
	jump_if_keys1_is_down KEY_A, sprite_moves
	; Если нажата кнопка (B), то идём на пошаговое изменение координат спрайта
	jump_if_keys1_is_down KEY_B, sprite_steps

	; Иначе обрабатываем изменение скроллинга:
	jump_if_keys1_is_not_down KEY_LEFT, skip_left0	; Если не нажата Влево - идём дальше
	dec scroll_x	; уменьшим scroll_x на 1
	lda # $FF	; загрузим в A $FF для сравнения 
	cmp scroll_x	; и сравним с scroll_x
	bne skip_left0	; если он не равен ($FF), то идём дальше
	lda # %0100	; иначе значит он провернулся и мы грузим в A битовую маску %100
	eor scroll_top	; чтобы по XOR с A инвертировтать этот бит в scroll_top
	sta scroll_top	; и сохраняем полученный байт из аккумулятора обратно
skip_left0:
	jump_if_keys1_is_not_down KEY_RIGHT, skip_right0	; Не нажата Вправо - идём дальше
	inc scroll_x	; увеличим scroll_x на 1
	bne skip_right0	; и если получился не ноль - идём дальше
	lda # %0100	; иначе значит он провернулся и мы грузим в A битовую маску %100
	eor scroll_top	; чтобы по XOR с A инвертировать этот бит в scroll_top
	sta scroll_top	; и сохраняем полученный байт из аккумулятора обратно
skip_right0:
	jump_if_keys1_is_not_down KEY_UP, skip_up0		; Не нажата Вверх - идём дальше
	dec scroll_y	; уменьшим scroll_y на 1
	lda # $FF	; загрузим в A $FF для сравнения 
	cmp scroll_y	; и сравним с scroll_y
	bne skip_up0	; если он не равен ($FF), то идём дальше
	lda # %1000	; иначе значит он провернулся и мы грузим в A битовую маску %1000
	eor scroll_top	; чтобы по XOR с A инвертировтать этот бит в scroll_top
	sta scroll_top	; и сохраняем полученный байт из аккумулятора обратно
	; А вот scroll_y при провороте через 0 вниз надо выставить в 239, т.к. в видеостраницах
	; по вертикали 240 строк пикселей и нельзя 'заезжать' на несуществующие...
	store scroll_y, # 239	
skip_up0:
	jump_if_keys1_is_not_down KEY_DOWN, skip_down0	; Не нажата Вниз - идём дальше
	inc scroll_y	; увеличим scroll_y на 1
	lda # 240	; загрузим в A 240 для сравнения 
	cmp scroll_y	; и сравним с scroll_y
	bne skip_down0	; если он не равен (240), то идём дальше
	lda # %1000	; иначе значит он вылез за верхнюю границу и мы грузим в A битовую маску %1000
	eor scroll_top	; чтобы по XOR с A инвертировтать этот бит в scroll_top
	sta scroll_top	; и сохраняем полученный байт из аккумулятора обратно
	; scroll_y при этом надо принудительно выставить в 0, т.к. в видеостраницах по вертикали
	; 240 строк пикселей и нельзя 'заезжать' на несуществующие...
	store scroll_y, # 0
skip_down0:
	jmp keys_check_end	; Выходим из проверки нажатых кнопок
	
sprite_moves:	
	; Проверяем кнопки на непрерывный сдвиг координат нулевого спрайта:
	jump_if_keys1_is_not_down KEY_LEFT, skip_left1
	dec SPR_FLD_X( 0 )
skip_left1:
	jump_if_keys1_is_not_down KEY_RIGHT, skip_right1
	inc SPR_FLD_X( 0 )
skip_right1:
	jump_if_keys1_is_not_down KEY_UP, skip_up1
	dec SPR_FLD_Y( 0 )
skip_up1:
	jump_if_keys1_is_not_down KEY_DOWN, skip_down1
	inc SPR_FLD_Y( 0 )
skip_down1:
	jmp keys_check_end	; Выходим из проверки нажатых кнопок
	
sprite_steps:	
	; Проверяем кнопки на попиксельный сдвиг координат нулевого спрайта:
	jump_if_keys1_was_not_pressed KEY_LEFT, skip_left2
	dec SPR_FLD_X( 0 )
skip_left2:
	jump_if_keys1_was_not_pressed KEY_RIGHT, skip_right2
	inc SPR_FLD_X( 0 )
skip_right2:
	jump_if_keys1_was_not_pressed KEY_UP, skip_up2
	dec SPR_FLD_Y( 0 )
skip_up2:
	jump_if_keys1_was_not_pressed KEY_DOWN, skip_down2
	inc SPR_FLD_Y( 0 )
skip_down2:

keys_check_end:

	; Три параметра для скроллинга - scroll_top, scroll_x и scroll_y мы поддерживаем
	; в актуальном состоянии прямо в процессе скроллинга. По сути это нижние 8 бит скроллинга
	; по осям в scroll_x/y, а в scroll_top находятся верхние девятые биты в виде
	; битовой маски '0000YX00'. Однако последний четвёртый параметр - scroll_bottom
	; является более сложным наложением частей scroll_x и scroll_y по маске 
	; по формуле ((Y & $F8) << 2) | (X >> 3) и её надо вычислить перед началом кадра:
	lda scroll_y	; Грузим в аккумулятор scroll_y: Y
	and # $F8	; по AND обнуляем ему нижние 3 бита: Y & $F8
	asl a		; сдвигаем его
	asl a		; влево на 2 бита: (Y & $F8) << 2
	sta arg0b	; и запоминаем в arg0b
	lda scroll_x	; Грузим в аккумулятор scroll_x: X
	lsr a		; сдвигаем его
	lsr a		; вправо на
	lsr a		; три бита: X >> 3
	ora arg0b	; и сочетаем по OR с arg0b: ((Y & $F8) << 2) | (X >> 3)
	sta scroll_bottom	; итог сохраняем в scroll_bottom

	jmp main_loop		; И уходим ждать нового VBlank в бесконечном цикле
.endproc