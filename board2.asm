;===============================================================================
;   HOME AUTOMATION SYSTEM - CURTAIN CONTROL
;   Microcontroller: PIC16F877A
;   Crystal: 4 MHz
;===============================================================================
;
;   DESCRIPTION:
;       Automated curtain control system with potentiometer, LDR sensor,
;       step motor, LCD display, and UART communication for PC interface.
;
;   FEATURES:
;       - Potentiometer for manual curtain position control (0-100%)
;       - LDR sensor for automatic mode (dark = curtain closed)
;       - 4-phase step motor with half-step control
;       - 16x2 LCD display showing curtain position and light level
;       - UART communication (9600 baud)
;
;   PIN CONFIGURATION:
;       RA0: Potentiometer (Analog Input)
;       RA1: LDR Sensor (Analog Input)
;       RB0-RB7: LCD Data (8-bit mode)
;       RC0-RC3: Step Motor Coils
;       RC6-RC7: UART TX/RX
;       RD4: LCD RS
;       RD5: LCD EN
;
;   OPERATING MODES:
;       LDR < 50: Automatic mode - Curtain forced to 100% (closed)
;       LDR >= 50: Manual mode - Potentiometer or UART control
;
;===============================================================================

    PROCESSOR   16F877A
    #include    <xc.inc>
    
    CONFIG  FOSC = HS
    CONFIG  WDTE = OFF
    CONFIG  PWRTE = ON
    CONFIG  BOREN = ON
    CONFIG  LVP = OFF
    CONFIG  CPD = OFF
    CONFIG  WRT = OFF
    CONFIG  CP = OFF

;-----------------------------------------------------------------------------
; CONSTANTS
;-----------------------------------------------------------------------------
LCD_RS          EQU     4
LCD_EN          EQU     5
LCD_LINE1       EQU     0x80
LCD_LINE2       EQU     0xC0

;-----------------------------------------------------------------------------
; VARIABLES
;-----------------------------------------------------------------------------
DELAY_COUNT1    EQU     0x20
DELAY_COUNT2    EQU     0x21
DELAY_COUNT3    EQU     0x22

; Potentiometer
POT_ADC         EQU     0x23        ; Raw ADC value (0-255)
TARGET_POS      EQU     0x24        ; Target position % (0-100)

; LDR
LDR_ADC         EQU     0x25        ; Raw ADC value (0-255)

; Motor (Half-step: 0-7)
CURRENT_POS     EQU     0x26        ; Current position % (0-100)
STEP_IDX        EQU     0x2D        ; 0..7 pattern index (Half Step)
INNER_CNT       EQU     0x30        ; loop counter

; Display
TEMP_VAL        EQU     0x28
DIGIT_100       EQU     0x29
DIGIT_10        EQU     0x2A
DIGIT_1         EQU     0x2B

; Conversion temporaries
MULT_A          EQU     0x2C
RESULT_L        EQU     0x2E
RESULT_H        EQU     0x2F
DIV_COUNT       EQU     0x31
       
; UART data
CURT_L          EQU     0x32    ; desired curtain low (fractional)
CURT_H          EQU     0x33    ; desired curtain high (integral)
LIGHT_L         EQU     0x34    ; light low (fractional)
LIGHT_H         EQU     0x35    ; light high (integral)

UART_RX         EQU     0x36    ; gelen komut byte'? için geçici
UART_OVERRIDE   EQU     0x37    ; 0 = pot/LDR, 1 = UART kontrolü

SUBSTEP         EQU     0x38    ; 0..19 (1% içindeki half-step sayac?)
POT_LAST        EQU     0x39    ; pot son okunan deger (0-255)
SAVED_CURT_H    EQU     0x3A    ; UART'tan gelen deger (auto mode'da saklanir)
SAVED_CURT_L    EQU     0x3B    ; UART'tan gelen frac deger


;-----------------------------------------------------------------------------
    PSECT   resetVec,class=CODE,delta=2
resetVec:
    GOTO    START

;-----------------------------------------------------------------------------
    PSECT   code,class=CODE,delta=2

