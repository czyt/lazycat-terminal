// KDE-style Window Shadow for GTK4
// This creates a transparent overlay window that draws shadows around the main content

// Window snap position enum
public enum WindowSnapPosition {
    NONE,           // Normal window, show all shadows
    MAXIMIZED,      // Maximized, no shadows
    LEFT,           // Snapped to left edge, shadow only on right
    RIGHT,          // Snapped to right edge, shadow only on left
    TOP_LEFT,       // Snapped to top-left corner, shadow on right and bottom
    TOP_RIGHT,      // Snapped to top-right corner, shadow on left and bottom
    BOTTOM_LEFT,    // Snapped to bottom-left corner, shadow on right and top
    BOTTOM_RIGHT    // Snapped to bottom-right corner, shadow on left and top
}

public class ShadowWindow : Gtk.ApplicationWindow {
    // Shadow parameters
    private const int SHADOW_SIZE = 40;
    private const double SHADOW_OPACITY_FOCUSED = 0.35;
    private const double SHADOW_OPACITY_UNFOCUSED = 0.18;

    // Child content
    private Gtk.Widget? content_widget = null;
    private Gtk.Overlay overlay;
    private Gtk.DrawingArea shadow_area;
    private Gtk.Box content_box;

    // State tracking
    private WindowSnapPosition snap_position = WindowSnapPosition.NONE;
    private bool is_focused = true;
    private int window_width = 0;
    private int window_height = 0;

    // Monitor info for snap detection
    private int monitor_width = 1920;
    private int monitor_height = 1080;

    public ShadowWindow(Gtk.Application app) {
        Object(application: app);
    }

    construct {
        setup_window();
        setup_layout();
        setup_state_tracking();
    }

