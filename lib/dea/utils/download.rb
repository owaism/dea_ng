class Download
  attr_reader :source_uri, :destination_file, :sha1_expected
  attr_reader :logger

  class DownloadError < StandardError
    attr_reader :data

    def initialize(msg, data = {})
      @data = data

      super("Error downloading: %s (%s)" % [uri, msg])
    end

    def uri
      data[:droplet_uri] || "(unknown)"
    end
  end

  def initialize(source_uri, destination_file, sha1_expected=nil, custom_logger=nil)
    @source_uri = source_uri
    @destination_file = destination_file
    @sha1_expected = sha1_expected
    @logger = custom_logger || self.class.logger
  end

  def download!(&blk)
    destination_file.binmode
    sha1 = Digest::SHA1.new

    http = EM::HttpRequest.new(source_uri).get

    http.stream do |chunk|
      destination_file << chunk
      sha1 << chunk
    end

    context = { :droplet_uri => source_uri }

    http.errback do
      error = DownloadError.new("Response status: unknown", context)
      logger.warn(error.message, error.data)
      blk.call(error)
    end

    http.callback do
      destination_file.close
      http_status = http.response_header.status

      context[:droplet_http_status] = http_status

      if http_status == 200
        sha1_actual = sha1.hexdigest
        if !sha1_expected || sha1_expected == sha1_actual
          logger.info("Download succeeded")
          blk.call(nil)
        else
          context[:droplet_sha1_expected] = sha1_expected
          context[:droplet_sha1_actual] = sha1_actual

          error = DownloadError.new("SHA1 mismatch", context)
          logger.warn(error.message, error.data)
          blk.call(error)
        end
      else
        error = DownloadError.new("HTTP status: #{http_status}", context)
        logger.warn(error.message, error.data)
        blk.call(error)
      end
    end
  end
end
