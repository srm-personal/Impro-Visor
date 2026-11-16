/*
 * HARNESS OVERRIDE of imp/util/ErrorLog.java.
 *
 * The original creates a Swing ErrorDialog in a static initializer, which
 * throws HeadlessException (or blocks on a modal dialog) when the engine is
 * driven without a GUI. This replacement keeps the same public API but only
 * records messages, so the golden driver can run headless and can report the
 * warnings Java raised for each input file. It is compiled INSTEAD of the
 * original by Testing/scripts/build_java.sh; the original source is untouched.
 */
package imp.util;

import imp.gui.ErrorDialog;
import java.util.ArrayList;
import java.util.List;

public class ErrorLog
{
public static final int FATAL = 3;
public static final int SEVERE = 2;
public static final int WARNING = 1;
public static final int COMMENT = 0;

static String name[] = {"Comment", "Warning", "Severe Error", "Fatal Error"};

private static final List<String> messages = new ArrayList<String>();
static boolean fatal = false;
static boolean severe = false;

public static void setDialogTitle(String title) { }

public static String log(int severity, String message)
  {
  return log(severity, message, true);
  }

public static synchronized String log(int severity, String message, boolean showDialog)
  {
  String line = "*** " + name[severity] + ": " + message;
  if( severity == 0 )
    {
    return line;
    }
  if( severity == SEVERE ) severe = true;
  if( severity == FATAL ) fatal = true;   // NOTE: original calls System.exit(1)
  messages.add(line);
  return line;
  }

public static boolean hadFatal() { return fatal; }
public static boolean hadSevere() { return severe || fatal; }
public static ErrorDialog getDialog() { return null; }

/** Harness-only: return and clear the messages logged since the last call. */
public static synchronized List<String> drain()
  {
  List<String> out = new ArrayList<String>(messages);
  messages.clear();
  severe = false;
  fatal = false;
  return out;
  }
}