    private void setup_window() {
        // Remove decorations for custom shadow
        set_decorated(false);
        set_default_size(900 + SHADOW_SIZE * 2, 600 + SHADOW_SIZE * 2);

        // Make window transparent
        add_css_class("shadow-window");

        // Load CSS for transparency
        var provider = new Gtk.CssProvider();
        provider.load_from_string("""
            .shadow-window {
                background-color: transparent;
            }
            .shadow-content {
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
        // Create overlay for shadow + content layering
        overlay = new Gtk.Overlay();

        // Shadow drawing area (bottom layer)
        shadow_area = new Gtk.DrawingArea();
        shadow_area.set_draw_func(on_draw_shadow);
        shadow_area.set_hexpand(true);
        shadow_area.set_vexpand(true);

        // Content box with margins for shadow space
        content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        content_box.add_css_class("shadow-content");
        content_box.set_hexpand(true);
        content_box.set_vexpand(true);
        update_content_margins();

        overlay.set_child(shadow_area);
        overlay.add_overlay(content_box);

        set_child(overlay);

        // Setup input region for click-through on shadow area
        setup_input_region();
    }

    private void update_content_margins() {
        int top = 0, bottom = 0, left = 0, right = 0;

        switch (snap_position) {
            case WindowSnapPosition.NONE:
                top = bottom = left = right = SHADOW_SIZE;
                break;
            case WindowSnapPosition.MAXIMIZED:
                top = bottom = left = right = 0;
                break;
            case WindowSnapPosition.LEFT:
                right = SHADOW_SIZE;
                break;
            case WindowSnapPosition.RIGHT:
                left = SHADOW_SIZE;
                break;
            case WindowSnapPosition.TOP_LEFT:
                right = SHADOW_SIZE;
                bottom = SHADOW_SIZE;
                break;
            case WindowSnapPosition.TOP_RIGHT:
                left = SHADOW_SIZE;
                bottom = SHADOW_SIZE;
                break;
            case WindowSnapPosition.BOTTOM_LEFT:
                right = SHADOW_SIZE;
                top = SHADOW_SIZE;
                break;
            case WindowSnapPosition.BOTTOM_RIGHT:
                left = SHADOW_SIZE;
                top = SHADOW_SIZE;
                break;
        }

        content_box.set_margin_top(top);
        content_box.set_margin_bottom(bottom);
        content_box.set_margin_start(left);
        content_box.set_margin_end(right);
    }

    private void setup_input_region() {
        // We need to update input region when window state changes
        // This makes clicks on shadow area pass through to windows below

        var surface = get_surface();
        if (surface != null) {
            surface.notify["state"].connect(on_surface_state_changed);
            surface.notify["width"].connect(on_surface_size_changed);
            surface.notify["height"].connect(on_surface_size_changed);
        }
    }

    private void on_surface_state_changed() {
        update_snap_position();
        update_input_region_for_current_state();
    }

    private void on_surface_size_changed() {
        update_snap_position();
        update_input_region_for_current_state();
    }

    private void update_input_region_for_current_state() {
        var surface = get_surface();
        if (surface == null) return;

        int width = get_width();
        int height = get_height();

        if (width <= 0 || height <= 0) return;

        // Get margins based on snap position
        int top = content_box.get_margin_top();
        int bottom = content_box.get_margin_bottom();
        int left = content_box.get_margin_start();
        int right = content_box.get_margin_end();

        // Create input region that covers only the content area (not shadows)
        var region = new Cairo.Region.rectangle({
            left, top,
            width - left - right,
            height - top - bottom
        });

        surface.set_input_region(region);
    }

    private void setup_state_tracking() {
        // Track focus changes
        notify["is-active"].connect(() => {
            bool new_focus = is_active;
            if (is_focused != new_focus) {
                is_focused = new_focus;
                shadow_area.queue_draw();
            }
        });

        // Track maximize state
        notify["maximized"].connect(() => {
            update_snap_position();
            update_content_margins();
            update_input_region_for_current_state();
            shadow_area.queue_draw();
        });

        // Setup frame clock for position tracking
        add_tick_callback((widget, clock) => {
            check_window_position();
            return true;
        });
    }

    private void check_window_position() {
        // In GTK4, we need to track window position through the surface
        var surface = get_surface();
        if (surface == null) return;

        // Get display and monitor info
        var display = Gdk.Display.get_default();
        if (display == null) return;

        var monitors = display.get_monitors();
        if (monitors.get_n_items() == 0) return;

        var monitor = (Gdk.Monitor)monitors.get_item(0);
        var geometry = monitor.get_geometry();
        monitor_width = geometry.width;
        monitor_height = geometry.height;

        // Store current dimensions
        window_width = get_width();
        window_height = get_height();

        // Update snap position based on size and position
        update_snap_position();
    }

    private void update_snap_position() {
        WindowSnapPosition new_position;

        if (is_maximized()) {
            new_position = WindowSnapPosition.MAXIMIZED;
        } else {
            // Detect snap position based on window size
            // When snapped, window typically takes half or quarter of screen
            bool half_width = (window_width > 0) &&
                              (window_width >= monitor_width / 2 - 50) &&
                              (window_width <= monitor_width / 2 + 50);
            bool full_height = (window_height > 0) &&
                               (window_height >= monitor_height - 100);
            bool half_height = (window_height > 0) &&
                               (window_height >= monitor_height / 2 - 50) &&
                               (window_height <= monitor_height / 2 + 50);

            // Use heuristics based on window size
            if (half_width && full_height) {
                // Left or right half snap - determine by checking actual position
                // For now, use a workaround based on window hints
                new_position = WindowSnapPosition.NONE; // Will be refined
            } else if (half_width && half_height) {
                // Corner snap
                new_position = WindowSnapPosition.NONE; // Will be refined
            } else {
                new_position = WindowSnapPosition.NONE;
            }
        }

        if (new_position != snap_position) {
            snap_position = new_position;
            update_content_margins();
            update_input_region_for_current_state();
            shadow_area.queue_draw();
        }
    }

    // Public method to set snap position manually (can be called from TerminalWindow)
    public void set_snap_position(WindowSnapPosition position) {
        if (snap_position != position) {
            snap_position = position;
            update_content_margins();
            update_input_region_for_current_state();
            shadow_area.queue_draw();
        }
    }

    public WindowSnapPosition get_snap_position() {
        return snap_position;
    }

    private void on_draw_shadow(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        // Don't draw shadow if maximized
        if (snap_position == WindowSnapPosition.MAXIMIZED) {
            return;
        }

        // Clear the drawing area
        cr.set_operator(Cairo.Operator.CLEAR);
        cr.paint();
        cr.set_operator(Cairo.Operator.OVER);

        // Get margins
        int top = content_box.get_margin_top();
        int bottom = content_box.get_margin_bottom();
        int left = content_box.get_margin_start();
        int right = content_box.get_margin_end();

        // Content area bounds
        int cx = left;
        int cy = top;
        int cw = width - left - right;
        int ch = height - top - bottom;

        if (cw <= 0 || ch <= 0) return;

        // Shadow opacity based on focus - KDE Breeze style
        double base_opacity = is_focused ? SHADOW_OPACITY_FOCUSED : SHADOW_OPACITY_UNFOCUSED;

        // Draw KDE Breeze-style shadow with smooth gaussian-like falloff
        draw_kde_shadow(cr, cx, cy, cw, ch, left, top, right, bottom, base_opacity);
    }

    private void draw_kde_shadow(Cairo.Context cr, int cx, int cy, int cw, int ch,
                                 int shadow_left, int shadow_top,
                                 int shadow_right, int shadow_bottom, double base_opacity) {
        // KDE Breeze uses a soft shadow with gaussian-like falloff
        // We simulate this with multiple gradient layers

        // Edge gradients with smooth gaussian-like curve
        // Top edge
        if (shadow_top > 0) {
            var pattern = new Cairo.Pattern.linear(0, cy - shadow_top, 0, cy);
            add_gaussian_stops(pattern, base_opacity, false);
            cr.set_source(pattern);
            cr.rectangle(cx, cy - shadow_top, cw, shadow_top);
            cr.fill();
        }

        // Bottom edge
        if (shadow_bottom > 0) {
            var pattern = new Cairo.Pattern.linear(0, cy + ch + shadow_bottom, 0, cy + ch);
            add_gaussian_stops(pattern, base_opacity, false);
            cr.set_source(pattern);
            cr.rectangle(cx, cy + ch, cw, shadow_bottom);
            cr.fill();
        }

        // Left edge
        if (shadow_left > 0) {
            var pattern = new Cairo.Pattern.linear(cx - shadow_left, 0, cx, 0);
            add_gaussian_stops(pattern, base_opacity, false);
            cr.set_source(pattern);
            cr.rectangle(cx - shadow_left, cy, shadow_left, ch);
            cr.fill();
        }

        // Right edge
        if (shadow_right > 0) {
            var pattern = new Cairo.Pattern.linear(cx + cw + shadow_right, 0, cx + cw, 0);
            add_gaussian_stops(pattern, base_opacity, false);
            cr.set_source(pattern);
            cr.rectangle(cx + cw, cy, shadow_right, ch);
            cr.fill();
        }

        // Corner shadows with radial gradients
        // Top-left corner
        if (shadow_left > 0 && shadow_top > 0) {
            draw_kde_corner(cr, cx, cy, shadow_left, shadow_top, base_opacity, true, true);
        }

        // Top-right corner
        if (shadow_right > 0 && shadow_top > 0) {
            draw_kde_corner(cr, cx + cw, cy, shadow_right, shadow_top, base_opacity, false, true);
        }

        // Bottom-left corner
        if (shadow_left > 0 && shadow_bottom > 0) {
            draw_kde_corner(cr, cx, cy + ch, shadow_left, shadow_bottom, base_opacity, true, false);
        }

        // Bottom-right corner
        if (shadow_right > 0 && shadow_bottom > 0) {
            draw_kde_corner(cr, cx + cw, cy + ch, shadow_right, shadow_bottom, base_opacity, false, false);
        }
    }

    private void add_gaussian_stops(Cairo.Pattern pattern, double base_opacity, bool reversed) {
        // Approximate gaussian falloff with multiple color stops
        // Values approximate a sigma ~= 0.35 gaussian
        double[] positions = { 0.0, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 0.9, 1.0 };
        double[] opacities = { 0.0, 0.02, 0.08, 0.18, 0.35, 0.55, 0.75, 0.88, 1.0 };

        for (int i = 0; i < positions.length; i++) {
            int idx = reversed ? (positions.length - 1 - i) : i;
            pattern.add_color_stop_rgba(positions[i], 0, 0, 0, base_opacity * opacities[idx]);
        }
    }

    private void draw_kde_corner(Cairo.Context cr, int corner_x, int corner_y,
                                 int radius_x, int radius_y, double base_opacity,
                                 bool is_left, bool is_top) {
        double radius = Math.fmax(radius_x, radius_y);

        var pattern = new Cairo.Pattern.radial(corner_x, corner_y, 0,
                                               corner_x, corner_y, radius);

        // Gaussian-like falloff for radial gradient
        double[] positions = { 0.0, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 0.9, 1.0 };
        double[] opacities = { 1.0, 0.88, 0.75, 0.55, 0.35, 0.18, 0.08, 0.02, 0.0 };

        for (int i = 0; i < positions.length; i++) {
            pattern.add_color_stop_rgba(positions[i], 0, 0, 0, base_opacity * opacities[i]);
        }

        cr.set_source(pattern);

        // Draw only the quarter for this corner
        double start_x = is_left ? corner_x - radius_x : corner_x;
        double start_y = is_top ? corner_y - radius_y : corner_y;

        cr.rectangle(start_x, start_y, radius_x, radius_y);
        cr.fill();
    }

    // Public method to set content widget
    public void set_content(Gtk.Widget widget) {
        if (content_widget != null) {
            content_box.remove(content_widget);
        }
        content_widget = widget;
        content_box.append(widget);
    }

    public Gtk.Widget? get_content() {
        return content_widget;
    }

    // Get the shadow size for external calculations
    public int get_shadow_size() {
        return SHADOW_SIZE;
    }

    // Get content area bounds (without shadow)
    public void get_content_bounds(out int x, out int y, out int width, out int height) {
        x = content_box.get_margin_start();
        y = content_box.get_margin_top();
        width = get_width() - x - content_box.get_margin_end();
        height = get_height() - y - content_box.get_margin_bottom();
    }
}
