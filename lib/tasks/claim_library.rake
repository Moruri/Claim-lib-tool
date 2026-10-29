# frozen_string_literal: true

require_relative '../claim_library'

# Builds and uses a claim library: Wikipedia claims, their cited sources, and
# human judgments of how well each source backs its claim. See README.md.
# Library files and the source cache live under data/, which git ignores.
namespace :claim_library do
  def env(name)
    value = ENV[name].to_s.strip
    value.empty? ? nil : value
  end

  def claim_library_contact
    env('CONTACT') || 'dev'
  end

  def claim_library_path
    env('LIBRARY') || abort('Set LIBRARY to the library file, eg data/claim_library/surrogacy.jsonl')
  end

  def claim_library_fetcher
    cache_dir = env('CACHE') || 'data/claim_library/sources'
    ClaimLibrary::SourceFetcher.new(cache_dir:, contact: claim_library_contact)
  end

  def claim_library
    ClaimLibrary::Library.new(claim_library_path)
  end

  def write_or_print(markdown)
    env('OUT') ? File.write(env('OUT'), markdown) : puts(markdown)
  end

  desc 'Add every cited sentence of a revision to a library. ' \
       'ENV: LIBRARY, REV or TITLE (latest revision), LANGUAGE (default en), CONTACT'
  task :extract do
    abort 'Set REV to a revision id or TITLE to an article title' if env('REV').nil? && env('TITLE').nil?
    wiki = ClaimLibrary::Wiki.new(language: env('LANGUAGE') || 'en', contact: claim_library_contact)
    build = ClaimLibrary::BuildRecords.new(wiki:, mw_rev_id: env('REV')&.to_i, title: env('TITLE'))
    library = claim_library
    added = library.add(build.records)
    library.save
    puts "#{build.article_title} (revision #{build.mw_rev_id}): #{build.records.size} cited " \
         "sentences, #{added} new. Library now holds #{library.records.size} claims."
  end

  desc 'Read and cache the source behind every claim in a library. ENV: LIBRARY, CACHE, CONTACT'
  task :fetch do
    library = claim_library
    fetcher = claim_library_fetcher
    library.records.each do |record|
      next puts("#{record.id}: offline source") if record.source_url.nil?
      record.source = fetcher.fetch(record.source_url, archive_url: record.archive_url)
      puts "#{record.id}: #{record.source.status} #{record.source.read_from || record.source.error}"
    end
    library.save
  end

  desc 'Judge the unjudged claims in a library, one at a time. ENV: LIBRARY, ANNOTATOR, CACHE'
  task :annotate do
    annotator = env('ANNOTATOR') || abort('Set ANNOTATOR to your name')
    recorded = ClaimLibrary::Annotator.new(library: claim_library, fetcher: claim_library_fetcher,
                                           annotator:).run
    puts "Recorded #{recorded} judgment#{'s' unless recorded == 1}."
  end

  desc 'Write the library as a Markdown report. ENV: LIBRARY, OUT (default: print)'
  task :report do
    write_or_print(ClaimLibrary::Report.new(claim_library).to_markdown)
  end

  desc 'Compare an automated verifier with the human judgments. ' \
       'ENV: LIBRARY, VERIFIER (a command), OUT'
  task :benchmark do
    command = env('VERIFIER') || abort('Set VERIFIER to the command that judges a claim')
    comparison = ClaimLibrary::VerifierComparison.new(library: claim_library, command:,
                                                      fetcher: claim_library_fetcher).run
    write_or_print(comparison.to_markdown)
  end
end
