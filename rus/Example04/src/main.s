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
famitone_vars:	.res 3	; 3 байта в zero page для библиотеки FamiTone
music_is_on:	.byte 0	; Флаг того играет ли музыка ($80 или $00)

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

; fill_attribs - заполнить область цетовых атрибутов байтом в аккумуляторе
; адрес в PPU_ADDR уже должен быть настроен на эту область атрибутов!
.proc fill_attribs
	ldx # 64		; надо залить 64 байта цветовых атрибутов
loop:	sta PPU_DATA		; записываем в VRAM аккумулятор
	dex			; декрементируем X
	bne loop		; цикл по счётчику в X
	rts			; возврат из процедуры
.endproc

; zstr_print - записывает в PPU_DATA ASCIZ-строку начиная с адреса arg0w
; останавливается на нулевом символе.
.proc zstr_print
	ldy # 0			; Y должен быть равен 0
loop:	lda (arg0w), y		; Грузим в A байт из адреса в слове arg0w
	beq exit		; если он нулевой - выходим
	sta PPU_DATA		; сохраняем байт в VRAM
	inc arg0w + 0		; увеличиваем младший байт адреса
	bne skip_inc_high	; если он не провернулся в 0 - идём дальше
	inc arg0w + 1		; если да, то надо увеличить старший байт адреса
skip_inc_high:
	jmp loop		; возвращаемся в начало цикла
exit:	rts			; выходим из процедуры
.endproc

; Перед подключением FamiTone2 надо настроить её параметры
FT_BASE_ADR		= $0100	; Страница с переменными Famitone2, должна быть вида $xx00
				; Мы отдадим библиотеке начало страницы стека ( FT_BASE_SIZE )
FT_TEMP			= famitone_vars	; 3 байта в zero page для быстрой памяти Famitone
FT_DPCM_OFF		= $C000	; Начало звуковых эффектов. Должно быть адресом $c000..$ffc0 64-байтными шажками
FT_SFX_STREAMS		= 4	; Число звуковых эффектов проигрываемых одновременно (от 1 до 4)

FT_DPCM_ENABLE		= 0	; 1 - DMC включен, 0 - выключен
FT_SFX_ENABLE		= 1	; 1 - звуковые эффекты включены, 0 - выключены
FT_THREAD		= 0	; 1 - если ф-я звуковых эффектов вызывается из другого потока, 0 - иначе
FT_PAL_SUPPORT		= 0	; 1 - если поддерживается PAL, 0 иначе
FT_NTSC_SUPPORT		= 1	; 1 - если поддерживается NTSC, 0 иначе

.include "famitone2.s"			; Включаем тело библиотеки прямо в код
.segment "ROM_L"			; переключимся на сегмент данных
.include "sounds/danger_streets.s"	; Подключим файл с музыкой
.include "sounds/sounds.s"		; Подключим файл со звуками
; Зададим строки меню на экране:
str1:	.byte "START - play/stop music", 0
str2:	.byte "LEFT  - score", 0
str3:	.byte "RIGHT - splash", 0
str4:	.byte "UP    - coin", 0
str5:	.byte "DOWN  - beep", 0

