// Port Forward Panel - SSH port forwarding management UI

public class PortForwardPanel : Gtk.Box {
    private Gtk.Box content_box;
    private Gtk.ListBox forward_list;
    private bool is_expanded = true;
    private Vte.Terminal terminal;
    private HashTable<string, ForwardEntry> forwards;
    private Gdk.RGBA fg_color;
    private Gdk.RGBA bg_color;
    private double bg_opacity;
    private bool is_ssh_connected = false;
    private Gtk.Label? status_label = null;

    private Gtk.Label? count_label = null;
    private SshForwarder? ssh_forwarder = null;

    public signal void close_requested();

    public PortForwardPanel(Vte.Terminal term, Gdk.RGBA foreground, Gdk.RGBA background, double bg_opacity) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        terminal = term;
        fg_color = foreground;
        bg_color = background;
        this.bg_opacity = bg_opacity;
        forwards = new HashTable<string, ForwardEntry>(str_hash, str_equal);

        setup_ui();
        load_saved_forwards();
        
        // Initialize SSH forwarder with terminal reference
        ssh_forwarder = new SshForwarder(terminal);
        ssh_forwarder.status_changed.connect(on_forwarder_status_changed);
        
        // Monitor terminal title changes to detect SSH connection
        terminal.notify["window-title"].connect(on_title_changed);
        check_ssh_connection();
        
