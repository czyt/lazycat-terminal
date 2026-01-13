// SSH Forwarder using GLib Subprocess - more robust than SSH command mode
using Vte;

public class SshForwarder : Object {
    private Subprocess? ssh_process = null;
    private string ssh_host = "";
    private bool is_active = false;
    private Terminal? terminal = null;  // 用于回退到SSH命令模式
    
    public signal void status_changed(bool active, string message);
    
    public SshForwarder(Terminal? terminal = null) {
        this.terminal = terminal;
    }
    
    public bool start_forward(string ssh_host, bool is_local, string local_port, string remote_host, string remote_port) {
        if (is_active) {
            stop_forward();
        }
        
        this.ssh_host = ssh_host;
        
        // SSH端口转发应该在现有SSH会话中进行，而不是创建新连接
        if (terminal != null) {
            stderr.printf("Using SSH command mode for port forwarding\n");
            return fallback_to_ssh_command_mode(is_local, local_port, remote_host, remote_port);
        } else {
            stderr.printf("No terminal available for SSH command mode\n");
            status_changed(false, "No SSH session available");
            return false;
        }
    }
    
    // SSH命令模式：在现有SSH会话中添加端口转发
    private bool fallback_to_ssh_command_mode(bool is_local, string local_port, string remote_host, string remote_port) {
        if (terminal == null) return false;
        
        string cmd;
        if (is_local) {
            cmd = "-L %s:%s:%s".printf(local_port, remote_host, remote_port);
        } else {
            cmd = "-R %s:%s:%s".printf(local_port, remote_host, remote_port);
        }
        
        stderr.printf("SSH escape command: %s\n", cmd);
        
        // 发送SSH转义命令序列
        terminal.feed_child("\r".data);
        
        GLib.Timeout.add(300, () => {
            stderr.printf("Sending SSH escape sequence ~C\n");
            terminal.feed_child("~C".data);
            return false;
        });
        
        GLib.Timeout.add(1000, () => {
            stderr.printf("Sending port forward command: %s\n", cmd);
            string command = cmd + "\r";
            terminal.feed_child(command.data);
            return false;
        });
        
        GLib.Timeout.add(2000, () => {
            stderr.printf("Exiting SSH command mode\n");
            terminal.feed_child("\r\r".data);
            is_active = true;
            status_changed(true, "Port forwarding established (SSH command mode)");
            return false;
        });
        
        return true;
    }
    
    private void monitor_process() {
        if (ssh_process == null) return;
        
        // Monitor process completion
        ssh_process.wait_async.begin(null, (obj, res) => {
            try {
                ssh_process.wait_async.end(res);
                
                // Process ended - check if it was successful
                if (ssh_process.get_successful()) {
                    status_changed(false, "SSH connection closed normally");
                } else {
                    // Get error message from stderr
                    get_error_message();
                }
                
            } catch (Error e) {
                status_changed(false, "SSH process error: %s".printf(e.message));
            }
            
            is_active = false;
            ssh_process = null;
        });
    }
    
    private void get_error_message() {
        if (ssh_process == null) return;
        
        try {
            var stderr_pipe = ssh_process.get_stderr_pipe();
            if (stderr_pipe != null) {
                var dis = new DataInputStream(stderr_pipe);
                string? line = dis.read_line();
                if (line != null && line.length > 0) {
                    stderr.printf("SSH error output: %s\n", line);
                    status_changed(false, "SSH error: %s".printf(line));
                } else {
                    stderr.printf("SSH process failed with no error output\n");
                    status_changed(false, "SSH connection failed");
                }
            } else {
                stderr.printf("No stderr pipe available\n");
                status_changed(false, "SSH connection failed");
            }
        } catch (Error e) {
            stderr.printf("Error reading SSH stderr: %s\n", e.message);
            status_changed(false, "SSH connection failed");
        }
    }
    
    public void stop_forward() {
        if (ssh_process != null && is_active) {
            try {
                ssh_process.force_exit();
                is_active = false;
                status_changed(false, "Port forwarding stopped");
            } catch (Error e) {
                stderr.printf("Error stopping SSH process: %s\n", e.message);
            }
            ssh_process = null;
        }
    }
    
    public bool is_forwarding() {
        return is_active && ssh_process != null;
    }
    
    public string get_ssh_host() {
        return ssh_host;
    }
}
