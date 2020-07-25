; ***************************************
; *   Famicom/NES/Денди API и утилиты   *
; ***************************************

; "Охранный ifndef" для исключения перекрёстных множественных подключений (как в C/C++)
.ifndef NESLIB_INC
NESLIB_INC		= 1

.p02	; режим процессора - MOS 6502

; *****************
; *  PPU (ВИДЕО)  *
; *****************

; *** PPU_CTRL - управление PPU (запись), ниже описаны битовые маски
PPU_CTRL		= $2000
; Бит 0: скроллинг по X увеличен на 256 (базовая экранная область справа)
PPU_SCR_X256		= %00000001
; Бит 1: скроллинг по Y увеличен на 240 (базовая экранная область снизу)
PPU_SCR_Y240		= %00000010
; Бит 2: PPU_ADDR инкрементируется на 32 (иначе - на 1)
PPU_ADDR_INC32		= %00000100
; Бит 3: таблица тайлов спрайтов находится по адресу $1000 (иначе - $0000)
PPU_SPR_TBL_1000	= %00001000
; Бит 4: таблица тайлов фона находится по адресу $1000 (иначе - $0000)
PPU_BGR_TBL_1000	= %00010000
; Бит 5: режим спрайтов 8x16 (иначе 8x8)
PPU_SPR_8x16		= %00100000
; Бит 6: подчинённый режим видео, не используется, выставлять крайне не рекомендуется.
;PPU_SLAVE_MODE		= %01000000	;	Не использовать!
; Бит 7: разрешение прерывания NMI по сигналу VBlank (когда PPU отрисовал кадр и можно с ним работать)
PPU_VBLANK_NMI		= %10000000

; *** PPU_MASK - флаги PPU (запись)
PPU_MASK		= $2001
; Бит 0: режим градаций серого
PPU_GRAYSCALE		= %00000001
; Бит 1: показывать задний фон в 8 левых столбцах пикселей экрана 
;        (иначе весь этот столбец будет нулевого цвета)
PPU_SHOW_LEFT_BGR	= %00000010
; Бит 2: показывать спрайты в 8 левых столбцах пикселей экрана
;        последние два флага полезны для реализации плавного появления
;        спрайтов из-за левой границы экрана, т.к. спрайты не могут иметь координату меньше нуля
PPU_SHOW_LEFT_SPR	= %00000100
; Бит 3: показывать задний фон
PPU_SHOW_BGR		= %00001000
; Бит 4: показывать спрайты
;        отключение двух последних бит выключает PPU и с ним можно работать не только в VBlank
PPU_SHOW_SPR		= %00010000
; Биты 5-7: выставленные биты выделяют свою компоненту RGB-цвета на экране приглушая остальные две
;           в результате если выставить их все, то картинка в целом становится темнее
PPU_TINT_R		= %00100000
PPU_TINT_G		= %01000000
PPU_TINT_B		= %10000000

; *** PPU_STATUS - состояние PPU (чтение)
PPU_STATUS		= $2002
; Бит 5: появилось переполнение спрайтов по строке (не более 8 в сканлайне)
PPU_STAT_OVERFLOW	= %00100000
; Бит 6: отрисовался первый непрозрачный пиксель спрайта номер 0
PPU_STAT_SPR0_HIT	= %01000000
; Бит 7: начался период VBlank. Этот бит сам сбрасывается аппаратурой в двух случаях:
;        1) при считывании PPU_STATUS (т.е. этого же самого порта)
;        2) при окончании периода VBlank
PPU_STAT_VBLANK		= %10000000

