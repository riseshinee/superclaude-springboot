# Condenses Java/Kotlin stack traces: keeps exception headers, the "Caused by" chain, the throw site and
# application frames, and collapses framework frames into a single "... N framework frame(s)" line.
# Any other line passes through unchanged (truncated). Shared by build.sh and trace.sh.
#
# Variables (awk -v): max_app = app frames kept per exception (default 8), max_line = line cap (default 300),
#                     root1/root2 = project root spellings stripped from messages (optional)

function is_framework(f) {
  return f ~ /^(java|javax|jakarta|jdk|sun|com\.sun|kotlin|kotlinx|groovy|org\.codehaus\.groovy|org\.springframework|org\.junit|junit|org\.opentest4j|org\.gradle|worker\.org\.gradle|org\.apache|org\.hibernate|org\.mockito|net\.bytebuddy|org\.assertj|org\.hamcrest|com\.zaxxer|io\.netty|reactor|org\.eclipse|org\.jboss|com\.fasterxml|io\.micrometer|org\.aspectj|io\.github\.resilience4j|org\.testcontainers|org\.h2|com\.mysql|org\.postgresql|org\.flywaydb|liquibase|feign|io\.undertow|org\.xnio|lombok|com\.intellij)\./ \
      || f ~ /\$\$(SpringCGLIB|EnhancerBySpringCGLIB|FastClassBySpringCGLIB|Lambda)/ \
      || f ~ /^(jdk\.proxy|<generated>|\$Proxy)/
}

function strip_root(s, r,   i) {
  if (r == "") return s
  while ((i = index(s, r)) > 0) s = substr(s, 1, i - 1) "<project>" substr(s, i + length(r))
  return s
}

function flush_skipped() {
  if (skipped > 0) print "\t... " skipped " framework frame(s)"
  skipped = 0
}

BEGIN {
  if (max_app == "") max_app = 8
  if (max_line == "") max_line = 300
  throw_site = 1
  root2_win = root2; gsub(/\//, "\\", root2_win)
}

{ sub(/\r$/, "") }

/^[ \t]*at [^ ]/ {
  frame = $0
  sub(/^[ \t]*at /, "", frame)
  f = frame
  sub(/^[^ (\/]*\/\/?/, "", f)          # module/loader prefix: "java.base/", "app//"
  if (throw_site && f !~ /^(jdk\.internal|sun\.reflect|java\.lang\.reflect)\./) {
    throw_site = 0
    print "\tat " frame
  } else if (!is_framework(f) && app < max_app) {
    flush_skipped()
    print "\tat " frame
    app++
  } else {
    skipped++
  }
  next
}

/^[ \t]*\.\.\. [0-9]+ (more|common frames omitted)/ { next }

{
  flush_skipped()
  line = strip_root(strip_root(strip_root($0, root2_win), root2), root1)
  if (length(line) > max_line) line = substr(line, 1, max_line) " [...]"
  print line
  throw_site = 1
  app = 0
}

END { flush_skipped() }
