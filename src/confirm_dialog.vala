// Confirmation dialog as an overlay widget (centered in parent)

public class ConfirmDialog : Gtk.Widget {
    private Gtk.Box shadow_container;
    private Gtk.Box main_box;
    private Gtk.Box overlay_bg;
    private Gtk.Label message_label;
    private Gtk.Button confirm_button;
    private Gtk.DrawingArea close_button;
    private Gdk.RGBA foreground_color;
    private Gdk.RGBA background_color;
    private double background_opacity = 0.95;
    private Gtk.CssProvider? css_provider = null;

    // Close button state
    private bool close_button_hover = false;
    private bool close_button_pressed = false;

    // Shadow parameters
    private const int SHADOW_SIZE = 12;
    private const int CLOSE_BTN_SIZE = 12;
    private const int DIALOG_WIDTH = 320;
    private const int DIALOG_HEIGHT = 130;

    public signal void confirmed();
    public signal void closed();

    public ConfirmDialog(string message, Gdk.RGBA fg_color, Gdk.RGBA bg_color) {
        foreground_color = fg_color;
        background_color = bg_color;

        // Set layout manager
        set_layout_manager(new Gtk.BinLayout());

        // Enable focus
        set_can_focus(true);
        set_focusable(true);

        setup_layout(message);
        load_css();

        // Grab focus when mapped
        map.connect(() => {
            overlay_bg.grab_focus();
            focus_confirm_button();
        });
    }

    static construct {
        set_css_name("confirm-dialog-widget");
    }

