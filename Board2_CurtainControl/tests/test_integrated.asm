;=============================================================================
; INTEGRATED CURTAIN CONTROL SYSTEM
; Modules: Potentiometer + Step Motor + LCD + LDR
;=============================================================================

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

;-----------------------------------------------------------------------------
    PSECT   resetVec,class=CODE,delta=2
resetVec:
    GOTO    START

;-----------------------------------------------------------------------------
    PSECT   code,class=CODE,delta=2

START:
    ; Configure ports
    BANKSEL TRISB
    CLRF    TRISB           ; PORTB output (LCD data)
    
    BANKSEL TRISD  
    BCF     TRISD,4         ; RD4 output (LCD RS)
    BCF     TRISD,5         ; RD5 output (LCD EN)
    
    BANKSEL TRISC
    CLRF    TRISC           ; PORTC output (Motor)
    
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
    CLRF    CURRENT_POS
    CLRF    TARGET_POS
    CLRF    STEP_IDX
    
    ; Initialize LCD
    CALL    DELAY_20MS
    CALL    LCD_INIT
    
    ; Show static labels
    CALL    SHOW_LABELS

;-----------------------------------------------------------------------------
; MAIN LOOP
;-----------------------------------------------------------------------------
MAIN_LOOP:
    ; 1. Read LDR
    CALL    READ_LDR
    
    ; 2. Check LDR threshold for mode selection (Threshold = 50)
    MOVF    LDR_ADC,W
    SUBLW   49              ; W = 49 - LDR
    BTFSS   STATUS,0        ; LDR < 50? (dark, automatic)
    GOTO    MANUAL_MODE
    
AUTOMATIC_MODE:
    ; LDR < 50 (dark): Automatic control, force close
    MOVLW   100
    MOVWF   TARGET_POS
    GOTO    CONTROL_MOTOR
    
MANUAL_MODE:
    ; LDR >= 50 (bright): Manual control via potentiometer
    CALL    READ_POT
    CALL    CONVERT_POT_TO_PERCENT
    
CONTROL_MOTOR:
    ; 3. Curtain control (smooth half-step)
    CALL    CURTAIN_CONTROL
    
    ; 4. Update display
    CALL    UPDATE_DISPLAY
    
    GOTO    MAIN_LOOP

;-----------------------------------------------------------------------------
; CURTAIN_CONTROL (HALF-STEP: 20 half-steps = 1%)
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
    DECFSZ  INNER_CNT,F
    GOTO    LOOP_CW
    DECF    CURRENT_POS,F
    RETURN

;-----------------------------------------------------------------------------
; MOTOR STEP (HALF-STEP 0-7)
;-----------------------------------------------------------------------------
MOTOR_STEP_CW:
    CALL    MOTOR_OUTPUT_PATTERN
    CALL    MOTOR_DELAY
    
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
    ; Line 1: "Cur:XXX"
    MOVLW   LCD_LINE1 + 4
    CALL    LCD_CMD
    MOVF    CURRENT_POS,W
    CALL    DISPLAY_NUMBER
    
    ; Line 2: "LDR:XXX"
    MOVLW   LCD_LINE2 + 4 ; "LDR:" den sonra
    CALL    LCD_CMD
    MOVF    LDR_ADC,W
    CALL    DISPLAY_NUMBER
    
    RETURN

;-----------------------------------------------------------------------------
; READ_POT - Read potentiometer (Channel 0)
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
; READ_LDR - Read LDR sensor (Channel 1)
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
    MOVF    ADRESH,W
    BANKSEL PORTB
    MOVWF   LDR_ADC
    
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
    ; Line 1: "Cur:000"
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
    MOVLW   '0'
    CALL    LCD_CHR
    MOVLW   '0'
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