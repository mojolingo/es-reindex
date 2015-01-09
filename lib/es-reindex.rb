require 'rest-client'
require 'multi_json'

class ESReindex

  DEFAULT_URL = 'http://127.0.0.1:9200'

  attr_accessor :src, :dst, :options, :start_time, :done

  def initialize(src, dst, options = {})
    @src     = src || ''
    @dst     = dst || ''
    @options = {
      from_cli: false, # Coming from CLI?
      remove: false, # remove the index in the new location first
      update: false, # update existing documents (default: only create non-existing)
      frame:  1000   # specify frame size to be obtained with one fetch during scrolling
    }.merge! options

    @done = 0

    @surl, @durl, @sidx, @didx = '', '', '', ''
    [[src, @surl, @sidx], [dst, @durl, @didx]].each do |param, url, idx|
      if param =~ %r{^(.*)/(.*?)$}
        url.replace $1
        idx.replace $2
      else
        url.replace DEFAULT_URL
        idx.replace param
      end
    end
  end

  def go!
    setup_json_options
    success = copy_mappings && copy_docs
    if from_cli?
      exit (success ? 0 : 1)
    else
      success
    end
  end

  def copy_mappings
    confirm_msg = from_cli? ? "Confirm or hit Ctrl-c to abort...\n" : ""
    printf "Copying '%s/%s' to '%s/%s'%s\n  #{confirm_msg}",
      @surl, @sidx, @durl, @didx,
      remove? ?
        ' with rewriting destination mapping!' :
        update? ? ' with updating existing documents!' : '.'

    $stdin.readline if from_cli?

    # remove old index in case of remove=true
    retried_request(:delete, "#{@durl}/#{@didx}") if remove? && retried_request(:get, "#{@durl}/#{@didx}/_status")

    # (re)create destination index
    unless retried_request :get, "#{@durl}/#{@didx}/_status"
      # obtain the original index settings first
      unless settings = retried_request(:get, "#{@surl}/#{@sidx}/_settings")
        warn "Failed to obtain original index '#{@surl}/#{@sidx}' settings!"
        return false
      end
      settings = MultiJson.load settings
      @sidx = settings.keys[0]
      settings[@sidx].delete 'index.version.created'
      printf 'Creating \'%s/%s\' index with settings from \'%s/%s\'... ', @durl, @didx, @surl, @sidx
      unless retried_request :post, "#{@durl}/#{@didx}", MultiJson.dump(settings[@sidx])
        puts 'FAILED!'
        return false
      else
        puts 'OK.'
      end
      unless mappings = retried_request(:get, "#{@surl}/#{@sidx}/_mapping")
        warn "Failed to obtain original index '#{@surl}/#{@sidx}' mappings!"
        return false
      end
      mappings = MultiJson.load mappings
      mappings = mappings[@sidx]
      mappings = mappings['mappings'] if mappings.is_a?(Hash) && mappings.has_key?('mappings')
      mappings.each_pair do |type, mapping|
        printf 'Copying mapping \'%s/%s/%s\'... ', @durl, @didx, type
        unless retried_request(:put, "#{@durl}/#{@didx}/#{type}/_mapping", MultiJson.dump(type => mapping))
          puts 'FAILED!'
          return false
        else
          puts 'OK.'
        end
      end
    end

    true
  end

  def copy_docs
    printf "Copying '%s/%s' to '%s/%s'... \n", @surl, @sidx, @durl, @didx
    @start_time = Time.now
    shards = retried_request :get, "#{@surl}/#{@sidx}/_count?q=*"
    shards = MultiJson.load(shards)['_shards']['total'].to_i
    scan = retried_request :get, "#{@surl}/#{@sidx}/_search?search_type=scan&scroll=10m&size=#{frame / shards}"
    scan = MultiJson.load scan
    scroll_id = scan['_scroll_id']
    total = scan['hits']['total']
    printf "    %u/%u (%.1f%%) done.\r", done, total, 0

    bulk_op = update? ? 'index' : 'create'

    while true do
      data = retried_request :get, "#{@surl}/_search/scroll?scroll=10m&scroll_id=#{scroll_id}"
      data = MultiJson.load data
      break if data['hits']['hits'].empty?
      scroll_id = data['_scroll_id']
      bulk = ''
      data['hits']['hits'].each do |doc|
        ### === implement possible modifications to the document
        ### === end modifications to the document
        base = {'_index' => @didx, '_id' => doc['_id'], '_type' => doc['_type']}
        ['_timestamp', '_ttl'].each{|doc_arg|
          base[doc_arg] = doc[doc_arg] if doc.key? doc_arg
        }
        bulk << MultiJson.dump(bulk_op => base) + "\n"
        bulk << MultiJson.dump(doc['_source'])  + "\n"
        @done = done + 1
      end
      unless bulk.empty?
        bulk << "\n" # empty line in the end required
        retried_request :post, "#{@durl}/_bulk", bulk
      end

      eta = total * (Time.now - start_time) / done
      printf "    %u/%u (%.1f%%) done in %s, E.T.A.: %s.\r",
        done, total, 100.0 * done / total, tm_len, start_time + eta
    end

    printf "#{' ' * 80}\r    %u/%u done in %s.\n", done, total, tm_len

    # no point for large reindexation with data still being stored in index
    printf 'Checking document count... '
    scount, dcount = 1, 0
    begin
      Timeout::timeout(60) do
        while true
          scount = retried_request :get, "#{@surl}/#{@sidx}/_count?q=*"
          dcount = retried_request :get, "#{@durl}/#{@didx}/_count?q=*"
          scount = MultiJson.load(scount)['count'].to_i
          dcount = MultiJson.load(dcount)['count'].to_i
          break if scount == dcount
          sleep 1
        end
      end
    rescue Timeout::Error
    end
    printf "%u == %u (%s\n", scount, dcount, scount == dcount ? 'equals).' : 'NOT EQUAL)!'

    true
  end

private

  def setup_json_options
    if MultiJson.respond_to? :load_options=
      MultiJson.load_options = {mode: :compat}
      MultiJson.dump_options = {mode: :compat}
    else
      MultiJson.default_options = {mode: :compat}
    end
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

  def retried_request(method, url, data=nil)
    while true
      begin
        return data ?
          RestClient.send(method, url, data) :
          RestClient.send(method, url)
      rescue RestClient::ResourceNotFound # no point to retry
        return nil
      rescue RestClient::BadRequest => e # Something's wrong!
        warn "\n#{method.to_s.upcase} #{url} :-> ERROR: #{e.class} - #{e.message}"
        warn e.response
        return nil
      rescue => e
        warn "\nRetrying #{method.to_s.upcase} ERROR: #{e.class} - #{e.message}"
        warn e.response
      end
    end
  end
end