START:
    
    MOVLW   0xFF
    MOVWF   POT_LAST
    CLRF    UART_OVERRIDE      ; bunu art?k "UART_LATCH" gibi kullanaca??z

    
    CLRF    SUBSTEP
    
    ; Configure ports
    BANKSEL TRISB
    CLRF    TRISB           ; PORTB output (LCD data)
    
    BANKSEL TRISD  
    BCF     TRISD,4         ; RD4 output (LCD RS)
    BCF     TRISD,5         ; RD5 output (LCD EN)
    
    BANKSEL TRISC
    MOVLW   0x80     ; RC7=1 input (RX), RC6..RC0=0 output
    MOVWF   TRISC

    
    BANKSEL TRISA
    BSF     TRISA,0         ; RA0 input (Potentiometer)
    BSF     TRISA,1         ; RA1 input (LDR)
    
    ; Configure ADC for 2 channels
    BANKSEL ADCON1
    MOVLW   0x04            ; Left justified, AN0-AN4 analog
    MOVWF   ADCON1
    
    BANKSEL ADCON0
    MOVLW   0x81            ; Start with Channel 0, ADC ON
    MOVWF   ADCON0
    
    ; Clear ports
    BANKSEL PORTB
    CLRF    PORTB
    CLRF    PORTD
    CLRF    PORTC
    
    ; Initialize variables
    CLRF    UART_OVERRIDE
    CLRF    CURRENT_POS
    CLRF    TARGET_POS
    CLRF    STEP_IDX
    
    ; Initialize LCD
    CALL    DELAY_20MS
    CALL    LCD_INIT
    
    ; Show static labels
    CALL    SHOW_LABELS
    CALL    UART_INIT


;-----------------------------------------------------------------------------
; MAIN_LOOP - Main control cycle for LDR reading, mode selection, motor control
;-----------------------------------------------------------------------------
MAIN_LOOP:
    ; 1. Read LDR
    CALL    READ_LDR
    CALL    UART_SERVICE

    MOVF    LDR_ADC,W
    SUBLW   49                  ; W = 49 - LDR
    BTFSS   STATUS,0            ; C=1 ise LDR<=49 yani LDR<50
    GOTO    MANUAL_MODE
    
AUTOMATIC_MODE:
    ; LDR < 50 (dark): Automatic control, force close to 100%
    ; Set TARGET_POS = 100 for motor control
    BANKSEL TARGET_POS
    MOVLW   100
    MOVWF   TARGET_POS
    
    ; Always show 100% in GUI (CURT_H/CURT_L)
    ; SAVED_CURT_H/L keeps the user's value for when returning to manual mode
    BANKSEL CURT_H
    MOVLW   100
    MOVWF   CURT_H
    BANKSEL CURT_L
    CLRF    CURT_L
    GOTO    CONTROL_MOTOR
    
MANUAL_MODE:
    ; LDR >= 50 (bright): Manual control via potentiometer
    CALL    READ_POT

    ;----------------------------------------------------------
    ; ONCELIK: UART'tan deger geldiyse (UART_OVERRIDE=1) onu uygula
    ; Sonra pot kontrolune gec. Pot degisirse normal calismaya devam eder.
    ;----------------------------------------------------------

    ; First check: UART_OVERRIDE=1 mi? (UART degeri bekliyor mu?)
    BANKSEL UART_OVERRIDE
    MOVF    UART_OVERRIDE,W
    BTFSC   STATUS,2            ; Z=1 means UART_OVERRIDE=0
    GOTO    CHECK_POT           ; UART_OVERRIDE=0, pot kontrolune gec
    
    ; UART_OVERRIDE=1: SAVED degerleri yukle ve motoru calistir
    BANKSEL SAVED_CURT_H
    MOVF    SAVED_CURT_H,W
    BANKSEL CURT_H
    MOVWF   CURT_H
    BANKSEL TARGET_POS
    MOVWF   TARGET_POS
    
    BANKSEL SAVED_CURT_L
    MOVF    SAVED_CURT_L,W
    BANKSEL CURT_L
    MOVWF   CURT_L
    
    ; POT_LAST'i guncelle - boylece pot degisince normal calisiyor
    BANKSEL POT_ADC
    MOVF    POT_ADC,W
    BANKSEL POT_LAST
    MOVWF   POT_LAST
    
    ; UART_OVERRIDE'i kapat (deger uygulandi)
    BANKSEL UART_OVERRIDE
    CLRF    UART_OVERRIDE
    
    GOTO    CONTROL_MOTOR

CHECK_POT:
    ; UART degeri yok, pot kontrolu yap
    ; W = POT_ADC XOR POT_LAST  (0 ise ayni)
    BANKSEL POT_ADC
    MOVF    POT_ADC,W
    BANKSEL POT_LAST
    XORWF   POT_LAST,W
    BTFSC   STATUS,2            ; Z=1 ise ayniydi, degismedi
    GOTO    CONTROL_MOTOR       ; Pot ayni, motor zaten dogru pozisyonda
    
    ; Pot degisti -> yeni degeri kaydet
    BANKSEL POT_ADC
    MOVF    POT_ADC,W
    BANKSEL POT_LAST
    MOVWF   POT_LAST


