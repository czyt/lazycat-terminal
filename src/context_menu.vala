public class ContextMenuItemSpec : Object {
    public string id;
    public string label;
    public bool enabled;
    public bool separator;

    public ContextMenuItemSpec() {
        id = "";
        label = "";
        enabled = true;
        separator = false;
    }

    public static ContextMenuItemSpec action(string id, string label, bool enabled = true) {
        var item = new ContextMenuItemSpec();
        item.id = id;
        item.label = label;
        item.enabled = enabled;
        return item;
    }

    public static ContextMenuItemSpec divider() {
        var item = new ContextMenuItemSpec();
        item.separator = true;
        item.enabled = false;
        return item;
    }
}

public class ContextMenuOverlay : Gtk.Widget {
    private Gtk.Overlay root_overlay;
    private Gtk.Box backdrop;
    private Gtk.Fixed menu_layer;
    private Gtk.Overlay menu_panel;
    private ContextMenuPanelWidget panel_background;
    private Gtk.Box item_box;
    private Gdk.RGBA foreground_color;
    private Gdk.RGBA background_color;
    private double panel_opacity;
    private int anchor_x;
    private int anchor_y;
    private int menu_width;
    private int panel_height;
    private bool is_closed = false;
    private bool is_positioned = false;
    private int outer_menu_x = 0;
    private int outer_menu_y = 0;
    private int outer_menu_width = 0;
    private int outer_menu_height = 0;
    private uint position_idle_id = 0;

    private const int PANEL_PADDING = 6;
    private const int SHADOW_MARGIN = 10;
    public const int DEFAULT_MENU_WIDTH = 236;

    public signal void closed();
    public signal void item_activated(string id);

    public ContextMenuOverlay(ContextMenuItemSpec[] items,
                              Gdk.RGBA fg_color,
                              Gdk.RGBA bg_color,
                              double opacity,
                              int anchor_x,
                              int anchor_y,
                              int menu_width = DEFAULT_MENU_WIDTH) {
        foreground_color = fg_color;
        background_color = bg_color;
        panel_opacity = opacity;
        this.anchor_x = anchor_x;
        this.anchor_y = anchor_y;
        this.menu_width = menu_width;

        set_layout_manager(new Gtk.BinLayout());
        set_hexpand(true);
        set_vexpand(true);
        set_halign(Gtk.Align.FILL);
        set_valign(Gtk.Align.FILL);
        set_can_focus(true);
        set_focusable(true);

        setup_layout(items);
        update_theme(fg_color, bg_color, opacity);

        map.connect(() => {
            schedule_position_menu();
            grab_focus();
        });

        notify["width"].connect(() => {
            schedule_position_menu();
        });
        notify["height"].connect(() => {
            schedule_position_menu();
        });
    }

    static construct {
        set_css_name("context-menu-widget");
    }

    public bool handle_key_press(uint keyval, uint keycode, Gdk.ModifierType state) {
        if (keyval == Gdk.Key.Escape) {
            close_menu();
        }

        return true;
    }

    public void close_menu() {
        if (is_closed) {
            return;
        }

        is_closed = true;
        if (position_idle_id != 0) {
            Source.remove(position_idle_id);
            position_idle_id = 0;
        }
        closed();
    }

    private void schedule_position_menu() {
        if (is_closed || position_idle_id != 0) {
            return;
        }

        position_idle_id = Idle.add(() => {
            position_idle_id = 0;

            if (!is_closed) {
                position_menu();
            }

            return false;
        });
    }

    public void update_theme(Gdk.RGBA fg_color, Gdk.RGBA bg_color, double opacity) {
        foreground_color = fg_color;
        background_color = bg_color;
        panel_opacity = opacity;

        panel_background.update_theme(fg_color, bg_color, opacity);

        Gtk.Widget? child = item_box.get_first_child();
        while (child != null) {
            if (child is ContextMenuItemWidget) {
                ((ContextMenuItemWidget)child).update_theme(fg_color, bg_color);
            } else if (child is ContextMenuSeparatorWidget) {
                ((ContextMenuSeparatorWidget)child).update_theme(fg_color, bg_color);
            }
            child = child.get_next_sibling();
        }
    }

