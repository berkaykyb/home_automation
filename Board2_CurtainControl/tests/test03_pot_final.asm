;=============================================================================
; TEST 03 - POTENTIOMETER TO CURTAIN STATUS (FINAL VERSION)
; Read potentiometer and display curtain status 0-100%
;
; LCD Display:
;   Line 1: "Curtain: XX %"
;   Line 2: "ADC Raw: XXX"
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
; MEMORY VARIABLES
;-----------------------------------------------------------------------------
DELAY_COUNT1    EQU     0x20
DELAY_COUNT2    EQU     0x21
ADC_RAW         EQU     0x22    ; Raw ADC value (0-255)
CURTAIN_STATUS  EQU     0x23    ; Curtain % (0-100)
TEMP_VAL        EQU     0x24
DIGIT_100       EQU     0x25
DIGIT_10        EQU     0x26
DIGIT_1         EQU     0x27
; Math variables
MULT_A          EQU     0x28    ; Multiplicand
MULT_B          EQU     0x29    ; Multiplier
RESULT_H        EQU     0x2A    ; Result high byte
RESULT_L        EQU     0x2B    ; Result low byte
DIV_COUNT       EQU     0x2C    ; Counter
MULT_TEMP       EQU     0x2D    ; Temp for multiplication

;-----------------------------------------------------------------------------
    PSECT   resetVec,class=CODE,delta=2
resetVec:
    GOTO    START

;-----------------------------------------------------------------------------
    PSECT   code,class=CODE,delta=2

START:
    ; Configure ports
    BANKSEL TRISB
    CLRF    TRISB           ; PORTB output
    
    BANKSEL TRISD  
    BCF     TRISD,4         ; RD4 output
    BCF     TRISD,5         ; RD5 output
    
    BANKSEL TRISA
    BSF     TRISA,0         ; RA0 input
    
    ; Configure ADC
    BANKSEL ADCON1
    MOVLW   0x0E            ; LEFT justified, AN0 analog
    MOVWF   ADCON1
    
    BANKSEL ADCON0
    MOVLW   0x81            ; Fosc/32, Ch0, ADC ON
    MOVWF   ADCON0
    
    BANKSEL PORTB
    CLRF    PORTB
    CLRF    PORTD
    
    ; Initialize LCD
    CALL    DELAY_20MS
    CALL    LCD_INIT
    
    ; Show labels (once)
    CALL    SHOW_LABELS

;-----------------------------------------------------------------------------
; MAIN LOOP
;-----------------------------------------------------------------------------
MAIN_LOOP:
    ; Read potentiometer
    CALL    READ_POT
    
    ; Convert ADC (0-255) to Percentage (0-100)
    CALL    CONVERT_TO_PERCENT
    
    ; Update display
    CALL    UPDATE_DISPLAY
    
    ; Delay ~100ms
    CALL    DELAY_20MS
    CALL    DELAY_20MS
    CALL    DELAY_20MS
    CALL    DELAY_20MS
    CALL    DELAY_20MS
    
    GOTO    MAIN_LOOP

;-----------------------------------------------------------------------------
; READ POTENTIOMETER
; Output: ADC_RAW (0-255)
;-----------------------------------------------------------------------------
READ_POT:
    BANKSEL ADCON0
    BSF     ADCON0,2        ; Start conversion
    
    ; ADC Acquisition delay - CRITICAL!
    ; Must wait for sampling capacitor to charge
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
    NOP                     ; 20 cycles @ 4MHz = 20 µs
    
WAIT_CONV:
    BTFSC   ADCON0,2
    GOTO    WAIT_CONV
    
    BANKSEL ADRESH          ; Use ADRESH for left justified
    MOVF    ADRESH,W        ; Read high 8 bits
    BANKSEL PORTB
    MOVWF   ADC_RAW
    
    RETURN

;-----------------------------------------------------------------------------
; CONVERT TO PERCENT
; Input: ADC_RAW (0-255)
; Output: CURTAIN_STATUS (0-100)
; Method: Shift and add approximation
; Formula: percent ≈ (ADC/2) + (ADC/8) gives ~0.625*ADC
; Better: (ADC*25)/64 = (ADC*25)>>6
;-----------------------------------------------------------------------------
CONVERT_TO_PERCENT:
    MOVF    ADC_RAW,W
    MOVWF   TEMP_VAL
    
    ; Use bit shifting for fast approximation
    ; percent = ADC * 0.392 ≈ ADC * 100/255
    ; Approximation: (ADC >> 1) + (ADC >> 3) - (ADC >> 6)
    ; Or simpler: ADC * 25 / 64
    
    MOVF    ADC_RAW,W
    MOVWF   TEMP_VAL
    
    ; Method: percent = (ADC * 100) >> 8
    ; This gives (ADC * 100) / 256 which is close to /255
    
    ; Clear result
    CLRF    RESULT_H
    CLRF    RESULT_L
    
    ; Multiply by 100 using shifts and adds
    ; 100 = 64 + 32 + 4 = 2^6 + 2^5 + 2^2
    
    ; result = ADC << 6 (ADC * 64)
    MOVF    TEMP_VAL,W
    MOVWF   RESULT_L
    CLRF    RESULT_H
    
    ; Shift left 6 times
    MOVLW   6
    MOVWF   DIV_COUNT