DO_POT_CALC:
    ; Special case: POT_ADC = 255 means pot at maximum (5V) -> 100.0%
    BANKSEL POT_ADC
    MOVF    POT_ADC,W
    XORLW   255                 ; Check if POT_ADC = 255
    BTFSC   STATUS,2            ; Z=1 if POT_ADC = 255
    GOTO    FORCE_CURT_100

    ; Normal calculation
    CALL    CONVERT_POT_TO_PERCENT

    ; Slayt uyumu: desired curtain high byte güncelle (0..100)
    BANKSEL TARGET_POS
    MOVF    TARGET_POS,W
    BANKSEL CURT_H
    MOVWF   CURT_H

    ; ----------------------------------------------------------
    ; CURT_L = (POT_ADC * 10) / 256  -> 0..9  (mant?kl? ondal?k)
    ; POT_ADC 0..255 -> 0..9
    ; ----------------------------------------------------------
    BANKSEL POT_ADC
    MOVF    POT_ADC,W
    BANKSEL TEMP_VAL
    MOVWF   TEMP_VAL

    BANKSEL CURT_L
    CLRF    CURT_L          ; CURT_L sayaç gibi kullan?lacak (0..9)

CURT_DEC_LOOP:
    ; TEMP_VAL >= 26 ise CURT_L++ (çünkü 256/10 ? 25.6)
    MOVLW   26
    SUBWF   TEMP_VAL,W
    BTFSS   STATUS,0        ; C=0 ise TEMP_VAL < 26 -> ç?k
    GOTO    CURT_DEC_DONE

    ; TEMP_VAL -= 26
    MOVLW   26
    SUBWF   TEMP_VAL,F

    BANKSEL CURT_L
    INCF    CURT_L,F
    GOTO    CURT_DEC_LOOP

CURT_DEC_DONE:
    ; Güvenlik: 10 olursa 9 yap (çok nadir)
    BANKSEL CURT_L
    MOVF    CURT_L,W
    XORLW   10
    BTFSS   STATUS,2
    GOTO    CURT_DEC_OK

    MOVLW   9
    MOVWF   CURT_L
    GOTO    CURT_DEC_OK

FORCE_CURT_100:
    ; Pot at maximum (5V) -> Force 100.0%
    BANKSEL CURT_H
    MOVLW   100
    MOVWF   CURT_H
    BANKSEL TARGET_POS
    MOVWF   TARGET_POS
    BANKSEL CURT_L
    CLRF    CURT_L
    GOTO    CONTROL_MOTOR

CURT_DEC_OK:

CONTROL_MOTOR:
    ; 3. Curtain control (smooth half-step)
    CALL    CURTAIN_CONTROL
    
    ; 4. Update display
    CALL    UPDATE_DISPLAY
    
    GOTO    MAIN_LOOP

;-----------------------------------------------------------------------------
; CURTAIN_CONTROL - Move step motor from CURRENT_POS to TARGET_POS
;-----------------------------------------------------------------------------
CURTAIN_CONTROL:
    ; Equal check
    MOVF    TARGET_POS,W
    SUBWF   CURRENT_POS,W
    BTFSC   STATUS,2
    RETURN

    ; Direction check (Target > Current -> CCW for closing curtain)
    MOVF    TARGET_POS,W
    SUBWF   CURRENT_POS,W
    BTFSC   STATUS,0
    GOTO    DO_CW

DO_CCW:
    ; 1% increase = 20 half-steps CCW (closing curtain)
    MOVLW   20
    MOVWF   INNER_CNT
LOOP_CCW:
    CALL    MOTOR_STEP_CCW

    ; ---- Check UART during motor movement for responsive GUI ----
    CALL    UART_SERVICE

    ; ---- LCD UPDATE inside loop (every 2 half-steps) ----
    ; SUBSTEP even? (bit0=0) => decimal changes each 2 step
    BANKSEL SUBSTEP
    BTFSC   SUBSTEP,0       ; if odd -> skip
    GOTO    CCW_SKIP_LCD
    CALL    UPDATE_DISPLAY   ; uses CURRENT_POS + SUBSTEP/2
CCW_SKIP_LCD:
    ; -----------------------------------------------------

    DECFSZ  INNER_CNT,F
    GOTO    LOOP_CCW

    INCF    CURRENT_POS,F
    RETURN

DO_CW:
    ; 1% decrease = 20 half-steps CW (opening curtain)
    MOVLW   20
    MOVWF   INNER_CNT
LOOP_CW:
    CALL    MOTOR_STEP_CW

    ; ---- Check UART during motor movement for responsive GUI ----
    CALL    UART_SERVICE

    ; ---- LCD UPDATE inside loop (every 2 half-steps) ----
    BANKSEL SUBSTEP
    BTFSC   SUBSTEP,0
    GOTO    CW_SKIP_LCD
    CALL    UPDATE_DISPLAY_DEC   ; special for decreasing motion
CW_SKIP_LCD:
    ; -----------------------------------------------------

    DECFSZ  INNER_CNT,F
    GOTO    LOOP_CW

    DECF    CURRENT_POS,F
    RETURN