        // Periodic SSH connection check for robustness
        GLib.Timeout.add_seconds(5, () => {
            check_ssh_connection();
            return true; // Keep checking
        });
    }
    
    private void on_title_changed() {
        check_ssh_connection();
    }
    
    private void check_ssh_connection() {
        string? title = terminal.get_window_title();
        bool was_connected = is_ssh_connected;
        
        // Check multiple indicators for SSH connection
        bool title_indicates_ssh = title != null && (
            title.down().contains("ssh") || 
            title.contains("@") ||
            title.down().contains("remote")
        );
        
        bool env_indicates_ssh = (
            Environment.get_variable("SSH_CLIENT") != null ||
            Environment.get_variable("SSH_CONNECTION") != null ||
            Environment.get_variable("SSH_TTY") != null
        );
        
        bool process_indicates_ssh = check_ssh_process();
        
        is_ssh_connected = title_indicates_ssh || env_indicates_ssh || process_indicates_ssh;
        
        stderr.printf("SSH connection check - Title: '%s', TitleSSH: %s, Env: %s, Process: %s, Result: %s\n",
            title ?? "null",
            title_indicates_ssh ? "yes" : "no",
            env_indicates_ssh ? "yes" : "no", 
            process_indicates_ssh ? "yes" : "no",
            is_ssh_connected ? "connected" : "not connected");
        
        update_status_label();
        
        // If just connected to SSH, apply all enabled forwards
        if (is_ssh_connected && !was_connected) {
            apply_all_enabled_forwards();
        }
        // If SSH disconnected, reset all forward statuses to PENDING
        else if (!is_ssh_connected && was_connected) {
            reset_all_forward_statuses();
        }
    }
    
    private void on_forwarder_status_changed(bool active, string message) {
        // Update UI based on forwarder status
        if (active) {
            stderr.printf("SSH Forward: %s\n", message);
        } else {
            stderr.printf("SSH Forward stopped: %s\n", message);
        }
    }
    
    private void reset_all_forward_statuses() {
        forwards.foreach((id, entry) => {
            entry.update_status(ForwardStatus.PENDING);
        });
    }
    
    private bool check_ssh_process() {
        // Try to check if current process is SSH by checking /proc
        try {
            var pty = terminal.get_pty();
            if (pty == null) return false;
            
            int pty_fd = pty.get_fd();
            if (pty_fd < 0) return false;
            
            // Get the foreground process group
            int fg_pgid = Posix.tcgetpgrp(pty_fd);
            if (fg_pgid <= 0) return false;
            
            string cmdline_path = "/proc/%d/cmdline".printf(fg_pgid);
            uint8[] cmdline_data;
            if (FileUtils.get_data(cmdline_path, out cmdline_data)) {
                // cmdline contains null-separated arguments, find first null or end
                int first_arg_end = 0;
                for (int i = 0; i < cmdline_data.length; i++) {
                    if (cmdline_data[i] == 0) {
                        first_arg_end = i;
                        break;
                    }
                }
                if (first_arg_end == 0) first_arg_end = cmdline_data.length;
                
                string first_arg = (string) cmdline_data[0:first_arg_end];
                string basename = Path.get_basename(first_arg);
                return basename == "ssh";
            }
        } catch (Error e) {
            // Ignore errors
        }
        return false;
    }
    
    private void update_status_label() {
        if (status_label != null) {
            if (is_ssh_connected) {
                status_label.set_markup("<span color='#4ade80'>●</span> SSH Connected");
                status_label.remove_css_class("ssh-disconnected");
                status_label.add_css_class("ssh-connected");
            } else {
                status_label.set_markup("<span color='#f87171'>○</span> Not in SSH session");
                status_label.remove_css_class("ssh-connected");
                status_label.add_css_class("ssh-disconnected");
            }
        }
    }
    
    private void apply_all_enabled_forwards() {
        forwards.foreach((id, entry) => {
            if (entry.enabled) {
                apply_forward(entry);
            }
        });
    }

    private void setup_ui() {
        set_size_request(320, -1);
        set_hexpand(false);
        set_vexpand(true);

        // Content box with padding matching settings dialog style
        content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        content_box.set_margin_start(16);
        content_box.set_margin_end(16);
        content_box.set_margin_top(16);
        content_box.set_margin_bottom(16);

        // Header with title and close button
        var header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        var title = new Gtk.Label("🔗 SSH Port Forward");
        title.set_halign(Gtk.Align.START);
        title.add_css_class("port-forward-title");
        
        var close_btn = new Gtk.Button.from_icon_name("window-close-symbolic");
        close_btn.set_halign(Gtk.Align.END);
        close_btn.set_hexpand(true);
        close_btn.add_css_class("port-forward-close-btn");
        close_btn.clicked.connect(() => close_requested());
        
        header_box.append(title);
        header_box.append(close_btn);
        content_box.append(header_box);
        
        // SSH connection status indicator with better styling
        var status_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        status_label = new Gtk.Label("○ Not in SSH session");
        status_label.set_halign(Gtk.Align.START);
        status_label.add_css_class("port-forward-status");
        status_label.add_css_class("ssh-disconnected");
        
        var refresh_btn = new Gtk.Button.from_icon_name("view-refresh-symbolic");
        refresh_btn.set_tooltip_text("Refresh SSH connection status");
        refresh_btn.add_css_class("port-forward-refresh-btn");
        refresh_btn.clicked.connect(() => {
            check_ssh_connection();
            // Add a subtle animation effect
            refresh_btn.add_css_class("refreshing");
            GLib.Timeout.add(300, () => {
                refresh_btn.remove_css_class("refreshing");
                return false;
            });
        });
        
        status_box.append(status_label);
        status_box.append(refresh_btn);
        content_box.append(status_box);

        // Add buttons section with better styling
        var add_label = new Gtk.Label("➕ Add Port Forward");
        add_label.set_halign(Gtk.Align.START);
        add_label.add_css_class("port-forward-section-label");
        add_label.set_margin_top(12);
        content_box.append(add_label);
        
        var add_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        var local_btn = new Gtk.Button();
        local_btn.set_child(create_button_content("📤", "Local Forward", "Local listens, connects to remote"));
        var remote_btn = new Gtk.Button();
        remote_btn.set_child(create_button_content("📥", "Remote Forward", "Remote listens, forwards to local"));
        
        local_btn.add_css_class("port-forward-btn");
        remote_btn.add_css_class("port-forward-btn");
        local_btn.clicked.connect(() => show_add_dialog(true));
        remote_btn.clicked.connect(() => show_add_dialog(false));
        add_box.append(local_btn);
        add_box.append(remote_btn);
        add_box.set_homogeneous(true);
        content_box.append(add_box);

        // Forward list section with better header
        var list_header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        var list_label = new Gtk.Label("📋 Active Forwards");
        list_label.set_halign(Gtk.Align.START);
        list_label.add_css_class("port-forward-section-label");
        
        var count_label = new Gtk.Label("0");
        count_label.set_halign(Gtk.Align.END);
        count_label.add_css_class("port-forward-count-label");
        this.count_label = count_label;
        
        list_header.append(list_label);
        list_header.append(count_label);
        list_header.set_margin_top(16);
        content_box.append(list_header);
        
        var scroll = new Gtk.ScrolledWindow();
        scroll.set_vexpand(true);
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scroll.add_css_class("port-forward-scroll");
        
        forward_list = new Gtk.ListBox();
        forward_list.add_css_class("port-forward-list");
        forward_list.set_selection_mode(Gtk.SelectionMode.NONE);
        scroll.set_child(forward_list);
        content_box.append(scroll);
        
        // Help tip at the bottom
        var tip_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        tip_box.set_margin_top(12);
        
        var tip_title = new Gtk.Label("💡 Tip");
        tip_title.set_halign(Gtk.Align.START);
        tip_title.add_css_class("port-forward-tip-title");
        tip_box.append(tip_title);
        
        var tip_text = new Gtk.Label("Add to ~/.ssh/config:");
        tip_text.set_halign(Gtk.Align.START);
        tip_text.add_css_class("port-forward-tip");
        tip_box.append(tip_text);
        
        var tip_code = new Gtk.Label("Host *\n    EnableEscapeCommandline yes");
        tip_code.set_halign(Gtk.Align.START);
        tip_code.add_css_class("port-forward-tip-code");
        tip_code.set_selectable(true);
        tip_box.append(tip_code);
        
        content_box.append(tip_box);

        append(content_box);
        apply_style();
    }

    private Gtk.Box create_button_content(string icon, string text, string tooltip) {
        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        var icon_label = new Gtk.Label(icon);
        icon_label.add_css_class("port-forward-btn-icon");
        var text_label = new Gtk.Label(text);
        text_label.add_css_class("port-forward-btn-text");
        box.append(icon_label);
        box.append(text_label);
        box.set_tooltip_text(tooltip);
        return box;
    }

    private void show_add_dialog(bool is_local) {
        var dialog = new Gtk.Window();
        dialog.set_transient_for((Gtk.Window)get_root());
        dialog.set_modal(true);
        dialog.set_decorated(false);
        dialog.set_default_size(380, 280);
        dialog.add_css_class("port-forward-dialog");
        
        // Apply theme style to dialog
        apply_dialog_style(dialog);

        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        box.set_margin_start(24);
        box.set_margin_end(24);
        box.set_margin_top(24);
        box.set_margin_bottom(24);

        // Dialog title
        var title_label = new Gtk.Label(is_local ? "Local Forward" : "Remote Forward");
        title_label.set_halign(Gtk.Align.START);
        title_label.add_css_class("port-forward-dialog-title");
        box.append(title_label);
        
        // Add explanation
        var explanation = new Gtk.Label(is_local ? 
            "💡 Local listens, connects to remote service\nFlow: Local Port → SSH Tunnel → Remote Target" :
            "💡 Remote listens, forwards to local service\nFlow: Remote Port → SSH Tunnel → Local Target");
        explanation.set_halign(Gtk.Align.START);
        explanation.add_css_class("port-forward-explanation");
        explanation.set_wrap(true);
        box.append(explanation);

        var alias_entry = new Gtk.Entry();
        alias_entry.set_placeholder_text("Alias (optional)");
        alias_entry.add_css_class("port-forward-entry");
        
        var local_port_entry = new Gtk.Entry();
        local_port_entry.set_placeholder_text(is_local ? "Local Port" : "Remote Port");
        local_port_entry.add_css_class("port-forward-entry");
        
        var remote_host_entry = new Gtk.Entry();
        remote_host_entry.set_placeholder_text("Target Host");
        remote_host_entry.set_text("localhost");
        remote_host_entry.add_css_class("port-forward-entry");
        
        var remote_port_entry = new Gtk.Entry();
        remote_port_entry.set_placeholder_text(is_local ? "Target Port" : "Local Port");
        remote_port_entry.add_css_class("port-forward-entry");

        box.append(alias_entry);
        box.append(local_port_entry);
        box.append(remote_host_entry);
        box.append(remote_port_entry);

        var btn_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        btn_box.set_halign(Gtk.Align.END);
        
        var cancel_btn = new Gtk.Button.with_label("Cancel");
        cancel_btn.add_css_class("port-forward-dialog-btn");
        var add_btn = new Gtk.Button.with_label("Add");
        add_btn.add_css_class("port-forward-dialog-btn");
        add_btn.add_css_class("port-forward-dialog-btn-primary");
        
        cancel_btn.clicked.connect(() => dialog.close());
        add_btn.clicked.connect(() => {
            string alias = alias_entry.get_text().strip();
            string local_port = local_port_entry.get_text().strip();
            string remote_host = remote_host_entry.get_text().strip();
            string remote_port = remote_port_entry.get_text().strip();
            
            if (local_port.length > 0 && remote_port.length > 0) {
                add_forward(alias, is_local, local_port, remote_host, remote_port);
                dialog.close();
            }
        });
        
        btn_box.append(cancel_btn);
        btn_box.append(add_btn);
        box.append(btn_box);

        dialog.set_child(box);
        dialog.present();
    }
    
    private void apply_dialog_style(Gtk.Window dialog) {
        var provider = new Gtk.CssProvider();
        
        string fg_hex = "#%02x%02x%02x".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        
        // Match settings dialog style
        int bg_r = (int)(bg_color.red * 255);
        int bg_g = (int)(bg_color.green * 255);
        int bg_b = (int)(bg_color.blue * 255);
        
        string dialog_bg = "rgba(%d, %d, %d, 0.95)".printf(bg_r, bg_g, bg_b);
        
        string entry_bg = "rgba(%d, %d, %d, 0.15)".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        
        string btn_bg = "rgba(%d, %d, %d, 0.15)".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        
        string btn_hover_bg = "rgba(%d, %d, %d, 0.25)".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        
        string btn_primary_bg = "rgba(%d, %d, %d, 0.35)".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        
        // Subdued foreground for explanations
        string fg_subdued = "rgba(%d, %d, %d, 0.8)".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        
        string css = """
            .port-forward-dialog {
                background: %s;
                border-radius: 8px;
                border: 1px solid %s;
            }
            .port-forward-dialog-title {
                font-weight: bold;
                font-size: 16px;
                color: %s;
                margin-bottom: 8px;
            }
            .port-forward-explanation {
                font-size: 11px;
                color: %s;
                background: rgba(%d, %d, %d, 0.1);
                padding: 8px 12px;
                border-radius: 6px;
                border-left: 3px solid %s;
                margin-bottom: 16px;
            }
            .port-forward-entry {
                background: %s;
                color: %s;
                border: 1px solid rgba(%d, %d, %d, 0.3);
                border-radius: 6px;
                padding: 10px 12px;
                font-size: 13px;
            }
            .port-forward-entry:focus {
                border-color: %s;
            }
            .port-forward-dialog-btn {
                background: %s;
                color: %s;
                border: 1px solid rgba(%d, %d, %d, 0.3);
                border-radius: 6px;
                padding: 10px 20px;
                font-size: 13px;
            }
            .port-forward-dialog-btn:hover {
                background: %s;
            }
            .port-forward-dialog-btn-primary {
                background: %s;
                font-weight: bold;
            }
            .port-forward-dialog-btn-primary:hover {
                background: rgba(%d, %d, %d, 0.45);
            }
        """.printf(
            dialog_bg, fg_hex,
            fg_hex,
            fg_subdued,
            (int)(fg_color.red * 255), (int)(fg_color.green * 255), (int)(fg_color.blue * 255),
            fg_hex,
            entry_bg, fg_hex,
            (int)(fg_color.red * 255), (int)(fg_color.green * 255), (int)(fg_color.blue * 255),
            fg_hex,
            btn_bg, fg_hex,
            (int)(fg_color.red * 255), (int)(fg_color.green * 255), (int)(fg_color.blue * 255),
            btn_hover_bg,
            btn_primary_bg,
            (int)(fg_color.red * 255), (int)(fg_color.green * 255), (int)(fg_color.blue * 255)
        );
        
        provider.load_from_string(css);
        Gtk.StyleContext.add_provider_for_display(
            dialog.get_display(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    private void add_forward(string alias, bool is_local, string local_port, string remote_host, string remote_port) {
        string id = "%s:%s:%s:%s".printf(is_local ? "L" : "R", local_port, remote_host, remote_port);
        
        if (forwards.contains(id)) return;

        var entry = new ForwardEntry(alias, is_local, local_port, remote_host, remote_port);
        forwards.set(id, entry);
        
        var row = create_forward_row(id, entry);
        forward_list.append(row);
        
        // Only apply forward if SSH is connected
        if (entry.enabled && is_ssh_connected) {
            apply_forward(entry);
        }
        
        save_forwards();
        update_forward_count();
    }

    private Gtk.Box create_forward_row(string id, ForwardEntry entry) {
        var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        row.set_margin_start(8);
        row.set_margin_end(8);
        row.set_margin_top(6);
        row.set_margin_bottom(6);

        // Status indicator with better styling
        var status_lbl = new Gtk.Label("○");
        status_lbl.set_valign(Gtk.Align.CENTER);
        status_lbl.add_css_class("port-forward-status-icon");
        status_lbl.add_css_class("status-pending");
        status_lbl.set_tooltip_text("Pending - SSH not connected");
        entry.status_label = status_lbl;
        row.append(status_lbl);

        // Info section with better layout
        var info_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        
        // Main label with direction icon
        string direction_icon = entry.is_local ? "📤" : "📥";
        string main_text = entry.alias.length > 0 ? 
            "%s %s".printf(direction_icon, entry.alias) : 
            "%s %s:%s→%s:%s".printf(direction_icon, 
                entry.is_local ? "L" : "R", 
                entry.local_port, entry.remote_host, entry.remote_port);
        
        var label = new Gtk.Label(main_text);
        label.set_halign(Gtk.Align.START);
        label.add_css_class("port-forward-label");
        info_box.append(label);
        
        // Sublabel with port details
        if (entry.alias.length > 0) {
            var sublabel = new Gtk.Label("%s:%s → %s:%s".printf(
                entry.is_local ? "localhost" : "remote",
                entry.local_port, entry.remote_host, entry.remote_port));
            sublabel.set_halign(Gtk.Align.START);
            sublabel.add_css_class("port-forward-sublabel");
            info_box.append(sublabel);
        }
        
        // Control section
        var control_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        
        var toggle = new Gtk.Switch();
        toggle.set_active(entry.enabled);
        toggle.set_valign(Gtk.Align.CENTER);
        toggle.notify["active"].connect(() => {
            entry.enabled = toggle.get_active();
            if (is_ssh_connected) {
                if (entry.enabled) {
                    apply_forward(entry);
                } else {
                    remove_forward(entry);
                }
            }
            save_forwards();
            update_forward_count();
        });
        
        var del_btn = new Gtk.Button.from_icon_name("user-trash-symbolic");
        del_btn.add_css_class("port-forward-delete");
        del_btn.set_tooltip_text("Delete this forward");
        del_btn.clicked.connect(() => {
            if (entry.enabled && is_ssh_connected) {
                remove_forward(entry);
            }
            forwards.remove(id);
            var list_row = row.get_parent() as Gtk.ListBoxRow;
            if (list_row != null) {
                forward_list.remove(list_row);
            }
            save_forwards();
            update_forward_count();
        });

        control_box.append(toggle);
        control_box.append(del_btn);
        
        row.append(info_box);
        row.append(control_box);
        info_box.set_hexpand(true);
        
        return row;
    }

    private void update_forward_count() {
        if (count_label != null) {
            int active_count = 0;
            forwards.foreach((id, entry) => {
                if (entry.enabled) active_count++;
            });
            count_label.set_text(active_count.to_string());
        }
    }

    private void apply_forward(ForwardEntry entry) {
        if (!is_ssh_connected) {
            stderr.printf("Cannot apply forward: not in SSH session\n");
            entry.update_status(ForwardStatus.FAILED);
            return;
        }
        
        // 额外检查：确保真的在SSH环境中，而不是本地终端
        bool really_in_ssh = (
            Environment.get_variable("SSH_CLIENT") != null ||
            Environment.get_variable("SSH_CONNECTION") != null ||
            Environment.get_variable("SSH_TTY") != null
        );
        
        if (!really_in_ssh) {
            stderr.printf("SSH detected by title but no SSH environment variables - skipping\n");
            entry.update_status(ForwardStatus.FAILED);
            return;
        }
        
        // Update status to SENT immediately
        entry.update_status(ForwardStatus.SENT);
        
        // Use SshForwarder to start the forward
        bool success = ssh_forwarder.start_forward(
            get_ssh_host(),
            entry.is_local,
            entry.local_port,
            entry.remote_host, 
            entry.remote_port
        );
        
        if (!success) {
            entry.update_status(ForwardStatus.FAILED);
        }
    }
    
    private void verify_forward_status(ForwardEntry entry) {
        // For remote forwards (-R), the port is listening on the remote server, not locally
        // For local forwards (-L), the port is listening locally
        // Since we can't easily verify remote ports, we'll assume success if no error occurred
        
        if (entry.is_local) {
            // Local forward: try to check if the local port is listening
            try {
                var socket = new Socket(SocketFamily.IPV4, SocketType.STREAM, SocketProtocol.TCP);
                var address = new InetSocketAddress(new InetAddress.loopback(SocketFamily.IPV4), 
                                                  (uint16)int.parse(entry.local_port));
                
                // Try to connect to the local port
                socket.connect(address);
                socket.close();
                entry.update_status(ForwardStatus.ACTIVE);
            } catch (Error e) {
                // Port might not be accepting connections yet, but forward could still be active
                entry.update_status(ForwardStatus.ACTIVE);
            }
        } else {
            // Remote forward: assume success since we can't easily verify remote ports
            entry.update_status(ForwardStatus.ACTIVE);
        }
    }

    private void remove_forward(ForwardEntry entry) {
        if (!is_ssh_connected) {
            return;
        }
        
        // Use SshForwarder to stop the forward
        ssh_forwarder.stop_forward();
        entry.update_status(ForwardStatus.PENDING);
    }
    
    private string get_ssh_host() {
        // Extract SSH host from terminal title or use default
        string? title = terminal.get_window_title();
        stderr.printf("Terminal title: %s\n", title ?? "null");
        
        if (title != null && title.contains("@")) {
            // Try to extract host from title like "user@hostname"
            string[] parts = title.split("@");
            if (parts.length > 1) {
                string host = parts[1].split(":")[0]; // Remove port if present
                stderr.printf("Extracted SSH host: %s\n", host);
                return host;
            }
        }
        
        // Try to get from environment variables
        string? ssh_connection = Environment.get_variable("SSH_CONNECTION");
        if (ssh_connection != null) {
            stderr.printf("SSH_CONNECTION: %s\n", ssh_connection);
            // SSH_CONNECTION format: "client_ip client_port server_ip server_port"
            string[] parts = ssh_connection.split(" ");
            if (parts.length >= 3) {
                string host = parts[2]; // server IP
                stderr.printf("SSH host from SSH_CONNECTION: %s\n", host);
                return host;
            }
        }
        
        stderr.printf("Using fallback SSH host: localhost\n");
        return "localhost"; // Fallback
    }

    private void save_forwards() {
        var config_dir = Path.build_filename(Environment.get_home_dir(), ".config", "lazycat-terminal");
        var forwards_file = Path.build_filename(config_dir, "port_forwards.conf");
        
        try {
            var key_file = new KeyFile();
            int idx = 0;
            
            forwards.foreach((id, entry) => {
                string section = "forward_%d".printf(idx++);
                key_file.set_string(section, "alias", entry.alias);
                key_file.set_boolean(section, "is_local", entry.is_local);
                key_file.set_string(section, "local_port", entry.local_port);
                key_file.set_string(section, "remote_host", entry.remote_host);
                key_file.set_string(section, "remote_port", entry.remote_port);
                key_file.set_boolean(section, "enabled", entry.enabled);
            });
            
            FileUtils.set_contents(forwards_file, key_file.to_data());
        } catch (Error e) {
            stderr.printf("Failed to save forwards: %s\n", e.message);
        }
    }

    private void load_saved_forwards() {
        var config_dir = Path.build_filename(Environment.get_home_dir(), ".config", "lazycat-terminal");
        var forwards_file = Path.build_filename(config_dir, "port_forwards.conf");
        
        try {
            var key_file = new KeyFile();
            key_file.load_from_file(forwards_file, KeyFileFlags.NONE);
            
            foreach (var section in key_file.get_groups()) {
                string alias = key_file.get_string(section, "alias");
                bool is_local = key_file.get_boolean(section, "is_local");
                string local_port = key_file.get_string(section, "local_port");
                string remote_host = key_file.get_string(section, "remote_host");
                string remote_port = key_file.get_string(section, "remote_port");
                bool enabled = key_file.get_boolean(section, "enabled");
                
                var entry = new ForwardEntry(alias, is_local, local_port, remote_host, remote_port);
                entry.enabled = enabled;
                
                string id = "%s:%s:%s:%s".printf(is_local ? "L" : "R", local_port, remote_host, remote_port);
                forwards.set(id, entry);
                
                var row = create_forward_row(id, entry);
                forward_list.append(row);
            }
            update_forward_count();
        } catch (Error e) {
            // File doesn't exist or parse error, ignore
        }
    }

    private void apply_style() {
        var provider = new Gtk.CssProvider();
        
        string fg_hex = "#%02x%02x%02x".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        
        // Make background darker than tab background (multiply by 0.7)
        double darker_factor = 0.7;
        string panel_bg = "rgba(%d, %d, %d, %.2f)".printf(
            (int)(bg_color.red * 255 * darker_factor),
            (int)(bg_color.green * 255 * darker_factor),
            (int)(bg_color.blue * 255 * darker_factor),
            bg_opacity + 0.1 > 1.0 ? 1.0 : bg_opacity + 0.1
        );
        
        // Button colors - slightly lighter than panel background
        string btn_bg = "rgba(%d, %d, %d, 0.3)".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        string btn_hover_bg = "rgba(%d, %d, %d, 0.4)".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        string btn_active_bg = "rgba(%d, %d, %d, 0.5)".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        
        // Background color for button text (inverted for contrast)
        string btn_fg = "#%02x%02x%02x".printf(
            (int)(bg_color.red * 255),
            (int)(bg_color.green * 255),
            (int)(bg_color.blue * 255)
        );
        
        // Subdued foreground for labels
        string fg_subdued = "rgba(%d, %d, %d, 0.7)".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        
        string css = """
            .port-forward-panel {
                background: %s;
                border-left: 1px solid %s;
                border-radius: 0;
            }
            .port-forward-title {
                font-weight: bold;
                font-size: 16px;
                color: %s;
                margin-bottom: 4px;
            }
            .port-forward-close-btn {
                min-width: 24px;
                min-height: 24px;
                padding: 4px;
                background: transparent;
                color: %s;
                border: none;
                border-radius: 4px;
            }
            .port-forward-close-btn:hover {
                background: rgba(239, 68, 68, 0.2);
                color: #ef4444;
            }
            .port-forward-status {
                font-size: 12px;
                margin-bottom: 8px;
                font-weight: 500;
            }
            .ssh-connected {
                color: #4ade80;
            }
            .ssh-disconnected {
                color: #f87171;
            }
            .port-forward-refresh-btn {
                min-width: 20px;
                min-height: 20px;
                padding: 2px;
                background: transparent;
                color: %s;
                border: none;
                border-radius: 3px;
                transition: all 0.2s ease;
            }
            .port-forward-refresh-btn:hover {
                background: %s;
                transform: scale(1.1);
            }
            .port-forward-refresh-btn.refreshing {
                animation: spin 0.5s linear;
            }
            @keyframes spin {
                from { transform: rotate(0deg); }
                to { transform: rotate(360deg); }
            }
            .port-forward-section-label {
                font-size: 12px;
                font-weight: bold;
                color: %s;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }
            .port-forward-count-label {
                font-size: 11px;
                color: %s;
                background: %s;
                padding: 2px 6px;
                border-radius: 10px;
                min-width: 16px;
                text-align: center;
            }
            .port-forward-btn {
                background: %s;
                color: %s;
                border: 1px solid %s;
                border-radius: 8px;
                padding: 12px 16px;
                font-size: 12px;
                transition: all 0.2s ease;
            }
            .port-forward-btn:hover {
                background: %s;
                transform: translateY(-1px);
                box-shadow: 0 4px 8px rgba(0,0,0,0.2);
            }
            .port-forward-btn:active {
                background: %s;
                transform: translateY(0);
            }
            .port-forward-btn-icon {
                font-size: 14px;
            }
            .port-forward-btn-text {
                font-size: 11px;
                font-weight: 500;
            }
            .port-forward-scroll {
                background: transparent;
            }
            .port-forward-list {
                background: transparent;
            }
            .port-forward-list row {
                background: %s;
                border: 1px solid rgba(%d, %d, %d, 0.15);
                border-radius: 8px;
                margin: 6px 0;
                padding: 12px 16px;
                transition: all 0.2s ease;
            }
            .port-forward-list row:hover {
                background: %s;
                border-color: rgba(%d, %d, %d, 0.3);
                transform: translateX(2px);
            }
            .port-forward-label {
                font-size: 13px;
                font-weight: 500;
                color: %s;
            }
            .port-forward-sublabel {
                font-size: 10px;
                color: %s;
                font-family: monospace;
            }
            .port-forward-status-icon {
                font-size: 12px;
                min-width: 16px;
                text-align: center;
            }
            .status-pending {
                color: %s;
            }
            .status-sent {
                color: #fbbf24;
            }
            .status-active {
                color: #4ade80;
            }
            .status-failed {
                color: #ef4444;
            }
            .port-forward-delete {
                min-width: 28px;
                min-height: 28px;
                padding: 4px;
                background: transparent;
                color: %s;
                border: none;
                border-radius: 6px;
                transition: all 0.2s ease;
            }
            .port-forward-delete:hover {
                background: rgba(239, 68, 68, 0.2);
                color: #ef4444;
                transform: scale(1.1);
            }
            .port-forward-tip-title {
                font-size: 11px;
                font-weight: bold;
                color: %s;
            }
            .port-forward-tip {
                font-size: 10px;
                color: %s;
                margin-top: 2px;
            }
            .port-forward-tip-code {
                font-size: 10px;
                font-family: monospace;
                color: %s;
                background: rgba(%d, %d, %d, 0.1);
                padding: 8px 10px;
                border-radius: 6px;
                margin-top: 4px;
                border: 1px solid rgba(%d, %d, %d, 0.2);
            }
        """.printf(
            panel_bg,
            fg_hex,
            fg_hex,
            fg_subdued,
            fg_subdued,
            btn_bg,
            fg_subdued,
            fg_hex, btn_bg,
            btn_bg, fg_hex, fg_hex,
            btn_hover_bg,
            btn_active_bg,
            btn_bg,
            (int)(fg_color.red * 255), (int)(fg_color.green * 255), (int)(fg_color.blue * 255),
            btn_hover_bg,
            (int)(fg_color.red * 255), (int)(fg_color.green * 255), (int)(fg_color.blue * 255),
            fg_hex,
            fg_subdued,
            fg_subdued,
            fg_subdued,
            fg_subdued,
            fg_subdued,
            fg_hex,
            (int)(fg_color.red * 255), (int)(fg_color.green * 255), (int)(fg_color.blue * 255),
            (int)(fg_color.red * 255), (int)(fg_color.green * 255), (int)(fg_color.blue * 255)
        );
        
        provider.load_from_string(css);
        StyleHelper.add_provider_for_display(Gdk.Display.get_default(), provider, 
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        
        add_css_class("port-forward-panel");
    }

    public void toggle_expand() {
        is_expanded = !is_expanded;
        content_box.set_visible(is_expanded);
        set_size_request(is_expanded ? 300 : 40, -1);
    }
}

public enum ForwardStatus {
    PENDING,    // Not yet sent (SSH not connected)
    SENT,       // Command sent, waiting for confirmation
    ACTIVE,     // Port is actively listening (verified)
    FAILED      // Failed to forward
}

private class ForwardEntry {
    public string alias;
    public bool is_local;
    public string local_port;
    public string remote_host;
    public string remote_port;
    public bool enabled;
    public ForwardStatus status;
    public Gtk.Label? status_label;
    
    public ForwardEntry(string a, bool local, string lport, string rhost, string rport) {
        alias = a;
        is_local = local;
        local_port = lport;
        remote_host = rhost;
        remote_port = rport;
        enabled = true;
        status = ForwardStatus.PENDING;
        status_label = null;
    }
    
    public void update_status(ForwardStatus new_status) {
        status = new_status;
        if (status_label != null) {
            switch (status) {
                case ForwardStatus.PENDING:
                    status_label.set_text("○");
                    status_label.set_tooltip_text("Pending - SSH not connected");
                    status_label.remove_css_class("status-active");
                    status_label.remove_css_class("status-sent");
                    status_label.remove_css_class("status-failed");
                    status_label.add_css_class("status-pending");
                    break;
                case ForwardStatus.SENT:
                    status_label.set_text("◐");
                    status_label.set_tooltip_text("Command sent - Establishing connection");
                    status_label.remove_css_class("status-active");
                    status_label.remove_css_class("status-pending");
                    status_label.remove_css_class("status-failed");
                    status_label.add_css_class("status-sent");
                    break;
                case ForwardStatus.ACTIVE:
                    status_label.set_text("●");
                    status_label.set_tooltip_text("Active - Port forwarding established");
                    status_label.remove_css_class("status-pending");
                    status_label.remove_css_class("status-sent");
                    status_label.remove_css_class("status-failed");
                    status_label.add_css_class("status-active");
                    break;
                case ForwardStatus.FAILED:
                    status_label.set_text("✕");
                    status_label.set_tooltip_text("Failed - Connection could not be established");
                    status_label.remove_css_class("status-active");
                    status_label.remove_css_class("status-sent");
                    status_label.remove_css_class("status-pending");
                    status_label.add_css_class("status-failed");
                    break;
            }
        }
    }
}
