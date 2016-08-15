require 'elasticsearch'
require 'logger'

require 'es-reindex/railtie' if defined?(Rails)

class ESReindex

  DEFAULT_URL = 'http://127.0.0.1:9200'

  attr_accessor :src, :dst, :options, :surl, :durl, :sidx, :didx, :sclient, :dclient, :start_time, :done, :settings, :mappings


  def sclient
    @sclient ||= Elasticsearch::Client.new host: surl
  end


  def dclient
    @dclient ||= Elasticsearch::Client.new host: durl
  end


  def self.copy!(src, dst, options = {})
    self.new(src, dst, options).tap do |reindexer|
      reindexer.setup_index_urls
      reindexer.copy! if reindexer.okay_to_proceed?
    end
  end

  def self.reindex!(src, dst, options={})
    self.new(src, dst, options.merge(copy_mappings: false)).tap do |reindexer|
      reindexer.setup_index_urls
      reindexer.copy! if reindexer.okay_to_proceed?
    end
  end

  def initialize(src, dst, options = {})
    ESReindex.logger ||= Logger.new(STDERR)

    @src     = src || ''
    @dst     = dst || ''
    @options = {
      from_cli: false, # Coming from CLI?
      remove: false, # remove the index in the new location first
      update: false, # update existing documents (default: only create non-existing)
      frame:  1000,  # specify frame size to be obtained with one fetch during scrolling
      copy_mappings: true, # Copy old mappings/settings
      scroll: '10m', #defined index live time and a user defined query
      query: { query: {match_all: {}}} #The default query is for all content

    }.merge! options


    %w{
      if unless mappings settings before_create after_create before_each after_each after_copy
    }.each do |callback|
      if options.has_key?(callback.to_sym) && !options[callback.to_sym].respond_to?(:call)
        raise ArgumentError, "#{callback} must be a callable object"
      end
    end

    @done = 0
  end

  def setup_index_urls
    @surl, @durl, @sidx, @didx = '', '', '', ''
    [[src, surl, sidx], [dst, durl, didx]].each do |param, url, idx|
      if param =~ %r{^(.*)/(.*?)$}
        url.replace $1
        idx.replace $2
      else
        url.replace DEFAULT_URL
        idx.replace param
      end
    end

    
  end

  def okay_to_proceed?
    okay = true
    okay = options[:if].call(sclient, dclient) if options.has_key?(:if)
    okay = (okay && !(options[:unless].call sclient, dclient)) if options.has_key?(:unless)
    log 'Skipping action due to guard callbacks' unless okay
    okay
  end

  def copy!
    log "Copying '#{surl}/#{sidx}' to '#{durl}/#{didx}'#{remove? ? ' with rewriting destination mapping!' : update? ? ' with updating existing documents!' : '.'}"
    confirm if from_cli?

    success = (
      clear_destination  &&
      create_destination &&
      copy_docs          &&
      check_docs
    )

    if from_cli?
      exit (success ? 0 : 1)
    else
      success
    end
  end

  def confirm
    printf "Confirm or hit Ctrl-c to abort...\n"
    $stdin.readline
  end

  def clear_destination
    dclient.indices.delete(index: didx) if remove? && dclient.indices.exists(index: didx)
    true
  rescue => e
    false
  end

  def create_destination
    unless dclient.indices.exists index: didx
      if copy_mappings?
        return false unless get_settings
        return false unless get_mappings
        create_msg = " with settings & mappings from '#{surl}/#{sidx}'"
      else
        @mappings = options[:mappings].nil? ? {} : options[:mappings].call
        @settings = options[:settings].nil? ? {} : options[:settings].call
        create_msg = ""
      end

      options[:before_create] && options[:before_create].call

      log "Creating '#{durl}/#{didx}' index#{create_msg}..."
      dclient.indices.create index: didx, body: { settings: settings, mappings: mappings }
      log "Succesfully created '#{durl}/#{didx}''#{create_msg}."

      options[:after_create] && options[:after_create].call
    end

    true
  end

  def get_settings
    unless settings = sclient.indices.get_settings(index: sidx)
      log "Failed to obtain original index '#{surl}/#{sidx}' settings!"
      return false
    end

    @settings = fetch_index_config(settings, sidx)["settings"]
    @settings["index"]["version"].delete "created"
  end

  def get_mappings
    unless mappings = sclient.indices.get_mapping(index: sidx)
      log "Failed to obtain original index '#{surl}/#{sidx}' mappings!", :error
      return false
    end
    @mappings = fetch_index_config(mappings, sidx)["mappings"]
  end

  def copy_docs
    log "Copying '#{surl}/#{sidx}' to '#{durl}/#{didx}'..."
    @start_time = Time.now
    #Appends a query and scroll time to source client search.

    scroll = sclient.search index: sidx, search_type: "scan", scroll: @options[:scroll], size: frame, body: @options[:query] 
    scroll_id = scroll['_scroll_id'] #initializes scroll id
    total = scroll['hits']['total']
    log "Copy progress: %u/%u (%.1f%%) done.\r" % [done, total, 0]

    action = update? ? 'index' : 'create'

    while scroll = sclient.scroll(scroll_id: scroll_id, scroll: @options[:scroll]) and not scroll['hits']['hits'].empty? do
      bulk = []
      scroll_id = scroll['_scroll_id'] #Updates scroll id
      scroll['hits']['hits'].each do |doc|
        options[:before_each] && options[:before_each].call(doc)
        ### === implement possible modifications to the document
        ### === end modifications to the document
        base = {'_index' => didx, '_id' => doc['_id'], '_type' => doc['_type'], data: doc['_source']}
        bulk << {action => base}
        @done = done + 1
        options[:after_each] && options[:after_each].call(doc)
      end
      unless bulk.empty?
        dclient.bulk body: bulk
      end

      eta = total * (Time.now - start_time) / done
      log "Copy progress: #{done}/#{total} (%.1f%%) done in #{tm_len}. E.T.A.: #{start_time + eta}." % (100.0 * done / total)
    end

    log "Copy progress: %u/%u done in %s.\n" % [done, total, tm_len]

    options[:after_copy] && options[:after_copy].call

    true
  end

  def check_docs
    log 'Checking document count... '
    scount, dcount = 1, 0
    begin
      Timeout::timeout(60) do
        while true
          scount = sclient.count(index: sidx)["count"]
          dcount = dclient.count(index: didx)["count"]
          break if scount == dcount
          sleep 1
        end
      end
    rescue Timeout::Error
    end
    log "Document count: #{scount} = #{dcount} (#{scount == dcount ? 'equal' : 'NOT EQUAL'})"

    scount == dcount
  end

  class << self
    attr_accessor :logger
  end

private

  def log(msg, level = :info)
    ESReindex.logger.send level, msg
  end

  def remove?
    @options[:remove]
  end

  def update?
    @options[:update]
  end

  def frame
    @options[:frame]
  end

  def from_cli?
    @options[:from_cli]
  end

  def copy_mappings?
    @options[:copy_mappings]
  end

  def tm_len
    l = Time.now - @start_time
    t = []
    t.push l/86400; l %= 86400
    t.push l/3600;  l %= 3600
    t.push l/60;    l %= 60
    t.push l
    out = sprintf '%u', t.shift
    out = out == '0' ? '' : out + ' days, '
    out << sprintf('%u:%02u:%02u', *t)
    out
  end

  # Accounts for aliased indices. When index is aliased there will not
  # be a key nor in settings, nor in mappings. But there will be the
  # only key for original index name.
  def fetch_index_config(config, index)
    config.fetch(index) { config.values.first }
  end

end