;-----------------------------------------------------------------------------
; MOTOR_STEP_CW/CCW - Execute single half-step in specified direction
;-----------------------------------------------------------------------------
MOTOR_STEP_CW:
    CALL    MOTOR_OUTPUT_PATTERN
    CALL    MOTOR_DELAY
    BANKSEL SUBSTEP
    INCF    SUBSTEP,F
    MOVLW   20
    SUBWF   SUBSTEP,W
    BTFSS   STATUS,2
    GOTO    SUBSTEP_OK_CW
    CLRF    SUBSTEP
SUBSTEP_OK_CW:

    
    INCF    STEP_IDX,F
    MOVLW   8
    SUBWF   STEP_IDX,W
    BTFSS   STATUS,2
    RETURN
    CLRF    STEP_IDX
    RETURN

MOTOR_STEP_CCW:
    CALL    MOTOR_OUTPUT_PATTERN
    CALL    MOTOR_DELAY
    BANKSEL SUBSTEP
    INCF    SUBSTEP,F
    MOVLW   20
    SUBWF   SUBSTEP,W
    BTFSS   STATUS,2
    GOTO    SUBSTEP_OK_CCW
    CLRF    SUBSTEP
SUBSTEP_OK_CCW:

    
    MOVF    STEP_IDX,F
    BTFSC   STATUS,2
    GOTO    WRAP_TO_7
    DECF    STEP_IDX,F
    RETURN
WRAP_TO_7:
    MOVLW   7
    MOVWF   STEP_IDX
    RETURN

;-----------------------------------------------------------------------------
; MOTOR OUTPUT PATTERN (HALF-STEP 0-7)
; 0:0001, 1:0011, 2:0010, 3:0110, 4:0100, 5:1100, 6:1000, 7:1001
;-----------------------------------------------------------------------------
MOTOR_OUTPUT_PATTERN:
    BANKSEL PORTC
    
    MOVF    STEP_IDX,W
    SUBLW   0
    BTFSC   STATUS,2
    GOTO    PAT_0
    
    MOVF    STEP_IDX,W
    SUBLW   1
    BTFSC   STATUS,2
    GOTO    PAT_1
    
    MOVF    STEP_IDX,W
    SUBLW   2
    BTFSC   STATUS,2
    GOTO    PAT_2

    MOVF    STEP_IDX,W
    SUBLW   3
    BTFSC   STATUS,2
    GOTO    PAT_3

    MOVF    STEP_IDX,W
    SUBLW   4
    BTFSC   STATUS,2
    GOTO    PAT_4

    MOVF    STEP_IDX,W
    SUBLW   5
    BTFSC   STATUS,2
    GOTO    PAT_5

    MOVF    STEP_IDX,W
    SUBLW   6
    BTFSC   STATUS,2
    GOTO    PAT_6

    GOTO    PAT_7

PAT_0:
    MOVLW   0x01
    MOVWF   PORTC
    RETURN
PAT_1:
    MOVLW   0x03
    MOVWF   PORTC
    RETURN
PAT_2:
    MOVLW   0x02
    MOVWF   PORTC
    RETURN
PAT_3:
    MOVLW   0x06
    MOVWF   PORTC
    RETURN
PAT_4:
    MOVLW   0x04
    MOVWF   PORTC
    RETURN
PAT_5:
    MOVLW   0x0C
    MOVWF   PORTC
    RETURN
PAT_6:
    MOVLW   0x08
    MOVWF   PORTC
    RETURN
PAT_7:
    MOVLW   0x09
    MOVWF   PORTC
    RETURN

MOTOR_DELAY:
    MOVLW   3
    MOVWF   DELAY_COUNT1
MD_OUTER:
    MOVLW   255
    MOVWF   DELAY_COUNT2
MD_INNER:
    DECFSZ  DELAY_COUNT2,F
    GOTO    MD_INNER
    DECFSZ  DELAY_COUNT1,F
    GOTO    MD_OUTER
    RETURN

UPDATE_DISPLAY:
    ; Line 1: "Cur:%XXX.X"
    MOVLW   LCD_LINE1 + 5
    CALL    LCD_CMD
    MOVF    CURRENT_POS,W
    CALL    DISPLAY_NUMBER

    MOVLW   '.'
    CALL    LCD_CHR
    
; E?er durduysak (CURRENT_POS == TARGET_POS) -> CURT_L yaz
    BANKSEL TARGET_POS
    MOVF    TARGET_POS,W
    BANKSEL CURRENT_POS
    SUBWF   CURRENT_POS,W
    BTFSC   STATUS,2
    GOTO    DEC_FROM_CURTL

    ; Hareket halindeyken -> SUBSTEP/2 yaz
    BANKSEL SUBSTEP
    MOVF    SUBSTEP,W
    BANKSEL TEMP_VAL
    MOVWF   TEMP_VAL
    BCF     STATUS,0
    RRF     TEMP_VAL,F          ; TEMP_VAL = SUBSTEP/2 (0..9)
    MOVF    TEMP_VAL,W
    ADDLW   '0'
    CALL    LCD_CHR
    GOTO    DEC_DONE

