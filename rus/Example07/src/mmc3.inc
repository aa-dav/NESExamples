; "Охранная" проверка на недопущение
; повторного ключения файла
.ifndef MMC3_INC_GUARD
MMC3_INC_GUARD		= 1		; Охранный символ

; *** MMC_BANK - выбор банка страницу которого мы можем переключить (запись)
MMC3_BANK		= $8000
; Три нижних бита порта определяют какому банку мы будем менять маппинг:
MMC3_CHR_H0	= %00000000	; Банк $0000-07FF, 2Кб в CHR0
MMC3_CHR_H1	= %00000001	; Банк $0800-0FFF, 2Кб в CHR0
MMC3_CHR_Q0	= %00000010	; Банк $1000-13FF, 1Кб в CHR1
MMC3_CHR_Q1	= %00000011	; Банк $1400-17FF, 1Кб в CHR1
MMC3_CHR_Q2	= %00000100	; Банк $1800-1BFF, 1Кб в CHR1
MMC3_CHR_Q3	= %00000101	; Банк $1C00-1FFF, 1Кб в CHR1
MMC3_PRG_H0	= %00000110	; Банк $8000-9FFF в RAM (8Кб) от 0 до 63
MMC3_PRG_H1	= %00000111	; Банк $A000-BFFF в RAM (8Кб) от 0 до 63
; Флаг альтернативной раскладки банка PRG_H1. Если взведён, то PRG_H1 находится
; по адресам $C000-DFFF, а на $A000-BFFF маппится предпоследняя страница PRG ROM.
MMC3_PRG_ALT_MODE	= %01000000
; Флаг альтернативной раскладки банков CHR. Если взведён, то CHR_Hx находятся
; в CHR1, а CHR_Qx - в CHR0, т.е. CHR0 состоит из 4-х страниц, а CHR1 - из двух.
MMC3_CHR_ALT_MODE	= %10000000

; *** MMC3_PAGE - выбор страницы отображаемой в выбранном банке (запись)
; Если записать в MMC3_PAGE байт, то банк выбранный в MMC3_BANK начнёт отображаться
; на соответствующую по номеру страницу ROM PRG или ROM CHR картриджа.
; Для банков MMC3_CHR1_Qx диапазон значений страниц 0-255, т.е. полный объём CHR ROM - 256Кб
; Для банков MMC3_CHR0_Hx диапазон значений страниц 0-254, только чётные значения, т.е. берутся
; те же блоки что и в CHR1_Qx просто выбираются два подряд идущих блока
; Для банков MMC3_PRG_* диапазон значений страниц 0-63, т.е. полный объём PRG ROM - 512Кб
MMC3_PAGE		= $8001

; mmc3_set_bank_page - выставить для банка pbank маппинг на страницу ppage
.macro mmc3_set_bank_page pbank, ppage
	store MMC3_BANK, pbank	; Выставим в MMC3_BANK номер банка
	store MMC3_PAGE, ppage	; Выставим в MMC3_PAGE номер страницы для этого банка
.endmacro

; *** MMC3_MIRROR - режим зеркалирования видеостраниц (запись)
MMC3_MIRROR		= $A000
; нижний бит выбирает вариант зеркалирования:
MMC3_MIRROR_V		= 0	; зеркалирование по вертикали
MMC3_MIRROR_H		= 1	; зеркалирование по горизонтали

; *** MMC3_RAM_PROTECT - режим защиты (S)RAM на картридже отображаемой 
; на адреса процессора $6000-7FFF (8Кб) (запись).
MMC3_RAM_PROTECT	= $A001
MMC3_RAM_ENABLED	= %10000000	; (S)RAM включена
MMC3_RAM_PROTECTED	= %01000000	; (S)RAM защищена от записи

; *** MMC3_IRQ_COUNTER - начальное значение для счётчика сканлайнов (запись).
; При записи в этот порт байта значение будет запомнено во внутреннем регистре маппера, но
; в сам счётчик оно попадёт либо когда он достигнет нуля либо в процессе RELOAD (см. ниже)
MMC3_IRQ_COUNTER	= $C000

; *** MMC3_IRQ_RELOAD - при записи любого байта в этот порт будет взведён бит перезагрузки
; и на следующем сканлайне счётчик будет перезаписан начальным значением.
MMC3_IRQ_RELOAD		= $C001

; *** MMC3_IRQ_OFF - запись любого значения в этот порт отключит генерацию прерываний (IRQ), но
; счётчик сканлайнов будет в остальном работать как ни в чём не бывало.
MMC3_IRQ_OFF		= $E000

; *** MMC3_IRQ_ON - запись любого значния в этот порт разрешит генерацию прерываний от маппера.
MMC3_IRQ_ON		= $E001

.endif		; MMC3_INC_GUARD