    private void load_css() {
        bool first_time = (css_provider == null);
        if (first_time) {
            css_provider = new Gtk.CssProvider();
        }

        string fg_hex = rgba_to_hex(foreground_color);

        int bg_r = (int)(background_color.red * 255);
        int bg_g = (int)(background_color.green * 255);
        int bg_b = (int)(background_color.blue * 255);

        string css = """
            .confirm-dialog-overlay {
                background-color: rgba(0, 0, 0, 0.3);
            }

            .confirm-shadow-container {
                background-color: transparent;
                box-shadow: 0px 4px 12px rgba(0, 0, 0, 0.35);
                border-radius: 8px;
            }

            .confirm-dialog {
                background-color: rgba(""" + bg_r.to_string() + """, """ + bg_g.to_string() + """, """ + bg_b.to_string() + """, """ + background_opacity.to_string() + """);
                border-radius: 8px;
                border: 1px solid """ + fg_hex + """;
            }

            .confirm-message {
                color: """ + fg_hex + """;
                font-size: 14px;
                padding: 5px 15px 10px 15px;
            }

            .confirm-button {
                background-color: transparent;
                background-image: none;
                color: """ + fg_hex + """;
                border: 1px solid """ + fg_hex + """;
                border-radius: 4px;
                padding: 6px 12px;
                min-width: 80px;
                outline: none;
                box-shadow: none;
            }

            .confirm-button:focus {
                background-color: transparent;
                background-image: none;
                border: 1px solid """ + fg_hex + """;
                outline: none;
                box-shadow: none;
            }

            .confirm-button:hover {
                background-color: rgba(""" +
                    (foreground_color.red * 255).to_string() + """, """ +
                    (foreground_color.green * 255).to_string() + """, """ +
                    (foreground_color.blue * 255).to_string() + """, 0.2);
                background-image: none;
            }

            .confirm-button:active {
                background-color: rgba(""" +
                    (foreground_color.red * 255).to_string() + """, """ +
                    (foreground_color.green * 255).to_string() + """, """ +
                    (foreground_color.blue * 255).to_string() + """, 0.3);
                background-image: none;
            }
        """;

        css_provider.load_from_string(css);

        if (first_time) {
            StyleHelper.add_provider_for_display(
                Gdk.Display.get_default(),
                css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }
    }

    private string rgba_to_hex(Gdk.RGBA color) {
        return "#%02x%02x%02x".printf(
            (int)(color.red * 255),
            (int)(color.green * 255),
            (int)(color.blue * 255)
        );
    }

    private void setup_layout(string message) {
        // Outer container for dark overlay background - fills entire parent
        overlay_bg = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        overlay_bg.add_css_class("confirm-dialog-overlay");
        overlay_bg.set_hexpand(true);
        overlay_bg.set_vexpand(true);
        overlay_bg.set_can_focus(true);
        overlay_bg.set_focusable(true);

        // Center container
        var center_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        center_box.set_halign(Gtk.Align.CENTER);
        center_box.set_valign(Gtk.Align.CENTER);
        center_box.set_hexpand(true);
        center_box.set_vexpand(true);

        // Shadow container with fixed size
        shadow_container = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        shadow_container.add_css_class("confirm-shadow-container");
        shadow_container.set_size_request(DIALOG_WIDTH + SHADOW_SIZE * 2, DIALOG_HEIGHT + SHADOW_SIZE * 2);
        shadow_container.set_margin_start(SHADOW_SIZE);
        shadow_container.set_margin_end(SHADOW_SIZE);
        shadow_container.set_margin_top(SHADOW_SIZE);
        shadow_container.set_margin_bottom(SHADOW_SIZE);

        // Create overlay for floating close button
        var overlay = new Gtk.Overlay();

        main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        main_box.add_css_class("confirm-dialog");

        // Message label
        message_label = new Gtk.Label(message);
        message_label.add_css_class("confirm-message");
        message_label.set_wrap(true);
        message_label.set_justify(Gtk.Justification.CENTER);
        message_label.set_vexpand(true);
        message_label.set_valign(Gtk.Align.CENTER);
        message_label.set_margin_top(15);

        // Button box
        var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
        button_box.set_halign(Gtk.Align.CENTER);
        button_box.set_margin_bottom(17);

        confirm_button = new Gtk.Button.with_label("Confirm");
        confirm_button.add_css_class("confirm-button");
        confirm_button.clicked.connect(() => {
            confirmed();
            close_dialog();
        });

        button_box.append(confirm_button);

        main_box.append(message_label);
        main_box.append(button_box);

        // Set main_box as overlay base
        overlay.set_child(main_box);

        // Close button (DrawingArea for custom drawing) - floats on top
        close_button = new Gtk.DrawingArea();
        close_button.set_size_request(CLOSE_BTN_SIZE * 2 + 10, CLOSE_BTN_SIZE * 2 + 10);
        close_button.set_valign(Gtk.Align.START);
        close_button.set_halign(Gtk.Align.END);
        close_button.set_margin_top(8);
        close_button.set_margin_end(8);
        close_button.set_draw_func(draw_close_button);

        // Setup close button interactions
        setup_close_button_interactions();

        // Add close button as overlay
        overlay.add_overlay(close_button);

        shadow_container.append(overlay);
        center_box.append(shadow_container);
        overlay_bg.append(center_box);

        // Set as child
        overlay_bg.set_parent(this);

        // Setup keyboard shortcuts
        setup_keyboard_shortcuts();

        // Click on background to close
        setup_background_click(overlay_bg);
    }

    private void setup_background_click(Gtk.Widget bg) {
        var click_gesture = new Gtk.GestureClick();
        click_gesture.set_button(1);
        click_gesture.pressed.connect((n_press, x, y) => {
            // Only close if clicked outside the dialog
            Graphene.Point point = Graphene.Point();
            point.x = (float)x;
            point.y = (float)y;

            // Check if click is on shadow_container
            Graphene.Point local;
            if (!shadow_container.compute_point(bg, point, out local)) {
                close_dialog();
            } else {
                // Check if point is outside shadow_container bounds
                int w = shadow_container.get_width();
                int h = shadow_container.get_height();
                if (local.x < 0 || local.y < 0 || local.x > w || local.y > h) {
                    close_dialog();
                }
            }
        });
        bg.add_controller(click_gesture);
    }

    private void draw_close_button(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        double center_x = width / 2.0;
        double center_y = height / 2.0;

        cr.set_source_rgba(
            foreground_color.red,
            foreground_color.green,
            foreground_color.blue,
            1.0
        );
        cr.set_line_width(1.0);
        cr.set_antialias(Cairo.Antialias.NONE);

        double offset = (CLOSE_BTN_SIZE - 3) / 2.0;
        cr.move_to(center_x - offset, center_y - offset);
        cr.line_to(center_x + offset, center_y + offset);
        cr.stroke();
        cr.move_to(center_x + offset, center_y - offset);
        cr.line_to(center_x - offset, center_y + offset);
        cr.stroke();
    }

    private void setup_close_button_interactions() {
        var motion_controller = new Gtk.EventControllerMotion();
        motion_controller.enter.connect(() => {
            close_button_hover = true;
            close_button.queue_draw();
        });
        motion_controller.leave.connect(() => {
            close_button_hover = false;
            close_button_pressed = false;
            close_button.queue_draw();
        });
        close_button.add_controller(motion_controller);

        var click_gesture = new Gtk.GestureClick();
        click_gesture.set_button(1);
        click_gesture.pressed.connect(() => {
            close_button_pressed = true;
            close_button.queue_draw();
        });
        click_gesture.released.connect(() => {
            if (close_button_pressed) {
                close_dialog();
            }
            close_button_pressed = false;
            close_button.queue_draw();
        });
        close_button.add_controller(click_gesture);
    }

    private void setup_keyboard_shortcuts() {
        var controller = new Gtk.EventControllerKey();
        controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);

        controller.key_pressed.connect((keyval, keycode, state) => {
            if (keyval == Gdk.Key.Escape) {
                close_dialog();
                return true;
            }
            if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                confirmed();
                close_dialog();
                return true;
            }
            return false;
        });

        ((Gtk.Widget)overlay_bg).add_controller(controller);
    }

    private void close_dialog() {
        closed();
    }

    // Public method to handle key events from parent window
    public bool handle_key_press(uint keyval, uint keycode, Gdk.ModifierType state) {
        if (keyval == Gdk.Key.Escape) {
            close_dialog();
            return true;
        }
        if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
            confirmed();
            close_dialog();
            return true;
        }
        return false;
    }

    public void focus_confirm_button() {
        confirm_button.grab_focus();
    }

    protected override void dispose() {
        // Unparent all children
        var child = get_first_child();
        while (child != null) {
            var next = child.get_next_sibling();
            child.unparent();
            child = next;
        }
        base.dispose();
    }
}
