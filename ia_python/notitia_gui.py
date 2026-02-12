#!/usr/bin/env python3
"""
🎨 Notitia Edge - Interface Graphique
Interface moderne pour le moteur de transcription avec correction Mistral AI
"""

import os
import sys
import json
import threading
import tempfile
from pathlib import Path
from datetime import datetime

# GUI
try:
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox, scrolledtext, simpledialog
except ImportError:
    print("Tkinter non disponible")
    sys.exit(1)

try:
    import numpy as np
    import sounddevice as sd
    import soundfile as sf
except ImportError:
    os.system("pip install numpy sounddevice soundfile")
    import numpy as np
    import sounddevice as sd
    import soundfile as sf

# Import du moteur STT
from notitia_stt import NotitiaSTT, AudioAmplifier, save_transcription

# Import Mistral (optionnel)
try:
    from mistral_integration import MistralCorrector, MistralConfig, CorrectionLevel
    MISTRAL_AVAILABLE = True
except ImportError:
    MISTRAL_AVAILABLE = False

# Import réduction de bruit (optionnel)
try:
    from noise_reduction import AdvancedNoiseReducer
    NOISE_REDUCTION_AVAILABLE = True
except ImportError:
    NOISE_REDUCTION_AVAILABLE = False

# Import fusion (optionnel)
try:
    from fusion_system import NotitiaFusionSTT
    FUSION_AVAILABLE = True
except ImportError:
    FUSION_AVAILABLE = False


