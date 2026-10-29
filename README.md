# Claim library

A claim library is a set of Wikipedia claims, the sources they cite, and a
person's judgment of how well each source backs its claim. It exists to
benchmark automated claim verification: a tool's verdicts are compared with
the human ones, claim by claim, so we can say not only how often a tool agrees
but which kinds of error it catches and which it misses.

The judgments are human. The tooling here finds the text and keeps the
records; it never suggests a verdict, and every judgment it writes carries
`ai_assisted: false` because there is no other way to put one in.
