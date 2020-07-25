; Подключаем заголовок библиотеки Famicom/NES/Денди
.include "src/neslib.inc"

; Сегмент векторов прерываний и сброса/включения - находится в самых
; последних шести байтах адресного пространства процессора ($FFFA-FFFF)
; и содержит адреса по которым процессор переходит при наступлении события
.segment "VECTORS"	
	.addr nmi	; Вектор прерывания NMI (процедура nmi ниже)
	.addr reset	; Вектор сброса/включения (процедура reset ниже)
	.addr irq	; Вектор прерывания IRQ (процедура irq ниже)

.segment "ZPAGE": zp	; Сегмент zero page, это надо пометить через ": zp"
vblank_counter:	.byte 0	; Счётчик прерываний VBlank
cur_sprite:	.byte 0	; Нижний байт адреса текущего спрайта в таблцие спрайтов

.segment "RAM"		; Сегмент неинициализированных данных в RAM

.segment "ROM_L"	; Сегмент данных в ПЗУ картриджа (страницы $C000-$FFFF)
palettes:		; Подготовленные наборы палитр (для фона и для спрайтов)
	; Повторяем наборы 2 раза - первый для фона и второй для спрайтов
	.repeat 2	
	.byte $0F, $00, $10, $20	; Черный, серый, светло-серый, белый
	.byte $0F, $16, $1A, $11	; -, красный, зеленый, синий
	.byte $0F, $1A, $11, $16	; -, зеленый, синий, красный
	.byte $0F, $11, $16, $1A	; -, синий, красный, зеленый
	.endrep
  
.segment "ROM_H"	; Сегмент кода в ПЗУ картриджа (страницы $C000-$FFFF)

; irq - процедура обработки прерывания IRQ
; Пока сразу же возвращается из прерывания как заглушка.
.proc irq
	rti		; Инструкция возврата из прерывания
.endproc

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
	; Теперь можно пользоваться стеком, например вызывать процедуры
	jsr warm_up		; вызовем процедуру "разогрева" (см. neslib.s)
	
	store_addr arg0w, palettes	; параметр arg0w = адрес наборов палитр
	jsr fill_palettes	; вызовем процедуру копирования палитр в PPU
	
SPR_TBL	= $0200			; Создадим символ для таблицы спрайтов в RAM
	; ********************************************************
	; * Инициализируем все 64 спрайта выстроив их 'лесенкой' *
	; ********************************************************
	store arg0b, 0		; arg0b будет хранить нарастающую координату
	store arg1b, # $30	; arg1b будет хранит ASCII-код символа начиная с '0'
	store arg2b, 0		; arg2b будет хранить нарастающий номер палитры 0-4
	ldx # 0			; занулим X
	; Для того чтобы в макрос store передать параметр содержащий запятую нужно
	; заключить его в фигурные скобки - это нужно для режима адресации ADDR+x
loop:	store { SPR_TBL, x }, arg0b	; в поле SPR_Y сохраним arg0b (координату)
	inx				; переходим к следующему полю
	store { SPR_TBL, x }, arg1b	; в поле SPR_TILE сохраним номер тайла
	inx				; переходим к следующему полю
	store { SPR_TBL, x }, arg2b	; в поле атрибутов сохраним нарастающий номер палитры
	inx				; переходим к следующему полю
	store { SPR_TBL, x }, arg0b	; и, наконец, сохраняем координату в SPR_X
	inx				; переходим к следующему тайлу
	
	inc arg0b
	inc arg0b
	inc arg0b			; нарастающую координату увеличим на 3
	inc arg1b			; номер тайла увеличим на 1
	inc arg2b			; номер палитры увеличим на 1
	lda arg2b			; но т.к. он не должен выходить за пределы двух бит
	and # %011			; то грузим его в аккумулятор и сбрасываем остальные биты
	sta arg2b			; и сохраняем обратно
	cpx # 0				; проверим не провернулся ли x в ноль (значит вся таблица пройдена)
	bne loop			; и если нет, то идём на следующую итерацию
	
	; **********************************************
	; * Стартуем видеочип и запускаем все процессы *
	; **********************************************
	; Включим генерацию прерываний по VBlank и источником тайлов для спрайтов
	; сделаем второй банк видеоданных где у нас находится шрифт.
	store PPU_CTRL, # PPU_VBLANK_NMI | PPU_SPR_TBL_1000
	; Включим отображение спрайтов и то что они отображаются в левых 8 столбцах пикселей
	store PPU_MASK, # PPU_SHOW_SPR | PPU_SHOW_LEFT_SPR | PPU_SHOW_LEFT_BGR
	cli			; Разрешаем прерывания
	
	; ***************************
	; * Основной цикл программы *
	; ***************************
main_loop:
	jsr wait_nmi		; ждём наступления VBlank

	; Чтобы обновить таблицу спрайтов в видеочипе надо записать в OAM_ADDR ноль
	store OAM_ADDR, # 0
	; И активировать DMA записью верхнего байта адреса страницы с описаниями
	store OAM_DMA, # >SPR_TBL

	; ********************************************************
	; * После работы с VRAM можно заняться другими вещами... *
	; ********************************************************

	jsr update_keys		; Обновим состояние кнопок опросив геймпады
	
	; Теперь можно обновить спрайты в SPR_TBL
	ldx cur_sprite		; Загрузим в X адрес (нижний байт) текущего спрайта
	inx			
	inx			; увеличим X на 2, т.е. перейдём к полю SPR_ATTR
	lda SPR_TBL, x		; Загрузим SPR_ATTR текущего спрайта в A
	clc			; Перед сложением надо очистить Carry
	adc # %01000000		; Сложив с $01000000 мы будем циклически изменять
				; все 4 варианта зеркалирования спрайта в верхих битах
	sta SPR_TBL, x		; Сохраним полученные атрибуты спрайта обратно
	inx
	inx			; Увеличиваем X на 2 чтобы перейти с следующему спрайту
	stx cur_sprite		; Сохраним указатель на новый текущий спрайт в cur_sprite
	
	inc SPR_TBL + 4 * 62 + SPR_X	; в предпоследнем спрайте увеличим X
	inc SPR_TBL + 4 * 63 + SPR_Y	; в последнем спрайте увеличим Y
	
	jmp main_loop		; И уходим ждать нового VBlank в бесконечном цикле
.endproc