SHIFT_64:
    BCF     STATUS,0
    RLF     RESULT_L,F
    RLF     RESULT_H,F
    DECFSZ  DIV_COUNT,F
    GOTO    SHIFT_64
    
    ; Save this (64 * ADC)
    MOVF    RESULT_L,W
    MOVWF   MULT_A
    MOVF    RESULT_H,W
    MOVWF   MULT_B
    
    ; Add (ADC << 5) = ADC * 32
    MOVF    TEMP_VAL,W
    MOVWF   RESULT_L
    CLRF    RESULT_H
    
    MOVLW   5
    MOVWF   DIV_COUNT
SHIFT_32:
    BCF     STATUS,0
    RLF     RESULT_L,F
    RLF     RESULT_H,F
    DECFSZ  DIV_COUNT,F
    GOTO    SHIFT_32
    
    ; Add to previous result
    MOVF    RESULT_L,W
    ADDWF   MULT_A,F
    BTFSC   STATUS,0
    INCF    MULT_B,F
    MOVF    RESULT_H,W
    ADDWF   MULT_B,F
    
    ; Add (ADC << 2) = ADC * 4
    MOVF    TEMP_VAL,W
    MOVWF   RESULT_L
    BCF     STATUS,0
    RLF     RESULT_L,F
    RLF     RESULT_L,F
    
    MOVF    RESULT_L,W
    ADDWF   MULT_A,F
    BTFSC   STATUS,0
    INCF    MULT_B,F
    
    ; Now we have ADC * 100 in MULT_B:MULT_A
    ; Divide by 256 (just take high byte)
    MOVF    MULT_B,W
    MOVWF   CURTAIN_STATUS
    
    ; If ADC_RAW >= 254, force to 100% (handles upper range)
    MOVLW   254
    SUBWF   ADC_RAW,W
    BTFSC   STATUS,0
    GOTO    FORCE_100
    
    ; Limit to 100 (safety)
    MOVF    CURTAIN_STATUS,W
    SUBLW   100
    BTFSS   STATUS,0
    GOTO    LIMIT_TO_100
    RETURN
    
FORCE_100:
    MOVLW   100
    MOVWF   CURTAIN_STATUS
    RETURN
    
LIMIT_TO_100:
    MOVLW   100
    MOVWF   CURTAIN_STATUS
    RETURN

;-----------------------------------------------------------------------------
; SHOW LABELS
;-----------------------------------------------------------------------------
SHOW_LABELS:
    ; Line 1: "Curtain:"
    MOVLW   LCD_LINE1
    CALL    LCD_CMD
    
    MOVLW   'C'
    CALL    LCD_CHR
    MOVLW   'u'
    CALL    LCD_CHR
    MOVLW   'r'
    CALL    LCD_CHR
    MOVLW   't'
    CALL    LCD_CHR
    MOVLW   'a'
    CALL    LCD_CHR
    MOVLW   'i'
    CALL    LCD_CHR
    MOVLW   'n'
    CALL    LCD_CHR
    MOVLW   ':'
    CALL    LCD_CHR
    
    ; Line 2: "ADC Raw:"
    MOVLW   LCD_LINE2
    CALL    LCD_CMD
    
    MOVLW   'A'
    CALL    LCD_CHR
    MOVLW   'D'
    CALL    LCD_CHR
    MOVLW   'C'
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   'R'
    CALL    LCD_CHR
    MOVLW   'a'
    CALL    LCD_CHR
    MOVLW   'w'
    CALL    LCD_CHR
    MOVLW   ':'
    CALL    LCD_CHR
    
    RETURN