class NotitiaGUI:
    """
    🎨 Interface graphique Notitia STT
    """
    
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("🎤 Notitia Edge - Speech to Text")
        self.root.geometry("900x700")
        self.root.minsize(800, 600)
        
        # Variables
        self.is_recording = False
        self.audio_data = []
        self.sample_rate = 16000
        self.stt_engine = None
        self.fusion_engine = None
        self.current_file = None
        self.mistral_corrector = None
        self.noise_reducer = None
        
        # Style
        self.setup_style()
        
        # Interface
        self.create_widgets()
        
        # Initialisation du modèle en arrière-plan
        self.status_var.set("⏳ Chargement du modèle...")
        threading.Thread(target=self.init_stt, daemon=True).start()
        
        # Initialisation Mistral si disponible
        if MISTRAL_AVAILABLE:
            threading.Thread(target=self.init_mistral, daemon=True).start()
        
        # Initialisation réduction de bruit
        if NOISE_REDUCTION_AVAILABLE:
            threading.Thread(target=self.init_noise_reducer, daemon=True).start()
    
    def setup_style(self):
        """Configure le style de l'interface"""
        self.root.configure(bg="#1a1a2e")
        
        style = ttk.Style()
        style.theme_use("clam")
        
        # Style personnalisé
        style.configure("TFrame", background="#1a1a2e")
        style.configure("TLabel", background="#1a1a2e", foreground="#eaeaea", 
                        font=("Segoe UI", 10))
        style.configure("Title.TLabel", font=("Segoe UI", 16, "bold"), 
                        foreground="#00d4ff")
        style.configure("TButton", font=("Segoe UI", 10), padding=10)
        style.configure("Record.TButton", font=("Segoe UI", 12, "bold"))
        style.configure("TCombobox", font=("Segoe UI", 10))
        
        style.map("TButton",
                  background=[("active", "#16213e"), ("!active", "#0f3460")],
                  foreground=[("active", "#00d4ff"), ("!active", "#eaeaea")])
    
    def create_widgets(self):
        """Crée les widgets de l'interface"""
        # Container principal
        main_frame = ttk.Frame(self.root, padding=20)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # === HEADER ===
        header_frame = ttk.Frame(main_frame)
        header_frame.pack(fill=tk.X, pady=(0, 20))
        
        title_label = ttk.Label(
            header_frame, 
            text="🎤 Notitia Edge - Speech to Text",
            style="Title.TLabel"
        )
        title_label.pack(side=tk.LEFT)
        
        # === CONFIGURATION ===
        config_frame = ttk.LabelFrame(main_frame, text="⚙️ Configuration", padding=10)
        config_frame.pack(fill=tk.X, pady=(0, 15))
        
        # Ligne 1: Modèle et Langue
        config_row1 = ttk.Frame(config_frame)
        config_row1.pack(fill=tk.X, pady=5)
        
        ttk.Label(config_row1, text="Modèle:").pack(side=tk.LEFT, padx=(0, 10))
        self.model_var = tk.StringVar(value="base")
        model_combo = ttk.Combobox(
            config_row1, 
            textvariable=self.model_var,
            values=["tiny", "base", "small", "medium", "large"],
            state="readonly",
            width=15
        )
        model_combo.pack(side=tk.LEFT, padx=(0, 30))
        model_combo.bind("<<ComboboxSelected>>", self.on_model_change)
        
        ttk.Label(config_row1, text="Langue:").pack(side=tk.LEFT, padx=(0, 10))
        self.lang_var = tk.StringVar(value="fr")
        lang_combo = ttk.Combobox(
            config_row1,
            textvariable=self.lang_var,
            values=["fr", "en", "es", "de", "it", "pt", "nl", "pl", "ru", "zh", "ja", "ko"],
            state="readonly",
            width=10
        )
        lang_combo.pack(side=tk.LEFT, padx=(0, 30))
        
        # Amplification
        self.enhance_var = tk.BooleanVar(value=True)
        enhance_check = ttk.Checkbutton(
            config_row1,
            text="🔊 Amplification audio",
            variable=self.enhance_var
        )
        enhance_check.pack(side=tk.LEFT, padx=(0, 20))
        
        # Timestamps
        self.timestamps_var = tk.BooleanVar(value=True)
        timestamps_check = ttk.Checkbutton(
            config_row1,
            text="⏱️ Timestamps par mot",
            variable=self.timestamps_var
        )
        timestamps_check.pack(side=tk.LEFT)
        
        # === CONFIGURATION MISTRAL (Ligne 2) ===
        config_row2 = ttk.Frame(config_frame)
        config_row2.pack(fill=tk.X, pady=5)
        
        # Correction Mistral
        self.mistral_var = tk.BooleanVar(value=MISTRAL_AVAILABLE)
        self.mistral_check = ttk.Checkbutton(
            config_row2,
            text="🤖 Correction Mistral AI",
            variable=self.mistral_var,
            state=tk.NORMAL if MISTRAL_AVAILABLE else tk.DISABLED
        )
        self.mistral_check.pack(side=tk.LEFT, padx=(0, 20))
        
        # Niveau de correction
        ttk.Label(config_row2, text="Niveau:").pack(side=tk.LEFT, padx=(0, 10))
        self.correction_level_var = tk.StringVar(value="medium")
        correction_combo = ttk.Combobox(
            config_row2,
            textvariable=self.correction_level_var,
            values=["light", "medium", "full"],
            state="readonly" if MISTRAL_AVAILABLE else tk.DISABLED,
            width=10
        )
        correction_combo.pack(side=tk.LEFT, padx=(0, 20))
        
        # Bouton configurer API
        self.config_api_btn = ttk.Button(
            config_row2,
            text="🔑 Configurer API",
            command=self.configure_api_key
        )
        self.config_api_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Status Mistral
        self.mistral_status_var = tk.StringVar(
            value="🤖 Mistral: En attente..." if MISTRAL_AVAILABLE else "🤖 Mistral: Non installé"
        )
        mistral_status_label = ttk.Label(config_row2, textvariable=self.mistral_status_var)
        mistral_status_label.pack(side=tk.RIGHT)
        
        # === CONFIGURATION AUDIO (Ligne 3) ===
        config_row3 = ttk.Frame(config_frame)
        config_row3.pack(fill=tk.X, pady=5)
        
        # Réduction de bruit
        self.noise_reduction_var = tk.BooleanVar(value=NOISE_REDUCTION_AVAILABLE)
        noise_check = ttk.Checkbutton(
            config_row3,
            text="🔇 Réduction de bruit",
            variable=self.noise_reduction_var,
            state=tk.NORMAL if NOISE_REDUCTION_AVAILABLE else tk.DISABLED
        )
        noise_check.pack(side=tk.LEFT, padx=(0, 15))
        
        # Force de réduction
        ttk.Label(config_row3, text="Force:").pack(side=tk.LEFT, padx=(0, 5))
        self.noise_strength_var = tk.DoubleVar(value=0.75)
        noise_scale = ttk.Scale(
            config_row3,
            from_=0.0,
            to=1.0,
            variable=self.noise_strength_var,
            orient=tk.HORIZONTAL,
            length=100
        )
        noise_scale.pack(side=tk.LEFT, padx=(0, 15))
        
        # Fusion intelligente
        self.fusion_var = tk.BooleanVar(value=FUSION_AVAILABLE and MISTRAL_AVAILABLE)
        fusion_check = ttk.Checkbutton(
            config_row3,
            text="🔄 Fusion Whisper+Mistral",
            variable=self.fusion_var,
            state=tk.NORMAL if (FUSION_AVAILABLE and MISTRAL_AVAILABLE) else tk.DISABLED
        )
        fusion_check.pack(side=tk.LEFT, padx=(0, 15))
        
        # Contexte
        ttk.Label(config_row3, text="Contexte:").pack(side=tk.LEFT, padx=(0, 5))
        self.context_var = tk.StringVar(value="")
        context_entry = ttk.Entry(
            config_row3,
            textvariable=self.context_var,
            width=25
        )
        context_entry.pack(side=tk.LEFT)
        
        # Status réduction de bruit
        self.noise_status_var = tk.StringVar(
            value="🔇 Prêt" if NOISE_REDUCTION_AVAILABLE else "🔇 Non disponible"
        )
        noise_status_label = ttk.Label(config_row3, textvariable=self.noise_status_var)
        noise_status_label.pack(side=tk.RIGHT)
        
        # === CONTRÔLES ===
        controls_frame = ttk.Frame(main_frame)
        controls_frame.pack(fill=tk.X, pady=(0, 15))
        
        # Bouton fichier
        self.file_btn = ttk.Button(
            controls_frame,
            text="📁 Ouvrir un fichier",
            command=self.open_file
        )
        self.file_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Bouton enregistrement
        self.record_btn = ttk.Button(
            controls_frame,
            text="🎙️ Enregistrer",
            command=self.toggle_recording,
            style="Record.TButton"
        )
        self.record_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Bouton transcrire
        self.transcribe_btn = ttk.Button(
            controls_frame,
            text="✨ Transcrire",
            command=self.transcribe,
            state=tk.DISABLED
        )
        self.transcribe_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Bouton exporter
        self.export_btn = ttk.Button(
            controls_frame,
            text="💾 Exporter",
            command=self.export_result,
            state=tk.DISABLED
        )
        self.export_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Bouton corriger (Mistral)
        self.correct_btn = ttk.Button(
            controls_frame,
            text="🤖 Corriger",
            command=self.correct_with_mistral,
            state=tk.DISABLED
        )
        self.correct_btn.pack(side=tk.LEFT)
        
        # Indicateur d'enregistrement
        self.record_indicator = tk.Label(
            controls_frame,
            text="",
            bg="#1a1a2e",
            fg="#ff4757",
            font=("Segoe UI", 12)
        )
        self.record_indicator.pack(side=tk.RIGHT)
        
        # === ZONE DE RÉSULTAT ===
        result_frame = ttk.LabelFrame(main_frame, text="📝 Transcription", padding=10)
        result_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 15))
        
        # Zone de texte
        self.result_text = scrolledtext.ScrolledText(
            result_frame,
            wrap=tk.WORD,
            font=("Consolas", 12),
            bg="#16213e",
            fg="#eaeaea",
            insertbackground="#00d4ff",
            selectbackground="#0f3460",
            relief=tk.FLAT,
            padx=15,
            pady=15
        )
        self.result_text.pack(fill=tk.BOTH, expand=True)
        
        # === MOTS AVEC TIMESTAMPS ===
        words_frame = ttk.LabelFrame(main_frame, text="⏱️ Mots détaillés", padding=10)
        words_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 15))
        
        # Treeview pour les mots
        columns = ("Mot", "Début", "Fin", "Confiance")
        self.words_tree = ttk.Treeview(words_frame, columns=columns, show="headings", height=6)
        
        for col in columns:
            self.words_tree.heading(col, text=col)
            self.words_tree.column(col, width=150)
        
        words_scrollbar = ttk.Scrollbar(words_frame, orient=tk.VERTICAL, 
                                         command=self.words_tree.yview)
        self.words_tree.configure(yscrollcommand=words_scrollbar.set)
        
        self.words_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        words_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        # === BARRE DE STATUT ===
        status_frame = ttk.Frame(main_frame)
        status_frame.pack(fill=tk.X)
        
        self.status_var = tk.StringVar(value="Prêt")
        status_label = ttk.Label(status_frame, textvariable=self.status_var)
        status_label.pack(side=tk.LEFT)
        
        # Info fichier
        self.file_info_var = tk.StringVar(value="")
        file_info_label = ttk.Label(status_frame, textvariable=self.file_info_var)
        file_info_label.pack(side=tk.RIGHT)
    
    def init_stt(self):
        """Initialise le moteur STT"""
        try:
            self.stt_engine = NotitiaSTT(
                model_size=self.model_var.get(),
                language=self.lang_var.get()
            )
            self.root.after(0, lambda: self.status_var.set("✅ Prêt"))
        except Exception as e:
            self.root.after(0, lambda: self.status_var.set(f"❌ Erreur: {str(e)}"))
    
    def init_noise_reducer(self):
        """Initialise le réducteur de bruit"""
        if not NOISE_REDUCTION_AVAILABLE:
            return
        
        try:
            self.noise_reducer = AdvancedNoiseReducer(strength=self.noise_strength_var.get())
            self.root.after(0, lambda: self.noise_status_var.set("🔇 Prêt"))
        except Exception as e:
            self.root.after(0, lambda: self.noise_status_var.set(f"🔇 Erreur: {str(e)[:20]}"))
    
    def init_mistral(self):
        """Initialise le correcteur Mistral"""
        if not MISTRAL_AVAILABLE:
            return
        
        try:
            config = MistralConfig.from_env()
            if config.api_key:
                self.mistral_corrector = MistralCorrector(config)
                self.root.after(0, lambda: self.mistral_status_var.set("🤖 Mistral: ✅ Connecté"))
            else:
                self.root.after(0, lambda: self.mistral_status_var.set("🤖 Mistral: ⚠️ Clé API manquante"))
        except Exception as e:
            self.root.after(0, lambda: self.mistral_status_var.set(f"🤖 Mistral: ❌ {str(e)[:30]}"))
    
    def configure_api_key(self):
        """Configure la clé API Mistral"""
        # Lire la clé actuelle depuis .env
        env_path = Path(__file__).parent / ".env"
        current_key = ""
        
        if env_path.exists():
            with open(env_path, "r") as f:
                for line in f:
                    if line.startswith("MISTRAL_API_KEY="):
                        current_key = line.split("=", 1)[1].strip()
                        break
        
        # Demander la nouvelle clé
        new_key = simpledialog.askstring(
            "Configuration API Mistral",
            "Entrez votre clé API Mistral:\n(https://console.mistral.ai/api-keys)",
            initialvalue=current_key if current_key and current_key != "your_mistral_api_key_here" else ""
        )
        
        if new_key:
            # Sauvegarder dans .env
            env_content = f"""# Configuration Notitia STT
MISTRAL_API_KEY={new_key}
MISTRAL_MODEL=mistral-small-latest
CORRECTION_LEVEL=medium
DEFAULT_LANGUAGE=fr
"""
            with open(env_path, "w") as f:
                f.write(env_content)
            
            # Réinitialiser Mistral
            self.mistral_status_var.set("🤖 Mistral: ⏳ Connexion...")
            threading.Thread(target=self.init_mistral, daemon=True).start()
            
            messagebox.showinfo("Succès", "Clé API sauvegardée!\nReconnexion en cours...")
    
    def on_model_change(self, event=None):
        """Callback lors du changement de modèle"""
        self.status_var.set(f"⏳ Chargement du modèle {self.model_var.get()}...")
        threading.Thread(target=self.init_stt, daemon=True).start()
    
    def open_file(self):
        """Ouvre un fichier audio"""
        filetypes = [
            ("Fichiers audio", "*.wav *.mp3 *.flac *.ogg *.m4a"),
            ("Tous les fichiers", "*.*")
        ]
        
        filepath = filedialog.askopenfilename(
            title="Sélectionner un fichier audio",
            filetypes=filetypes
        )
        
        if filepath:
            self.current_file = filepath
            self.audio_data = []
            self.file_info_var.set(f"📁 {Path(filepath).name}")
            self.transcribe_btn.config(state=tk.NORMAL)
            self.status_var.set(f"✅ Fichier chargé: {Path(filepath).name}")
    
    def toggle_recording(self):
        """Active/désactive l'enregistrement"""
        if self.is_recording:
            self.stop_recording()
        else:
            self.start_recording()
    
    def start_recording(self):
        """Démarre l'enregistrement"""
        self.is_recording = True
        self.audio_data = []
        self.current_file = None
        
        self.record_btn.config(text="⏹️ Arrêter")
        self.record_indicator.config(text="🔴 Enregistrement...")
        self.file_btn.config(state=tk.DISABLED)
        self.transcribe_btn.config(state=tk.DISABLED)
        self.status_var.set("🎙️ Enregistrement en cours...")
        
        def audio_callback(indata, frames, time_info, status):
            if status:
                print(f"Status: {status}")
            self.audio_data.append(indata.copy())
        
        self.stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=1,
            dtype=np.float32,
            callback=audio_callback
        )
        self.stream.start()
    
    def stop_recording(self):
        """Arrête l'enregistrement"""
        self.is_recording = False
        self.stream.stop()
        self.stream.close()
        
        self.record_btn.config(text="🎙️ Enregistrer")
        self.record_indicator.config(text="")
        self.file_btn.config(state=tk.NORMAL)
        
        if self.audio_data:
            self.transcribe_btn.config(state=tk.NORMAL)
            duration = len(np.concatenate(self.audio_data)) / self.sample_rate
            self.file_info_var.set(f"🎤 Enregistrement ({duration:.1f}s)")
            self.status_var.set(f"✅ Enregistrement terminé ({duration:.1f}s)")
        else:
            self.status_var.set("⚠️ Aucun audio enregistré")
    
    def transcribe(self):
        """Lance la transcription"""
        if not self.stt_engine:
            messagebox.showerror("Erreur", "Le moteur STT n'est pas initialisé")
            return
        
        self.status_var.set("⏳ Transcription en cours...")
        self.transcribe_btn.config(state=tk.DISABLED)
        self.result_text.delete(1.0, tk.END)
        
        # Clear words tree
        for item in self.words_tree.get_children():
            self.words_tree.delete(item)
        
        def do_transcribe():
            try:
                # Préparation de l'audio
                if self.current_file:
                    audio, sr = sf.read(self.current_file)
                    if len(audio.shape) > 1:
                        audio = np.mean(audio, axis=1)
                elif self.audio_data:
                    audio = np.concatenate(self.audio_data).flatten()
                    sr = self.sample_rate
                else:
                    raise ValueError("Aucun audio à transcrire")
                
                # 1. Réduction de bruit si activée
                noise_stats = {}
                if self.noise_reduction_var.get() and self.noise_reducer:
                    self.root.after(0, lambda: self.status_var.set("🔇 Réduction de bruit..."))
                    # Mise à jour de la force
                    self.noise_reducer.strength = self.noise_strength_var.get()
                    audio, noise_stats = self.noise_reducer.process(audio, sr)
                
                # 2. Transcription Whisper
                self.root.after(0, lambda: self.status_var.set("🎤 Transcription Whisper..."))
                result = self.stt_engine.transcribe_array(
                    audio,
                    sr,
                    enhance_audio=self.enhance_var.get(),
                    word_timestamps=self.timestamps_var.get()
                )
                
                # Ajout des stats de réduction de bruit
                if noise_stats:
                    result["noise_reduction"] = noise_stats
                
                self.last_result = result
                self.root.after(0, lambda: self.display_result(result))
                
                # 3. Fusion ou Correction Mistral
                if self.fusion_var.get() and FUSION_AVAILABLE and self.mistral_corrector:
                    # Mode Fusion intelligente
                    self.root.after(0, lambda: self.status_var.set("🔄 Fusion Whisper+Mistral..."))
                    from fusion_system import WhisperMistralFusion
                    fusion = WhisperMistralFusion()
                    if fusion.available:
                        context = self.context_var.get() if self.context_var.get() else None
                        fusion_result = fusion.fuse_transcription(result, context_hint=context)
                        
                        # Mise à jour du résultat
                        result["original_text"] = fusion_result.whisper_text
                        result["full_text"] = fusion_result.final_text
                        result["fusion"] = {
                            "applied": True,
                            "confidence": fusion_result.confidence,
                            "changes": fusion_result.changes,
                            "metadata": fusion_result.metadata
                        }
                        self.last_result = result
                        self.root.after(0, lambda: self.display_result(result, show_original=True, show_fusion=True))
                
                elif self.mistral_var.get() and self.mistral_corrector:
                    # Mode Correction simple
                    self.root.after(0, lambda: self.status_var.set("🤖 Correction Mistral..."))
                    corrected_result = self.mistral_corrector.correct_transcription_result(
                        result,
                        level=CorrectionLevel(self.correction_level_var.get())
                    )
                    self.last_result = corrected_result
                    self.root.after(0, lambda: self.display_result(corrected_result, show_original=True))
                
            except Exception as e:
                self.root.after(0, lambda: self.show_error(str(e)))
        
        threading.Thread(target=do_transcribe, daemon=True).start()
    
    def correct_with_mistral(self):
        """Corrige le texte actuel avec Mistral"""
        if not hasattr(self, 'last_result') or not self.last_result:
            messagebox.showwarning("Attention", "Aucun texte à corriger")
            return
        
        if not self.mistral_corrector:
            messagebox.showerror("Erreur", "Mistral AI n'est pas configuré.\nCliquez sur 'Configurer API' pour ajouter votre clé.")
            return
        
        self.status_var.set("🤖 Correction Mistral en cours...")
        self.correct_btn.config(state=tk.DISABLED)
        
        def do_correct():
            try:
                corrected_result = self.mistral_corrector.correct_transcription_result(
                    self.last_result,
                    level=CorrectionLevel(self.correction_level_var.get())
                )
                self.last_result = corrected_result
                self.root.after(0, lambda: self.display_result(corrected_result, show_original=True))
            except Exception as e:
                self.root.after(0, lambda: self.show_error(f"Erreur Mistral: {str(e)}"))
            finally:
                self.root.after(0, lambda: self.correct_btn.config(state=tk.NORMAL))
        
        threading.Thread(target=do_correct, daemon=True).start()
    
    def display_result(self, result, show_original=False, show_fusion=False):
        """Affiche le résultat de la transcription"""
        # Texte principal
        self.result_text.delete(1.0, tk.END)
        
        # Tag pour le header
        self.result_text.tag_configure("header", foreground="#00d4ff", font=("Consolas", 12, "bold"))
        self.result_text.tag_configure("fusion_info", foreground="#ffa500", font=("Consolas", 10, "italic"))
        
        # Afficher selon le mode
        if show_fusion and result.get("fusion", {}).get("applied"):
            fusion = result["fusion"]
            self.result_text.insert(tk.END, "📝 WHISPER (original):\n", "header")
            self.result_text.insert(tk.END, result.get("original_text", "") + "\n\n")
            self.result_text.insert(tk.END, "🔄 FUSION (Whisper + Mistral):\n", "header")
            self.result_text.insert(tk.END, result["full_text"] + "\n\n")
            
            # Afficher les changements
            if fusion.get("changes"):
                self.result_text.insert(tk.END, f"📊 Modifications ({len(fusion['changes'])}):\n", "fusion_info")
                for change in fusion["changes"][:10]:
                    self.result_text.insert(
                        tk.END,
                        f"  • '{change['original']}' → '{change['corrected']}' ({change.get('reason', '')})\n",
                        "fusion_info"
                    )
        elif show_original and "original_text" in result:
            self.result_text.insert(tk.END, "📝 ORIGINAL:\n", "header")
            self.result_text.insert(tk.END, result["original_text"] + "\n\n")
            self.result_text.insert(tk.END, "✨ CORRIGÉ (Mistral):\n", "header")
            self.result_text.insert(tk.END, result["full_text"])
        else:
            self.result_text.insert(tk.END, result["full_text"])
        
        # Mots avec timestamps
        for item in self.words_tree.get_children():
            self.words_tree.delete(item)
        
        if "words" in result:
            for word in result["words"]:
                self.words_tree.insert("", tk.END, values=(
                    word["word"],
                    f"{word['start']:.2f}s",
                    f"{word['end']:.2f}s",
                    f"{word['probability']:.1%}"
                ))
        
        # Mise à jour du statut
        status_parts = [
            f"✅ Terminé",
            f"Durée: {result.get('duration', 0):.1f}s",
            f"Langue: {result.get('language', 'N/A')} ({result.get('language_probability', 0):.0%})"
        ]
        
        # Info réduction de bruit
        if result.get("noise_reduction", {}).get("noise_reduction_db"):
            nr_db = result["noise_reduction"]["noise_reduction_db"]
            status_parts.append(f"🔇 -{abs(nr_db):.1f}dB")
        
        # Info fusion/correction
        if result.get("fusion", {}).get("applied"):
            conf = result["fusion"].get("confidence", 0)
            status_parts.append(f"🔄 Fusion ({conf:.0%})")
        elif result.get("mistral_corrected"):
            status_parts.append(f"🤖 Corrigé ({result.get('correction_level', 'medium')})")
        
        self.status_var.set(" | ".join(status_parts))
        
        self.transcribe_btn.config(state=tk.NORMAL)
        self.export_btn.config(state=tk.NORMAL)
        if self.mistral_corrector:
            self.correct_btn.config(state=tk.NORMAL)
    
    def show_error(self, error_msg):
        """Affiche une erreur"""
        self.status_var.set(f"❌ Erreur: {error_msg}")
        self.transcribe_btn.config(state=tk.NORMAL)
        messagebox.showerror("Erreur", error_msg)
    
    def export_result(self):
        """Exporte le résultat"""
        if not hasattr(self, 'last_result'):
            messagebox.showwarning("Attention", "Aucun résultat à exporter")
            return
        
        filetypes = [
            ("JSON", "*.json"),
            ("Texte", "*.txt"),
            ("Sous-titres SRT", "*.srt")
        ]
        
        filepath = filedialog.asksaveasfilename(
            title="Exporter la transcription",
            filetypes=filetypes,
            defaultextension=".json"
        )
        
        if filepath:
            ext = Path(filepath).suffix.lower()
            format_map = {".json": "json", ".txt": "txt", ".srt": "srt"}
            save_transcription(
                self.last_result,
                filepath,
                format_map.get(ext, "json")
            )
            self.status_var.set(f"💾 Exporté: {filepath}")
            messagebox.showinfo("Succès", f"Transcription exportée:\n{filepath}")
    
    def run(self):
        """Lance l'application"""
        self.root.mainloop()


def main():
    """Point d'entrée"""
    app = NotitiaGUI()
    app.run()


if __name__ == "__main__":
    main()
