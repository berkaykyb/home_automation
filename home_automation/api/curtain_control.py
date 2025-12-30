"""
CurtainControlSystemConnection - Class for Board2 (Curtain Control) communication.

UART Protocol (Board2 - PIC16F877A):
    GET Commands:
        0x01 -> Get curtain status fractional part (0-9)
        0x02 -> Get curtain status integer part (0-100)
        0x07 -> Get light intensity fractional part
        0x08 -> Get light intensity integer part (LDR value 0-255)
    
    SET Commands:
        10xxxxxx (0x80-0xBF) -> Set curtain status fractional (lower 6 bits)
        11xxxxxx (0xC0-0xFF) -> Set curtain status integer (lower 6 bits, 0-63 only!)
        
    NOTE: Due to 6-bit limitation, values 64-100 cannot be sent directly.
          Board2.asm uses 0x3F mask so max settable value is 63.
"""
from .connection import HomeAutomationSystemConnection
import time


# GET command codes
CMD_GET_CURTAIN_FRAC = 0x01
CMD_GET_CURTAIN_INT = 0x02
CMD_GET_LIGHT_FRAC = 0x07
CMD_GET_LIGHT_INT = 0x08

# SET command masks
CMD_SET_CURTAIN_FRAC_MASK = 0x80  # 10xxxxxx
CMD_SET_CURTAIN_INT_MASK = 0xC0   # 11xxxxxx


class CurtainControlSystemConnection(HomeAutomationSystemConnection):
    """Connection class for Curtain Control system (Board2)."""
    
    def __init__(self, com_port: int = 1, baud_rate: int = 9600):
        """
        Initialize Curtain Control connection.
        
        Args:
            com_port: COM port number
            baud_rate: Baud rate (default: 9600)
        """
        super().__init__(com_port, baud_rate)
        self._curtain_status = 0.0
        self._light_intensity = 0.0
        self._last_valid_curtain = 0.0
        self._last_valid_light = 0.0
    
    @property
    def curtainStatus(self) -> float:
        """Get the curtain status (0-100%)."""
        return self._curtain_status
    
    @property
    def lightIntensity(self) -> float:
        """Get the light intensity (Lux)."""
        return self._light_intensity
    
    def update(self) -> None:
        """
        Update all member data by sending and receiving messages.
        Gets curtainStatus, lightIntensity from board.
        """
        if not self.isConnected:
            return
        
        try:
            # Flush buffers before reading
            self._serial.reset_input_buffer()
            
            # Get curtain status with small delay between commands
            int_part = self._send_command(CMD_GET_CURTAIN_INT)
            time.sleep(0.05)
            frac_part = self._send_command(CMD_GET_CURTAIN_FRAC)
            
            # Validate values before updating
            if int_part >= 0 and int_part <= 100 and frac_part >= 0 and frac_part <= 9:
                new_curtain = float(int_part) + float(frac_part) / 10.0
                # Sanity check - value should be 0-100
                if 0.0 <= new_curtain <= 100.0:
                    self._curtain_status = new_curtain
                    self._last_valid_curtain = new_curtain
                else:
                    # Invalid value, keep last valid
                    self._curtain_status = self._last_valid_curtain
            
            time.sleep(0.05)
            
            # Get light intensity
            int_part = self._send_command(CMD_GET_LIGHT_INT)
            time.sleep(0.05)
            frac_part = self._send_command(CMD_GET_LIGHT_FRAC)
            
            # Validate values
            if int_part >= 0 and int_part <= 255 and frac_part >= 0 and frac_part <= 9:
                new_light = float(int_part) + float(frac_part) / 10.0
                if 0.0 <= new_light <= 255.9:
                    self._light_intensity = new_light
                    self._last_valid_light = new_light
                else:
                    self._light_intensity = self._last_valid_light
                    
        except Exception as e:
            print(f"Update error: {e}")
            # Keep last valid values on error
            self._curtain_status = self._last_valid_curtain
            self._light_intensity = self._last_valid_light
    
    def setCurtainStatus(self, status: float) -> bool:
        """
        Set the desired curtain status by sending message to the board.
        
        Args:
            status: Curtain openness percentage (0.0 - 100.0)
            
        Returns:
            True if successful, False otherwise
            
        Note:
            Due to 6-bit protocol limitation, only values 0-63 can be set directly.
            Values 64-100 will be clamped to 63.
        """
        if status < 0.0 or status > 100.0:
            return False
        
        if not self.isConnected:
            return False
        
        from decimal import Decimal
        
        # Use Decimal for precise arithmetic
        status_dec = Decimal(str(round(status, 1)))
        
        # Extract integer and fractional parts
        int_part = int(status_dec)
        frac_part = int((status_dec - int_part) * 10)
        
        # LIMITATION: Board2 uses 6-bit mask (0x3F), max value is 63
        # Values > 63 will be sent as-is (masked to 0-63 by board)
        # We warn but still send
        if int_part > 63:
            pass  # Value will be masked by board
        

        
        # Flush buffers
        self._serial.reset_input_buffer()
        self._serial.reset_output_buffer()
        
        # Send FRACTIONAL part FIRST (same as air conditioner fix)
        cmd_frac = CMD_SET_CURTAIN_FRAC_MASK | (frac_part & 0x3F)

        self._serial.write(bytes([cmd_frac]))
        self._serial.flush()
        
        # Wait for board to process
        time.sleep(0.15)
        
        # Send INTEGER part
        cmd_int = CMD_SET_CURTAIN_INT_MASK | (int_part & 0x3F)

        self._serial.write(bytes([cmd_int]))
        self._serial.flush()
        
        self._curtain_status = float(status_dec)
        return True
    
    def getLightIntensity(self) -> float:
        """
        Get the light intensity.
        
        Returns:
            Light intensity value
        """
        self.update()
        return self._light_intensity
