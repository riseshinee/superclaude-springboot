# Reads JUnit XML reports (Gradle build/test-results, Maven surefire/failsafe) and prints each failed
# test as "### FAILED <class> > <test>" followed by its stack trace, plus a final
# "@@TOTALS tests failures errors skipped" line. <system-out>/<system-err> are ignored.
#
# Variables (awk -v): max_fail = failed tests printed in full (default 15)

function unescape(s) {
  gsub(/<!\[CDATA\[/, "", s); gsub(/\]\]>/, "", s)
  gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s); gsub(/&apos;/, "'", s)
  gsub(/&#10;/, "\n", s); gsub(/&#13;/, "", s); gsub(/&#9;/, "\t", s); gsub(/&amp;/, "\\&", s)
  return s
}

function attr(tag, key,   v) {
  if (!match(tag, "[ \t]" key "=\"[^\"]*\"")) return ""
  v = substr(tag, RSTART, RLENGTH)
  sub(/^[ \t][^=]*="/, "", v); sub(/"$/, "", v)
  return unescape(v)
}

function body(text) {
  text = unescape(text)
  if (text ~ /^[ \t]*$/ && lines == 0) return
  if (shown) print text
  lines++
}

function end_failure() {
  if (shown && lines == 0) print type (message != "" ? ": " message : "")
  in_failure = 0
}

BEGIN { if (max_fail == "") max_fail = 15 }

{ sub(/\r$/, "") }

in_failure {
  if ((i = index($0, "</failure>")) || (i = index($0, "</error>"))) {
    body(substr($0, 1, i - 1))
    end_failure()
  } else {
    body($0)
  }
  next
}

/<testsuite[ \t>]/ {
  tests += attr($0, "tests"); failures += attr($0, "failures")
  errors += attr($0, "errors"); skipped += attr($0, "skipped")
}

/<testcase[ \t>]/ { cls = attr($0, "classname"); name = attr($0, "name") }

/<(failure|error)[ \t>\/]/ {
  match($0, /<(failure|error)[^>]*>/)
  tag = substr($0, RSTART, RLENGTH)
  rest = substr($0, RSTART + RLENGTH)
  failed++
  shown = failed <= max_fail
  lines = 0
  type = attr(tag, "type"); message = attr(tag, "message")
  if (shown) print "### FAILED " cls " > " name
  if (tag ~ /\/>$/) { end_failure(); next }
  if ((i = index(rest, "</failure>")) || (i = index(rest, "</error>"))) {
    body(substr(rest, 1, i - 1))
    end_failure()
  } else {
    body(rest)
    in_failure = 1
  }
}

END {
  if (failed > max_fail) print "### ... and " (failed - max_fail) " more failed test(s), see the log"
  print "@@TOTALS " tests + 0, failures + 0, errors + 0, skipped + 0
}
