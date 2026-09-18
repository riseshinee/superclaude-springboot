# Pulls the actionable parts out of a Gradle/Maven console log: compiler errors (javac, Kotlin, Maven
# format; localized javac labels such as Korean or Japanese included), Gradle "What went wrong" blocks, Maven
# [ERROR] lines minus help noise, and Gradle "> FAILED" test lines when no XML reports exist.
#
# Variables (awk -v): root1/root2 = project root spellings stripped from paths, have_xml = 1 when test
# failures come from XML reports (suppresses duplicate console listings), max_err (default 30)

function shorten(s) {
  gsub(/\\/, "/", s)
  sub(/file:\/\/\/?/, "", s)
  s = strip_root(s, root1); s = strip_root(s, root2)
  return s
}

# Removes "<root>/" and Maven's "/<root>/" (/C:/proj/...) spellings.
function strip_root(s, r,   i) {
  if (r == "") return s
  while ((i = index(s, "/" r "/")) > 0) s = substr(s, 1, i - 1) substr(s, i + length(r) + 2)
  while ((i = index(s, r "/")) > 0) s = substr(s, 1, i - 1) substr(s, i + length(r) + 1)
  return s
}

function cap(s) { return length(s) > 300 ? substr(s, 1, 300) " [...]" : s }

# Records an error; a repeat (Maven lists each error twice) still consumes its context lines.
function add_error(s) {
  s = cap(shorten(s))
  ctx_left = 4
  duplicate = (s in seen)
  if (duplicate) return
  seen[s] = 1
  nerr++
  if (nerr <= max_err) err[nerr] = s
}

function add_ctx(s) {
  ctx_left--
  if (!duplicate && nerr <= max_err) err[nerr] = err[nerr] "\n" cap(s)
}

BEGIN { if (max_err == "") max_err = 30 }

{ sub(/\r$/, "") }

# --- compiler errors -------------------------------------------------------------------------------
# javac (Gradle): src/.../Foo.java:42: error: cannot find symbol   (kind may be localized)
/\.(java|groovy):[0-9]+: [^ :]+: / {
  kind = $0; sub(/^.*\.(java|groovy):[0-9]+: /, "", kind); sub(/:.*/, "", kind)
  if (kind !~ /^(warning|note|경고|참고|警告|注意)$/) { add_error($0); next }
  ctx_left = 0; next
}
# Kotlin: e: file:///.../Foo.kt:42:10 Unresolved reference
/^e: / { add_error(substr($0, 4)); ctx_left = 0; next }
# Maven: [ERROR] /path/Foo.java:[42,17] cannot find symbol
/^\[ERROR\] .*\.(java|kt|groovy):\[[0-9]+(,[0-9]+)?\]/ { add_error(substr($0, 9)); next }
/^(\[ERROR\])?[ \t]+(symbol|location|required|found|reason)[ \t]*:/ && ctx_left > 0 {
  line = $0; sub(/^\[ERROR\]/, "", line); add_ctx(line); next
}
ctx_left > 0 {
  if ($0 ~ /^[0-9]+ (error|errors|warning|warnings)$/ || $0 ~ /^([>*\[]|FAILURE|BUILD|Note:)/ || $0 ~ /^[ \t]*$/) ctx_left = 0
  else { add_ctx($0); next }
}

# --- Gradle "* What went wrong:" --------------------------------------------------------------------
/^\* What went wrong:/ { in_wrong = 1; next }
in_wrong {
  if ($0 ~ /^(\* (Try|Exception is|Get more help)|BUILD (FAILED|SUCCESSFUL))/) { in_wrong = 0; next }
  if ($0 ~ /^[ \t]*$/ || $0 ~ /Compilation failed; see the compiler (error|output)/ || nwrong >= 20) next
  wrong[++nwrong] = cap(shorten($0))
  next
}

# --- Gradle console test failures (fallback when there are no XML reports) -------------------------
/ > .* FAILED$/ { if (nfailed < 15) { failed_line[++nfailed] = $0; grab_cause = 1 }; next }
grab_cause { grab_cause = 0; if ($0 ~ /^[ \t]+[^ \t]/) { failed_line[nfailed] = failed_line[nfailed] "\n" cap($0); next } }

# --- Maven [ERROR] lines ----------------------------------------------------------------------------
/^\[(ERROR|FATAL)\]/ {
  line = $0
  sub(/^\[(ERROR|FATAL)\][ \t]?/, "", line)
  sub(/[ \t]*-> \[Help [0-9]+\][ \t]*$/, "", line)
  if (line ~ /^[ \t]*$/ || line ~ /(^\[Help [0-9]|Re-run Maven|To see the full stack trace|full debug logging|For more information about the errors|After correcting the problems|There are test failures|Please refer to|dump files|COMPILATION ERROR|^Failures: *$|^Errors: *$)/) next
  if (nerr && line ~ /Compilation failure/) next
  if (have_xml && (line ~ /^(Tests run:|  [A-Za-z0-9_$.]+[:.])/ || line ~ /<<< (FAILURE|ERROR)!/)) next
  line = cap(shorten(line))
  if (!(line in mseen) && nmvn < 12) { mseen[line] = 1; mvn[++nmvn] = line }
}

END {
  if (nerr) {
    print "## Compile errors (" nerr ")"
    for (i = 1; i <= nerr && i <= max_err; i++) print err[i]
    if (nerr > max_err) print "... and " (nerr - max_err) " more, see the log"
    print ""
  }
  if (nwrong) {
    print "## What went wrong (Gradle)"
    for (i = 1; i <= nwrong; i++) print wrong[i]
    print ""
  }
  if (nmvn) {
    print "## Maven errors"
    for (i = 1; i <= nmvn; i++) print mvn[i]
    print ""
  }
  if (nfailed && !have_xml) {
    print "## Failed tests (console; no XML reports found)"
    for (i = 1; i <= nfailed; i++) print failed_line[i]
    print ""
  }
}
