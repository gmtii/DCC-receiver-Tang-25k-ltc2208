#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UI para enviar frecuencias por puerto serie + controlar pines por comandos.

Frecuencia:
- Tú introduces la frecuencia en kHz (puede ser decimal, ej: 7235, 0.5, 0.001)
- Se envía en Hz, multiplicando por 1000 y con 8 dígitos con ceros delante:
    7235    ->  07235000
    0.5     ->  00000500
    0.001   ->  00000001

Offset:
- Se introduce en kHz y se suma a la frecuencia antes de enviar.

Atajos:
  '+'  : subir frecuencia (kHz, con el paso indicado)
  '-'  : bajar frecuencia (kHz, con el paso indicado)

Comandos FPGA (UART):
  P0/P1 : PGA
  R0/R1 : RAND
  S0/S1 : SHDN
  D0/D1 : DITH
  A0/A1 : PREAMP
  Q     : devuelve estado "P#R#S#D#A#"
  f     : devuelve frecuencia (como ya tenías)
  Gnn   : atenuación PE4302 (0..63) en decimal (0.5 dB por paso)
"""

import tkinter as tk
from tkinter import ttk, messagebox
import serial
import serial.tools.list_ports


def list_serial_ports():
    ports = []
    for p in serial.tools.list_ports.comports():
        ports.append((p.device, p.description))
    return ports


def format_khz_to_8digits_hz(khz: float) -> str:
    # kHz (float) -> Hz (int) -> "00000000".."99999999"
    hz = int(round(khz * 1000.0))
    if hz < 0:
        hz = 0
    if hz > 99_999_999:
        hz = 99_999_999
    return f"{hz:08d}"


class SerialFreqUI:
    def __init__(self, root: tk.Tk):
        self.root = root
        root.title("Serial Frequency Sender (kHz -> 8d Hz) + Pins + PE4302")
        root.geometry("860x440")

        self.ser = None

        self.port_var = tk.StringVar()
        self.baud_var = tk.StringVar(value="115200")
        self.khz_var = tk.StringVar(value="7235")
        self.offset_var = tk.StringVar(value="0")
        self.step_var = tk.StringVar(value="1")
        self.status_var = tk.StringVar(value="Desconectado")

        # pines: checkbox 0/1
        self.pga_var = tk.IntVar(value=0)
        self.rand_var = tk.IntVar(value=0)
        self.shdn_var = tk.IntVar(value=0)
        self.dith_var = tk.IntVar(value=0)
        self.preamp_var = tk.IntVar(value=0)

        # PE4302
        self.att_var = tk.IntVar(value=0)          # 0..63
        self.att_auto_send = tk.IntVar(value=1)    # auto enviar al mover (1=si)

        frm = ttk.Frame(root, padding=12)
        frm.pack(fill="both", expand=True)

        ttk.Label(frm, text="Puerto:").grid(row=0, column=0, sticky="w")
        self.port_combo = ttk.Combobox(frm, textvariable=self.port_var, width=22, state="readonly")
        self.port_combo.grid(row=0, column=1, sticky="w", padx=(6, 12))

        ttk.Button(frm, text="Refrescar", command=self.refresh_ports).grid(row=0, column=2, sticky="w")
        self.conn_btn = ttk.Button(frm, text="Conectar", command=self.toggle_connection)
        self.conn_btn.grid(row=0, column=3, sticky="w", padx=(12, 0))

        ttk.Label(frm, text="Baudios:").grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(frm, textvariable=self.baud_var, width=12).grid(row=1, column=1, sticky="w", padx=(6, 0), pady=(8, 0))

        # ---- Frecuencia ----
        ttk.Label(frm, text="Frecuencia (kHz):").grid(row=2, column=0, sticky="w", pady=(12, 0))
        self.khz_entry = ttk.Entry(frm, textvariable=self.khz_var, width=16)
        self.khz_entry.grid(row=2, column=1, sticky="w", padx=(6, 0), pady=(12, 0))

        ttk.Button(frm, text="Enviar", command=self.send_current).grid(row=2, column=2, sticky="w", pady=(12, 0))
        ttk.Button(frm, text="Enviar + pedir 'f'", command=self.send_and_query_f).grid(row=2, column=3, sticky="w", pady=(12, 0))

        # ---- Offset ----
        ttk.Label(frm, text="Offset (kHz):").grid(row=3, column=0, sticky="w", pady=(12, 0))
        ttk.Entry(frm, textvariable=self.offset_var, width=12).grid(row=3, column=1, sticky="w", padx=(6, 0), pady=(12, 0))

        ttk.Label(frm, text="Paso (kHz):").grid(row=4, column=0, sticky="w", pady=(12, 0))
        ttk.Entry(frm, textvariable=self.step_var, width=12).grid(row=4, column=1, sticky="w", padx=(6, 0), pady=(12, 0))

        btns = ttk.Frame(frm)
        btns.grid(row=4, column=2, columnspan=2, sticky="w", pady=(12, 0))
        ttk.Button(btns, text="−", width=5, command=lambda: self.bump(-1)).pack(side="left")
        ttk.Button(btns, text="+", width=5, command=lambda: self.bump(+1)).pack(side="left", padx=(10, 0))

        self.preview_lbl = ttk.Label(frm, text="Se enviará: —", font=("TkDefaultFont", 10, "bold"))
        self.preview_lbl.grid(row=5, column=0, columnspan=4, sticky="w", pady=(18, 0))

        # ---- Pines + PE4302 ----
        pins_box = ttk.LabelFrame(frm, text="Pines (P/R/S/D/A) + PE4302 (G) + Q", padding=10)
        pins_box.grid(row=0, column=4, rowspan=8, sticky="nsew", padx=(18, 0))

        # Checkboxes (envían al cambiar)
        self._add_pin_check(pins_box, 0, "PGA (P)", self.pga_var, lambda: self.send_pin("P", self.pga_var.get()))
        self._add_pin_check(pins_box, 1, "RAND (R)", self.rand_var, lambda: self.send_pin("R", self.rand_var.get()))
        self._add_pin_check(pins_box, 2, "SHDN (S)", self.shdn_var, lambda: self.send_pin("S", self.shdn_var.get()))
        self._add_pin_check(pins_box, 3, "DITH (D)", self.dith_var, lambda: self.send_pin("D", self.dith_var.get()))
        self._add_pin_check(pins_box, 4, "PREAMP (A)", self.preamp_var, lambda: self.send_pin("A", self.preamp_var.get()))

        ttk.Separator(pins_box, orient="horizontal").grid(row=5, column=0, columnspan=3, sticky="ew", pady=10)

        # --- PE4302 attenuation controls ---
        ttk.Label(pins_box, text="Atenuación PE4302 (G):").grid(row=6, column=0, columnspan=3, sticky="w")

        self.att_lbl = ttk.Label(pins_box, text="Valor: 0  (0.0 dB)")
        self.att_lbl.grid(row=7, column=0, columnspan=3, sticky="w", pady=(4, 4))

        # Scale 0..63
        self.att_scale = ttk.Scale(
            pins_box,
            from_=0, to=31,
            orient="horizontal",
            command=self._on_att_scale
        )
        self.att_scale.grid(row=8, column=0, columnspan=3, sticky="ew")

        # snap initial
        self.att_scale.set(self.att_var.get())

        att_btns = ttk.Frame(pins_box)
        att_btns.grid(row=9, column=0, columnspan=3, sticky="w", pady=(6, 0))
        ttk.Button(att_btns, text="Enviar G", command=self.send_att).pack(side="left")
        ttk.Checkbutton(att_btns, text="Auto-enviar al mover", variable=self.att_auto_send).pack(side="left", padx=(10, 0))

        ttk.Separator(pins_box, orient="horizontal").grid(row=10, column=0, columnspan=3, sticky="ew", pady=10)

        ttk.Button(pins_box, text="Leer estado (Q)", command=self.query_q).grid(row=11, column=0, sticky="w")
        ttk.Button(pins_box, text="Leer freq (f)", command=self.query_f).grid(row=11, column=1, sticky="w", padx=(8, 0))

        self.q_resp_var = tk.StringVar(value="Estado: —")
        ttk.Label(pins_box, textvariable=self.q_resp_var).grid(row=12, column=0, columnspan=3, sticky="w", pady=(8, 0))

        ttk.Label(frm, textvariable=self.status_var).grid(row=7, column=0, columnspan=4, sticky="w", pady=(10, 0))

        frm.columnconfigure(1, weight=1)
        pins_box.columnconfigure(2, weight=1)

        root.bind("<KeyPress-plus>", lambda e: self.bump(+1))
        root.bind("<KeyPress-minus>", lambda e: self.bump(-1))
        root.bind("<KeyPress-KP_Add>", lambda e: self.bump(+1))
        root.bind("<KeyPress-KP_Subtract>", lambda e: self.bump(-1))

        # actualizar preview cuando cambie freq u offset
        self.khz_var.trace_add("write", lambda *_: self.update_preview())
        self.offset_var.trace_add("write", lambda *_: self.update_preview())

        self.refresh_ports()
        self.update_preview()
        self._update_att_label()

    def _add_pin_check(self, parent, row, label, var, on_toggle):
        ttk.Checkbutton(parent, text=label, variable=var, command=on_toggle).grid(row=row, column=0, columnspan=3, sticky="w")

    # --- PE4302 helpers ---
    def _update_att_label(self):
        v = int(self.att_var.get())
        db = v * 0.5
        self.att_lbl.config(text=f"Valor: {v}  ({db:.1f} dB)")

    def _on_att_scale(self, value_str):
        # ttk.Scale gives float string; snap to int
        try:
            v = int(round(float(value_str)))
        except Exception:
            return
        if v < 0: v = 0
        if v > 31: v = 31
        if v != self.att_var.get():
            self.att_var.set(v)
            self._update_att_label()
            if self.att_auto_send.get() == 1:
                # enviar sin spamear demasiado: solo cuando cambia el entero
                self._send_att_value(v)

    def _send_att_value(self, v: int):
        try:
            v = int(v)
            if v < 0: v = 0
            if v > 31: v = 31
            # comando: "G" + decimal (sin padding) + \n
            self.write_line(f"G{v}")
            self.status_var.set(f"Enviado: G{v} ({v*0.5:.1f} dB)")
        except Exception as e:
            messagebox.showerror("Error", str(e))

    def send_att(self):
        self._send_att_value(self.att_var.get())

    # --- Serial stuff ---
    def refresh_ports(self):
        ports = list_serial_ports()
        values = [p[0] for p in ports]
        self.port_combo["values"] = values
        if values and (self.port_var.get() not in values):
            self.port_var.set(values[0])
        if not values:
            self.port_var.set("/dev/ttyUSB1")
        self.status_var.set("Puertos encontrados: " + (", ".join(values) if values else "ninguno"))

    def toggle_connection(self):
        if self.ser and self.ser.is_open:
            try:
                self.ser.close()
            except Exception:
                pass
            self.ser = None
            self.conn_btn.config(text="Conectar")
            self.status_var.set("Desconectado")
            return

        port = self.port_var.get().strip()
        if not port:
            messagebox.showerror("Error", "No hay puerto seleccionado.")
            return

        try:
            baud = int(self.baud_var.get().strip())
        except ValueError:
            messagebox.showerror("Error", "Baudios inválidos.")
            return

        try:
            self.ser = serial.Serial(port, baud, timeout=1)
            try:
                self.ser.reset_input_buffer()
                self.ser.reset_output_buffer()
            except Exception:
                pass

            self.conn_btn.config(text="Desconectar")
            self.status_var.set(f"Conectado a {port} @ {baud}")
        except Exception as e:
            self.ser = None
            messagebox.showerror("Error", f"No pude abrir el puerto:\n{e}")

    def write_line(self, payload: str):
        if not (self.ser and self.ser.is_open):
            raise RuntimeError("No estás conectado al puerto serie.")
        self.ser.write((payload + "\n").encode("ascii"))

    def write_raw(self, payload: str):
        if not (self.ser and self.ser.is_open):
            raise RuntimeError("No estás conectado al puerto serie.")
        self.ser.write(payload.encode("ascii"))

    # ------------------ Frecuencia ------------------
    def get_khz(self) -> float:
        s = self.khz_var.get().strip().replace(",", ".")
        if s == "":
            return 0.0
        try:
            return float(s)
        except ValueError:
            raise ValueError("La frecuencia debe ser un número en kHz (puede tener decimales). Ej: 0.5, 7235, 0.001")

    def get_offset(self) -> float:
        s = self.offset_var.get().strip().replace(",", ".")
        if s == "":
            return 0.0
        try:
            return float(s)
        except ValueError:
            raise ValueError("El offset debe ser un número en kHz (puede tener decimales). Ej: 0.455, -0.1, 0")

    def get_total_khz(self) -> float:
        return self.get_khz() + self.get_offset()

    def get_step(self) -> float:
        s = self.step_var.get().strip().replace(",", ".")
        if s == "":
            return 1.0
        try:
            step = float(s)
        except ValueError:
            raise ValueError("El paso debe ser un número en kHz (puede tener decimales). Ej: 0.1")
        return step if step > 0 else 1.0

    def update_preview(self):
        try:
            base = self.get_khz()
            off = self.get_offset()
            total = base + off
            out = format_khz_to_8digits_hz(total)
            self.preview_lbl.config(
                text=f"Se enviará: {out} (Hz, 8 dígitos)   |   base={base:g} kHz + offset={off:g} kHz = {total:g} kHz"
            )
        except Exception:
            self.preview_lbl.config(text="Se enviará: — (entrada inválida)")

    def send_current(self):
        try:
            total_khz = self.get_total_khz() - 12
            out = format_khz_to_8digits_hz(total_khz)
            self.write_line(out)
            self.status_var.set(f"Enviado: {out} (base+offset)")
        except Exception as e:
            messagebox.showerror("Error", str(e))

    def send_and_query_f(self):
        """Envía frecuencia (base+offset) y luego manda 'f' y muestra lo que devuelve."""
        try:
            total_khz = self.get_total_khz() - 12
            out = format_khz_to_8digits_hz(total_khz)
            self.write_line(out)

            self.write_raw("f")
            resp = self.read_line_ascii()
            if resp:
                self.status_var.set(f"Enviado: {out} | Respuesta 'f': {resp}")
            else:
                self.status_var.set(f"Enviado: {out} | Sin respuesta a 'f'")
        except Exception as e:
            messagebox.showerror("Error", str(e))

    def bump(self, direction: int):
        """Sube/baja en kHz con paso decimal y envía automáticamente (solo base, no offset)."""
        try:
            khz = self.get_khz()
            step = self.get_step()
            khz = max(0.0, khz + direction * step)
            khz = round(khz, 6)
            self.khz_var.set(str(khz))
            self.send_current()
        except Exception as e:
            messagebox.showerror("Error", str(e))

    # ------------------ Pines / comandos ------------------
    def read_line_ascii(self) -> str:
        """Lee una línea (hasta \\n o timeout). Devuelve strip()."""
        if not (self.ser and self.ser.is_open):
            raise RuntimeError("No estás conectado al puerto serie.")
        try:
            raw = self.ser.readline()
            return raw.decode("ascii", errors="replace").strip()
        except Exception:
            return ""

    def send_pin(self, letter: str, value: int):
        """Envía comando tipo 'P1' (mandamos \\n por comodidad)."""
        try:
            cmd = f"{letter}{int(value)}"
            self.write_line(cmd)
            self.status_var.set(f"Enviado: {cmd}")
        except Exception as e:
            messagebox.showerror("Error", str(e))

    def query_q(self):
        """Envía 'Q' y parsea respuesta esperada: P#R#S#D#A#"""
        try:
            self.write_line("Q")
            resp = self.read_line_ascii()
            if resp:
                self.q_resp_var.set(f"Estado: {resp}")
                self.status_var.set(f"Respuesta 'Q': {resp}")
                self._apply_q_to_ui(resp)
            else:
                self.q_resp_var.set("Estado: — (sin respuesta)")
                self.status_var.set("Sin respuesta a 'Q'")
        except Exception as e:
            messagebox.showerror("Error", str(e))

    def _apply_q_to_ui(self, resp: str):
        """Actualiza checkboxes a partir de 'P1R0S1D0A1'"""
        s = resp.replace(" ", "")
        try:
            def get(letter):
                idx = s.upper().find(letter)
                if idx >= 0 and idx + 1 < len(s):
                    return 1 if s[idx + 1] == "1" else 0
                return None

            v = get("P")
            if v is not None: self.pga_var.set(v)
            v = get("R")
            if v is not None: self.rand_var.set(v)
            v = get("S")
            if v is not None: self.shdn_var.set(v)
            v = get("D")
            if v is not None: self.dith_var.set(v)
            v = get("A")
            if v is not None: self.preamp_var.set(v)
        except Exception:
            pass

    def query_f(self):
        """Envía 'f' y muestra lo que devuelve."""
        try:
            self.write_raw("f")
            resp = self.read_line_ascii()
            if resp:
                self.status_var.set(f"Respuesta 'f': {resp}")
            else:
                self.status_var.set("Sin respuesta a 'f'")
        except Exception as e:
            messagebox.showerror("Error", str(e))


def main():
    root = tk.Tk()
    try:
        ttk.Style().theme_use("clam")
    except Exception:
        pass
    SerialFreqUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
