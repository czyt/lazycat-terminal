// LazyCat Terminal - A Chrome-style tabbed terminal emulator

public class LazyCatTerminal : Gtk.Application {
    public LazyCatTerminal() {
        Object(
            application_id: "com.lazycat.terminal",
            flags: ApplicationFlags.FLAGS_NONE
        );
    }

    protected override void activate() {
        var window = new TerminalWindow(this);
        window.present();
    }

    public static int main(string[] args) {
        var app = new LazyCatTerminal();
        return app.run(args);
    }
}