;-----------------------------------------------------------------------------
; UPDATE DISPLAY
;-----------------------------------------------------------------------------
UPDATE_DISPLAY:
    ; Update Line 1 - Show curtain percentage
    MOVLW   LCD_LINE1 + 9   ; Position after "Curtain: "
    CALL    LCD_CMD
    
    MOVF    CURTAIN_STATUS,W
    CALL    DISPLAY_NUMBER
    
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   '%'
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    
    ; Update Line 2 - Show raw ADC
    MOVLW   LCD_LINE2 + 9   ; Position after "ADC Raw: "
    CALL    LCD_CMD
    
    MOVF    ADC_RAW,W
    CALL    DISPLAY_NUMBER
    
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    
    RETURN

;-----------------------------------------------------------------------------
; DISPLAY NUMBER (0-255)
; Input: W = number to display
;-----------------------------------------------------------------------------
DISPLAY_NUMBER:
    MOVWF   TEMP_VAL
    
    CLRF    DIGIT_100
    CLRF    DIGIT_10
    CLRF    DIGIT_1
    
    ; Extract hundreds
DIV_100:
    MOVLW   100
    SUBWF   TEMP_VAL,W
    BTFSS   STATUS,0
    GOTO    DIV_10
    MOVWF   TEMP_VAL
    INCF    DIGIT_100,F
    GOTO    DIV_100
    
    ; Extract tens
DIV_10:
    MOVLW   10
    SUBWF   TEMP_VAL,W
    BTFSS   STATUS,0
    GOTO    DIV_1
    MOVWF   TEMP_VAL
    INCF    DIGIT_10,F
    GOTO    DIV_10
    
DIV_1:
    MOVF    TEMP_VAL,W
    MOVWF   DIGIT_1
    
    ; Display hundreds (if > 0)
    MOVF    DIGIT_100,W
    BTFSC   STATUS,2
    GOTO    SKIP_100
    ADDLW   '0'
    CALL    LCD_CHR
    GOTO    SHOW_10
    
SKIP_100:
    MOVLW   ' '
    CALL    LCD_CHR
    
SHOW_10:
    MOVF    DIGIT_10,W
    ADDLW   '0'
    CALL    LCD_CHR
    
    MOVF    DIGIT_1,W
    ADDLW   '0'
    CALL    LCD_CHR
    
    RETURN

;-----------------------------------------------------------------------------
; LCD ROUTINES
;-----------------------------------------------------------------------------
LCD_INIT:
    CALL    DELAY_20MS
    MOVLW   0x38
    CALL    LCD_CMD
    CALL    DELAY_5MS
    MOVLW   0x38
    CALL    LCD_CMD
    CALL    DELAY_200US
    MOVLW   0x38
    CALL    LCD_CMD
    CALL    DELAY_200US
    MOVLW   0x0C
    CALL    LCD_CMD
    CALL    DELAY_200US
    MOVLW   0x01
    CALL    LCD_CMD
    CALL    DELAY_5MS
    MOVLW   0x06
    CALL    LCD_CMD
    CALL    DELAY_200US
    RETURN

LCD_CMD:
    BANKSEL PORTB
    MOVWF   PORTB
    BANKSEL PORTD
    BCF     PORTD,LCD_RS
    BSF     PORTD,LCD_EN
    NOP
    NOP
    BCF     PORTD,LCD_EN
    BANKSEL PORTB
    RETURN

LCD_CHR:
    BANKSEL PORTB
    MOVWF   PORTB
    BANKSEL PORTD
    BSF     PORTD,LCD_RS
    BSF     PORTD,LCD_EN
    NOP
    NOP
    BCF     PORTD,LCD_EN
    BANKSEL PORTB
    CALL    DELAY_200US
    RETURN

;-----------------------------------------------------------------------------
; DELAY ROUTINES
;-----------------------------------------------------------------------------
DELAY_20MS:
    MOVLW   40
    MOVWF   DELAY_COUNT1
DL20_LOOP:
    CALL    DELAY_500US
    DECFSZ  DELAY_COUNT1,F
    GOTO    DL20_LOOP
    RETURN

DELAY_5MS:
    MOVLW   10
    MOVWF   DELAY_COUNT1
DL5_LOOP:
    CALL    DELAY_500US
    DECFSZ  DELAY_COUNT1,F
    GOTO    DL5_LOOP
    RETURN

DELAY_500US:
    MOVLW   165
    MOVWF   DELAY_COUNT2
DL500_LOOP:
    NOP
    DECFSZ  DELAY_COUNT2,F
    GOTO    DL500_LOOP
    RETURN

DELAY_200US:
    MOVLW   66
    MOVWF   DELAY_COUNT2
DL200_LOOP:
    NOP
    DECFSZ  DELAY_COUNT2,F
    GOTO    DL200_LOOP
    RETURN