; *** OAM_ADDR - байт адреса данных спрайтов в PPU
;     Запись в этот порт портит само содержимое данных спрайтов, поэтому
;     рекомендуется использовать OAM_DMA
OAM_ADDR		= $2003
; *** OAM_DATA - запись в данные спрайтов (по адресу OAM_ADDR)
;     Прямое использование имеет ряд проблем, лучше использовать OAM_DMA
OAM_DATA		= $2004
; *** OAM_DMA - при записи байта XX передаст из адресного пространства процессора
;     256 байт начиная с адреса $XX00 в память спрайтов PPU. 
;     Рекомендованная схема работы: записать $00 в OAM_ADDR и активировать OAM_DMA.
OAM_DMA			= $4014
; *** PPU_SCROLL - первая запись выставляет скроллинг по X (0-255), а вторая - по Y (0-239)
;     в пределах базовой экранной области (нижние биты PPU_CTRL). Пиксель с координатами
;     (x, y) - левый верхний на экране, но надо учитывать что на NTSC первые 8 сканлайнов
;     экрана не видно. PPU_SCROLL и PPU_ADDR делят одни и те же внутренние регистры PPU, поэтому
;     PPU_SCROLL следует заполнять после всех записей в PPU_ADDR до начала VDraw.
PPU_SCROLL		= $2005
; *** PPU_ADDR - адрес в VRAM куда будет осуществляться доступ через PPU_DATA
;     Первая запись выставляет старший байт, вторая - младший. Делит регистры с PPU_SCROLL.
PPU_ADDR		= $2006
; *** PPU_DATA - запись пишет в VRAM байт, а чтение - получает данные из временного регистра, а
;     во временный регистр помещает прочитанные из VRAM данные, т.е. отстаёт на один шаг.
;     После доступа продвигает PPU_ADDR на 1 или 32 байта (бит PPU_ADDR_INC32 в PPU_CTRL).
PPU_DATA		= $2007

; *** SPRITE DESC - описание спрайта
; SPR_Y - смещение до координаты Y спрайта. Из-за того, что данные о спрайтах запаздывают на 
;         один сканлайн значение нужно уменьшить на 1.
SPR_Y			= 0
; SPR_TILE - смещение до номера тайла спрайта (0-255)
SPR_TILE		= 1
; SPR_ATTR - смещение до атрибутов спрайта (см. ниже)
SPR_ATTR		= 2
; SPR_X - смещение до координаты X спрайта
SPR_X			= 3
; *** Битовые флаги атрибутов спрайта (SPR_ATTR):
; Биты 0-1: палитра спрайта (0-3)
SPR_PAL_0		= %00000000
SPR_PAL_1		= %00000001
SPR_PAL_2		= %00000010
SPR_PAL_3		= %00000011
; Бит 5: приоритет - под задним фоном
SPR_BEHIND_BGR		= %00100000
; Бит 6: зеркалирование по горизонтали
SPR_FLIP_H		= %01000000
; Бит 7: зеркалирвоание по вертикали
SPR_FLIP_V		= %10000000

; *** Некоторые интересные адреса в VRAM
PPU_SCR0		= $2000	; Адрес начала первой экранной области в VRAM
PPU_SCR0_ATTRS		= $23C0	; Начало атрибутов первой экранной области в VRAM
PPU_SCR1		= $2400	; Адрес начала второй экранной области в VRAM
PPU_SCR1_ATTRS		= $27C0	; Начало атрибутов второй экранной области в VRAM
PPU_PALETTES		= $3F00	; Начало всех палитр в VRAM
PPU_BGR_PALETTES	= $3F00	; Начало палитр заднего фона в VRAM
PPU_SPR_PALETTES	= $3F10	; Начало палитр спрайтов в VRAM
SPR_TBL			= $0200	; Начало таблицы спрайтов в RAM
; Макросы SPR_FLD_* получают адрес поля спрайта в RAM по его номеру
.define SPR_FLD_X( i )		SPR_TBL + (4 * i) + SPR_X
.define SPR_FLD_Y( i )		SPR_TBL + (4 * i) + SPR_Y
.define SPR_FLD_TILE( i )	SPR_TBL + (4 * i) + SPR_TILE
.define SPR_FLD_ATTR( i )	SPR_TBL + (4 * i) + SPR_ATTR

; ******************
; *  INPUT (ВВОД)  *
; ******************

; *** JOY_PAD1 - порт управления вводом (при записи) и считывания первого геймпада (при чтении)
JOY_PAD1		= $4016
; *** JOY_PAD2 - считывание второго геймпада (по совместительству APU_FRAME_COUNTER)
JOY_PAD2		= $4017

; Битовые маски кнопок стандартных геймпадов
KEY_RIGHT		= %00000001
KEY_LEFT		= %00000010
KEY_DOWN		= %00000100
KEY_UP			= %00001000
KEY_START		= %00010000
KEY_SELECT		= %00100000
KEY_B			= %01000000
KEY_A			= %10000000

