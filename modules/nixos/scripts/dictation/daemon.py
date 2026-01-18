import os
import sys
import json
import time
import signal
import socket
import struct
import threading
import subprocess
import numpy as np
import pyaudio
import collections

# Attempt to import faster_whisper, handle if missing (will be provided by nix)
try:
    from faster_whisper import WhisperModel
except ImportError:
    print("Error: faster_whisper not found. Ensure it is installed.", file=sys.stderr)
    sys.exit(1)

# Configuration
SOCKET_PATH = "/tmp/dictation_daemon.sock"
STATUS_FILE = "/tmp/dictation_status.json"
MODEL_SIZE = "small" # adjustable: tiny, base, small, medium, large-v2
DEVICE = "cuda" if os.environ.get("USE_CUDA") == "1" else "cpu"
COMPUTE_TYPE = "float16" if DEVICE == "cuda" else "int8"
SAMPLE_RATE = 16000
CHUNK_DURATION = 0.5 # seconds
CHUNK_SIZE = int(SAMPLE_RATE * CHUNK_DURATION)

class DictationDaemon:
    def __init__(self):
        self.running = False
        self.active = False # recording state
        self.stop_event = threading.Event()
        self.model = None
        self.audio_queue = collections.deque()
        self.status = {"active": False, "text": "", "error": None}
        self.lock = threading.Lock()
        
        # Setup Waybar/Overlay status
        self.update_status(active=False, text="")

    def load_model(self):
        print(f"Loading model ({MODEL_SIZE}) on {DEVICE}...")
        try:
            self.model = WhisperModel(MODEL_SIZE, device=DEVICE, compute_type=COMPUTE_TYPE)
            print("Model loaded.")
        except Exception as e:
            print(f"Failed to load model: {e}")
            self.update_status(error=str(e))
            sys.exit(1)

    def update_status(self, active=None, text=None, error=None):
        with self.lock:
            if active is not None: self.status["active"] = active
            if text is not None: self.status["text"] = text
            if error is not None: self.status["error"] = error
            
            # Write to file for Waybar/Quickshell
            try:
                with open(STATUS_FILE, "w") as f:
                    json.dump(self.status, f)
            except Exception as e:
                print(f"Failed to write status: {e}")

    def type_text(self, text):
        if not text: return
        try:
            # Use wtype to simulate keystrokes
            subprocess.run(["wtype", text], check=False)
        except Exception as e:
            print(f"Failed to type text: {e}")

    def audio_callback(self, in_data, frame_count, time_info, status):
        if self.active:
            # Convert raw bytes to float32 numpy array
            audio_data = np.frombuffer(in_data, dtype=np.int16).astype(np.float32) / 32768.0
            self.audio_queue.append(audio_data)
        return (in_data, pyaudio.paContinue)

    def transcription_loop(self):
        while not self.stop_event.is_set():
            if self.active and self.audio_queue:
                # Process available audio chunks
                # For real-time, we might want to accumulate a bit or use stream
                # faster-whisper is not strictly streaming frame-by-frame, it processes segments
                
                # Simple strategy: Accumulate at least 2 seconds or process what we have if silence?
                # For "real-time typing", we want to process frequently.
                # Let's try to process every 1-2 seconds of audio.
                
                if len(self.audio_queue) * CHUNK_DURATION >= 2.0:
                    # Combine chunks
                    audio_data = np.concatenate(list(self.audio_queue))
                    self.audio_queue.clear()
                    
                    segments, info = self.model.transcribe(audio_data, beam_size=1, word_timestamps=False)
                    
                    text_segment = ""
                    for segment in segments:
                        text_segment += segment.text
                    
                    text_segment = text_segment.strip()
                    if text_segment:
                        print(f"Transcribed: {text_segment}")
                        self.type_text(text_segment + " ")
                        self.update_status(text=text_segment)
            else:
                time.sleep(0.1)

    def run(self):
        self.load_model()
        
        # Audio setup
        p = pyaudio.PyAudio()
        stream = p.open(format=pyaudio.paInt16,
                        channels=1,
                        rate=SAMPLE_RATE,
                        input=True,
                        frames_per_buffer=CHUNK_SIZE,
                        stream_callback=self.audio_callback)
        
        stream.start_stream()
        
        # Transcribe thread
        t_thread = threading.Thread(target=self.transcription_loop)
        t_thread.start()

        # Socket listener
        if os.path.exists(SOCKET_PATH):
            os.remove(SOCKET_PATH)
            
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(SOCKET_PATH)
        server.listen(1)
        print("Daemon ready. Listening on socket.")
        
        try:
            while not self.stop_event.is_set():
                conn, _ = server.accept()
                try:
                    data = conn.recv(1024).decode().strip()
                    if data == "START":
                        print("Command: START")
                        self.active = True
                        self.audio_queue.clear()
                        self.update_status(active=True)
                    elif data == "STOP":
                        print("Command: STOP")
                        self.active = False
                        self.update_status(active=False)
                        # Process remaining audio? Maybe skip for instant stop
                    elif data == "TOGGLE":
                        self.active = not self.active
                        self.audio_queue.clear()
                        self.update_status(active=self.active)
                        print(f"Command: TOGGLE -> {self.active}")
                except Exception as e:
                    print(f"Socket error: {e}")
                finally:
                    conn.close()
        except KeyboardInterrupt:
            pass
        finally:
            self.stop_event.set()
            t_thread.join()
            stream.stop_stream()
            stream.close()
            p.terminate()
            os.remove(SOCKET_PATH)

if __name__ == "__main__":
    daemon = DictationDaemon()
    daemon.run()