DEC_FROM_CURTL:
    ; Eğer CURRENT_POS == 100 ise decimal = 0
    BANKSEL CURRENT_POS
    MOVF    CURRENT_POS,W
    XORLW   100
    BTFSS   STATUS,2
    GOTO    NORMAL_DEC

    MOVLW   '0'
    CALL    LCD_CHR
    RETURN

NORMAL_DEC:
    BANKSEL CURT_L
    MOVF    CURT_L,W
    ADDLW   '0'
    CALL    LCD_CHR

DEC_DONE:

    MOVLW   LCD_LINE2 + 4
    CALL    LCD_CMD

    BANKSEL LIGHT_H
    MOVF    LIGHT_H,W
    CALL    DISPLAY_NUMBER

    MOVLW   '.'
    CALL    LCD_CHR

    BANKSEL LIGHT_L
    MOVF    LIGHT_L,W
    ADDLW   '0'
    CALL    LCD_CHR

    RETURN

;-----------------------------------------------------------------------------
; READ_POT - Read potentiometer position via ADC Channel 0
;-----------------------------------------------------------------------------
READ_POT:
    ; Select Channel 0
    BANKSEL ADCON0
    MOVLW   0x81            ; Channel 0
    MOVWF   ADCON0
    
    ; Channel settling delay
    CALL    DELAY_500US
    
    ; Start conversion
    BSF     ADCON0,2
    
    ; Acquisition delay
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    
WAIT_POT:
    BTFSC   ADCON0,2
    GOTO    WAIT_POT
    
    BANKSEL ADRESH
    MOVF    ADRESH,W
    BANKSEL PORTB
    MOVWF   POT_ADC
    
    RETURN
    
;-----------------------------------------------------------------------------
; UPDATE_DISPLAY_DEC - LCD update for CW motor movement (counting down)
;-----------------------------------------------------------------------------
UPDATE_DISPLAY_DEC:
    ; Line 1: "Cur:%XXX.X"
    MOVLW   LCD_LINE1 + 5
    CALL    LCD_CMD

    ; integer = CURRENT_POS - 1
    BANKSEL CURRENT_POS
    MOVF    CURRENT_POS,W
    ADDLW   0xFF            ; W = CURRENT_POS - 1
    CALL    DISPLAY_NUMBER

    MOVLW   '.'
    CALL    LCD_CHR

    ; E?er durduysak -> CURT_L yaz
    BANKSEL TARGET_POS
    MOVF    TARGET_POS,W
    BANKSEL CURRENT_POS
    SUBWF   CURRENT_POS,W
    BTFSC   STATUS,2
    GOTO    DEC2_FROM_CURTL

    ; Hareket halindeyken -> 9 - (SUBSTEP/2)
    BANKSEL SUBSTEP
    MOVF    SUBSTEP,W
    BANKSEL TEMP_VAL
    MOVWF   TEMP_VAL
    BCF     STATUS,0
    RRF     TEMP_VAL,F          ; TEMP_VAL = SUBSTEP/2
    MOVF    TEMP_VAL,W
    SUBLW   9                   ; W = 9 - W
    ADDLW   '0'
    CALL    LCD_CHR
    GOTO    DEC2_DONE

DEC2_FROM_CURTL:
    BANKSEL CURT_L
    MOVF    CURT_L,W
    ADDLW   '0'
    CALL    LCD_CHR

DEC2_DONE:
    
    MOVLW   LCD_LINE2 + 4
    CALL    LCD_CMD

    BANKSEL LIGHT_H
    MOVF    LIGHT_H,W
    CALL    DISPLAY_NUMBER

    MOVLW   '.'
    CALL    LCD_CHR

    BANKSEL LIGHT_L
    MOVF    LIGHT_L,W
    ADDLW   '0'
    CALL    LCD_CHR



;-----------------------------------------------------------------------------
; READ_LDR - Read light level via ADC Channel 1 for mode selection
;-----------------------------------------------------------------------------
READ_LDR:
    ; Select Channel 1
    BANKSEL ADCON0
    MOVLW   0x89            ; Channel 1
    MOVWF   ADCON0
    
    ; Channel settling delay
    CALL    DELAY_500US
    
    ; Start conversion
    BSF     ADCON0,2
    
    ; Acquisition delay
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    
WAIT_LDR:
    BTFSC   ADCON0,2
    GOTO    WAIT_LDR
    
    BANKSEL ADRESH
    MOVF    ADRESH,W        ; W = ADRESH (0..255)
    SUBLW   255             ; W = 255 - W   (invert)
    BANKSEL LDR_ADC
    MOVWF   LDR_ADC


    ; LIGHT_H = LDR_ADC
    BANKSEL LIGHT_H
    MOVF    LDR_ADC,W
    MOVWF   LIGHT_H

    ; LIGHT_L = (LDR_ADC * 10) / 256  -> 0..9
    BANKSEL LDR_ADC
    MOVF    LDR_ADC,W
    BANKSEL TEMP_VAL
    MOVWF   TEMP_VAL

    BANKSEL LIGHT_L
    CLRF    LIGHT_L

