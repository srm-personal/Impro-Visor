/*
 * HARNESS OVERRIDE of imp/util/ErrorLogWithResponse.java.
 *
 * The original shows a modal "continue / abort" dialog. Headless, the harness
 * records the message through the ErrorLog stub and answers as if the user
 * pressed the default button (continue): log() returns false = "do not abort".
 */
package imp.util;

public class ErrorLogWithResponse
{
public static final int FATAL = 3;
public static final int SEVERE = 2;
public static final int WARNING = 1;
public static final int COMMENT = 0;

public static void setDialogTitle(String title) { }

public static boolean log(int severity, String message)
  {
  return log(severity, message, true);
  }

public static boolean log(int severity, String message, boolean showDialog)
  {
  if( severity != COMMENT )
    {
    ErrorLog.log(severity == FATAL ? ErrorLog.SEVERE : severity, message, false);
    }
  return false;
  }

public static boolean hadFatal() { return false; }
public static boolean hadSevere() { return ErrorLog.hadSevere(); }
}
