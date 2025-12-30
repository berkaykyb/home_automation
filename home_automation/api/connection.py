"""
HomeAutomationSystemConnection - Base class for serial communication with PIC16F877A boards.
"""
import serial
import serial.tools.list_ports
from abc import ABC, abstractmethod


class HomeAutomationSystemConnection(ABC):
    """Base class for home automation system connections."""
    
    def __init__(self, com_port: int = 1, baud_rate: int = 9600):
        """
        Initialize connection settings.
        
        Args:
            com_port: COM port number (e.g., 1 for COM1)
            baud_rate: Baud rate for serial communication (default: 9600)
        """
        self._com_port = com_port
        self._baud_rate = baud_rate
        self._serial: serial.Serial = None
        self._connected = False
    
    @property
    def comPort(self) -> int:
        """Get the COM port number."""
        return self._com_port
    
    @property
    def baudRate(self) -> int:
        """Get the baud rate."""
        return self._baud_rate
    
    @property
    def isConnected(self) -> bool:
        """Check if connected."""
        return self._connected and self._serial is not None and self._serial.is_open
    
    def open(self) -> bool:
        """
        Open connection to the board via UART port.
        
        Returns:
            True if connection successful, False otherwise.
        """
        try:
            port_name = f"COM{self._com_port}"
            self._serial = serial.Serial(
                port=port_name,
                baudrate=self._baud_rate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=1.0
            )
            self._connected = True
            return True
        except serial.SerialException as e:
            print(f"Error opening port: {e}")
            self._connected = False
            return False
    
    def close(self) -> bool:
        """
        Close the connection to the board.
        
        Returns:
            True if closed successfully, False otherwise.
        """
        try:
            if self._serial and self._serial.is_open:
                self._serial.close()
            self._connected = False
            return True
        except Exception as e:
            print(f"Error closing port: {e}")
            return False
    
    def setComPort(self, port: int) -> None:
        """
        Set the communication port number.
        
        Args:
            port: COM port number
        """
        if self.isConnected:
            self.close()
        self._com_port = port
    
    def setBaudRate(self, rate: int) -> None:
        """
        Set the communication baud rate.
        
        Args:
            rate: Baud rate
        """
        if self.isConnected:
            self.close()
        self._baud_rate = rate
    
    def _send_command(self, cmd: int) -> int:
        """
        Send a command byte and receive response.
        
        Args:
            cmd: Command byte to send
            
        Returns:
            Response byte or -1 on error
        """
        if not self.isConnected:
            return -1
        try:
            self._serial.write(bytes([cmd]))
            response = self._serial.read(1)
            if response:
                return response[0]
            return -1
        except Exception as e:
            print(f"Communication error: {e}")
            return -1
    
    def _send_byte(self, value: int) -> bool:
        """
        Send a single byte without expecting response.
        
        Args:
            value: Byte value to send
            
        Returns:
            True if sent successfully
        """
        if not self.isConnected:
            return False
        try:
            self._serial.write(bytes([value & 0xFF]))
            return True
        except Exception as e:
            print(f"Communication error: {e}")
            return False
    
    @abstractmethod
    def update(self) -> None:
        """Update all member data by communicating with the board."""
        pass
    
    @staticmethod
    def getAvailablePorts() -> list:
        """
        Get list of available COM ports.
        
        Returns:
            List of tuples (port_name, description)
        """
        ports = []
        for port in serial.tools.list_ports.comports():
            ports.append((port.device, port.description))
        return ports