LDR_DEC_LOOP:
    MOVLW   26
    SUBWF   TEMP_VAL,W
    BTFSS   STATUS,0
    GOTO    LDR_DEC_DONE

    MOVLW   26
    SUBWF   TEMP_VAL,F
    INCF    LIGHT_L,F
    GOTO    LDR_DEC_LOOP

LDR_DEC_DONE:
    ; Eğer LDR_ADC = 255 ise 255.0 görünsün (ondalık 0)
    BANKSEL LDR_ADC
    MOVF    LDR_ADC,W
    XORLW   255
    BTFSS   STATUS,2
    GOTO    LDR_NOT_MAX

    BANKSEL LIGHT_L
    CLRF    LIGHT_L
    GOTO    LDR_DEC_OK

LDR_NOT_MAX:
    ; güvenlik
    BANKSEL LIGHT_L
    MOVF    LIGHT_L,W
    XORLW   10
    BTFSS   STATUS,2
    GOTO    LDR_DEC_OK
    MOVLW   9
    MOVWF   LIGHT_L

LDR_DEC_OK:
    RETURN


;-----------------------------------------------------------------------------
; CONVERT_POT_TO_PERCENT - Convert POT_ADC to TARGET_POS (0-100%)
;-----------------------------------------------------------------------------
CONVERT_POT_TO_PERCENT:
    MOVF    POT_ADC,W
    MOVWF   TEMP_VAL
    
    ; Clear result
    CLRF    RESULT_H
    CLRF    RESULT_L
    
    ; Multiply by 100 (64 + 32 + 4)
    ; result = ADC << 6 (ADC * 64)
    MOVF    TEMP_VAL,W
    MOVWF   RESULT_L
    CLRF    RESULT_H
    
    MOVLW   6
    MOVWF   DIV_COUNT
SHIFT_64:
    BCF     STATUS,0
    RLF     RESULT_L,F
    RLF     RESULT_H,F
    DECFSZ  DIV_COUNT,F
    GOTO    SHIFT_64
    
    ; Save (64 * ADC)
    MOVF    RESULT_L,W
    MOVWF   MULT_A
    MOVF    RESULT_H,W
    MOVWF   RESULT_L      ; Use RESULT_L as high byte temp
    
    ; Add (ADC << 5) = ADC * 32
    MOVF    TEMP_VAL,W
    MOVWF   RESULT_H      ; Reuse RESULT_H
    CLRF    DIV_COUNT     ; Temp high byte
    
    MOVLW   5
    MOVWF   DELAY_COUNT3
SHIFT_32:
    BCF     STATUS,0
    RLF     RESULT_H,F
    RLF     DIV_COUNT,F
    DECFSZ  DELAY_COUNT3,F
    GOTO    SHIFT_32
    
    MOVF    RESULT_H,W
    ADDWF   MULT_A,F
    BTFSC   STATUS,0
    INCF    RESULT_L,F
    MOVF    DIV_COUNT,W
    ADDWF   RESULT_L,F
    
    ; Add (ADC << 2) = ADC * 4
    MOVF    TEMP_VAL,W
    MOVWF   RESULT_H
    BCF     STATUS,0
    RLF     RESULT_H,F
    RLF     RESULT_H,F
    
    MOVF    RESULT_H,W
    ADDWF   MULT_A,F
    BTFSC   STATUS,0
    INCF    RESULT_L,F
    
    ; Result_L has high byte = percentage
    MOVF    RESULT_L,W
    MOVWF   TARGET_POS
    
    ; Force to 100 if >= 254
    MOVLW   254
    SUBWF   POT_ADC,W
    BTFSC   STATUS,0
    GOTO    FORCE_100
    
    ; Limit to 100
    MOVF    TARGET_POS,W
    SUBLW   100
    BTFSS   STATUS,0
    GOTO    LIMIT_100
    RETURN
    
FORCE_100:
    MOVLW   100
    MOVWF   TARGET_POS
    RETURN
    
LIMIT_100:
    MOVLW   100
    MOVWF   TARGET_POS
    RETURN

