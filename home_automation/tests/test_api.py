"""
Test script for Home Automation API classes.
Tests communication with Board1 (Air Conditioner) and Board2 (Curtain Control).
"""
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from api.air_conditioner import AirConditionerSystemConnection
from api.curtain_control import CurtainControlSystemConnection
from api.connection import HomeAutomationSystemConnection


def test_air_conditioner(port: int = 11):
    """Test Air Conditioner System Connection."""
    print("\n" + "="*50)
    print("Testing Air Conditioner System Connection")
    print("="*50)
    
    ac = AirConditionerSystemConnection(com_port=port, baud_rate=9600)
    
    print(f"\n1. Initial values:")
    print(f"   - Desired Temp: {ac.desiredTemperature}°C")
    print(f"   - COM Port: COM{ac.comPort}")
    print(f"   - Baud Rate: {ac.baudRate}")
    
    print(f"\n2. Opening connection to COM{port}...")
    if ac.open():
        print("   ✓ Connection successful!")
        
        print("\n3. Reading data from board...")
        ac.update()
        print(f"   - Ambient Temp: {ac.ambientTemperature}°C")
        print(f"   - Desired Temp: {ac.desiredTemperature}°C")
        print(f"   - Fan Speed: {ac.fanSpeed} RPS")
        
        print("\n4. Setting desired temperature to 30.5°C...")
        if ac.setDesiredTemp(30.5):
            print("   ✓ Temperature set successfully!")
        else:
            print("   ✗ Failed to set temperature")
        
        print("\n5. Verifying new temperature...")
        ac.update()
        print(f"   - Desired Temp: {ac.desiredTemperature}°C")
        
        print("\n6. Closing connection...")
        ac.close()
        print("   ✓ Connection closed")
    else:
        print("   ✗ Connection failed!")
    
    return ac


def test_curtain_control(port: int = 10):
    """Test Curtain Control System Connection."""
    print("\n" + "="*50)
    print("Testing Curtain Control System Connection")
    print("="*50)
    
    curtain = CurtainControlSystemConnection(com_port=port, baud_rate=9600)
    
    print(f"\n1. Initial values:")
    print(f"   - Curtain Status: {curtain.curtainStatus}%")
    print(f"   - COM Port: COM{curtain.comPort}")
    print(f"   - Baud Rate: {curtain.baudRate}")
    
    print(f"\n2. Opening connection to COM{port}...")
    if curtain.open():
        print("   ✓ Connection successful!")
        
        print("\n3. Reading data from board...")
        curtain.update()
        print(f"   - Curtain Status: {curtain.curtainStatus}%")
        print(f"   - Light Intensity: {curtain.lightIntensity} Lux")
        
        print("\n4. Setting curtain status to 75.0%...")
        if curtain.setCurtainStatus(75.0):
            print("   ✓ Curtain status set successfully!")
        else:
            print("   ✗ Failed to set curtain status")
        
        print("\n5. Verifying new status...")
        curtain.update()
        print(f"   - Curtain Status: {curtain.curtainStatus}%")
        
        print("\n6. Closing connection...")
        curtain.close()
        print("   ✓ Connection closed")
    else:
        print("   ✗ Connection failed!")
    
    return curtain


def test_port_listing():
    """Test available port listing."""
    print("\n" + "="*50)
    print("Available COM Ports")
    print("="*50)
    
    ports = HomeAutomationSystemConnection.getAvailablePorts()
    
    if ports:
        for port, desc in ports:
            print(f"   - {port}: {desc}")
    else:
        print("   No COM ports found")


def main():
    """Run all tests."""
    print("\n" + "#"*60)
    print("   HOME AUTOMATION API TEST SUITE")
    print("#"*60)
    
    # List available ports
    test_port_listing()
    
    # Get user input for ports
    print("\n" + "-"*50)
    ac_port = input("Enter Air Conditioner COM port number (e.g., 11): ").strip()
    curtain_port = input("Enter Curtain Control COM port number (e.g., 10): ").strip()
    
    try:
        ac_port = int(ac_port) if ac_port else 11
        curtain_port = int(curtain_port) if curtain_port else 10
    except ValueError:
        print("Invalid port number, using defaults")
        ac_port, curtain_port = 11, 10
    
    # Run tests
    test_air_conditioner(ac_port)
    test_curtain_control(curtain_port)
    
    print("\n" + "#"*60)
    print("   ALL TESTS COMPLETED")
    print("#"*60 + "\n")


if __name__ == "__main__":
    main()
