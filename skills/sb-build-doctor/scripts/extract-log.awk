# Extracts what matters from a Spring Boot application log: the "APPLICATION FAILED TO START" report,
# ERROR/FATAL lines (deduplicated, with counts), and stack traces (deduplicated by their first line).
# Output is meant to be piped through condense.awk.
#
# Variables (awk -v): only_startup = 1 prints just the startup-failure report (used by build.sh)

function key(s) { gsub(/[0-9]+/, "#", s); return substr(s, 1, 200) }

function is_header(s) {
  return s ~ /^[ \t]*(Caused by: |Suppressed: |Exception in thread "[^"]*" )?([A-Za-z_$][A-Za-z0-9_$]*\.)+[A-Za-z_$][A-Za-z0-9_$]*(Exception|Error|Throwable|Failure)[A-Za-z0-9_$]*(:|$)/
}

function close_block() {
  if (!in_block) return
  in_block = 0
  k = key(block_first)
  if (k in trace_count) { trace_count[k]++; return }
  trace_count[k] = 1
  trace_key[++ntrace] = k
  trace_text[k] = block
}

{ sub(/\r$/, "") }

# --- startup failure report ------------------------------------------------------------------------
/APPLICATION FAILED TO START/ { if (!startup_done) { in_startup = 1; nstartup = 0; after_action = 0 } ; next }
in_startup {
  if ($0 ~ /^\*+$/) next
  if ($0 ~ /^Action:/) after_action = 1
  else if (after_action == 1 && $0 !~ /^[ \t]*$/) after_action = 2
  else if (after_action == 2 && $0 ~ /^[ \t]*$/) { in_startup = 0; startup_done = 1; next }
  if (nstartup < 30 && !($0 ~ /^[ \t]*$/ && (nstartup == 0 || startup[nstartup] ~ /^[ \t]*$/))) startup[++nstartup] = $0
  next
}
only_startup { next }

# --- stack traces --------------------------------------------------------------------------------
in_block {
  if ($0 ~ /^[ \t]*at [^ ]/ || $0 ~ /^[ \t]*\.\.\. [0-9]+ (more|common frames omitted)/) {
    block = block "\n" $0; frames_since_header++; msg_lines = 0; next
  }
  if (is_header($0)) { block = block "\n" $0; frames_since_header = 0; msg_lines = 0; next }
  if (frames_since_header == 0 && msg_lines < 10) { block = block "\n" $0; msg_lines++; next }
  close_block()
}
is_header($0) {
  in_block = 1; block = $0; block_first = $0; frames_since_header = 0; msg_lines = 0
  next
}

# --- ERROR / FATAL log lines ---------------------------------------------------------------------
/(^|[ \t\[])(ERROR|FATAL)([ \t\]]|$)/ {
  if ($0 ~ /^\[(ERROR|FATAL)\][ \t]*$/ || $0 ~ /-> \[Help [0-9]|^\[ERROR\] (\[Help|To see the full|Re-run Maven|For more information|Please refer to)/) next
  k = key($0)                               # digits masked: timestamps, pids and thread numbers collapse
  if (k in err_count) { err_count[k]++; next }
  err_count[k] = 1
  err_key[++nerr] = k
  err_text[k] = $0
}

END {
  close_block()
  if (nstartup) {
    print "## APPLICATION FAILED TO START"
    for (i = 1; i <= nstartup; i++) print startup[i]
    print ""
  }
  if (only_startup) exit
  if (nerr) {
    print "## Error log lines (" nerr " distinct)"
    for (i = 1; i <= nerr && i <= 20; i++) {
      k = err_key[i]
      print (err_count[k] > 1 ? err_count[k] "x  " : "") err_text[k]
    }
    if (nerr > 20) print "... and " (nerr - 20) " more distinct error lines"
    print ""
  }
  if (ntrace) {
    print "## Stack traces (" ntrace " distinct)"
    for (i = 1; i <= ntrace && i <= 10; i++) {
      k = trace_key[i]
      if (trace_count[k] > 1) print "### seen " trace_count[k] "x"
      print trace_text[k]
      print ""
    }
    if (ntrace > 10) print "... and " (ntrace - 10) " more distinct stack traces"
  }
}
