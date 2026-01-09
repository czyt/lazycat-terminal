// Terminal Window with transparent background and custom title bar

public class TerminalWindow : Gtk.ApplicationWindow {
    private TabBar tab_bar;
    private Gtk.Stack stack;
    private List<TerminalTab> tabs;
    private int tab_counter = 0;

    public TerminalWindow(Gtk.Application app) {
        Object(application: app);
    }

    construct {
        tabs = new List<TerminalTab>();
        setup_window();
        setup_layout();
        add_new_tab();
    }

    private void setup_window() {
        // Remove default title bar, use CSD
        set_decorated(false);
        set_default_size(900, 600);
        set_title("LazyCat Terminal");

        // Enable transparency
        setup_transparency();

        // Add CSS for styling
        load_css();
    }

    private void setup_transparency() {
        // Set visual for transparency
        var surface = get_surface();
        if (surface != null) {
            // GTK4 handles transparency differently
        }

        // Add CSS class for transparency
        add_css_class("transparent-window");
    }

    private void load_css() {
        var provider = new Gtk.CssProvider();
        provider.load_from_string("""
            .transparent-window {
                background-color: rgba(30, 30, 30, 0.75);
            }
            .tab-bar {
                background-color: rgba(40, 40, 40, 0.9);
                min-height: 38px;
            }
            .terminal-container {
                background-color: transparent;
            }
        """);

        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    private void setup_layout() {
        var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

        // Create tab bar
        tab_bar = new TabBar();
        tab_bar.add_css_class("tab-bar");
        tab_bar.tab_selected.connect(on_tab_selected);
        tab_bar.tab_closed.connect(on_tab_closed);
        tab_bar.new_tab_requested.connect(add_new_tab);

        // Create stack for terminal tabs
        stack = new Gtk.Stack();
        stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE);
        stack.set_vexpand(true);
        stack.set_hexpand(true);
        stack.add_css_class("terminal-container");

        main_box.append(tab_bar);
        main_box.append(stack);

        set_child(main_box);

        // Enable window dragging from tab bar
        setup_window_drag();
    }

    private void setup_window_drag() {
        // Window move gesture
        var drag = new Gtk.GestureDrag();
        drag.set_button(1);

        drag.drag_begin.connect((x, y) => {
            // Only drag from tab bar empty area
            if (!tab_bar.is_over_tab((int)x, (int)y)) {
                // Use native window drag
                var surface = get_surface() as Gdk.Toplevel;
                if (surface != null) {
                    var device = drag.get_device();
                    if (device != null) {
                        // Get timestamp from the last event
                        surface.begin_move(device, 0, x, y, Gdk.CURRENT_TIME);
                    }
                }
            }
        });

        tab_bar.add_controller(drag);

        // Double-click to maximize/restore
        var double_click = new Gtk.GestureClick();
        double_click.set_button(1);
        double_click.pressed.connect((n_press, x, y) => {
            if (n_press == 2 && !tab_bar.is_over_tab((int)x, (int)y)) {
                if (is_maximized()) {
                    unmaximize();
                } else {
                    maximize();
                }
            }
        });
        tab_bar.add_controller(double_click);

        // Keyboard shortcuts
        setup_keyboard_shortcuts();
    }

    private void setup_keyboard_shortcuts() {
        var controller = new Gtk.EventControllerKey();
        controller.key_pressed.connect((keyval, keycode, state) => {
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;

            if (ctrl && shift) {
                switch (keyval) {
                    case Gdk.Key.T:
                        add_new_tab();
                        return true;
                    case Gdk.Key.W:
                        if (tabs.length() > 0) {
                            var tab = tabs.nth_data((uint)tab_bar.get_active_index());
                            if (tab != null) close_tab(tab);
                        }
                        return true;
                    case Gdk.Key.Tab:
                        // Next tab
                        cycle_tab(1);
                        return true;
                    case Gdk.Key.ISO_Left_Tab:
                        // Previous tab
                        cycle_tab(-1);
                        return true;
                }
            } else if (ctrl) {
                // Ctrl+PageUp/PageDown for tab switching
                if (keyval == Gdk.Key.Page_Up) {
                    cycle_tab(-1);
                    return true;
                } else if (keyval == Gdk.Key.Page_Down) {
                    cycle_tab(1);
                    return true;
                }
            }

            return false;
        });
        ((Gtk.Widget)this).add_controller(controller);
    }

    private void cycle_tab(int direction) {
        int current = tab_bar.get_active_index();
        int count = (int)tabs.length();
        if (count <= 1) return;

        int next = (current + direction + count) % count;
        tab_bar.set_active_tab(next);
        on_tab_selected(next);
    }

    public void add_new_tab() {
        tab_counter++;
        var tab = new TerminalTab("Terminal " + tab_counter.to_string());

        tab.title_changed.connect((title) => {
            tab_bar.update_tab_title(tabs.index(tab), title);
        });

        tab.close_requested.connect(() => {
            close_tab(tab);
        });

        tabs.append(tab);
        stack.add_named(tab, "tab_" + tab_counter.to_string());
        tab_bar.add_tab("Terminal " + tab_counter.to_string());

        // Switch to new tab
        stack.set_visible_child(tab);
        tab_bar.set_active_tab((int)tabs.length() - 1);

        tab.grab_focus();
    }

    private void on_tab_selected(int index) {
        if (index >= 0 && index < tabs.length()) {
            var tab = tabs.nth_data((uint)index);
            stack.set_visible_child(tab);
            tab.grab_focus();
        }
    }

    private void on_tab_closed(int index) {
        if (index >= 0 && index < tabs.length()) {
            var tab = tabs.nth_data((uint)index);
            close_tab(tab);
        }
    }

    private void close_tab(TerminalTab tab) {
        int index = tabs.index(tab);
        if (index < 0) return;

        tabs.remove(tab);
        stack.remove(tab);
        tab_bar.remove_tab(index);

        if (tabs.length() == 0) {
            close();
        } else {
            int new_index = index >= tabs.length() ? (int)tabs.length() - 1 : index;
            on_tab_selected(new_index);
            tab_bar.set_active_tab(new_index);
        }
    }
}
