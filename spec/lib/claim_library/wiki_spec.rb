# frozen_string_literal: true

describe ClaimLibrary::Wiki do
  let(:wiki) { described_class.new(language: 'en', contact: 'dev@example.org') }
  let(:api) { %r{\Ahttps://en\.wikipedia\.org/w/api\.php} }

  it 'names itself the way records do' do
    expect(wiki.name).to eq('en.wikipedia')
  end

  it 'finds the latest revision of an article' do
    stub_request(:get, api).with(query: hash_including('titles' => 'Third place'))
                           .to_return(body: { query: { pages: { '9' => { revisions: [{ revid: 42 }] } } } }.to_json)
    expect(wiki.latest_revision_id('Third place')).to eq(42)
  end

  it 'renders a revision with its title' do
    stub_request(:get, api).with(query: hash_including('action' => 'parse', 'oldid' => '42'))
                           .to_return(body: { parse: { title: 'Third place', text: { '*' => '<p>Hi</p>' } } }.to_json)
    expect(wiki.revision_html(42)).to eq(html: '<p>Hi</p>', title: 'Third place')
  end

  it 'gives nothing for a revision the API cannot render' do
    stub_request(:get, api).to_return(body: { error: { code: 'nosuchrevid' } }.to_json)
    expect(wiki.revision_html(1)).to eq({})
  end
end