; ******************
; *   APU (ЗВУК)   *
; ******************

; *** APU_PULSE1 - первый канал "прямоугольного" звука (меандр)
APU_PULSE1_0		= $4000
APU_PULSE1_1		= $4001
APU_PULSE1_2		= $4002
APU_PULSE1_3		= $4003

; *** APU_PULSE2 - второй канал "прямоугольного" звука
APU_PULSE2_0		= $4004
APU_PULSE2_1		= $4005
APU_PULSE2_2		= $4006
APU_PULSE2_3		= $4007

; *** APU_TRIANGLE - канал пилообразного звука
APU_TRIANGLE_0		= $4008
APU_TRIANGLE_2		= $400A
APU_TRIANGLE_3		= $400B

; *** APU_NOISE - канал шумового звука
APU_NOISE_0		= $400C
APU_NOISE_2		= $400E
APU_NOISE_3		= $400F

; *** APU_DMC - канал DPCM-звука
APU_DMC_0		= $4010
APU_DMC_1		= $4011
APU_DMC_2		= $4012
APU_DMC_3		= $4013

; *** APU_CONTROL/APU_STATUS - управление звуков (запись) и опрос состояния звука (чтение)
APU_CONTROL		= $4015
APU_STATUS		= $4015
; Флаги участвующие и при чтении и при записи
APU_PULSE1_ON		= %00000001
APU_PULSE2_ON		= %00000010
APU_TRIANGLE_ON		= %00000100
APU_NOISE_ON		= %00001000
APU_DMC_ON		= %00010000
; Флаги только на запись (APU_CONTROL)
APU_FRAME_IRQ		= %01000000
APU_DMC_IRQ		= %10000000

; *** APU_FRAME_COUNTER - управление секвенсором аудио
APU_FRAME_COUNTER	= $4017
; Бит 6 - запрещение прерываний IRQ от секвенсора
;         (судя по всему это IRQ - менее удобная альтернатива VBlank NMI и не особо нужна)
APU_FC_IRQ_OFF		= %01000000
; Бит 7 - 5-шаговый режим секвенсора (4-шаговый если 0)
;         Прим.: в 5-шаговом режиме IRQ от секвенсера никогда не генерируется
APU_FC_5_STEP		= %10000000

; ********************
; * Полезные макросы *
; ********************

; store dest, src - сохранить байт в память
; чтобы избежать обильных многословных конструкций вида из:
;	lda значение
;	sta переменная	; переменная = значение
; которые заполняют переменные в памяти этот макрос
; позволяет записывать в одну строку:
;	store переменная, значение	; переменная = значение
; dest и src могут быть любыми аргументами инструкций lda/sta
; так что обратите внимание, что нужен префикс # для констант!
; портит аккумулятор!
.macro store dest, src
	lda src
	sta dest
.endmacro

; store_addr dest, addr - сохранить адрес в слово в памяти
; чтобы избежать многословных конструкций вида:
;	lda # < addr	; загрузить lsb байт адреса
;	sta dest	; сохранить в начало слова
;	lda # > addr	; загрузить msb байт адреса
;	sta dest + 1	; сохранить в конец слова
; которые сохраняет адрес переменной в слово в памяти этот макрос
; позволяет записывать в одну строку:
;	store_addr переменная, адрес	; переменная = адрес
; dest и addr должны быть адресами в памяти
; портит аккумулятор!
.macro store_addr dest, addr
	lda # < (addr)
	sta dest
	lda # > (addr)
	sta dest + 1
.endmacro

; store_word dest, word - сохранить слово в память.
; по сути то же самое что и store_addr, но название
; подчёркивает что сохраняется данное, а не адрес.
; портит аккумулятор!
.macro store_word dest, word
	lda # < (word)
	sta dest
	lda # > (word)
	sta dest + 1
.endmacro

; fill_ppu_addr - записать в PPU_ADDR адрес в VRAM
; чтобы избежать многословной конструкции (в теле макроса)
; можно записать в одну строку 
;	fill_ppu_addr адрес-в-vram
; vaddr должен быть адресом, переставлять нижний и верхний
; байты не нужно
; портит аккумулятор!
.macro fill_ppu_addr vaddr
	lda # > (vaddr)
	sta PPU_ADDR
	lda # < (vaddr)
	sta PPU_ADDR
