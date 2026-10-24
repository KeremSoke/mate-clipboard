[CCode (cheader_filename = "X11/extensions/XTest.h")]
namespace XTest {
	[CCode (cname = "XTestFakeKeyEvent")]
	public int fake_key_event (X.Display display, uint keycode, bool is_press, ulong delay);
}
