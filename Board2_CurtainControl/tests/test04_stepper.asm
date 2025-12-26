;=============================================================================
; TEST 04 - STEP MOTOR TEST
; Test stepper motor control with forward/reverse rotation
; Motor: 4-phase unipolar, 1.8° per step (200 steps/revolution)
; Pins: RD0, RD1, RD2, RD3
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

; Stepper motor phase patterns (full-step mode)
; Phase sequence: A -> AB -> B -> BC -> C -> CD -> D -> DA (half-step)
; Full-step: A -> B -> C -> D
STEP_PATTERN_0  EQU     0x01        ; Phase A (RD0)
STEP_PATTERN_1  EQU     0x02        ; Phase B (RD1)
STEP_PATTERN_2  EQU     0x04        ; Phase C (RD2)
STEP_PATTERN_3  EQU     0x08        ; Phase D (RD3)

;-----------------------------------------------------------------------------
; VARIABLES
;-----------------------------------------------------------------------------
DELAY_COUNT1    EQU     0x20
DELAY_COUNT2    EQU     0x21
DELAY_COUNT3    EQU     0x22
STEP_INDEX      EQU     0x23        ; Current step in sequence (0-3)
STEP_COUNT_L    EQU     0x24        ; Step counter low byte
STEP_COUNT_H    EQU     0x25        ; Step counter high byte
DIRECTION       EQU     0x26        ; 0=forward, 1=reverse
TEMP_VAL        EQU     0x27
DIGIT_100       EQU     0x28
DIGIT_10        EQU     0x29
DIGIT_1         EQU     0x2A

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
    CLRF    TRISD           ; All PORTD output (LCD + Motor)
    
    ; Clear ports
    BANKSEL PORTB
    CLRF    PORTB
    CLRF    PORTD
    
    ; Initialize variables
    CLRF    STEP_INDEX
    CLRF    STEP_COUNT_L
    CLRF    STEP_COUNT_H
    CLRF    DIRECTION       ; Start with forward
    
    ; Initialize LCD
    CALL    DELAY_20MS
    CALL    LCD_INIT
    
    ; Show labels
    CALL    SHOW_LABELS

;-----------------------------------------------------------------------------
; MAIN LOOP
;-----------------------------------------------------------------------------
MAIN_LOOP:
    ; Pattern 1: RD0
    MOVF    PORTD,W
    ANDLW   0xF0
    IORLW   0x01
    MOVWF   PORTD
    CALL    DELAY_5MS
    INCF    STEP_COUNT_L,F
    
    ; Pattern 2: RD1
    MOVF    PORTD,W
    ANDLW   0xF0
    IORLW   0x02
    MOVWF   PORTD
    CALL    DELAY_5MS
    INCF    STEP_COUNT_L,F
    
    ; Pattern 3: RD2
    MOVF    PORTD,W
    ANDLW   0xF0
    IORLW   0x04
    MOVWF   PORTD
    CALL    DELAY_5MS
    INCF    STEP_COUNT_L,F
    
    ; Pattern 4: RD3
    MOVF    PORTD,W
    ANDLW   0xF0
    IORLW   0x08
    MOVWF   PORTD
    CALL    DELAY_5MS
    INCF    STEP_COUNT_L,F
    
    ; Update display every 64 steps (less frequently)
    MOVF    STEP_COUNT_L,W
    ANDLW   0x3F
    BTFSS   STATUS,2
    GOTO    MAIN_LOOP
    
    MOVLW   LCD_LINE1 + 13
    CALL    LCD_CMD
    MOVF    STEP_COUNT_L,W
    CALL    DISPLAY_NUMBER
    
    GOTO    MAIN_LOOP

;-----------------------------------------------------------------------------
; REVERSE_DIR - Change motor direction
;-----------------------------------------------------------------------------
REVERSE_DIR:
    ; Toggle direction
    MOVLW   1
    XORWF   DIRECTION,F
    
    ; Reset counter
    CLRF    STEP_COUNT_L
    CLRF    STEP_COUNT_H
    
    RETURN

;-----------------------------------------------------------------------------
; STEP_FORWARD - Move motor one step forward
;-----------------------------------------------------------------------------
STEP_FORWARD:
    ; Increment step counter
    INCF    STEP_COUNT_L,F
    BTFSC   STATUS,2
    INCF    STEP_COUNT_H,F
    
    ; Get pattern directly based on step index
    MOVF    STEP_INDEX,W
    ANDLW   0x03            ; Keep only 0-3
    MOVWF   STEP_INDEX
    
    ; Output pattern based on index
    MOVF    STEP_INDEX,W
    ADDWF   PCL,F
    GOTO    STEP_0
    GOTO    STEP_1
    GOTO    STEP_2
    GOTO    STEP_3
    
STEP_0:
    MOVLW   0x01
    GOTO    OUTPUT_PATTERN
STEP_1:
    MOVLW   0x02
    GOTO    OUTPUT_PATTERN
STEP_2:
    MOVLW   0x04
    GOTO    OUTPUT_PATTERN
STEP_3:
    MOVLW   0x08
    GOTO    OUTPUT_PATTERN
    