    private void setup_layout(ContextMenuItemSpec[] items) {
        root_overlay = new Gtk.Overlay();
        root_overlay.set_hexpand(true);
        root_overlay.set_vexpand(true);

        backdrop = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        backdrop.set_hexpand(true);
        backdrop.set_vexpand(true);
        root_overlay.set_child(backdrop);

        menu_layer = new Gtk.Fixed();
        menu_layer.set_hexpand(true);
        menu_layer.set_vexpand(true);
        root_overlay.add_overlay(menu_layer);

        panel_height = calculate_panel_height(items);

        menu_panel = new Gtk.Overlay();
        menu_panel.set_halign(Gtk.Align.START);
        menu_panel.set_valign(Gtk.Align.START);
        menu_panel.set_visible(false);

        panel_background = new ContextMenuPanelWidget(
            menu_width,
            panel_height,
            SHADOW_MARGIN
        );
        menu_panel.set_child(panel_background);

        item_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        item_box.set_margin_start(SHADOW_MARGIN + PANEL_PADDING);
        item_box.set_margin_end(SHADOW_MARGIN + PANEL_PADDING);
        item_box.set_margin_top(SHADOW_MARGIN + PANEL_PADDING);
        item_box.set_margin_bottom(SHADOW_MARGIN + PANEL_PADDING);

        int item_width = menu_width - PANEL_PADDING * 2;
        foreach (var item in items) {
            if (item.separator) {
                var separator = new ContextMenuSeparatorWidget(item_width);
                item_box.append(separator);
            } else {
                var entry = new ContextMenuItemWidget(item, item_width);
                entry.activated.connect((id) => {
                    close_menu();
                    item_activated(id);
                });
                item_box.append(entry);
            }
        }

        menu_panel.add_overlay(item_box);
        menu_layer.put(menu_panel, 0, 0);

        root_overlay.set_parent(this);

        var key_controller = new Gtk.EventControllerKey();
        key_controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        key_controller.key_pressed.connect(handle_key_press);
        add_controller(key_controller);

        var dismiss_click = new Gtk.GestureClick();
        dismiss_click.set_button(0);
        dismiss_click.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        dismiss_click.pressed.connect((n_press, x, y) => {
            if (is_positioned && !is_inside_menu_bounds(x, y)) {
                dismiss_click.set_state(Gtk.EventSequenceState.CLAIMED);
                close_menu();
            }
        });
        add_controller(dismiss_click);
    }

    private int calculate_panel_height(ContextMenuItemSpec[] items) {
        int content_height = PANEL_PADDING * 2;

        foreach (var item in items) {
            if (item.separator) {
                content_height += ContextMenuSeparatorWidget.HEIGHT;
            } else {
                content_height += ContextMenuItemWidget.HEIGHT;
            }
        }

        return content_height;
    }

    private void position_menu() {
        int outer_width = menu_width + SHADOW_MARGIN * 2;
        int outer_height = panel_height + SHADOW_MARGIN * 2;

        int available_width = int.max(get_width(), root_overlay.get_width());
        int available_height = int.max(get_height(), root_overlay.get_height());
        var parent = get_parent();
        if (parent != null) {
            available_width = int.max(available_width, parent.get_width());
            available_height = int.max(available_height, parent.get_height());
        }

        if (available_width <= 0 || available_height <= 0) {
            is_positioned = false;
            schedule_position_menu();
            return;
        }

        int max_x = int.max(0, available_width - outer_width);
        int max_y = int.max(0, available_height - outer_height);

        // Align the visible panel with the click position. When the menu would
        // overflow, move it back by the smallest distance needed to keep the
        // full menu, including shadow, inside the overlay.
        int final_x = int.max(0, int.min(anchor_x - SHADOW_MARGIN, max_x));
        int final_y = int.max(0, int.min(anchor_y - SHADOW_MARGIN, max_y));

        outer_menu_x = final_x;
        outer_menu_y = final_y;
        outer_menu_width = outer_width;
        outer_menu_height = outer_height;
        is_positioned = true;

        menu_layer.move(menu_panel, final_x, final_y);
        menu_panel.set_visible(true);
    }

