class Location < ActiveRecord::Base
  has_and_belongs_to_many :technologies

  attr_accessor :skip_scan

  after_create :scan 

  def fetch_body(location = nil)
    # This fetches the source/body of the location
    # It's recursive and will follow the location in the
    # event of a 301 or other redirect
    
    location ||= self.url

    uri = URI(location) 
    if uri.port == 443
      # Ran into some ssl sites with bad certs, so we'll bypass
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      response = http.get(uri.request_uri)
    else
      response = Net::HTTP.get_response(uri)
    end
    
    case response
    when Net::HTTPSuccess   
      body = response.body
      self.update_attribute(:cached_source, body.encode('UTF-8'))
      return body
    when Net::HTTPRedirection 
      self.update_attribute(:url, response['location'])
      fetch_body(response['location'])
    end
  end

  def headers
    response = Net::HTTP.get_response(URI.parse(self.url))
    return response.header.to_hash
  end

  def scan
    # Skip scanning if set (this is for batch imports)
    return if self.skip_scan
    # Fetch the body, get all technologies and scan
    body = self.fetch_body
    tech = Technology.all
    tech.each do |t|
      if t.regex =~ body 
        # There's a match, add it unless it's already there
        self.technologies << t unless self.technologies.include? t
      else
        # No match, make sure to delete if it's there (maybe they removed it)
        self.technologies.delete(t) if self.technologies.include? t
      end
    end
  end

end
