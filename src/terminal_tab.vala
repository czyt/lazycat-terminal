// Terminal Tab - Wrapper for VTE terminal widget

public class TerminalTab : Gtk.Box {
    private Vte.Terminal terminal;
    public string tab_title { get; private set; }

    public signal void title_changed(string title);
    public signal void close_requested();

    public TerminalTab(string title) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        tab_title = title;
    }

    construct {
        setup_terminal();
        spawn_shell();
    }

    private void setup_terminal() {
        terminal = new Vte.Terminal();

        // Terminal appearance
        terminal.set_scrollback_lines(10000);
        terminal.set_scroll_on_output(false);
        terminal.set_scroll_on_keystroke(true);

        // Transparency
        var bg = Gdk.RGBA();
        bg.parse("rgba(30, 30, 30, 0.0)");
        terminal.set_color_background(bg);

        var fg = Gdk.RGBA();
        fg.parse("#ffffff");
        terminal.set_color_foreground(fg);

        // Set font
        var font = Pango.FontDescription.from_string("Monospace 11");
        terminal.set_font(font);

        terminal.set_vexpand(true);
        terminal.set_hexpand(true);

        // Connect signals
        terminal.window_title_changed.connect(() => {
            var title = terminal.get_window_title();
            if (title != null && title.length > 0) {
                tab_title = title;
                title_changed(title);
            }
        });

        terminal.child_exited.connect(() => {
            close_requested();
        });

        // Scrollbar
        var scrolled = new Gtk.ScrolledWindow();
        scrolled.set_child(terminal);
        scrolled.set_vexpand(true);
        scrolled.set_hexpand(true);
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);

        append(scrolled);
    }

    private void spawn_shell() {
        string? shell = Environment.get_variable("SHELL");
        if (shell == null) {
            shell = "/bin/bash";
        }

        string[] argv = { shell };
        string[]? envv = Environ.get();

        terminal.spawn_async(
            Vte.PtyFlags.DEFAULT,
            Environment.get_current_dir(),
            argv,
            envv,
            0,  // GLib.SpawnFlags
            null,
            -1,
            null,
            null
        );
    }

    public new void grab_focus() {
        terminal.grab_focus();
    }
}