.endmacro

; jump_if_keys1_is_not_down - перейти на метку label если в keys1_is_down
; не зажжён хотя бы один бит в переданном сканкоде key_code.
; Т.е. можно передать несколько битовых паттернов кнопок 
; наложенных по OR и если хоть одна окажется нажата - перехода не будет.
; портит аккумулятор!
.macro jump_if_keys1_is_not_down key_code, label
	lda keys1_is_down
	and # key_code
	beq label
.endmacro

; jump_if_keys2_is_not_down - перейти на метку label если в keys2_is_down
; не зажжён хотя бы один бит в переданном сканкоде key_code.
; портит аккумулятор!
.macro jump_if_keys2_is_not_down key_code, label
	lda keys2_is_down
	and # key_code
	beq label
.endmacro

; jump_if_keys1_was_not_pressed - перейти на метку label если в keys1_was_pressed
; не зажжён хотя бы один бит в переданном сканкоде key_code.
.macro jump_if_keys1_was_not_pressed key_code, label
	lda keys1_was_pressed
	and # key_code
	beq label
.endmacro

; jump_if_keys2_was_not_pressed - перейти на метку label если в keys2_was_pressed
; не зажжён хотя бы один бит в переданном сканкоде key_code.
.macro jump_if_keys2_was_not_pressed key_code, label
	lda keys2_was_pressed
	and # key_code
	beq label
.endmacro

; locate_in_vpage - выставить в PPU_ADDR адрес байта в 
; указанной странице page на координаты тайла (cx, cy)
;   page - PPU_SCR0 или PPU_SCR1
;   cx - от 0 до 31
;   cy - от 0 до 29
; портит аккумулятор!
; Заметьте, что параметры заключаются в скобки потому что иначе при 
; подстановке сложных выражений они могли бы неправильно развернуться.
.macro	locate_in_vpage page, cx, cy
	fill_ppu_addr (page) + (cx) + ((cy) * 32)
.endmacro

; poke_vpage - записать байт value по координатам (cx, cy) 
; в указанной странице page.
; портит аккумулятор!
.macro	poke_vpage page, cx, cy, value
	locate_in_vpage page, cx, cy
	store PPU_DATA, value
.endmacro

; fill_vpage_line - записать байт value times раз начиная с
; координат (cx, cy) в указанной странице page. 
; times не может быть больше 255!
; портит: A, X
.macro	fill_vpage_line page, cx, cy, times, value
	.local mloop
	locate_in_vpage page, cx, cy
	lda value
	ldx times
mloop:	sta PPU_DATA
	dex
	bne mloop
.endmacro

; fill_page_by - заливает все байты тайлов страницы page байтом value
; не затрагивает область атрибутов.
; портит: A, X
.macro	fill_page_by page, value
	.local mloop
	fill_ppu_addr page
	ldx # 32 * 30 / 4
	lda value
mloop:	sta PPU_DATA
	sta PPU_DATA
	sta PPU_DATA
	sta PPU_DATA
	dex
	bne mloop
.endmacro

; set_sprite - установить все поля спрайта
.macro	set_sprite num, cx, cy, tile, attr
	store SPR_FLD_X( num ), cx
	store SPR_FLD_Y( num ), cy
	store SPR_FLD_TILE( num ), tile
	store SPR_FLD_ATTR( num ), attr
.endmacro

; ****************************************
; * Экспорт/импорт глобальных переменных *
; ****************************************

; Экспорт/импорт из zero page надо делать через .globalzp
.globalzp arg0w
.globalzp arg1w
.globalzp arg2w
.globalzp arg3w

.globalzp arg0b
.globalzp arg1b
.globalzp arg2b
.globalzp arg3b
.globalzp arg4b
.globalzp arg5b
.globalzp arg6b
.globalzp arg7b

.globalzp keys1_is_down
.globalzp keys2_is_down

; Экспорт/импорт из остальной памяти - .global
.global keys1_was_pressed
.global keys2_was_pressed
.global update_keys
.global warm_up

.endif