;-----------------------------------------------------------------------------
; SHOW_LABELS - Display static text
;-----------------------------------------------------------------------------
SHOW_LABELS:
    ; Line 1: "Cur:%000.0"
    MOVLW   LCD_LINE1
    CALL    LCD_CMD

    MOVLW   'C'
    CALL    LCD_CHR
    MOVLW   'u'
    CALL    LCD_CHR
    MOVLW   'r'
    CALL    LCD_CHR
    MOVLW   ':'
    CALL    LCD_CHR
    MOVLW   '%'
    CALL    LCD_CHR
    MOVLW   '0'
    CALL    LCD_CHR
    MOVLW   '0'
    CALL    LCD_CHR
    MOVLW   '0'
    CALL    LCD_CHR
    MOVLW   '.'
    CALL    LCD_CHR
    MOVLW   '0'
    CALL    LCD_CHR

    
    ; Line 2: "LDR:000"
    MOVLW   LCD_LINE2
    CALL    LCD_CMD
    
    MOVLW   'L'
    CALL    LCD_CHR
    MOVLW   'D'
    CALL    LCD_CHR
    MOVLW   'R'
    CALL    LCD_CHR
    MOVLW   ':'
    CALL    LCD_CHR
    MOVLW   '0'
    CALL    LCD_CHR
    MOVLW   '0'
    CALL    LCD_CHR
    MOVLW   '0'
    CALL    LCD_CHR
    
    RETURN

;-----------------------------------------------------------------------------
; DISPLAY_NUMBER - Display 3-digit number
;-----------------------------------------------------------------------------
DISPLAY_NUMBER:
    MOVWF   TEMP_VAL
    CLRF    DIGIT_100
    CLRF    DIGIT_10
    CLRF    DIGIT_1
    
LOOP_100:
    MOVLW   100
    SUBWF   TEMP_VAL,W
    BTFSS   STATUS,0
    GOTO    DONE_100
    MOVWF   TEMP_VAL
    INCF    DIGIT_100,F
    GOTO    LOOP_100
DONE_100:

LOOP_10:
    MOVLW   10
    SUBWF   TEMP_VAL,W
    BTFSS   STATUS,0
    GOTO    DONE_10
    MOVWF   TEMP_VAL
    INCF    DIGIT_10,F
    GOTO    LOOP_10
DONE_10:

    MOVF    TEMP_VAL,W
    MOVWF   DIGIT_1
    
    MOVF    DIGIT_100,W
    ADDLW   '0'
    CALL    LCD_CHR
    
    MOVF    DIGIT_10,W
    ADDLW   '0'
    CALL    LCD_CHR
    
    MOVF    DIGIT_1,W
    ADDLW   '0'
    CALL    LCD_CHR
    
    RETURN

;-----------------------------------------------------------------------------
; LCD FUNCTIONS
;-----------------------------------------------------------------------------
LCD_INIT:
    CALL    DELAY_20MS
    
    MOVLW   0x38
    CALL    LCD_CMD
    
    MOVLW   0x0C
    CALL    LCD_CMD
    
    MOVLW   0x06
    CALL    LCD_CMD
    
    MOVLW   0x01
    CALL    LCD_CMD
    CALL    DELAY_20MS
    
    RETURN

LCD_CMD:
    MOVWF   PORTB
    BCF     PORTD,LCD_RS
    CALL    LCD_PULSE
    RETURN

LCD_CHR:
    MOVWF   PORTB
    BSF     PORTD,LCD_RS
    CALL    LCD_PULSE
    RETURN

LCD_PULSE:
    BSF     PORTD,LCD_EN
    CALL    DELAY_500US
    BCF     PORTD,LCD_EN
    CALL    DELAY_500US
    RETURN

;-----------------------------------------------------------------------------
; UART FUNCTIONS (EUSART)
;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------
; UART FUNCTIONS (EUSART)
;-----------------------------------------------------------------------------
UART_INIT:
    BANKSEL SPBRG
    MOVLW   25            ; 20MHz/9600 için (8MHz ise 51 yap)
    MOVWF   SPBRG

    BANKSEL TXSTA
    MOVLW   0x24           ; BRGH=1, SYNC=0, TXEN=1
    MOVWF   TXSTA

    BANKSEL RCSTA
    MOVLW   0x90           ; SPEN=1, CREN=1
    MOVWF   RCSTA
    RETURN

UART_TX_BYTE:
WAIT_TX:
    BANKSEL PIR1
    BTFSS   PIR1,4         ; TXIF
    GOTO    WAIT_TX
    BANKSEL TXREG
    MOVWF   TXREG
    RETURN

UART_RX_BYTE:
WAIT_RX:
    BANKSEL PIR1
    BTFSS   PIR1,5         ; RCIF
    GOTO    WAIT_RX

    BANKSEL RCSTA
    BTFSC   RCSTA,2        ; FERR? (Framing error)
    GOTO    DISCARD_FERR

    BTFSC   RCSTA,1        ; OERR?
    GOTO    FIX_OERR

    BANKSEL RCREG
    MOVF    RCREG,W
    RETURN

DISCARD_FERR:
    BANKSEL RCREG
    MOVF    RCREG,W        ; read to clear RCIF, discard
    RETURN

FIX_OERR:
    BCF     RCSTA,4        ; CREN=0
    BSF     RCSTA,4        ; CREN=1
    GOTO    WAIT_RX


