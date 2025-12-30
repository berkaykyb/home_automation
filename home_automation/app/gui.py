"""
Home Automation System - Modern GUI Application
Tkinter-based graphical interface for controlling Air Conditioner and Curtain systems.
"""
import tkinter as tk
from tkinter import ttk, messagebox
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from api.air_conditioner import AirConditionerSystemConnection
from api.curtain_control import CurtainControlSystemConnection
from api.connection import HomeAutomationSystemConnection


class ModernStyle:
    """Modern color scheme and styling."""
    # Dark theme colors
    BG_DARK = "#1a1a2e"
    BG_CARD = "#16213e"
    BG_ACCENT = "#0f3460"
    TEXT_PRIMARY = "#ffffff"
    TEXT_SECONDARY = "#a0a0a0"
    ACCENT_BLUE = "#4361ee"
    ACCENT_GREEN = "#06d6a0"
    ACCENT_ORANGE = "#ff6b35"
    ACCENT_RED = "#ef476f"
    ACCENT_PURPLE = "#7b2cbf"
    
    # Gradients simulation colors
    TEMP_HOT = "#ff6b6b"
    TEMP_COLD = "#4ecdc4"
    
    # Fonts
    FONT_TITLE = ("Segoe UI", 24, "bold")
    FONT_SUBTITLE = ("Segoe UI", 14, "bold")
    FONT_LABEL = ("Segoe UI", 11)
    FONT_VALUE = ("Segoe UI", 18, "bold")
    FONT_SMALL = ("Segoe UI", 9)


