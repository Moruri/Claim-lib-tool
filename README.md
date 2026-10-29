# Claim library

A claim library is a set of Wikipedia claims, the sources they cite, and a
person's judgment of how well each source backs its claim. It exists to
benchmark automated claim verification: a tool's verdicts are compared with
the human ones, claim by claim, so we can say not only how often a tool agrees
but which kinds of error it catches and which it misses.

The judgments are human. The tooling here finds the text and keeps the
records; it never suggests a verdict, and every judgment it writes carries
`ai_assisted: false` because there is no other way to put one in.

## The file

A library is one file with one JSON record per line, so it diffs cleanly and
can be shared and used anywhere. Each record holds:

| Field | What it is |
|---|---|
| `id` | Derived from wiki, revision, reference and sentence, so re-extracting a revision gives the same ids |
| `wiki`, `article_title`, `mw_rev_id` | Where the claim comes from |
| `ref_id`, `sentence`, `context` | The cited sentence, the reference attached to it, and the paragraph up to that sentence |
| `citation` | The reference text, its URLs, its archive URLs, and whether it is an offline source |
| `source` | Which copy of the source was read, what kind of page it is, when, or why it could not be read |
| `judgment` | `verdict`, `reason`, `passage` quoted from the source, `flags`, `annotator`, `judged_at`, `ai_assisted` |

Verdicts are the ones the fact-verification exercise offers students, so the
library and student responses can be compared: `full_support`,
`partial_support`, `unsupported`, `contradicted`, `undetermined`.

Flags name the ways a claim can be wrong while still citing a real source:
`fabricated_quotation`, `misattribution`, `time_drift`, `prediction_as_fact`,
`opinion_as_reporting`, `single_case_generalised`, `circular_citation`,
`dead_or_bare_link`, `true_but_unsupported`.

## Setup

Needs Ruby 3.2 or later, and `pdftotext` (poppler-utils) for PDF sources.

```bash
bundle install
bundle exec rspec          # or: bundle exec rake
bundle exec rake -T        # lists the claim_library tasks
```

## Commands

Library files and the source cache go under `data/`, which git ignores. Set
`CONTACT` to an email or URL; it goes in the User-Agent sent to Wikipedia and
to source sites, as Wikimedia's API policy asks.

```bash
# One record per cited sentence in a revision. TITLE alone takes the latest revision.
LIBRARY=data/claim_library/surrogacy.jsonl REV=1321874993 bundle exec rake claim_library:extract

# Read the source behind each claim and cache the text, with where it came from.
LIBRARY=data/claim_library/surrogacy.jsonl bundle exec rake claim_library:fetch

# Judge the unjudged claims, one at a time, at the terminal.
LIBRARY=data/claim_library/surrogacy.jsonl ANNOTATOR="Your name" bundle exec rake claim_library:annotate

# The library as a readable report with a scorecard.
LIBRARY=data/claim_library/surrogacy.jsonl OUT=report.md bundle exec rake claim_library:report

# Compare an automated verifier with the human judgments.
LIBRARY=data/claim_library/surrogacy.jsonl \
  VERIFIER=lib/claim_library/verifiers/always_full_support.rb bundle exec rake claim_library:benchmark
```

Sources are read from the first of these that yields text: Europe PMC's full
text for anything with a PMC id, the citation's own URL, the archive link the
citation carries, then the Wayback Machine snapshot nearest the revision's
date. PDFs need `pdftotext` installed. A source that cannot be read stays in
the library as unreadable, with the reason, and is retried on the next fetch.

## The web app

Everything the commands do can also be done in the browser:

```bash
CONTACT="you@example.org" bundle exec rake web
```

Then open <http://127.0.0.1:4567>. It listens only on your own machine. Set
`PORT` to change the port, and `DATA_DIR` to use library files other than
the ones in `data/claim_library/`. You can:

- extract an article into a library, new or existing;
- fetch every source in the background and watch the count go up;
- judge claims one at a time. You see the claim, its context, the citation,
  the likely passages and the full source text, and you can select text in
  the source to quote it. The page never suggests a verdict, and a quote
  that isn't in the source is refused, as at the terminal;
- read the report or download it as Markdown;
- benchmark any executable in `lib/claim_library/verifiers/`.

The web app and the rake tasks share the same library files, so you can
switch between them.

## Writing a verifier

A verifier is any command. It receives one record as JSON on standard input,
with the source text added as `source_text`, and prints a JSON object with a
`verdict` from the list above. `lib/claim_library/verifiers/always_full_support.rb`
is the smallest possible example and the baseline every real tool should beat.

## Third-party code

`lib/claim_verification/` (the sentence and citation extractor) is © Wiki
Education Foundation, used under the MIT licence; see
`lib/claim_verification/LICENSE`.