;-----------------------------------------------------------------------------
; UART_SERVICE - Process incoming UART commands from PC application
;-----------------------------------------------------------------------------
UART_SERVICE:
    ; veri yoksa ç?k (RCIF = 0)
    BANKSEL PIR1
    BTFSS   PIR1,5          ; RCIF
    RETURN

    ; 1 byte al -> UART_RX
    CALL    UART_RX_BYTE
    BANKSEL UART_RX
    MOVWF   UART_RX

    ; ---------- GET komutlar? ----------
    ; 0x01 -> curtain low
    BANKSEL UART_RX
    MOVF    UART_RX,W
    XORLW   0x01
    BTFSC   STATUS,2
    GOTO    SEND_CURT_L

    ; 0x02 -> curtain high
    BANKSEL UART_RX
    MOVF    UART_RX,W
    XORLW   0x02
    BTFSC   STATUS,2
    GOTO    SEND_CURT_H

    ; 0x07 -> light low
    BANKSEL UART_RX
    MOVF    UART_RX,W
    XORLW   0x07
    BTFSC   STATUS,2
    GOTO    SEND_LIGHT_L

    ; 0x08 -> light high
    BANKSEL UART_RX
    MOVF    UART_RX,W
    XORLW   0x08
    BTFSC   STATUS,2
    GOTO    SEND_LIGHT_H

    ; ---------- SET komutlar? ----------
    ; 10xxxxxx -> SET_CURT_L
    BANKSEL UART_RX
    MOVF    UART_RX,W
    ANDLW   0xC0
    XORLW   0x80
    BTFSC   STATUS,2
    GOTO    SET_CURT_L

    ; 11xxxxxx -> SET_CURT_H
    BANKSEL UART_RX
    MOVF    UART_RX,W
    ANDLW   0xC0
    XORLW   0xC0
    BTFSC   STATUS,2
    GOTO    SET_CURT_H

    RETURN

SEND_CURT_L:
    BANKSEL CURT_L
    MOVF    CURT_L,W
    CALL    UART_TX_BYTE
    RETURN

SEND_CURT_H:
    BANKSEL CURT_H
    MOVF    CURT_H,W
    CALL    UART_TX_BYTE
    RETURN

SEND_LIGHT_L:
    BANKSEL LIGHT_L
    MOVF    LIGHT_L,W
    CALL    UART_TX_BYTE
    RETURN


SEND_LIGHT_H:
    BANKSEL LDR_ADC
    MOVF    LDR_ADC,W
    CALL    UART_TX_BYTE
    RETURN

SET_CURT_L:
    BANKSEL UART_RX
    MOVF    UART_RX,W
    ANDLW   0x3F
    ; Save to both CURT_L and SAVED_CURT_L
    BANKSEL CURT_L
    MOVWF   CURT_L
    BANKSEL SAVED_CURT_L
    MOVWF   SAVED_CURT_L
    
    MOVLW   1
    BANKSEL UART_OVERRIDE
    MOVWF   UART_OVERRIDE
    RETURN

SET_CURT_H:
    BANKSEL UART_RX
    MOVF    UART_RX,W
    ANDLW   0x3F
    ; Save to both CURT_H and SAVED_CURT_H
    BANKSEL CURT_H
    MOVWF   CURT_H
    BANKSEL SAVED_CURT_H
    MOVWF   SAVED_CURT_H

    ; TARGET_POS = CURT_H
    BANKSEL CURT_H
    MOVF    CURT_H,W
    BANKSEL TARGET_POS
    MOVWF   TARGET_POS
    
    ; Update POT_LAST to current pot value - prevents pot from overriding UART value
    BANKSEL POT_ADC
    MOVF    POT_ADC,W
    BANKSEL POT_LAST
    MOVWF   POT_LAST

    ; UART kontrolü aktif
    MOVLW   1
    BANKSEL UART_OVERRIDE
    MOVWF   UART_OVERRIDE
    RETURN





;-----------------------------------------------------------------------------
; DELAY FUNCTIONS
;-----------------------------------------------------------------------------
DELAY_20MS:
    MOVLW   40
    MOVWF   DELAY_COUNT3
DELAY_20MS_LOOP:
    CALL    DELAY_500US
    DECFSZ  DELAY_COUNT3,F
    GOTO    DELAY_20MS_LOOP
    RETURN

DELAY_5MS:
    MOVLW   10
    MOVWF   DELAY_COUNT3
DELAY_5MS_LOOP:
    CALL    DELAY_500US
    DECFSZ  DELAY_COUNT3,F
    GOTO    DELAY_5MS_LOOP
    RETURN

DELAY_500US:
    MOVLW   250
    MOVWF   DELAY_COUNT2
DELAY_500US_LOOP:
    NOP
    DECFSZ  DELAY_COUNT2,F
    GOTO    DELAY_500US_LOOP
    RETURN

    END