    private bool is_inside_menu_bounds(double x, double y) {
        return x >= outer_menu_x &&
               x <= outer_menu_x + outer_menu_width &&
               y >= outer_menu_y &&
               y <= outer_menu_y + outer_menu_height;
    }
}

private class ContextMenuPanelWidget : Gtk.DrawingArea {
    private Gdk.RGBA foreground_color;
    private Gdk.RGBA background_color;
    private double panel_opacity = 0.95;
    private int panel_width;
    private int panel_height;
    private int shadow_margin;

    private const int CORNER_RADIUS = 10;

    public ContextMenuPanelWidget(int panel_width, int panel_height, int shadow_margin) {
        this.panel_width = panel_width;
        this.panel_height = panel_height;
        this.shadow_margin = shadow_margin;

        set_content_width(panel_width + shadow_margin * 2);
        set_content_height(panel_height + shadow_margin * 2);
        set_draw_func(draw_panel);
    }

    public void update_theme(Gdk.RGBA fg_color, Gdk.RGBA bg_color, double opacity) {
        foreground_color = fg_color;
        background_color = bg_color;
        panel_opacity = opacity;
        queue_draw();
    }

    private bool is_color_dark() {
        double brightness = (0.2126 * background_color.red) +
                            (0.7152 * background_color.green) +
                            (0.0722 * background_color.blue);
        return brightness < 0.5;
    }

    private void draw_rounded_rect(Cairo.Context cr, double x, double y, double width, double height, double radius) {
        cr.new_sub_path();
        cr.arc(x + width - radius, y + radius, radius, -Math.PI / 2, 0);
        cr.arc(x + width - radius, y + height - radius, radius, 0, Math.PI / 2);
        cr.arc(x + radius, y + height - radius, radius, Math.PI / 2, Math.PI);
        cr.arc(x + radius, y + radius, radius, Math.PI, 3 * Math.PI / 2);
        cr.close_path();
    }

    private void draw_panel(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        double panel_x = shadow_margin;
        double panel_y = shadow_margin;
        double shadow_alpha = is_color_dark() ? 0.18 : 0.11;

        for (int i = 3; i >= 1; i--) {
            double expand = i * 2;
            draw_rounded_rect(
                cr,
                panel_x - expand / 2.0,
                panel_y - expand / 2.0,
                panel_width + expand,
                panel_height + expand,
                CORNER_RADIUS + i
            );
            cr.set_source_rgba(0, 0, 0, shadow_alpha / (double)(i + 1));
            cr.fill();
        }

        draw_rounded_rect(cr, panel_x, panel_y, panel_width, panel_height, CORNER_RADIUS);
        cr.set_source_rgba(
            background_color.red,
            background_color.green,
            background_color.blue,
            panel_opacity
        );
        cr.fill_preserve();

        cr.set_source_rgba(
            foreground_color.red,
            foreground_color.green,
            foreground_color.blue,
            is_color_dark() ? 0.22 : 0.18
        );
        cr.set_line_width(1.0);
        cr.stroke();
    }
}

private class ContextMenuItemWidget : Gtk.DrawingArea {
    public const int HEIGHT = 32;

    private ContextMenuItemSpec item;
    private Gdk.RGBA foreground_color;
    private Gdk.RGBA background_color;
    private bool hovered = false;
    private bool pressed = false;

    public signal void activated(string id);

