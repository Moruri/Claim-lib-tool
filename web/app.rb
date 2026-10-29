# frozen_string_literal: true

require 'sinatra/base'
require 'redcarpet'
require 'shellwords'
require_relative '../lib/claim_library'

module ClaimLibrary
  # A local web front end to the library: extract a revision, read its
  # sources, judge claims, and look at the report and the benchmark. It drives
  # the same classes as the rake tasks, so a library made in one works in the
  # other. Like the terminal annotator, it never suggests a verdict.
  class WebApp < Sinatra::Base
    NAME = /\A[\w-]+\z/
    VERIFIERS_DIR = File.expand_path('../lib/claim_library/verifiers', __dir__)

    # Every write reloads the library from disk inside this lock, so a
    # background fetch and a judgment saved meanwhile never overwrite each
    # other.
    WRITE_LOCK = Mutex.new
    JOBS = {}
    JOBS_LOCK = Mutex.new

    set :root, __dir__
    set :data_dir, ENV.fetch('DATA_DIR', File.expand_path('../data/claim_library', __dir__))
    set :contact, ENV.fetch('CONTACT', 'dev')

    helpers do
      def h(text)
        Rack::Utils.escape_html(text.to_s)
      end

      # Only web links become hrefs; anything else is shown as text.
      def link(url, label = url)
        return h(label) unless url.to_s.match?(%r{\Ahttps?://}i)
        %(<a href="#{h(url)}" target="_blank" rel="noopener noreferrer">#{h(label)}</a>)
      end

      def markdown(text)
        renderer = Redcarpet::Render::HTML.new(escape_html: true)
        Redcarpet::Markdown.new(renderer, tables: true).render(text)
      end

      def claim_path(name, record)
        "/libraries/#{name}/claims/#{record.id}"
      end
    end

    get '/' do
      @libraries = library_names.map { |name| [name, load_library(name)] }
      erb :index
    end

    post '/extract' do
      name = file_name(params[:library])
      name = file_name(params[:title].to_s.downcase) if name.empty?
      return extract_error('Give a library name with at least one letter or number.') if name.empty?
      title = params[:title].to_s.strip
      rev = params[:rev].to_s.strip
      return extract_error('Give an article title or a revision id.') if title.empty? && rev.empty?

      wiki = Wiki.new(language: params[:language].to_s.strip.then { |l| l.empty? ? 'en' : l },
                      contact: settings.contact)
      build = BuildRecords.new(wiki:, mw_rev_id: rev.empty? ? nil : rev.to_i,
                               title: title.empty? ? nil : title)
      return extract_error('No cited sentences found. Check the title or revision.') if build.records.empty?

      added = update_library(name) { |library| library.add(build.records) }
      redirect "/libraries/#{name}?found=#{build.records.size}&added=#{added}"
    rescue StandardError => e
      extract_error("Could not reach Wikipedia: #{e.message}")
    end

    get '/libraries/:name' do
      @name = library_name
      @library = load_library(@name)
      @job = job(@name)
      @show = %w[unjudged judged all].include?(params[:show]) ? params[:show] : 'all'
      @records = { 'unjudged' => @library.unjudged, 'judged' => @library.judged }
                 .fetch(@show, @library.records)
      erb :library
    end

    post '/libraries/:name/fetch' do
      start_fetch(library_name)
      redirect "/libraries/#{library_name}"
    end

    get '/libraries/:name/next' do
      name = library_name
      records = load_library(name).records
      after = records.index { |record| record.id == params[:after] } || -1
      record = records.drop(after + 1).find { |r| !r.judged? } ||
               records.find { |r| !r.judged? && r.id != params[:after] }
      redirect(record ? claim_path(name, record) : "/libraries/#{name}?show=judged")
    end

    get '/libraries/:name/claims/:id' do
      load_claim
      @source = source_for(@record, retry_fetch: params[:retry] == '1')
      @judgment = @record.judgment
      erb :claim
    end

    post '/libraries/:name/claims/:id' do
      load_claim
      @source = @record.source_url && fetcher.from_cache(@record.source_url) || @record.source
      @judgment = Judgment.new(verdict: params[:verdict], reason: params[:reason],
                               passage: params[:passage], flags: Array(params[:flags]),
                               annotator: params[:annotator])
      @errors = @judgment.errors(source_text: @source&.text)
      if @errors.any?
        status 422
        return erb :claim
      end
      response.set_cookie('annotator', value: @judgment.annotator, path: '/', httponly: true,
                                       same_site: :strict)
      update_library(@name) { |library| library.find(@record.id).judgment = @judgment }
      redirect "/libraries/#{@name}/next?after=#{@record.id}"
    end

    get '/libraries/:name/report' do
      @name = library_name
      @report = Report.new(load_library(@name)).to_markdown
      erb :report
    end

    get '/libraries/:name/report.md' do
      content_type 'text/markdown'
      attachment "#{library_name}_report.md"
      Report.new(load_library(library_name)).to_markdown
    end

    get '/libraries/:name/benchmark' do
      @name = library_name
      @verifiers = verifiers
      erb :benchmark
    end

    post '/libraries/:name/benchmark' do
      @name = library_name
      @verifiers = verifiers
      @verifier = params[:verifier]
      halt 400, 'Unknown verifier' unless @verifiers.include?(@verifier)
      command = Shellwords.escape(File.join(VERIFIERS_DIR, @verifier))
      @comparison = VerifierComparison.new(library: load_library(@name), command:, fetcher:).run
      erb :benchmark
    end

    private

    def library_name
      name = params[:name].to_s
      halt 404, 'No such library' unless name.match?(NAME)
      name
    end

    # A library name as typed, made safe to use as a file name: anything but
    # letters, digits, - and _ (spaces included) becomes _.
    def file_name(text)
      text.to_s.gsub(/[^A-Za-z0-9_-]+/, '_').gsub(/\A_+|_+\z/, '')
    end

    def library_names
      Dir[File.join(settings.data_dir, '*.jsonl')].map { |path| File.basename(path, '.jsonl') }.sort
    end

    def library_path(name)
      File.join(settings.data_dir, "#{name}.jsonl")
    end

    def load_library(name)
      Library.new(library_path(name))
    end

    def update_library(name)
      WRITE_LOCK.synchronize do
        library = load_library(name)
        result = yield library
        library.save
        result
      end
    end

    def load_claim
      @name = library_name
      @library = load_library(@name)
      @record = @library.find(params[:id]) || halt(404, 'No such claim')
      @annotator = request.cookies['annotator']
    end

    def fetcher
      @fetcher ||= SourceFetcher.new(cache_dir: File.join(settings.data_dir, 'sources'),
                                     contact: settings.contact)
    end

    # The cached copy if there is one. A source already found unreadable is
    # not tried again unless asked, since every copy may take a while to fail.
    def source_for(record, retry_fetch: false)
      return if record.source_url.nil?
      cached = fetcher.from_cache(record.source_url)
      return cached if cached
      return record.source if record.source && !record.source.readable? && !retry_fetch
      source = fetcher.fetch(record.source_url, archive_url: record.archive_url)
      update_library(@name) { |library| library.find(record.id).source = source }
      source
    end

    def job(name)
      JOBS_LOCK.synchronize { JOBS[name]&.dup }
    end

    def start_fetch(name)
      JOBS_LOCK.synchronize do
        return if JOBS.dig(name, :running)
        JOBS[name] = { running: true, done: 0, total: 0, read: 0 }
      end
      fetcher = self.fetcher
      Thread.new { fetch_all(name, fetcher) }
    end

    def fetch_all(name, fetcher)
      records = load_library(name).records.reject { |record| record.source_url.nil? }
      JOBS_LOCK.synchronize { JOBS[name][:total] = records.size }
      sources = records.to_h do |record|
        source = fetcher.fetch(record.source_url, archive_url: record.archive_url)
        JOBS_LOCK.synchronize do
          JOBS[name][:done] += 1
          JOBS[name][:read] += 1 if source.readable?
        end
        [record.id, source]
      end
      update_library(name) do |library|
        library.records.each { |record| record.source = sources[record.id] if sources.key?(record.id) }
      end
    ensure
      JOBS_LOCK.synchronize { JOBS[name][:running] = false }
    end

    def verifiers
      Dir[File.join(VERIFIERS_DIR, '*')].select { |path| File.file?(path) && File.executable?(path) }
                                         .map { |path| File.basename(path) }.sort
    end

    def extract_error(message)
      @error = message
      @libraries = library_names.map { |name| [name, load_library(name)] }
      status 422
      erb :index
    end
  end
end