OUTPUT_PATTERN:
    ; Output to motor (lower 4 bits of PORTD)
    MOVWF   TEMP_VAL
    MOVF    PORTD,W
    ANDLW   0xF0            ; Keep upper 4 bits (LCD control)
    IORWF   TEMP_VAL,W
    MOVWF   PORTD
    
    ; Advance to next step
    INCF    STEP_INDEX,F
    MOVF    STEP_INDEX,W
    SUBLW   4
    BTFSS   STATUS,0
    CLRF    STEP_INDEX
    
    RETURN

;-----------------------------------------------------------------------------
; GET_STEP_PATTERN - Return pattern for current step
; Input: W = step index (0-3)
; Output: W = bit pattern
;-----------------------------------------------------------------------------
GET_STEP_PATTERN:
    ADDWF   PCL,F
    RETLW   0x01            ; Phase A (RD0)
    RETLW   0x02            ; Phase B (RD1)
    RETLW   0x04            ; Phase C (RD2)
    RETLW   0x08            ; Phase D (RD3)

;-----------------------------------------------------------------------------
; SHOW_LABELS - Display static text
;-----------------------------------------------------------------------------
SHOW_LABELS:
    ; Line 1: "Motor Steps:"
    MOVLW   LCD_LINE1
    CALL    LCD_CMD
    
    MOVLW   'M'
    CALL    LCD_CHR
    MOVLW   'o'
    CALL    LCD_CHR
    MOVLW   't'
    CALL    LCD_CHR
    MOVLW   'o'
    CALL    LCD_CHR
    MOVLW   'r'
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   'S'
    CALL    LCD_CHR
    MOVLW   't'
    CALL    LCD_CHR
    MOVLW   'e'
    CALL    LCD_CHR
    MOVLW   'p'
    CALL    LCD_CHR
    MOVLW   's'
    CALL    LCD_CHR
    MOVLW   ':'
    CALL    LCD_CHR
    
    ; Line 2: "Dir:"
    MOVLW   LCD_LINE2
    CALL    LCD_CMD
    
    MOVLW   'D'
    CALL    LCD_CHR
    MOVLW   'i'
    CALL    LCD_CHR
    MOVLW   'r'
    CALL    LCD_CHR
    MOVLW   ':'
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   'F'
    CALL    LCD_CHR
    MOVLW   'W'
    CALL    LCD_CHR
    MOVLW   'D'
    CALL    LCD_CHR
    
    RETURN

;-----------------------------------------------------------------------------
; UPDATE_DISPLAY
;-----------------------------------------------------------------------------
UPDATE_DISPLAY:
    ; Update Line 1 - Show step count
    MOVLW   LCD_LINE1 + 13
    CALL    LCD_CMD
    
    MOVF    STEP_COUNT_L,W
    CALL    DISPLAY_NUMBER
    
    ; Update Line 2 - Show direction
    MOVLW   LCD_LINE2 + 5
    CALL    LCD_CMD
    
    BTFSC   DIRECTION,0
    GOTO    SHOW_REV
    
SHOW_FWD:
    MOVLW   'F'
    CALL    LCD_CHR
    MOVLW   'W'
    CALL    LCD_CHR
    MOVLW   'D'
    CALL    LCD_CHR
    RETURN
    
SHOW_REV:
    MOVLW   'R'
    CALL    LCD_CHR
    MOVLW   'E'
    CALL    LCD_CHR
    MOVLW   'V'
    CALL    LCD_CHR
    RETURN

;-----------------------------------------------------------------------------
; DISPLAY_NUMBER - Convert number to 3 digits and display
; Input: W = number (0-255)
;-----------------------------------------------------------------------------
DISPLAY_NUMBER:
    MOVWF   TEMP_VAL
    CLRF    DIGIT_100
    CLRF    DIGIT_10
    CLRF    DIGIT_1
    
    ; Hundreds digit
LOOP_100:
    MOVLW   100
    SUBWF   TEMP_VAL,W
    BTFSS   STATUS,0
    GOTO    DONE_100
    MOVWF   TEMP_VAL
    INCF    DIGIT_100,F
    GOTO    LOOP_100
DONE_100:

    ; Tens digit  
LOOP_10:
    MOVLW   10
    SUBWF   TEMP_VAL,W
    BTFSS   STATUS,0
    GOTO    DONE_10
    MOVWF   TEMP_VAL
    INCF    DIGIT_10,F
    GOTO    LOOP_10
DONE_10:

    ; Ones digit
    MOVF    TEMP_VAL,W
    MOVWF   DIGIT_1
    
    ; Display all 3 digits
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
    
    MOVLW   0x38            ; 8-bit, 2 lines, 5x8 font
    CALL    LCD_CMD
    
    MOVLW   0x0C            ; Display ON, cursor OFF
    CALL    LCD_CMD
    
    MOVLW   0x06            ; Entry mode: increment, no shift
    CALL    LCD_CMD
    
    MOVLW   0x01            ; Clear display
    CALL    LCD_CMD
    CALL    DELAY_20MS
    
    RETURN

LCD_CMD:
    MOVWF   PORTB
    BCF     PORTD,LCD_RS    ; RS = 0 for command
    CALL    LCD_PULSE
    RETURN

LCD_CHR:
    MOVWF   PORTB
    BSF     PORTD,LCD_RS    ; RS = 1 for data
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