class HomeAutomationGUI:
    """Main GUI Application class."""
    
    def __init__(self, root):
        self.root = root
        self.root.title("🏠 Home Automation System")
        self.root.geometry("900x700")
        self.root.configure(bg=ModernStyle.BG_DARK)
        self.root.resizable(True, True)
        
        # Connection objects
        self.ac_connection = AirConditionerSystemConnection()
        self.curtain_connection = CurtainControlSystemConnection()
        
        # Variables
        self.ac_port_var = tk.StringVar(value="COM1")
        self.curtain_port_var = tk.StringVar(value="COM2")
        self.baud_var = tk.StringVar(value="9600")
        
        # Data variables
        self.ac_ambient_var = tk.StringVar(value="--.-")
        self.ac_desired_var = tk.StringVar(value="25.0")
        self.ac_fan_var = tk.StringVar(value="--")
        self.ac_status_var = tk.StringVar(value="Disconnected")
        
        self.curtain_status_var = tk.StringVar(value="--.-")
        self.curtain_light_var = tk.StringVar(value="--.-")
        self.curtain_conn_status_var = tk.StringVar(value="Disconnected")
        
        self.setup_styles()
        self.create_widgets()
        self.refresh_ports()
        
        # Auto-refresh timer
        self.auto_refresh()
    
    def setup_styles(self):
        """Configure ttk styles for modern look."""
        style = ttk.Style()
        style.theme_use('clam')
        
        # Configure button style
        style.configure('Modern.TButton',
                       background=ModernStyle.ACCENT_BLUE,
                       foreground=ModernStyle.TEXT_PRIMARY,
                       font=ModernStyle.FONT_LABEL,
                       padding=(20, 10))
        style.map('Modern.TButton',
                 background=[('active', ModernStyle.ACCENT_PURPLE)])
        
        style.configure('Connect.TButton',
                       background=ModernStyle.ACCENT_GREEN,
                       foreground=ModernStyle.TEXT_PRIMARY,
                       font=ModernStyle.FONT_LABEL,
                       padding=(15, 8))
        
        style.configure('Disconnect.TButton',
                       background=ModernStyle.ACCENT_RED,
                       foreground=ModernStyle.TEXT_PRIMARY,
                       font=ModernStyle.FONT_LABEL,
                       padding=(15, 8))
        
        # Configure combobox
        style.configure('Modern.TCombobox',
                       fieldbackground=ModernStyle.BG_ACCENT,
                       background=ModernStyle.BG_ACCENT,
                       foreground=ModernStyle.TEXT_PRIMARY)
    
    def create_widgets(self):
        """Create all GUI widgets."""
        # Main container
        main_frame = tk.Frame(self.root, bg=ModernStyle.BG_DARK)
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        # Title
        title_frame = tk.Frame(main_frame, bg=ModernStyle.BG_DARK)
        title_frame.pack(fill=tk.X, pady=(0, 20))
        
        title_label = tk.Label(title_frame,
                               text="🏠 Home Automation Control Panel",
                               font=ModernStyle.FONT_TITLE,
                               fg=ModernStyle.TEXT_PRIMARY,
                               bg=ModernStyle.BG_DARK)
        title_label.pack()
        
        subtitle = tk.Label(title_frame,
                           text="PIC16F877A UART Communication Interface",
                           font=ModernStyle.FONT_SMALL,
                           fg=ModernStyle.TEXT_SECONDARY,
                           bg=ModernStyle.BG_DARK)
        subtitle.pack()
        
        # Content area - two columns
        content_frame = tk.Frame(main_frame, bg=ModernStyle.BG_DARK)
        content_frame.pack(fill=tk.BOTH, expand=True)
        
        # Left column - Air Conditioner
        self.create_ac_panel(content_frame)
        
        # Right column - Curtain Control
        self.create_curtain_panel(content_frame)
        
        # Bottom - Port refresh button
        bottom_frame = tk.Frame(main_frame, bg=ModernStyle.BG_DARK)
        bottom_frame.pack(fill=tk.X, pady=(20, 0))
        
        refresh_btn = tk.Button(bottom_frame,
                                text="🔄 Refresh Ports",
                                font=ModernStyle.FONT_LABEL,
                                bg=ModernStyle.BG_ACCENT,
                                fg=ModernStyle.TEXT_PRIMARY,
                                activebackground=ModernStyle.ACCENT_PURPLE,
                                activeforeground=ModernStyle.TEXT_PRIMARY,
                                relief=tk.FLAT,
                                cursor="hand2",
                                command=self.refresh_ports)
        refresh_btn.pack(side=tk.LEFT)
        
        # Version info
        version_label = tk.Label(bottom_frame,
                                text="ESOGU Computer Engineering & Electrical - Electronics Engineering",
                                font=ModernStyle.FONT_SMALL,
                                fg=ModernStyle.TEXT_SECONDARY,
                                bg=ModernStyle.BG_DARK)
        version_label.pack(side=tk.RIGHT)
    
    def create_ac_panel(self, parent):
        """Create Air Conditioner control panel."""
        # Card frame
        card = tk.Frame(parent, bg=ModernStyle.BG_CARD, relief=tk.FLAT)
        card.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 10))
        
        inner = tk.Frame(card, bg=ModernStyle.BG_CARD)
        inner.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        # Header
        header = tk.Frame(inner, bg=ModernStyle.BG_CARD)
        header.pack(fill=tk.X, pady=(0, 15))
        
        tk.Label(header,
                text="❄️ Air Conditioner",
                font=ModernStyle.FONT_SUBTITLE,
                fg=ModernStyle.ACCENT_BLUE,
                bg=ModernStyle.BG_CARD).pack(side=tk.LEFT)
        
        self.ac_status_label = tk.Label(header,
                                        textvariable=self.ac_status_var,
                                        font=ModernStyle.FONT_SMALL,
                                        fg=ModernStyle.ACCENT_RED,
                                        bg=ModernStyle.BG_CARD)
        self.ac_status_label.pack(side=tk.RIGHT)
        
        # Connection settings
        conn_frame = tk.Frame(inner, bg=ModernStyle.BG_ACCENT)
        conn_frame.pack(fill=tk.X, pady=(0, 15))
        conn_inner = tk.Frame(conn_frame, bg=ModernStyle.BG_ACCENT)
        conn_inner.pack(fill=tk.X, padx=10, pady=10)
        
        tk.Label(conn_inner, text="Port:", font=ModernStyle.FONT_SMALL,
                fg=ModernStyle.TEXT_SECONDARY, bg=ModernStyle.BG_ACCENT).grid(row=0, column=0, sticky="w")
        
        self.ac_port_combo = ttk.Combobox(conn_inner, textvariable=self.ac_port_var,
                                          width=10, state="readonly")
        self.ac_port_combo.grid(row=0, column=1, padx=5)
        
        tk.Label(conn_inner, text="Baud:", font=ModernStyle.FONT_SMALL,
                fg=ModernStyle.TEXT_SECONDARY, bg=ModernStyle.BG_ACCENT).grid(row=0, column=2, padx=(10, 0))
        
        baud_combo = ttk.Combobox(conn_inner, textvariable=self.baud_var,
                                  values=["9600", "19200", "38400", "57600", "115200"],
                                  width=8, state="readonly")
        baud_combo.grid(row=0, column=3, padx=5)
        
        self.ac_connect_btn = tk.Button(conn_inner, text="Connect",
                                        font=ModernStyle.FONT_SMALL,
                                        bg=ModernStyle.ACCENT_GREEN,
                                        fg=ModernStyle.TEXT_PRIMARY,
                                        relief=tk.FLAT,
                                        cursor="hand2",
                                        command=self.toggle_ac_connection)
        self.ac_connect_btn.grid(row=0, column=4, padx=(10, 0))
        
        # Data display
        data_frame = tk.Frame(inner, bg=ModernStyle.BG_CARD)
        data_frame.pack(fill=tk.X, pady=10)
        
        # Ambient Temperature
        self.create_data_row(data_frame, "🌡️ Ambient Temperature:",
                            self.ac_ambient_var, "°C", 0)
        
        # Desired Temperature
        self.create_data_row(data_frame, "🎯 Desired Temperature:",
                            self.ac_desired_var, "°C", 1)
        
        # Fan Speed
        self.create_data_row(data_frame, "🌀 Fan Speed:",
                            self.ac_fan_var, "RPS", 2)
        
        # Temperature control
        ctrl_frame = tk.Frame(inner, bg=ModernStyle.BG_ACCENT)
        ctrl_frame.pack(fill=tk.X, pady=(15, 0))
        ctrl_inner = tk.Frame(ctrl_frame, bg=ModernStyle.BG_ACCENT)
        ctrl_inner.pack(fill=tk.X, padx=10, pady=10)
        
        tk.Label(ctrl_inner, text="Set Temperature (10-50°C):",
                font=ModernStyle.FONT_SMALL,
                fg=ModernStyle.TEXT_SECONDARY,
                bg=ModernStyle.BG_ACCENT).pack(anchor="w")
        
        temp_input_frame = tk.Frame(ctrl_inner, bg=ModernStyle.BG_ACCENT)
        temp_input_frame.pack(fill=tk.X, pady=(5, 0))
        
        self.temp_entry = tk.Entry(temp_input_frame,
                                   font=ModernStyle.FONT_VALUE,
                                   bg=ModernStyle.BG_DARK,
                                   fg=ModernStyle.TEXT_PRIMARY,
                                   insertbackground=ModernStyle.TEXT_PRIMARY,
                                   width=8,
                                   relief=tk.FLAT)
        self.temp_entry.pack(side=tk.LEFT, padx=(0, 10))
        self.temp_entry.insert(0, "25.0")
        
        set_temp_btn = tk.Button(temp_input_frame, text="Set Temperature",
                                 font=ModernStyle.FONT_LABEL,
                                 bg=ModernStyle.ACCENT_ORANGE,
                                 fg=ModernStyle.TEXT_PRIMARY,
                                 relief=tk.FLAT,
                                 cursor="hand2",
                                 command=self.set_temperature)
        set_temp_btn.pack(side=tk.LEFT)
    
    def create_curtain_panel(self, parent):
        """Create Curtain Control panel."""
        # Card frame
        card = tk.Frame(parent, bg=ModernStyle.BG_CARD, relief=tk.FLAT)
        card.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True, padx=(10, 0))
        
        inner = tk.Frame(card, bg=ModernStyle.BG_CARD)
        inner.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        # Header
        header = tk.Frame(inner, bg=ModernStyle.BG_CARD)
        header.pack(fill=tk.X, pady=(0, 15))
        
        tk.Label(header,
                text="🪟 Curtain Control",
                font=ModernStyle.FONT_SUBTITLE,
                fg=ModernStyle.ACCENT_PURPLE,
                bg=ModernStyle.BG_CARD).pack(side=tk.LEFT)
        
        self.curtain_status_label = tk.Label(header,
                                             textvariable=self.curtain_conn_status_var,
                                             font=ModernStyle.FONT_SMALL,
                                             fg=ModernStyle.ACCENT_RED,
                                             bg=ModernStyle.BG_CARD)
        self.curtain_status_label.pack(side=tk.RIGHT)
        
        # Connection settings
        conn_frame = tk.Frame(inner, bg=ModernStyle.BG_ACCENT)
        conn_frame.pack(fill=tk.X, pady=(0, 15))
        conn_inner = tk.Frame(conn_frame, bg=ModernStyle.BG_ACCENT)
        conn_inner.pack(fill=tk.X, padx=10, pady=10)
        
        tk.Label(conn_inner, text="Port:", font=ModernStyle.FONT_SMALL,
                fg=ModernStyle.TEXT_SECONDARY, bg=ModernStyle.BG_ACCENT).grid(row=0, column=0, sticky="w")
        
        self.curtain_port_combo = ttk.Combobox(conn_inner, textvariable=self.curtain_port_var,
                                               width=10, state="readonly")
        self.curtain_port_combo.grid(row=0, column=1, padx=5)
        
        tk.Label(conn_inner, text="Baud:", font=ModernStyle.FONT_SMALL,
                fg=ModernStyle.TEXT_SECONDARY, bg=ModernStyle.BG_ACCENT).grid(row=0, column=2, padx=(10, 0))
        
        curtain_baud_combo = ttk.Combobox(conn_inner, textvariable=self.baud_var,
                                          values=["9600", "19200", "38400", "57600", "115200"],
                                          width=8, state="readonly")
        curtain_baud_combo.grid(row=0, column=3, padx=5)
        
        self.curtain_connect_btn = tk.Button(conn_inner, text="Connect",
                                             font=ModernStyle.FONT_SMALL,
                                             bg=ModernStyle.ACCENT_GREEN,
                                             fg=ModernStyle.TEXT_PRIMARY,
                                             relief=tk.FLAT,
                                             cursor="hand2",
                                             command=self.toggle_curtain_connection)
        self.curtain_connect_btn.grid(row=0, column=4, padx=(10, 0))
        
        # Data display
        data_frame = tk.Frame(inner, bg=ModernStyle.BG_CARD)
        data_frame.pack(fill=tk.X, pady=10)
        
        # Curtain Status
        self.create_data_row(data_frame, "📊 Curtain Status:",
                            self.curtain_status_var, "%", 0)
        
        # Light Intensity
        self.create_data_row(data_frame, "💡 Light Intensity:",
                            self.curtain_light_var, "Lux", 1)
        
        # Curtain control
        ctrl_frame = tk.Frame(inner, bg=ModernStyle.BG_ACCENT)
        ctrl_frame.pack(fill=tk.X, pady=(15, 0))
        ctrl_inner = tk.Frame(ctrl_frame, bg=ModernStyle.BG_ACCENT)
        ctrl_inner.pack(fill=tk.X, padx=10, pady=10)
        
        tk.Label(ctrl_inner, text="Set Curtain Openness (0-63%):",
                font=ModernStyle.FONT_SMALL,
                fg=ModernStyle.TEXT_SECONDARY,
                bg=ModernStyle.BG_ACCENT).pack(anchor="w")
        
        curtain_input_frame = tk.Frame(ctrl_inner, bg=ModernStyle.BG_ACCENT)
        curtain_input_frame.pack(fill=tk.X, pady=(5, 0))
        
        self.curtain_entry = tk.Entry(curtain_input_frame,
                                      font=ModernStyle.FONT_VALUE,
                                      bg=ModernStyle.BG_DARK,
                                      fg=ModernStyle.TEXT_PRIMARY,
                                      insertbackground=ModernStyle.TEXT_PRIMARY,
                                      width=8,
                                      relief=tk.FLAT)
        self.curtain_entry.pack(side=tk.LEFT, padx=(0, 10))
        self.curtain_entry.insert(0, "50.0")
        
        set_curtain_btn = tk.Button(curtain_input_frame, text="Set Curtain",
                                    font=ModernStyle.FONT_LABEL,
                                    bg=ModernStyle.ACCENT_PURPLE,
                                    fg=ModernStyle.TEXT_PRIMARY,
                                    relief=tk.FLAT,
                                    cursor="hand2",
                                    command=self.set_curtain)
        set_curtain_btn.pack(side=tk.LEFT)
    
    def create_data_row(self, parent, label_text, var, unit, row):
        """Create a data display row."""
        frame = tk.Frame(parent, bg=ModernStyle.BG_CARD)
        frame.pack(fill=tk.X, pady=5)
        
        tk.Label(frame, text=label_text,
                font=ModernStyle.FONT_LABEL,
                fg=ModernStyle.TEXT_SECONDARY,
                bg=ModernStyle.BG_CARD).pack(side=tk.LEFT)
        
        value_frame = tk.Frame(frame, bg=ModernStyle.BG_CARD)
        value_frame.pack(side=tk.RIGHT)
        
        tk.Label(value_frame, textvariable=var,
                font=ModernStyle.FONT_VALUE,
                fg=ModernStyle.TEXT_PRIMARY,
                bg=ModernStyle.BG_CARD).pack(side=tk.LEFT)
        
        if unit:
            tk.Label(value_frame, text=f" {unit}",
                    font=ModernStyle.FONT_LABEL,
                    fg=ModernStyle.TEXT_SECONDARY,
                    bg=ModernStyle.BG_CARD).pack(side=tk.LEFT)
    
    def refresh_ports(self):
        """Refresh available COM ports."""
        ports = HomeAutomationSystemConnection.getAvailablePorts()
        port_list = [p[0] for p in ports] if ports else ["COM1", "COM2", "COM3", "COM4"]
        
        self.ac_port_combo['values'] = port_list
        self.curtain_port_combo['values'] = port_list
        
        if port_list:
            if self.ac_port_var.get() not in port_list:
                self.ac_port_var.set(port_list[0])
            if self.curtain_port_var.get() not in port_list:
                self.curtain_port_var.set(port_list[-1] if len(port_list) > 1 else port_list[0])
    
    def toggle_ac_connection(self):
        """Toggle Air Conditioner connection."""
        if self.ac_connection.isConnected:
            self.ac_connection.close()
            self.ac_connect_btn.config(text="Connect", bg=ModernStyle.ACCENT_GREEN)
            self.ac_status_var.set("Disconnected")
            self.ac_status_label.config(fg=ModernStyle.ACCENT_RED)
        else:
            port = self.ac_port_var.get()
            port_num = int(port.replace("COM", ""))
            baud = int(self.baud_var.get())
            
            self.ac_connection.setComPort(port_num)
            self.ac_connection.setBaudRate(baud)
            
            if self.ac_connection.open():
                self.ac_connect_btn.config(text="Disconnect", bg=ModernStyle.ACCENT_RED)
                self.ac_status_var.set(f"Connected ({port})")
                self.ac_status_label.config(fg=ModernStyle.ACCENT_GREEN)
                self.update_ac_data()
            else:
                messagebox.showerror("Connection Error",
                                    f"Failed to connect to {port}")
    
    def toggle_curtain_connection(self):
        """Toggle Curtain Control connection."""
        if self.curtain_connection.isConnected:
            self.curtain_connection.close()
            self.curtain_connect_btn.config(text="Connect", bg=ModernStyle.ACCENT_GREEN)
            self.curtain_conn_status_var.set("Disconnected")
            self.curtain_status_label.config(fg=ModernStyle.ACCENT_RED)
        else:
            port = self.curtain_port_var.get()
            port_num = int(port.replace("COM", ""))
            baud = int(self.baud_var.get())
            
            self.curtain_connection.setComPort(port_num)
            self.curtain_connection.setBaudRate(baud)
            
            if self.curtain_connection.open():
                self.curtain_connect_btn.config(text="Disconnect", bg=ModernStyle.ACCENT_RED)
                self.curtain_conn_status_var.set(f"Connected ({port})")
                self.curtain_status_label.config(fg=ModernStyle.ACCENT_GREEN)
                self.update_curtain_data()
            else:
                messagebox.showerror("Connection Error",
                                    f"Failed to connect to {port}")
    
    def update_ac_data(self):
        """Update Air Conditioner data from board."""
        if self.ac_connection.isConnected:
            try:
                self.ac_connection.update()
                self.ac_ambient_var.set(f"{self.ac_connection.ambientTemperature:.1f}")
                self.ac_desired_var.set(f"{self.ac_connection.desiredTemperature:.1f}")
                self.ac_fan_var.set(str(self.ac_connection.fanSpeed))
            except Exception as e:
                print(f"Error updating AC data: {e}")
    
    def update_curtain_data(self):
        """Update Curtain Control data from board."""
        if self.curtain_connection.isConnected:
            try:
                self.curtain_connection.update()
                self.curtain_status_var.set(f"{self.curtain_connection.curtainStatus:.1f}")
                self.curtain_light_var.set(f"{self.curtain_connection.lightIntensity:.1f}")
            except Exception as e:
                print(f"Error updating curtain data: {e}")
    
    def set_temperature(self):
        """Set desired temperature."""
        try:
            temp = float(self.temp_entry.get())
            if temp < 10.0 or temp > 50.0:
                messagebox.showwarning("Invalid Value",
                                      "Temperature must be between 10°C and 50°C")
                return
            
            if self.ac_connection.isConnected:
                if self.ac_connection.setDesiredTemp(temp):
                    self.ac_desired_var.set(f"{temp:.1f}")
                    messagebox.showinfo("Success",
                                       f"Temperature set to {temp:.1f}°C")
                else:
                    messagebox.showerror("Error", "Failed to set temperature")
            else:
                messagebox.showwarning("Not Connected",
                                      "Please connect to Air Conditioner first")
        except ValueError:
            messagebox.showerror("Invalid Input",
                                "Please enter a valid number")
    
    def set_curtain(self):
        """Set curtain openness."""
        try:
            status = float(self.curtain_entry.get())
            if status < 0.0 or status > 100.0:
                messagebox.showwarning("Invalid Value",
                                      "Curtain status must be between 0% and 100%")
                return
            
            if self.curtain_connection.isConnected:
                if self.curtain_connection.setCurtainStatus(status):
                    self.curtain_status_var.set(f"{status:.1f}")
                    messagebox.showinfo("Success",
                                       f"Curtain set to {status:.1f}%")
                else:
                    messagebox.showerror("Error", "Failed to set curtain status")
            else:
                messagebox.showwarning("Not Connected",
                                      "Please connect to Curtain Control first")
        except ValueError:
            messagebox.showerror("Invalid Input",
                                "Please enter a valid number")
    
    def auto_refresh(self):
        """Auto-refresh data every 500ms for responsive updates."""
        self.update_ac_data()
        self.update_curtain_data()
        self.root.after(500, self.auto_refresh)
    
    def on_closing(self):
        """Handle window close."""
        self.ac_connection.close()
        self.curtain_connection.close()
        self.root.destroy()


def main():
    """Main entry point."""
    root = tk.Tk()
    app = HomeAutomationGUI(root)
    root.protocol("WM_DELETE_WINDOW", app.on_closing)
    root.mainloop()


if __name__ == "__main__":
    main()
