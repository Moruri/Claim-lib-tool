# frozen_string_literal: true

ENV['APP_ENV'] = 'test'

require 'rack/test'
require 'tmpdir'
require_relative '../../web/app'

describe ClaimLibrary::WebApp do
  include Rack::Test::Methods

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      described_class.set :data_dir, dir
      example.run
    end
  end

  let(:app) { described_class }
  let(:path) { File.join(@dir, 'surrogacy.jsonl') }
  let(:record) { library_record }
  let(:source_text) { 'The Confederation of Indian Industry predicts US$2.3 billion annually.' }

  def save_library(*records)
    ClaimLibrary::Library.new(path).tap { |library| library.add(records) }.save
  end

  def stored
    ClaimLibrary::Library.new(path)
  end

  def stub_source(text = source_text)
    stub_request(:get, %r{europepmc/webservices/rest/PMC10327345})
      .to_return(status: 200, body: "<article><body><p>#{text}</p></body></article>",
                 headers: { 'Content-Type' => 'application/xml' })
  end

  def judge(**fields)
    defaults = { verdict: 'partial_support', reason: 'One body, not industry groups.',
                 passage: 'predicts US$2.3 billion annually', annotator: 'Moruri' }
    post "/libraries/surrogacy/claims/#{record.id}", defaults.merge(fields)
  end

  describe 'the library list' do
    it 'invites an extraction when there is no library yet' do
      get '/'
      expect(last_response).to be_ok
      expect(last_response.body).to include('No libraries yet')
    end

    it 'lists each library with its counts' do
      save_library(record, judged_record(sentence: 'Judged.'))
      get '/'
      expect(last_response.body).to include('>surrogacy</a>', '<td>2</td>', '<td>1</td>')
    end
  end

  describe 'extracting an article' do
    let(:html) { File.read("#{ROOT}/fixtures/third_place_diff.html") }

    it 'adds the cited sentences of a revision to a library' do
      stub_request(:get, %r{en\.wikipedia\.org/w/api\.php})
        .with(query: hash_including('action' => 'parse', 'oldid' => '1340536495'))
        .to_return(body: { parse: { title: 'Third place', text: { '*' => html } } }.to_json)
      post '/extract', rev: '1340536495', library: 'third'
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with('/libraries/third?found=2&added=2')
      expect(ClaimLibrary::Library.new(File.join(@dir, 'third.jsonl')).records.size).to eq(2)
    end

    it 'asks for a title or a revision' do
      post '/extract', library: 'x'
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include('Give an article title or a revision id.')
    end

    it 'turns a typed library name into a safe file name' do
      stub_request(:get, %r{en\.wikipedia\.org/w/api\.php})
        .to_return(body: { parse: { title: 'Third place', text: { '*' => html } } }.to_json)
      post '/extract', rev: '1340536495', library: "../Charles Moruri\u00a0"
      expect(last_response.location).to include('/libraries/Charles_Moruri?')
      expect(Dir.children(@dir)).to eq(['Charles_Moruri.jsonl'])
    end

    it 'asks for a library name when nothing usable was given' do
      post '/extract', rev: '1', library: '../..'
      expect(last_response.status).to eq(422)
      expect(Dir.children(@dir)).to be_empty
    end
  end

  describe 'judging a claim' do
    before do
      save_library(record)
      stub_source
    end

    it 'shows the claim, the source and the likely passage, and suggests no verdict' do
      get "/libraries/surrogacy/claims/#{record.id}"
      expect(last_response).to be_ok
      expect(last_response.body).to include(record.sentence, 'journal, read from',
                                            'predicts US$2.3 billion annually')
      expect(last_response.body).not_to include('checked')
    end

    it 'records the source it read in the library' do
      get "/libraries/surrogacy/claims/#{record.id}"
      expect(stored.records.first.source.read_from).to include('europepmc')
    end

    it 'saves a judgment and moves on to the next claim' do
      get "/libraries/surrogacy/claims/#{record.id}"
      judge(flags: ['true_but_unsupported'])
      expect(last_response.location).to end_with("/libraries/surrogacy/next?after=#{record.id}")
      judgment = stored.records.first.judgment
      expect(judgment.verdict).to eq('partial_support')
      expect(judgment.flags).to eq(['true_but_unsupported'])
      expect(judgment.to_h['ai_assisted']).to eq(false)
    end

    it 'refuses a passage that is not in the source and keeps what was typed' do
      get "/libraries/surrogacy/claims/#{record.id}"
      judge(passage: 'thousands of clinics')
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include('passage was not found in the source text',
                                            'One body, not industry groups.')
      expect(stored.judged).to be_empty
    end

    it 'remembers the annotator for the next claim' do
      get "/libraries/surrogacy/claims/#{record.id}"
      judge
      get "/libraries/surrogacy/claims/#{record.id}"
      expect(last_response.body).to include('value="Moruri"')
    end

    it 'goes to the next unjudged claim after the one just judged' do
      second = library_record(sentence: 'Second claim.')
      save_library(record, second)
      get "/libraries/surrogacy/next?after=#{record.id}"
      expect(last_response.location).to end_with("/claims/#{second.id}")
    end

    it 'goes to the judged list when no claim is left to judge' do
      File.delete(path)
      save_library(judged_record)
      get '/libraries/surrogacy/next'
      expect(last_response.location).to end_with('/libraries/surrogacy?show=judged')
    end

    it 'escapes text taken from Wikipedia and the source' do
      save_library(library_record(sentence: '<script>alert(1)</script> claim.'))
      xss = stored.records.last
      get "/libraries/surrogacy/claims/#{xss.id}"
      expect(last_response.body).not_to include('<script>alert(1)</script>')
      expect(last_response.body).to include('&lt;script&gt;alert(1)&lt;/script&gt;')
    end
  end

  describe 'fetching every source' do
    it 'reads the sources in the background and records them' do
      save_library(record)
      stub_source
      post '/libraries/surrogacy/fetch'
      deadline = Time.now + 5
      sleep 0.05 until stored.records.first.source || Time.now > deadline
      expect(stored.records.first.source).to be_readable
    end
  end

  describe 'the report and the benchmark' do
    before { save_library(judged_record, record) }

    it 'renders the report' do
      get '/libraries/surrogacy/report'
      expect(last_response.body).to include('1 of 2 claims judged')
      expect(last_response.body).to include('<table>')
    end

    it 'offers the report as a Markdown download' do
      get '/libraries/surrogacy/report.md'
      expect(last_response.headers['Content-Disposition']).to include('surrogacy_report.md')
      expect(last_response.body).to start_with('# Claim library report')
    end

    it 'runs the baseline verifier' do
      stub_source
      post '/libraries/surrogacy/benchmark', verifier: 'always_full_support.rb'
      expect(last_response.body).to include('Agreement on 1 judged claims: 100%')
    end

    it 'runs only the verifiers in the verifiers folder' do
      post '/libraries/surrogacy/benchmark', verifier: 'rm -rf /'
      expect(last_response.status).to eq(400)
    end
  end

  it 'answers 404 for a library name it would not create' do
    get '/libraries/..%2Fetc'
    expect(last_response.status).to eq(404)
  end
end
