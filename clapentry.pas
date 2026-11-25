unit clapentry;
{ The CLAP entry symbol. Declared "cvar" so its name is unmangled (clap_entry)
  on every target; the library's .lpr exports it with an "exports" clause,
  which is what places it in the dynamic symbol table on Windows/Linux/macOS. }
{$mode fpc}{$H+}
interface
uses clap;

var
  clap_entry: clap_plugin_entry_t; cvar;

implementation
end.