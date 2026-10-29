# frozen_string_literal: true

# A claim library: Wikipedia claims, the sources they cite, and human
# judgments of how well each source backs its claim. See README.md.
require_relative 'claim_library/wiki'
require_relative 'claim_library/build_records'
require_relative 'claim_library/library'
require_relative 'claim_library/source_fetcher'
require_relative 'claim_library/annotator'
require_relative 'claim_library/report'
require_relative 'claim_library/verifier_comparison'