.segment "ROM_H"		; Переключимся обратно в сегмент кода

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
	
	; ***************************
	; * Нарисуем на экране меню *
	; ***************************
	fill_page_by PPU_SCR0, # ' '	; Заполним экран пробелами
	lda # 0
	jsr fill_attribs		; С нулевой палитрой
	
	; Выведем строки меню одну под одной начиная со строки 10
	locate_in_vpage PPU_SCR0, 0, 10	; Нацелимся в PPU_ADDR на тайл с координатами (0, 10)
	store_addr arg0w, str1		; arg0w = адрес строки str1
	jsr zstr_print			; вызываем процедуру вывода строки
	locate_in_vpage PPU_SCR0, 0, 11	; и так 5 раз...
	store_addr arg0w, str2
	jsr zstr_print
	locate_in_vpage PPU_SCR0, 0, 12
	store_addr arg0w, str3
	jsr zstr_print
	locate_in_vpage PPU_SCR0, 0, 13
	store_addr arg0w, str4
	jsr zstr_print
	locate_in_vpage PPU_SCR0, 0, 14
	store_addr arg0w, str5
	jsr zstr_print

	; ********************************
	; * Инициализируем музыку и звук *
	; ********************************
	; Загрузим в X и Y нижний и верхний байты адреса музыки соответственно
	ldx # < danger_streets_music_data
	ldy # > danger_streets_music_data
	lda # 1					; 1 для NTSC, 0 для PAL
	jsr FamiToneInit			; Инициализируем музыкальный движок
	
	; Загрузим в X и Y нижний и верхний байты адреса звуков соответственно
	ldx # < sounds
	ldy # > sounds
	jsr FamiToneSfxInit			; Инициализируем звуковой движок
	
	; **********************************************
	; * Стартуем видеочип и запускаем все процессы *
	; **********************************************
	; Включим генерацию прерываний по VBlank и источником тайлов для спрайтов
	; сделаем второй банк видеоданных где у нас находится шрифт.
	store PPU_CTRL, # PPU_VBLANK_NMI | PPU_BGR_TBL_1000
	; Включим отображение спрайтов и то что они отображаются в левых 8 столбцах пикселей
	store PPU_MASK, # PPU_SHOW_BGR | PPU_SHOW_LEFT_BGR
	cli			; Разрешаем прерывания
	
	; ***************************
	; * Основной цикл программы *
	; ***************************
main_loop:
	jsr wait_nmi		; ждём наступления VBlank

	store PPU_SCROLL, # 0	; Перед началом кадра выставим скроллинг
	store PPU_SCROLL, # 0	; в (0, 0) чтобы панель рисовалась фиксированно
	
	; ********************************************************
	; * После работы с VRAM можно заняться другими вещами... *
	; ********************************************************

	jsr FamiToneUpdate	; Проведём шаг библиотеки FamiTone2

	jsr update_keys		; Обновим состояние кнопок опросив геймпады
	
	; Если сейчас нажали на START...
	jump_if_keys1_was_not_pressed KEY_START, skip_start
	bit music_is_on		; проверяем флаг того играет ли уже музыка
	bmi stop_music		; если да, идём останавливать её
	lda # 0			; иначе выбираем музыку номер 0
	jsr FamiToneMusicPlay	; и запускаем её воспроизведение
	store music_is_on, # $80	; помечаем во флаге что музыка играет
	jmp skip_start		; и идём дальше
stop_music:
	jsr FamiToneMusicStop	; тут мы останавливаем музыку
	store music_is_on, # $00	; и помечаем во флаге что она остановлена
skip_start:
	; Если нажали LEFT
	jump_if_keys1_was_not_pressed KEY_LEFT, skip_left
	lda # 0			; Выбираем нулевой звук
	ldx # FT_SFX_CH0	; и канал CH0
	jsr FamiToneSfxPlay	; и запускаем воспроизведение звука
skip_left:
	; Если нажали RIGHT
	jump_if_keys1_was_not_pressed KEY_RIGHT, skip_right
	lda # 1			; Выбираем звук 1
	ldx # FT_SFX_CH0	; и канал CH0
	jsr FamiToneSfxPlay	; и запускаем воспроизведение звука
skip_right:
	jump_if_keys1_was_not_pressed KEY_UP, skip_up
	lda # 2
	ldx # FT_SFX_CH0
	jsr FamiToneSfxPlay	; Для UP звук 2
skip_up:
	jump_if_keys1_was_not_pressed KEY_DOWN, skip_down
	lda # 3
	ldx # FT_SFX_CH0
	jsr FamiToneSfxPlay	; И для DOWN звук 3
skip_down:

	jmp main_loop		; И уходим ждать нового VBlank в бесконечном цикле
.endproc