# frozen_string_literal: true

describe ClaimLibrary::BuildRecords do
  let(:wiki) { ClaimLibrary::Wiki.new(language: 'en', project: 'wikipedia') }
  let(:html) { File.read("#{ROOT}/fixtures/third_place_diff.html") }

  it 'makes one record per cited sentence from rendered HTML' do
    build = described_class.new(wiki:, mw_rev_id: 1_340_536_495, title: 'Third place', html:)
    records = build.records
    expect(records.size).to eq(2)
    expect(records.map(&:ref_id)).to eq(%w[cite_note-1 cite_note-2])
    expect(records.first.sentence).to match(/privilege certain social groups/)
    expect(records.first.citation['text']).to include('Putnam')
    expect(records.first.citation['offline']).to eq(true)
    expect(records.first.wiki).to eq('en.wikipedia')
    expect(records.first.article_title).to eq('Third place')
    expect(records).to all(satisfy { |record| !record.judged? })
  end

  it 'renders the full revision when no HTML is given' do
    allow(wiki).to receive(:revision_html).with(1_340_536_495)
                                          .and_return(html:, title: 'Third place')
    build = described_class.new(wiki:, mw_rev_id: 1_340_536_495)
    expect(build.article_title).to eq('Third place')
    expect(build.records.size).to eq(2)
  end

  it 'takes the latest revision when given only a title' do
    allow(wiki).to receive(:latest_revision_id).with('Third place').and_return(77)
    build = described_class.new(wiki:, title: 'Third place', html:)
    expect(build.mw_rev_id).to eq(77)
    expect(build.records.map(&:mw_rev_id)).to all(eq(77))
  end

  it 'produces nothing when the revision cannot be rendered' do
    allow(wiki).to receive(:revision_html).and_return({})
    expect(described_class.new(wiki:, mw_rev_id: 1).records).to be_empty
  end
end
