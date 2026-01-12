// Port Forward Panel - SSH port forwarding management UI

public class PortForwardPanel : Gtk.Box {
    private Gtk.Box content_box;
    private Gtk.Button toggle_button;
    private Gtk.ListBox forward_list;
    private bool is_expanded = true;
    private Vte.Terminal terminal;
    private HashTable<string, ForwardEntry> forwards;
    private Gdk.RGBA fg_color;
    private Gdk.RGBA bg_color;
    private double opacity;

    public signal void close_requested();

    public PortForwardPanel(Vte.Terminal term, Gdk.RGBA foreground, Gdk.RGBA background, double bg_opacity) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        terminal = term;
        fg_color = foreground;
        bg_color = background;
        opacity = bg_opacity;
        forwards = new HashTable<string, ForwardEntry>(str_hash, str_equal);

        setup_ui();
        load_saved_forwards();
    }

    private void setup_ui() {
        set_size_request(300, -1);
        set_hexpand(false);
        set_vexpand(true);

        // Content box
        content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
        content_box.set_margin_start(8);
        content_box.set_margin_end(8);
        content_box.set_margin_top(8);
        content_box.set_margin_bottom(8);

        // Header
        var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        var title = new Gtk.Label("SSH Port Forward");
        title.set_halign(Gtk.Align.START);
        title.add_css_class("port-forward-title");
        
        var close_btn = new Gtk.Button.with_label("×");
        close_btn.add_css_class("port-forward-close");
        close_btn.clicked.connect(() => close_requested());
        
        header.append(title);
        header.append(close_btn);
        content_box.append(header);

        // Add buttons
        var add_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
        var local_btn = new Gtk.Button.with_label("Local→Remote");
        var remote_btn = new Gtk.Button.with_label("Remote→Local");
        local_btn.clicked.connect(() => show_add_dialog(true));
        remote_btn.clicked.connect(() => show_add_dialog(false));
        add_box.append(local_btn);
        add_box.append(remote_btn);
        add_box.set_homogeneous(true);
        content_box.append(add_box);

        // Forward list
        var scroll = new Gtk.ScrolledWindow();
        scroll.set_vexpand(true);
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        
        forward_list = new Gtk.ListBox();
        forward_list.add_css_class("port-forward-list");
        scroll.set_child(forward_list);
        content_box.append(scroll);

        append(content_box);
        apply_style();
    }

    private void show_add_dialog(bool is_local) {
        var dialog = new Gtk.Window();
        dialog.set_transient_for((Gtk.Window)get_root());
        dialog.set_modal(true);
        dialog.set_title(is_local ? "Local Port Forward" : "Remote Port Forward");
        dialog.set_default_size(350, 200);

        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        box.set_margin_start(16);
        box.set_margin_end(16);
        box.set_margin_top(16);
        box.set_margin_bottom(16);

        var alias_entry = new Gtk.Entry();
        alias_entry.set_placeholder_text("Alias (optional)");
        
        var local_port_entry = new Gtk.Entry();
        local_port_entry.set_placeholder_text(is_local ? "Local Port" : "Remote Port");
        
        var remote_host_entry = new Gtk.Entry();
        remote_host_entry.set_placeholder_text("Target Host");
        remote_host_entry.set_text("localhost");
        
        var remote_port_entry = new Gtk.Entry();
        remote_port_entry.set_placeholder_text(is_local ? "Remote Port" : "Local Port");

        box.append(alias_entry);
        box.append(local_port_entry);
        box.append(remote_host_entry);
        box.append(remote_port_entry);

        var btn_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        btn_box.set_halign(Gtk.Align.END);
        
        var cancel_btn = new Gtk.Button.with_label("Cancel");
        var add_btn = new Gtk.Button.with_label("Add");
        add_btn.add_css_class("suggested-action");
        
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

    private void add_forward(string alias, bool is_local, string local_port, string remote_host, string remote_port) {
        string id = "%s:%s:%s:%s".printf(is_local ? "L" : "R", local_port, remote_host, remote_port);
        
        if (forwards.contains(id)) return;

        var entry = new ForwardEntry(alias, is_local, local_port, remote_host, remote_port);
        forwards.set(id, entry);
        
        var row = create_forward_row(id, entry);
        forward_list.append(row);
        
        if (entry.enabled) {
            apply_forward(entry);
        }
        
        save_forwards();
    }

    private Gtk.Box create_forward_row(string id, ForwardEntry entry) {
        var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        row.set_margin_start(4);
        row.set_margin_end(4);
        row.set_margin_top(4);
        row.set_margin_bottom(4);

        var info_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        var label = new Gtk.Label(entry.alias.length > 0 ? entry.alias : 
            (entry.is_local ? "L:%s→%s:%s".printf(entry.local_port, entry.remote_host, entry.remote_port) :
                             "R:%s←%s:%s".printf(entry.local_port, entry.remote_host, entry.remote_port)));
        label.set_halign(Gtk.Align.START);
        label.add_css_class("port-forward-label");
        info_box.append(label);
        
        var toggle = new Gtk.Switch();
        toggle.set_active(entry.enabled);
        toggle.set_valign(Gtk.Align.CENTER);
        toggle.notify["active"].connect(() => {
            entry.enabled = toggle.get_active();
            if (entry.enabled) {
                apply_forward(entry);
            } else {
                remove_forward(entry);
            }
            save_forwards();
        });
        
        var del_btn = new Gtk.Button.with_label("×");
        del_btn.add_css_class("port-forward-delete");
        del_btn.clicked.connect(() => {
            if (entry.enabled) remove_forward(entry);
            forwards.remove(id);
            forward_list.remove(row);
            save_forwards();
        });

        row.append(info_box);
        row.append(toggle);
        row.append(del_btn);
        info_box.set_hexpand(true);
        
        return row;
    }

    private void apply_forward(ForwardEntry entry) {
        string cmd;
        if (entry.is_local) {
            cmd = "-L %s:%s:%s".printf(entry.local_port, entry.remote_host, entry.remote_port);
        } else {
            cmd = "-R %s:%s:%s".printf(entry.local_port, entry.remote_host, entry.remote_port);
        }
        
        // Send SSH escape sequence: Enter, ~, C, then command
        // \r = Enter, ~ = tilde, C = capital C
        string sequence = "\r~C" + cmd + "\r";
        terminal.feed_child(sequence.data);
    }

    private void remove_forward(ForwardEntry entry) {
        string cmd;
        if (entry.is_local) {
            cmd = "-KL %s".printf(entry.local_port);
        } else {
            cmd = "-KR %s".printf(entry.local_port);
        }
        
        string sequence = "\r~C" + cmd + "\r";
        terminal.feed_child(sequence.data);
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
        } catch (Error e) {
            // File doesn't exist or parse error, ignore
        }
    }

    private void apply_style() {
        var provider = new Gtk.CssProvider();
        double panel_opacity = double.min(1.0, opacity + 0.15);
        
        int r = (int)(bg_color.red * 255);
        int g = (int)(bg_color.green * 255);
        int b = (int)(bg_color.blue * 255);
        
        string fg_hex = "#%02x%02x%02x".printf(
            (int)(fg_color.red * 255),
            (int)(fg_color.green * 255),
            (int)(fg_color.blue * 255)
        );
        
        string css = """
            .port-forward-title {
                font-weight: bold;
                font-size: 14px;
                color: %s;
            }
            .port-forward-close {
                min-width: 24px;
                min-height: 24px;
                padding: 0;
                font-size: 20px;
            }
            .port-forward-list {
                background: transparent;
            }
            .port-forward-label {
                font-size: 12px;
                color: %s;
            }
            .port-forward-delete {
                min-width: 24px;
                min-height: 24px;
                padding: 0;
                font-size: 16px;
            }
        """.printf(fg_hex, fg_hex);
        
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

private class ForwardEntry {
    public string alias;
    public bool is_local;
    public string local_port;
    public string remote_host;
    public string remote_port;
    public bool enabled;
    
    public ForwardEntry(string a, bool local, string lport, string rhost, string rport) {
        alias = a;
        is_local = local;
        local_port = lport;
        remote_host = rhost;
        remote_port = rport;
        enabled = true;
    }
}
