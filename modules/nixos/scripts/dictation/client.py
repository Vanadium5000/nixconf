import socket
import sys

SOCKET_PATH = "/tmp/dictation_daemon.sock"

def send_command(cmd):
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.connect(SOCKET_PATH)
        client.sendall(cmd.encode())
        client.close()
    except Exception as e:
        print(f"Failed to connect to daemon: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: client.py [START|STOP|TOGGLE]")
        sys.exit(1)
    
    send_command(sys.argv[1].upper())