    public ContextMenuItemWidget(ContextMenuItemSpec item, int item_width) {
        this.item = item;

        set_content_width(item_width);
        set_content_height(HEIGHT);
        set_draw_func(draw_item);

        var motion = new Gtk.EventControllerMotion();
        motion.motion.connect(() => {
            if (!hovered) {
                hovered = true;
                queue_draw();
            }
        });
        motion.leave.connect(() => {
            if (hovered || pressed) {
                hovered = false;
                pressed = false;
                queue_draw();
            }
        });
        add_controller(motion);

        var click = new Gtk.GestureClick();
        click.set_button(1);
        click.pressed.connect((n_press, x, y) => {
            if (!item.enabled) {
                return;
            }

            pressed = true;
            queue_draw();
        });
        click.released.connect((n_press, x, y) => {
            bool should_activate = item.enabled &&
                                   pressed &&
                                   x >= 0 &&
                                   x <= get_width() &&
                                   y >= 0 &&
                                   y <= get_height();

            pressed = false;
            queue_draw();

            if (should_activate) {
                activated(item.id);
            }
        });
        add_controller(click);
    }

    public void update_theme(Gdk.RGBA fg_color, Gdk.RGBA bg_color) {
        foreground_color = fg_color;
        background_color = bg_color;
        queue_draw();
    }

    private void draw_rounded_rect(Cairo.Context cr, double x, double y, double width, double height, double radius) {
        cr.new_sub_path();
        cr.arc(x + width - radius, y + radius, radius, -Math.PI / 2, 0);
        cr.arc(x + width - radius, y + height - radius, radius, 0, Math.PI / 2);
        cr.arc(x + radius, y + height - radius, radius, Math.PI / 2, Math.PI);
        cr.arc(x + radius, y + radius, radius, Math.PI, 3 * Math.PI / 2);
        cr.close_path();
    }

    private void draw_item(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        if ((hovered || pressed) && item.enabled) {
            double alpha = pressed ? 0.24 : 0.15;
            draw_rounded_rect(cr, 0, 1, width, height - 2, 7);
            cr.set_source_rgba(
                foreground_color.red,
                foreground_color.green,
                foreground_color.blue,
                alpha
            );
            cr.fill();
        }

        var layout = create_pango_layout(item.label);
        var font_desc = Pango.FontDescription.from_string("Sans 12");
        layout.set_font_description(font_desc);
        layout.set_width((int)((width - 32) * Pango.SCALE));
        layout.set_ellipsize(Pango.EllipsizeMode.END);

        int text_width;
        int text_height;
        layout.get_pixel_size(out text_width, out text_height);

        double text_y = (height - text_height) / 2.0;
        double text_alpha = item.enabled ? 1.0 : 0.38;

        cr.set_source_rgba(
            foreground_color.red,
            foreground_color.green,
            foreground_color.blue,
            text_alpha
        );
        cr.move_to(14, text_y);
        Pango.cairo_show_layout(cr, layout);
    }
}

private class ContextMenuSeparatorWidget : Gtk.DrawingArea {
    public const int HEIGHT = 10;

    private Gdk.RGBA foreground_color;
    private Gdk.RGBA background_color;

    public ContextMenuSeparatorWidget(int item_width) {
        set_content_width(item_width);
        set_content_height(HEIGHT);
        set_draw_func(draw_separator);
    }

    public void update_theme(Gdk.RGBA fg_color, Gdk.RGBA bg_color) {
        foreground_color = fg_color;
        background_color = bg_color;
        queue_draw();
    }

    private bool is_color_dark() {
        double brightness = (0.2126 * background_color.red) +
                            (0.7152 * background_color.green) +
                            (0.0722 * background_color.blue);
        return brightness < 0.5;
    }

    private void draw_separator(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        double alpha = is_color_dark() ? 0.14 : 0.12;

        cr.set_source_rgba(
            foreground_color.red,
            foreground_color.green,
            foreground_color.blue,
            alpha
        );
        cr.set_line_width(1.0);
        cr.move_to(12, height / 2.0);
        cr.line_to(width - 12, height / 2.0);
        cr.stroke();
    }
}
