# frozen_string_literal: true

require_relative '../claim_verification/claim_citation_extractor'
require_relative 'record'

module ClaimLibrary
  # Turns one revision of an article into claim-library records: one per cited
  # sentence, carrying the citation attached to it and no judgment yet. The
  # revision is rendered in full so every named reference resolves. Given a
  # title and no revision, the article's latest revision is used. Pre-rendered
  # HTML may be passed in, which is how the specs avoid the network.
  class BuildRecords
    attr_reader :records, :article_title, :mw_rev_id

    def initialize(wiki:, mw_rev_id: nil, title: nil, html: nil)
      @wiki = wiki
      @mw_rev_id = mw_rev_id
      @article_title = title
      @html = html
      @records = []
      perform
    end

    private

    def perform
      @mw_rev_id ||= latest_revision_id
      return if @mw_rev_id.nil?
      html = @html || render
      return if html.nil? || html.strip.empty?
      extraction = ClaimVerification::ClaimCitationExtractor.new(html)
      citations = extraction.citations.to_h { |citation| [citation.ref_id, citation] }
      @records = extraction.claims.flat_map { |claim| records_for(claim, citations) }
    end

    def latest_revision_id
      return if @article_title.nil? || @article_title.strip.empty?
      @wiki.latest_revision_id(@article_title)
    end

    def render
      rendered = @wiki.revision_html(@mw_rev_id)
      @article_title = rendered[:title] || @article_title
      rendered[:html]
    end

    # A sentence with several citations becomes several records, one per
    # source, since each source is judged on its own.
    def records_for(claim, citations)
      claim.ref_ids.filter_map do |ref_id|
        citation = citations[ref_id]
        next if citation.nil?
        Record.from_claim(claim, citation, wiki: @wiki.name, article_title: @article_title,
                                           mw_rev_id: @mw_rev_id)
      end
    end
  end
end
