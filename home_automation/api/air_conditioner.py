"""
AirConditionerSystemConnection - Class for Board1 (Air Conditioner) communication.

UART Protocol (Board1 - PIC16F877A):
    GET Commands:
        0x01 -> Get desired temperature fractional part (0-9)
        0x02 -> Get desired temperature integer part (10-50)
        0x03 -> Get ambient temperature fractional part
        0x04 -> Get ambient temperature integer part
        0x05 -> Get fan speed (RPS)
    
    SET Commands:
        10xxxxxx (0x80-0xBF) -> Set desired temperature fractional (lower 6 bits)
        11xxxxxx (0xC0-0xFF) -> Set desired temperature integer (lower 6 bits, valid: 10-50)
"""
from .connection import HomeAutomationSystemConnection


# GET command codes
CMD_GET_DESIRED_FRAC = 0x01
CMD_GET_DESIRED_INT = 0x02
CMD_GET_AMBIENT_FRAC = 0x03
CMD_GET_AMBIENT_INT = 0x04
CMD_GET_FAN_SPEED = 0x05

# SET command masks
CMD_SET_DESIRED_FRAC_MASK = 0x80  # 10xxxxxx
CMD_SET_DESIRED_INT_MASK = 0xC0   # 11xxxxxx


class AirConditionerSystemConnection(HomeAutomationSystemConnection):
    """Connection class for Air Conditioner system (Board1)."""
    
    def __init__(self, com_port: int = 1, baud_rate: int = 9600):
        """
        Initialize Air Conditioner connection.
        
        Args:
            com_port: COM port number
            baud_rate: Baud rate (default: 9600)
        """
        super().__init__(com_port, baud_rate)
        self._desired_temperature = 25.0
        self._ambient_temperature = 0.0
        self._fan_speed = 0
    
    @property
    def desiredTemperature(self) -> float:
        """Get the desired temperature."""
        return self._desired_temperature
    
    @property
    def ambientTemperature(self) -> float:
        """Get the ambient temperature."""
        return self._ambient_temperature
    
    @property
    def fanSpeed(self) -> int:
        """Get the fan speed in RPS."""
        return self._fan_speed
    
    def update(self) -> None:
        """
        Update all member data by sending and receiving messages.
        Gets desiredTemperature, ambientTemperature, fanSpeed from board.
        """
        if not self.isConnected:
            return
        
        # Get desired temperature
        int_part = self._send_command(CMD_GET_DESIRED_INT)
        frac_part = self._send_command(CMD_GET_DESIRED_FRAC)
        if int_part >= 0 and frac_part >= 0:
            self._desired_temperature = float(int_part) + float(frac_part) / 10.0
        
        # Get ambient temperature
        int_part = self._send_command(CMD_GET_AMBIENT_INT)
        frac_part = self._send_command(CMD_GET_AMBIENT_FRAC)
        if int_part >= 0 and frac_part >= 0:
            self._ambient_temperature = float(int_part) + float(frac_part) / 10.0
        
        # Get fan speed
        speed = self._send_command(CMD_GET_FAN_SPEED)
        if speed >= 0:
            self._fan_speed = speed
    
    def setDesiredTemp(self, temp: float) -> bool:
        """
        Set the desired temperature by sending message to the board.
        
        Args:
            temp: Desired temperature (10.0 - 50.0)
            
        Returns:
            True if successful, False otherwise
        """
        if temp < 10.0 or temp > 50.0:
            return False
        
        if not self.isConnected:
            return False
        
        import time
        from decimal import Decimal
        
        # Use Decimal for precise arithmetic
        temp_dec = Decimal(str(round(temp, 1)))
        
        # Extract integer and fractional parts
        int_part = int(temp_dec)
        frac_part = int((temp_dec - int_part) * 10)
        

        
        # Flush any pending data
        self._serial.reset_input_buffer()
        self._serial.reset_output_buffer()
        
        # Send INTEGER part FIRST: 11xxxxxx (0xC0 | value)
        cmd_int = CMD_SET_DESIRED_INT_MASK | (int_part & 0x3F)

        self._serial.write(bytes([cmd_int]))
        self._serial.flush()
        
        # Wait for board to process
        time.sleep(0.2)
        
        # Send FRACTIONAL part: 10xxxxxx (0x80 | value)
        cmd_frac = CMD_SET_DESIRED_FRAC_MASK | (frac_part & 0x3F)

        self._serial.write(bytes([cmd_frac]))
        self._serial.flush()
        
        self._desired_temperature = float(temp_dec)
        return True
    
    def getAmbientTemp(self) -> float:
        """
        Get the ambient temperature.
        
        Returns:
            Ambient temperature in Celsius
        """
        self.update()
        return self._ambient_temperature
    
    def getFanSpeed(self) -> int:
        """
        Get the fan speed.
        
        Returns:
            Fan speed in RPS
        """
        self.update()
        return self._fan_speed
    
    def getDesiredTemp(self) -> float:
        """
        Get the desired temperature.
        
        Returns:
            Desired temperature in Celsius
        """
        self.update()
        return self._desired_temperature
