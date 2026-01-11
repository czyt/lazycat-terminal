// Configuration Manager - Handles loading and parsing config.conf

public class ConfigManager {
    private KeyFile config_file;
    private string config_path;

    // Configuration values
    public string theme { get; private set; }
    public double opacity { get; private set; }
    public string font { get; private set; }
    public int font_size { get; private set; }

    // Shortcut mappings
    private HashTable<string, string> shortcuts;

    public ConfigManager() {
        config_file = new KeyFile();
        shortcuts = new HashTable<string, string>(str_hash, str_equal);

        // Set default configuration path
        string config_dir = Path.build_filename(Environment.get_home_dir(), ".config", "lazycat-theme");
        config_path = Path.build_filename(config_dir, "config.conf");

        // Check and copy config file if needed
        ensure_config_exists();

        // Load configuration
        load_config();
    }

    private void ensure_config_exists() {
        var config_file_obj = File.new_for_path(config_path);

        // Check if config file exists
        if (!config_file_obj.query_exists()) {
            try {
                // Create config directory if it doesn't exist
                string config_dir = Path.get_dirname(config_path);
                var dir = File.new_for_path(config_dir);
                if (!dir.query_exists()) {
                    dir.make_directory_with_parents();
                }

                // Copy config.conf from current directory to ~/.config/lazycat-theme/
                string source_path = Path.build_filename(Environment.get_current_dir(), "config.conf");
                var source_file = File.new_for_path(source_path);

                if (source_file.query_exists()) {
                    source_file.copy(config_file_obj, FileCopyFlags.NONE);
                } else {
                    stderr.printf("Warning: Source config.conf not found at: %s\n", source_path);
                }
            } catch (Error e) {
                stderr.printf("Error ensuring config exists: %s\n", e.message);
            }
        }
    }

    private void load_config() {
        try {
            config_file.load_from_file(config_path, KeyFileFlags.NONE);

            // Load general settings
            if (config_file.has_group("general")) {
                theme = config_file.get_string("general", "theme");
                opacity = config_file.get_double("general", "opacity");
                font = config_file.get_string("general", "font");
                font_size = config_file.get_integer("general", "font_size");
            } else {
                // Set defaults if general section is missing
                theme = "default";
                opacity = 0.88;
                font = "Hack";
                font_size = 13;
            }

            // Load shortcuts
            if (config_file.has_group("shortcut")) {
                string[] keys = config_file.get_keys("shortcut");
                foreach (string key in keys) {
                    string value = config_file.get_string("shortcut", key);
                    shortcuts.set(key, value);
                }
            }
        } catch (Error e) {
            stderr.printf("Error loading config: %s\n", e.message);
            // Set defaults
            theme = "default";
            opacity = 0.88;
            font = "Hack";
            font_size = 13;
        }
    }

    // Get shortcut value by name
    public string? get_shortcut(string name) {
        return shortcuts.get(name);
    }

    // Parse shortcut string into modifiers and key
    // Returns true if the key event matches the shortcut
    public bool match_shortcut(string shortcut_name, uint keyval, Gdk.ModifierType state) {
        string? shortcut = get_shortcut(shortcut_name);
        if (shortcut == null) return false;

        // Parse shortcut string (e.g., "Ctrl + Shift + c")
        bool ctrl_needed = false;
        bool shift_needed = false;
        bool alt_needed = false;
        uint target_key = 0;

        string[] parts = shortcut.split("+");
        foreach (string part in parts) {
            string trimmed = part.strip().down();

            if (trimmed == "ctrl") {
                ctrl_needed = true;
            } else if (trimmed == "shift") {
                shift_needed = true;
            } else if (trimmed == "alt") {
                alt_needed = true;
            } else {
                // This is the key part
                target_key = parse_key_string(trimmed);
            }
        }

        // Check if current state matches
        bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
        bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
        bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;

        return (ctrl == ctrl_needed) &&
               (shift == shift_needed) &&
               (alt == alt_needed) &&
               (keyval == target_key);
    }

    // Convert key string to Gdk.Key value
    private uint parse_key_string(string key_str) {
        switch (key_str) {
            case "c": return Gdk.Key.C;
            case "v": return Gdk.Key.V;
            case "f": return Gdk.Key.f;
            case "a": return Gdk.Key.A;
            case "t": return Gdk.Key.T;
            case "w": return Gdk.Key.W;
            case "j": return Gdk.Key.J;
            case "h": return Gdk.Key.H;
            case "k": return Gdk.Key.k;
            case "l": return Gdk.Key.l;
            case "q": return Gdk.Key.q;
            case "e": return Gdk.Key.e;
            case "=": return Gdk.Key.equal;
            case "-": return Gdk.Key.minus;
            case "0": return Gdk.Key.@0;
            case "tab": return Gdk.Key.Tab;
            default: return 0;
        }
    }
}
