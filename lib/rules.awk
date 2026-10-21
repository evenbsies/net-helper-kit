# SPDX-License-Identifier: MIT
# Domain-only input. local=/domain/ returns NXDOMAIN (all query types)
# for domains with no locally defined records. No hosts/DHCP sources are enabled.
BEGIN { count=0; bad=0 }
{
    sub(/\r$/, "")
    sub(/#.*/, "")
    gsub(/^[ \t]+|[ \t]+$/, "")
    if ($0 == "") next
    domain=tolower($0)
    if (length(domain)>253 || domain !~ /^[a-z0-9.-]+$/ || index(domain,".")==0) {
        print "Invalid domain at line " NR > "/dev/stderr"; bad=1; next
    }
    n=split(domain, parts, ".")
    valid=1
    for(i=1;i<=n;i++) {
        if(length(parts[i])<1 || length(parts[i])>63 || parts[i] !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) valid=0
    }
    if (!valid) { print "Invalid label at line " NR > "/dev/stderr"; bad=1; next }
    if (!seen[domain]++) {
        count++
        if (count>5000) { print "Rule cap exceeded (5000)" > "/dev/stderr"; bad=1; exit }
        print "local=/" domain "/"
    }
}
END { if (bad || count==0) exit 1 }
